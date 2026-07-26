//
//  KillSwitchTap.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox  // kVK_Escape
import CoreGraphics
import Observation
import os

/// 안전장치(하드 킬 스위치) 전용 `CGEventTap`의 소유자.
///
/// 버그 있는 전역 키 탭은 사용자를 키보드에서 완전히 차단할 수 있어 안전장치는 타협 불가이고,
/// 메인 탭 안에서 감지하면 킬 스위치가 버그와 함께 죽는다 — 그래서 별도 탭이고, 메인 탭의
/// off/failed/재설치와 **생명주기를 공유하지 않는다**. 정리 시점은 앱 종료뿐이다.
///
/// 발동 효과는 주입받는다(`onTrigger`) — 이 타입은 무엇이 꺼지는지 모르고 콤보 감지까지만
/// 책임진다. 콤보는 고정값 `Ctrl-Opt-Cmd-Esc`이며 사용자 설정은 아직 없다.
@MainActor
@Observable
final class KillSwitchTap {
    /// 킬 탭이 어느 지점에 설치됐는지. 우선순위가 다르므로 사용자에게도 노출한다
    /// (Settings "Kill Switch" 행) — 안전장치가 조용히 부재하는 것이 최악의 실패 모드다.
    enum Installation: Equatable {
        case notInstalled
        /// `kCGHIDEventTap` — 최고 우선순위. 의도한 설치 지점이다.
        case hid
        /// `kCGSessionEventTap` 폴백. HID 생성이 거부됐을 때만 — 아래 설치 순서 주석 참고.
        case session
    }

    private(set) var installation: Installation = .notInstalled

    @ObservationIgnored private nonisolated let onTrigger: @Sendable () -> Void
    @ObservationIgnored private nonisolated let portBox = TapPortBox()
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init(onTrigger: @escaping @Sendable () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Accessibility 권한이 있을 때만 킬 탭을 설치한다 (메인 탭과 같은 불변식).
    /// 권한 없이 호출되면 보류만 하고, 부여 감지 시 `AppState`가 다시 부른다.
    ///
    /// **설치 순서가 계약이다**: 세션 폴백 경로에서는 메인 탭과 킬 탭이 같은 위치에
    /// `.headInsertEventTap`으로 들어가고, 이때 **나중에 삽입된 쪽이 먼저 받는다**.
    /// 호출자는 반드시 메인 탭 설치 *다음에* 이 함수를 불러야 한다 (`AppState.bootstrap`).
    func startIfPermitted() {
        // 단위 테스트(TEST_HOST=앱 프로세스)가 라이브 탭을 설치하면 안 된다 — 메인 탭과 같은 가드.
        guard !isRunningUnderXCTest() else { return }
        guard installation == .notInstalled else { return }
        guard AXIsProcessTrusted() else {
            Logger.eventTap.info("Accessibility 미허용 — 킬스위치 탭 설치 보류")
            return
        }

        // keyDown만 관심 대상이다 — modifier는 keyDown의 flags로 함께 온다.
        // (`tapDisabledBy*`는 마스크와 무관하게 배달된다.)
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        // refcon 가정: self는 AppState가 앱 수명 동안 보유하고, 해제 전에 stop()으로 invalidate된다.
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        func create(at location: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: killSwitchTapCallback,
                userInfo: userInfo
            )
        }

        let port: CFMachPort
        if let hidPort = create(at: .cghidEventTap) {
            port = hidPort
            installation = .hid
        } else if let sessionPort = create(at: .cgSessionEventTap) {
            // HID 능동 탭이 거부되는 환경(문서상 root 제약)에서의 폴백. 메인 탭과 같은
            // 위치라 우선순위가 설치 순서에 의존하고, 메인 탭이 off→on으로 재설치되면
            // 킬 탭이 뒤로 밀린다 — 그때 메인 탭이 콤보를 삼키면 발동하지 못한다.
            port = sessionPort
            installation = .session
            Logger.eventTap.notice(
                "킬스위치 HID 탭 생성 실패 — 세션 탭으로 폴백 (메인 탭 재설치 시 우선순위 밀림)")
        } else {
            Logger.eventTap.fault("킬스위치 탭 생성 실패 — 안전장치 부재")
            return
        }

        // 탭은 생성 즉시 활성이다 — 전용 스레드가 소스를 붙이기 전까지 어느 런루프에도
        // 없는 활성 탭이 되고, 그 사이 들어온 이벤트가 서비스되지 않으면 OS가 탭을 도로
        // 꺼버린다. 부착 전까지 꺼 두고, 소스를 붙인 뒤에만 켠다 (startRunLoopThread).
        CGEvent.tapEnable(tap: port, enable: false)
        portBox.set(port)
        startRunLoopThread(port: port)
        registerTerminationObserverIfNeeded()
        Logger.eventTap.info(
            "킬스위치 탭 설치 완료 (\(String(describing: self.installation), privacy: .public))")
    }

    /// 킬 탭 전용 스레드 — 자체 `CFRunLoop`를 돌린다.
    ///
    /// 메인 런루프에 붙이면 메인 스톨 중에 콜백이 배달되지 않아 "메인이 멈춰도 발동한다"는
    /// 존재 이유가 무너진다. 메인 런루프 유지 결정은 **엔진이 붙은 메인 탭 한정**이며, 그
    /// 근거(assumeIsolated 제거의 nonisolated 연쇄 비용, 스톨 시 양성 degrade 수용)는
    /// `(keycode, flags)` 비교뿐인 이 콜백에는 성립하지 않는다.
    private func startRunLoopThread(port: CFMachPort) {
        // Thread 블록은 @Sendable이고 CFMachPort는 Sendable이 아니다 — 워치독의 강캡처와
        // 같은 근거(스레드 안전 C API, invalidate 후 no-op)로 안전하다.
        nonisolated(unsafe) let port = port
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            // 활성화는 소스를 붙인 **뒤에** — 설치 경로가 부착 전까지 탭을 꺼 두므로
            // (startIfPermitted의 선제 disable) 여기가 킬 탭의 유일한 활성화 지점이다.
            CGEvent.tapEnable(tap: port, enable: true)
            // stop()의 CFMachPortInvalidate가 소스를 무효화하면 남은 소스가 없어 이 호출이
            // 반환하고 스레드가 끝난다.
            CFRunLoopRun()
        }
        thread.name = "dev.pilyang.VimAction.killSwitchTap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func registerTerminationObserverIfNeeded() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
    }

    /// 킬 탭 정리 — 앱 종료 시에만 호출된다 (대롱거리는 탭 방지).
    ///
    /// 런루프 소스는 제거하지 않는다: 소스는 킬 스레드의 런루프에 있고, 포트 invalidate가
    /// 소스를 무효화해 그 스레드의 `CFRunLoopRun`이 반환하며 스스로 끝난다.
    func stop() {
        guard let port = portBox.get() else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        portBox.set(nil)
        installation = .notInstalled
        Logger.eventTap.info("킬스위치 탭 제거 완료")
    }

    /// 시스템이 킬 탭을 비활성화(타임아웃/사용자 개입)했을 때의 자체 재활성화.
    ///
    /// 킬 탭에는 **전용 워치독을 두지 않는다** — 메인 탭이 워치독을 필요로 한 이유는
    /// "스톨로 통지 자체가 유실되는" 실패 모드인데, 이 콜백은 `(keycode, flags)` 비교뿐이라
    /// 그 상황에 놓이지 않는다. 없는 실패 모드에 폴링을 다는 것은 과잉 방어다.
    fileprivate nonisolated func reenableAfterDisable(type: CGEventType) {
        guard let port = portBox.get() else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        Logger.eventTap.notice(
            "킬스위치 탭 재활성화 (type=\(type.rawValue, privacy: .public))")
    }

    /// 콤보 발동 — 킬 탭 전용 스레드에서 실행된다 (메인 스톨과 무관).
    fileprivate nonisolated func fire() {
        Logger.eventTap.fault("킬스위치 콤보 감지 — 가로채기 off")
        onTrigger()
    }

    /// 킬스위치 콤보 판정 — `CGEvent` 의존 없이 `(keycode, flags)`만 보는 순수 함수다.
    /// 실탭 경로는 TEST_HOST 포트가 항상 nil이라 CI에서 도달 불가하므로 판정만 분리해
    /// 단위 테스트한다 (`EventTapController.watchdogTick`과 같은 seam 패턴).
    ///
    /// 비교 대상은 **의도한 modifier 5종**뿐이다 — Caps Lock·numericPad·nonCoalesced 같은
    /// 상태/부수 비트는 마스킹해 무시한다. Caps Lock이 켜져 있다는 이유로 안전장치가 안 먹는
    /// 쪽이 오발동보다 나쁘기 때문이다: 오발동의 복구는 메뉴바 토글 1클릭이지만, 미발동의
    /// 대가는 키보드 인질 상태다.
    nonisolated static func isKillCombo(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == Int64(kVK_Escape) else { return false }
        let intentional: CGEventFlags = [
            .maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn,
        ]
        return flags.intersection(intentional) == [.maskControl, .maskAlternate, .maskCommand]
    }

    /// keyDown 하나가 발동 대상인지 — 콤보 판정 앞의 방어 가드 두 겹.
    nonisolated static func shouldFire(_ event: CGEvent) -> Bool {
        // 우리가 게시한 합성 이벤트로는 발동하지 않는다. 지금 세션에 게시한 이벤트는 HID
        // 탭까지 오지 않지만 **세션 폴백 경로에서는 들어오고**, 어댑터가 modifier 조합 Esc를
        // 합성하게 되면 앱이 자기 출력으로 자기를 끄게 된다 (메인 탭의 마커 최우선 판정과
        // 같은 정신 — 상태 무관 불변식이다).
        guard !SyntheticEventMarker.isMarked(event) else { return false }
        // 오토리핏 무시 — 콤보를 꾹 누르면 fault 로그와 메인 홉이 초당 수십 건 도배된다
        // (효과 자체는 소프트 off didSet의 등가 가드가 이미 멱등하게 만든다).
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        return isKillCombo(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
    }
}

/// C 함수 포인터 콜백 — 킬 탭 전용 스레드의 `CFRunLoop`에서 실행된다.
/// 메인 탭 콜백과 달리 `MainActor.assumeIsolated`를 쓰지 않는다: 메인 런루프가 아니라
/// 그 가정이 거짓이고, 메인 격리에 의존하지 않는 것이 이 탭의 존재 이유다.
private nonisolated func killSwitchTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KillSwitchTap>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // 키 이벤트가 아니라 아웃오브밴드 제어 통지 — 반환값은 시스템이 무시한다.
        tap.reenableAfterDisable(type: type)
        return nil
    case .keyDown:
        #if DEBUG
        // HID 지점의 keyDown이 modifier 비트를 싣고 오는지 확인하는 진단(Esc에 한해).
        // 콤보 미발동 시 원인을 가른다: 이 줄이 있는데 modifier 비트가 없으면 HID flags
        // 문제, 줄 자체가 없으면 탭이 이벤트를 못 받는 것이다.
        if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) {
            Logger.eventTap.debug(
                "킬스위치 진단 — Esc keyDown flags=\(event.flags.rawValue, privacy: .public)")
        }
        #endif
        guard KillSwitchTap.shouldFire(event) else { return Unmanaged.passUnretained(event) }
        tap.fire()
        // 콤보는 삼킨다 — 안전장치 조합이 포커스 앱까지 새지 않게 한다.
        return nil
    default:
        return Unmanaged.passUnretained(event)
    }
}

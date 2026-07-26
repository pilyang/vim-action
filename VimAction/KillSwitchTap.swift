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
        /// 탭은 만들어졌으나 활성화가 먹지 않았다 — 콤보가 오지 않는다.
        ///
        /// `.notInstalled`로 되돌리지 않는 이유: 그러면 `startIfPermitted`의 설치 가드가
        /// 다시 열리는데 `portBox`에는 살아 있는 포트가 남아 있어, 권한 재부여 경로가
        /// 두 번째 탭을 만들고 첫 탭을 고아로 남긴다.
        case failed
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
            // 방어적 폴백 — **실제로 타는 경로가 아니다.** `CGEvent.h`의 "HID 탭은 root만"
            // 문구는 낡았다: Accessibility를 부여받은 비root 프로세스도 능동 HID 탭을
            // 정상 생성한다(macOS 26.5 실측). 그래도 남겨 두는 이유는 안전장치가 아예
            // 없는 것보다 우선순위가 밀린 안전장치가 낫기 때문이다.
            //
            // 이 경로에서만 두 탭이 같은 위치에 들어가 우선순위가 설치 순서에 의존한다.
            // 순서를 지키는 것은 `EventTapController.onTapInstalled` 훅이다 — 메인 탭이
            // (재)설치될 때마다 킬 탭 설치가 그 **뒤에** 이어진다. off→on 토글은 포트를
            // 유지한 채 tapEnable만 하므로 재삽입도 순서 역전도 일으키지 않는다.
            port = sessionPort
            installation = .session
            Logger.eventTap.notice(
                "킬스위치 HID 탭 생성 실패 — 세션 탭으로 폴백 (메인 탭과 같은 위치, 순서 의존)")
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
        let thread = Thread { [self] in
            // 소스 생성은 nil일 수 있다 — `thread.start()`는 블록을 기다리지 않으므로
            // 그 사이에 stop()이 포트를 invalidate하면 여기서 NULL이 온다. 그대로 넘기면
            // CoreFoundation 안에서 널 역참조로 프로세스가 죽는다 (Swift 가드 없음:
            // 반환형도 파라미터도 Optional이라 nil이 그대로 C로 건너간다).
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                Logger.eventTap.notice("킬스위치 런루프 소스 생성 실패 — 포트가 이미 무효 (종료 경합)")
                return
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            // 활성화는 소스를 붙인 **뒤에** — 설치 경로가 부착 전까지 탭을 꺼 두므로
            // (startIfPermitted의 선제 disable) 여기가 킬 탭의 유일한 활성화 지점이다.
            CGEvent.tapEnable(tap: port, enable: true)
            // 켰다고 믿지 않는다 — 메인 탭의 `enableAndCheck`와 같은 검증 계약이다.
            // 여기가 유일한 활성화 지점이고 재시도가 없으므로, 실패를 놓치면 Settings가
            // 세션 내내 "Active"를 주장하는 채로 안전장치만 조용히 부재한다.
            if !CGEvent.tapIsEnabled(tap: port) { reportEnableFailure(reason: "설치") }
            // stop()의 CFMachPortInvalidate가 소스를 무효화하면 남은 소스가 없어 이 호출이
            // 반환하고 스레드가 끝난다 (활성화 실패와 무관하게 수명 계약은 동일하다).
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
    /// 킬 탭에는 **전용 워치독을 두지 않는다** — 근거는 두 겹이다.
    ///
    /// ① 메인 탭이 워치독을 필요로 한 이유 하나는 "스톨로 통지 자체가 유실되는" 실패
    ///    모드인데, 이 콜백은 `(keycode, flags)` 비교뿐이라 그 상황에 놓이지 않는다.
    /// ② **더 결정적인 쪽**: 메인 탭의 재활성화는 *게이트가 걸려 있다*(킬 래치·토글 off).
    ///    의도적으로 건너뛴 재활성화는 나중에 폴링이 풀어 줘야 한다. 이 함수에는 게이트가
    ///    하나도 없어 "보류됐다가 잊히는" 상태 자체가 존재하지 않는다.
    ///
    /// 폴링 대신 필요한 것은 **검증**이다 — 아래 `tapIsEnabled` 확인이 그 몫이다.
    /// 재시도 타이머는 두지 않는다: 반복 타이머는 런루프를 영구히 붙잡아 `stop()`의
    /// invalidate로 스레드가 끝난다는 아래 수명 계약을 깨고, 거부는 일시적이 아니라
    /// 영구적(포트/신원) 성격이라 재시도의 기대값이 없다.
    fileprivate nonisolated func reenableAfterDisable(type: CGEventType) {
        guard let port = portBox.get() else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        // 설치 경로와 같은 검증 계약. 여기서 특히 중요한 이유: `tapDisabledBy*` 통지는
        // **한 번뿐이다** — 꺼진 탭은 이벤트를 못 받으므로 두 번째 통지가 오지 않는다
        // (실측 확인). 재활성화가 먹지 않은 것을 여기서 놓치면 복구 기회가 영영 없다.
        guard CGEvent.tapIsEnabled(tap: port) else {
            reportEnableFailure(reason: "비활성화 통지(type=\(type.rawValue))")
            return
        }
        Logger.eventTap.notice(
            "킬스위치 탭 재활성화 (type=\(type.rawValue, privacy: .public))")
    }

    /// 활성화 실패 보고 — 킬 스레드에서 호출된다.
    ///
    /// 로그는 **여기서 직접** 남긴다 (메인이 굳어도 기록은 남아야 한다). UI 강등은
    /// 메인 홉의 부차 채널이다 — Settings 자체가 메인 구동이라 홉이 못 가는 상황에서는
    /// 어차피 볼 수 없고, `async`라 킬 스레드를 붙잡지도 않는다.
    private nonisolated func reportEnableFailure(reason: String) {
        Logger.eventTap.fault(
            "킬스위치 탭 활성화 실패 — 안전장치 부재 (\(reason, privacy: .public))")
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.installation = .failed }
        }
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

    /// keyDown 하나를 삼킬지 — 안전장치 조합이 포커스 앱까지 새지 않게 한다.
    ///
    /// 삼킴은 발동보다 넓다: 오토리핏 콤보는 발동하지 않지만(아래 `shouldFire`) **삼키기는
    /// 한다**. 콤보를 꾹 누르면 HID 계층이 초당 10여 건의 Esc keyDown을 계속 올려보내는데,
    /// 발동 판정만으로 통과시키면 그 전부가 포커스 앱에 쏟아진다.
    nonisolated static func shouldSwallow(_ event: CGEvent) -> Bool {
        // 우리가 게시한 합성 이벤트는 건드리지 않는다. 지금 세션에 게시한 이벤트는 HID
        // 탭까지 오지 않지만 **세션 폴백 경로에서는 들어오고**, 어댑터가 modifier 조합 Esc를
        // 합성하게 되면 앱이 자기 출력으로 자기를 끄게 된다 (메인 탭의 마커 최우선 판정과
        // 같은 정신 — 상태 무관 불변식이다).
        guard !SyntheticEventMarker.isMarked(event) else { return false }
        return isKillCombo(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
    }

    /// 삼킬 콤보 중 실제로 발동시킬 것인지 — 오토리핏 제외.
    /// 콤보를 꾹 누르면 fault 로그와 메인 홉이 초당 10여 건 도배된다
    /// (효과 자체는 소프트 off didSet의 등가 가드가 이미 멱등하게 만든다).
    nonisolated static func shouldFire(_ event: CGEvent) -> Bool {
        guard shouldSwallow(event) else { return false }
        return event.getIntegerValueField(.keyboardEventAutorepeat) == 0
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
        // 삼킴이 먼저다 — 오토리핏 콤보는 발동하지 않아도 통과시키지 않는다.
        guard KillSwitchTap.shouldSwallow(event) else { return Unmanaged.passUnretained(event) }
        if KillSwitchTap.shouldFire(event) { tap.fire() }
        // 콤보는 삼킨다 — 안전장치 조합이 포커스 앱까지 새지 않게 한다.
        return nil
    default:
        return Unmanaged.passUnretained(event)
    }
}

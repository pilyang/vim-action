//
//  EventTapController.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox  // IsSecureEventInputEnabled() 제공 — 제거 시 빌드 실패 (곧 kVK_* 키코드도 사용).
import Observation
import os
import VimEngine

/// 유일한 메인 CGEventTap의 소유자. keyDown을 `KeyTranslator`→`VimEngine`으로 흘려
/// 엔진 결정(통과/삼킴/대체)을 이벤트에 적용한다. 대체(replace)의 실제 실행은 디스패처
/// 마일스톤 — 지금은 삼키고 로그만 남긴다. 합성 이벤트 마커 확인도 그때 얹힌다.
@MainActor
@Observable
final class EventTapController {
    enum Status: Equatable {
        /// Accessibility 미허용 — 불변식에 따라 설치 거부 상태.
        case waitingForPermission
        /// 탭 활성.
        case running
        /// 권한 외 원인으로 tapCreate 실패.
        case failed
        /// 종료 정리 후.
        case stopped
    }

    private(set) var status: Status = .waitingForPermission

    /// 현재 모드 — `handle` 후 `engine.mode`의 복사본. 메뉴바 글리프가 관찰한다.
    private(set) var mode: Mode = .insert

    /// 엔진 소유 — UI 관찰 대상이 아니다. Configuration은 배선 단계 하드코딩 기본값
    /// (제품 기본 on) — 안전장치 단계에서 설정 주입으로 교체.
    @ObservationIgnored private var engine = VimEngine(
        configuration: .init(normalModeEscapeModifiers: [.command, .option]))

    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    /// Accessibility 권한이 있을 때만 탭을 설치한다 (권한 없으면 설치 거부 — 불변식).
    func startIfPermitted() {
        guard tapPort == nil else { return }
        guard AXIsProcessTrusted() else {
            status = .waitingForPermission
            Logger.eventTap.info("Accessibility 미허용 — 탭 설치 보류")
            return
        }

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        // refcon 가정: self는 AppState가 앱 수명 동안 보유하고, 해제 전에 stop()으로 invalidate된다.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = .failed
            Logger.eventTap.fault("CGEvent.tapCreate 실패 — 권한 외 원인 의심")
            return
        }
        tapPort = port

        // 스파이크는 메인 런루프에 부착한다: 콜백이 거의 no-op이고 프로젝트의 MainActor 기본
        // 격리와 정합. 엔진 연결 전에 전용 CFRunLoop 스레드 필요 여부를 재검토할 것 —
        // 아래 재활성화 로그 빈도가 판단 데이터가 된다.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        Logger.eventTap.info("탭 설치 완료 (secureInput=\(IsSecureEventInputEnabled()))")
        status = .running

        if terminationObserver == nil {
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                }
            }
        }
    }

    /// 탭 정리: 비활성화 → 런루프 소스 제거 → 포트 invalidate. 앱 종료 시 호출된다.
    func stop() {
        guard let port = tapPort else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        tapPort = nil
        runLoopSource = nil
        status = .stopped
        Logger.eventTap.info("탭 제거 완료")
    }

    /// 시스템이 탭을 비활성화(타임아웃/사용자 개입)했을 때 재활성화한다.
    fileprivate func reenableAfterDisable(type: CGEventType) {
        guard let port = tapPort else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        Logger.eventTap.info("시스템이 탭 비활성화(type=\(type.rawValue)) — 재활성화")
    }

    /// keyDown 하나를 엔진 결정으로 번역해 적용한다. 탭 설치와 무관한 순수 경로라
    /// internal이다 — 합성 CGEvent 시퀀스로 단위 테스트하는 계약.
    func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // 번역 불가는 무조건 통과 — 번역기 계약.
        guard let key = KeyTranslator.translate(event) else {
            return Unmanaged.passUnretained(event)
        }
        let output = engine.handle(key)
        // 등가 가드: @Observable은 등가 비교 없이 대입만으로 발화하므로, 무조건 대입이면
        // Insert 타이핑 내내 매 keyDown마다 메뉴바 SwiftUI 무효화가 콜백 경로에서 돈다.
        if mode != engine.mode { mode = engine.mode }

        // 로그는 swallow/replace만 — passthrough(Insert 타이핑)까지 남기면 키로거가 된다.
        switch output.decision {
        case .passthrough:
            return Unmanaged.passUnretained(event)
        case .swallow:
            #if DEBUG
            Logger.eventTap.debug("swallow")
            #endif
            return nil
        case .replace:
            // 과도기: 실행 없이 삼키고 요약 1건만 로그. actions는 수천 개일 수 있어
            // (카운트 도입 예정) 콜백 내 다발 로그는 탭 타임아웃을 유발한다.
            #if DEBUG
            Logger.eventTap.debug(
                "replace ×\(output.actions.count, privacy: .public): \(String(describing: output.actions.first), privacy: .public)"
            )
            #endif
            return nil
        }
    }
}

/// C 함수 포인터 콜백 — 프로젝트 기본 MainActor 격리를 벗어나야 하므로 명시적 nonisolated.
/// 탭 소스를 메인 런루프에 붙였으므로 항상 메인 스레드에서 실행된다 — `assumeIsolated`의 근거.
/// (런루프 선택이 바뀌면 이 가정부터 깨진다.)
private nonisolated func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()

    return MainActor.assumeIsolated { () -> Unmanaged<CGEvent>? in
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 키 이벤트가 아니라 아웃오브밴드 제어 통지 — 반환값은 시스템이 무시한다.
            // 재활성화만 하고, 이벤트가 흐르지 않음을 드러내려 nil 반환.
            controller.reenableAfterDisable(type: type)
            return nil
        case .keyDown:
            return controller.handleKeyDown(event)
        default:
            break
        }
        // flagsChanged 등 나머지는 무수정 통과 — modifier는 keyDown의 flags로 이미
        // 엔진에 전달되므로 flagsChanged를 엔진에 넣지 않는다.
        return Unmanaged.passUnretained(event)
    }
}

//
//  EventTapController.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox  // IsSecureEventInputEnabled() 제공 — 제거 시 빌드 실패 (곧 kVK_* 키코드도 사용).
import Observation
import os

/// 유일한 메인 CGEventTap의 소유자. 지금은 스파이크 단계 — 모든 이벤트를 무수정 통과시키고
/// 로그만 남긴다. 이후 마일스톤에서 CGEvent→Key 변환, 합성 이벤트 마커 확인, VimEngine 연결이
/// 이 스켈레톤 위에 얹힌다.
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

    fileprivate func logKeyEvent(type: CGEventType, event: CGEvent) {
        // 키 입력 로그는 사실상 키로거 — DEBUG 빌드에만 컴파일한다(릴리스 산출물엔 존재하지 않음).
        // keycode 관찰이 이 스파이크의 목적이라 DEBUG에서는 .public 유지. TODO: 엔진 연결 시 제거.
        #if DEBUG
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = String(event.flags.rawValue, radix: 16)
        Logger.eventTap.debug("\(type == .keyDown ? "keyDown" : "flagsChanged", privacy: .public) keycode=\(keycode, privacy: .public) flags=0x\(flags, privacy: .public)")
        #endif
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
        case .keyDown, .flagsChanged:
            controller.logKeyEvent(type: type, event: event)
        default:
            break
        }
        // 스파이크: 키 이벤트는 무수정 통과.
        return Unmanaged.passUnretained(event)
    }
}

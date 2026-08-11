//
//  DockIconControllerTests.swift
//  VimActionTests
//

import AppKit
import Testing

@testable import VimAction

/// 설정 창을 대신하는 창. Sparkle의 'Checking for updates…' 창 등 "잡아 둔 창이 아닌
/// 다른 창"도 같은 헬퍼로 모사한다 — 판정이 창의 속성이 아니라 동일성이라 모양은 무관하다.
/// 알림을 직접 post하므로 화면에 띄우지 않는다.
@MainActor
private func makeTitledWindow() -> NSWindow {
    NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
}

/// 격리된 `NotificationCenter`와 기록용 클로저를 주입해 라이브 창 알림 구독과 실제
/// `NSApp` 정책 변경을 모두 피한다 — TEST_HOST가 앱 프로세스라 둘 다 실물에 닿는다.
@MainActor
private final class PolicyRecorder {
    var applied: [NSApplication.ActivationPolicy] = []
    var activateCount = 0
    let center = NotificationCenter()

    func makeController() -> DockIconController {
        DockIconController(
            setPolicy: { [self] in applied.append($0) },
            activate: { [self] in activateCount += 1 },
            notificationCenter: center)
    }
}

@MainActor
struct DockIconControllerTests {
    @Test("설정 창이 열리면 .regular, 닫히면 .accessory로 되돌린다")
    func settingsLifecycleDrivesActivationPolicy() {
        let recorder = PolicyRecorder()
        let settingsWindow = makeTitledWindow()
        let controller = recorder.makeController()

        #expect(controller.policy == .accessory)

        controller.settingsWindowDidConnect(settingsWindow)
        controller.settingsWindowDidAppear()
        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
        // 메뉴바에서 연 설정 창은 앱이 활성화되지 않은 채 뜬다 — 승격에는 activate가
        // 따라와야 창이 다른 앱 뒤에 깔리지 않는다.
        #expect(recorder.activateCount == 1)

        // 강등의 유일한 조건은 "설정 뷰가 넘겨준 바로 그 창"이다.
        recorder.center.post(name: NSWindow.willCloseNotification, object: settingsWindow)
        #expect(controller.policy == .accessory)
        #expect(recorder.applied == [.regular, .accessory])
        // 강등은 activate하지 않는다 — 포커스는 다음 앱으로 넘어가야 한다.
        #expect(recorder.activateCount == 1)
    }

    /// `onAppear`는 재오픈마다 오고 창이 포커스를 되찾을 때 리렌더로도 올 수 있으며,
    /// `viewDidMoveToWindow`도 같은 창으로 재발화할 수 있다 — 멱등이 아니면 정책 재설정과
    /// `activate`가 반복된다.
    @Test("같은 정책 반복 요청은 무시된다")
    func repeatedRequestsAreIdempotent() {
        let recorder = PolicyRecorder()
        let settingsWindow = makeTitledWindow()
        let controller = recorder.makeController()

        for _ in 0..<3 {
            controller.settingsWindowDidConnect(settingsWindow)
            controller.settingsWindowDidAppear()
        }

        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
        #expect(recorder.activateCount == 1)
    }

    /// Sparkle의 'Checking for updates…'(`SUStatusController`)·업데이트 알림(`SUUpdateAlert`)이나
    /// 'Reload Config' 실패 패널이 설정 창이 열린 채 닫히는 경로 — 잡아 둔 창이 아니므로
    /// 아이콘을 내려서는 안 된다. 재승격 신호가 `onAppear`뿐이라 여기서 내려가면 설정 창이
    /// 떠 있는 한 돌아오지 않는다.
    @Test("다른 창이 닫혀도 Dock 아이콘을 유지한다")
    func closingOtherWindowKeepsDockIcon() {
        let recorder = PolicyRecorder()
        let controller = recorder.makeController()

        controller.settingsWindowDidConnect(makeTitledWindow())
        controller.settingsWindowDidAppear()
        recorder.center.post(name: NSWindow.willCloseNotification, object: makeTitledWindow())

        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
    }

    /// `Settings` 씬이 재오픈에서 새 `NSWindow`를 만들 수 있다 — 새 뷰 계층의
    /// `viewDidMoveToWindow`가 새 창을 다시 넘기므로 두 번째 창의 닫힘도 판정된다.
    @Test("재오픈하면 새 설정 창을 다시 넘겨받는다")
    func reopenReconnectsNewSettingsWindow() {
        let recorder = PolicyRecorder()
        let first = makeTitledWindow()
        let controller = recorder.makeController()

        controller.settingsWindowDidConnect(first)
        controller.settingsWindowDidAppear()
        recorder.center.post(name: NSWindow.willCloseNotification, object: first)
        #expect(controller.policy == .accessory)

        let second = makeTitledWindow()
        controller.settingsWindowDidConnect(second)
        controller.settingsWindowDidAppear()
        #expect(controller.policy == .regular)

        recorder.center.post(name: NSWindow.willCloseNotification, object: second)
        #expect(controller.policy == .accessory)
        #expect(recorder.applied == [.regular, .accessory, .regular, .accessory])
    }

    /// 창을 넘겨받지 못했을 때의 방향 — 승격은 하되 어떤 창이 닫혀도 강등하지 않는다.
    /// 아이콘이 남는 쪽이 fail-safe다 (술어 폴백을 두면 Sparkle 창 버그가 되살아난다).
    @Test("설정 창을 못 넘겨받으면 강등하지 않는다")
    func missingConnectionNeverDemotes() {
        let recorder = PolicyRecorder()
        let controller = recorder.makeController()

        controller.settingsWindowDidAppear()
        #expect(controller.policy == .regular)

        recorder.center.post(name: NSWindow.willCloseNotification, object: makeTitledWindow())
        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
    }

    /// 닫힘 알림만 먼저 오는 경우(설정 창을 연 적 없음) 정책을 건드리지 않는다.
    @Test("설정 창을 연 적 없으면 닫힘 알림이 무해하다")
    func closeWithoutOpenIsNoOp() {
        let recorder = PolicyRecorder()
        let controller = recorder.makeController()

        recorder.center.post(name: NSWindow.willCloseNotification, object: makeTitledWindow())

        #expect(controller.policy == .accessory)
        #expect(recorder.applied.isEmpty)
    }
}

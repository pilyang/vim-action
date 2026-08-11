//
//  DockIconControllerTests.swift
//  VimActionTests
//

import AppKit
import Testing

@testable import VimAction

/// 설정 창을 대신하는 창 — 찾기 술어의 조건(보이는 titled 비-패널)을 갖춘다.
/// Sparkle의 'Checking for updates…' 창도 같은 조건이라 이 헬퍼로 함께 모사한다.
@MainActor
private func makeTitledWindow() -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    // 알림을 직접 post하므로 최전면에 띄우지 않는다 — 판정이 보는 `isVisible`만 켠다.
    window.orderBack(nil)
    return window
}

/// 'Reload Config' 실패 `NSAlert`를 대신하는 패널.
@MainActor
private func makePanel() -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled], backing: .buffered, defer: false)
    panel.orderBack(nil)
    return panel
}

/// 격리된 `NotificationCenter`와 기록용 클로저를 주입해 라이브 창 알림 구독과 실제
/// `NSApp` 정책 변경을 모두 피한다 — TEST_HOST가 앱 프로세스라 둘 다 실물에 닿는다.
@MainActor
private final class PolicyRecorder {
    var applied: [NSApplication.ActivationPolicy] = []
    var activateCount = 0
    /// 열림 훅이 설정 창을 찾아갈 창 목록 — 라이브 `NSApp.windows` 대신 주입한다.
    var visibleWindows: [NSWindow] = []
    let center = NotificationCenter()

    func makeController() -> DockIconController {
        DockIconController(
            setPolicy: { [self] in applied.append($0) },
            activate: { [self] in activateCount += 1 },
            windows: { [self] in visibleWindows },
            notificationCenter: center)
    }
}

@MainActor
struct DockIconControllerTests {
    /// 찾기 술어만 검증 — 알림 배선 없이 전 분기를 커버한다.
    @Test("찾기 술어는 설정 창 조건만 통과시킨다")
    func onlySettingsWindowIsRecognized() {
        #expect(DockIconController.isSettingsWindow(makeTitledWindow()))
        // 실패 알림 패널을 설정 창으로 잡으면 그 패널이 닫힐 때 아이콘이 사라진다.
        #expect(!DockIconController.isSettingsWindow(makePanel()))

        // 메뉴바 상태 항목 창 계열 — titled가 아니다.
        let borderless = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        borderless.orderBack(nil)
        #expect(!DockIconController.isSettingsWindow(borderless))

        // 이미 화면에서 내려간 창.
        let hidden = makeTitledWindow()
        hidden.orderOut(nil)
        #expect(!DockIconController.isSettingsWindow(hidden))
    }

    @Test("설정 창이 열리면 .regular, 닫히면 .accessory로 되돌린다")
    func settingsLifecycleDrivesActivationPolicy() {
        let recorder = PolicyRecorder()
        let settingsWindow = makeTitledWindow()
        recorder.visibleWindows = [settingsWindow]
        let controller = recorder.makeController()

        #expect(controller.policy == .accessory)

        controller.settingsWindowDidAppear()
        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
        // 메뉴바에서 연 설정 창은 앱이 활성화되지 않은 채 뜬다 — 승격에는 activate가
        // 따라와야 창이 다른 앱 뒤에 깔리지 않는다.
        #expect(recorder.activateCount == 1)

        // 강등의 유일한 조건은 "열림 훅이 잡아 둔 바로 그 창"이다.
        recorder.center.post(name: NSWindow.willCloseNotification, object: settingsWindow)
        #expect(controller.policy == .accessory)
        #expect(recorder.applied == [.regular, .accessory])
        // 강등은 activate하지 않는다 — 포커스는 다음 앱으로 넘어가야 한다.
        #expect(recorder.activateCount == 1)
    }

    /// `onAppear`는 재오픈마다 오고 창이 포커스를 되찾을 때 리렌더로도 올 수 있다 —
    /// 멱등이 아니면 정책 재설정과 `activate`가 반복된다.
    @Test("같은 정책 반복 요청은 무시된다")
    func repeatedRequestsAreIdempotent() {
        let recorder = PolicyRecorder()
        recorder.visibleWindows = [makeTitledWindow()]
        let controller = recorder.makeController()

        controller.settingsWindowDidAppear()
        controller.settingsWindowDidAppear()
        controller.settingsWindowDidAppear()

        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
        #expect(recorder.activateCount == 1)
    }

    /// 설정 창이 열린 채 리로드 실패 알림이 떴다 닫히는 경로 — 패널의 `willClose`가
    /// Dock 아이콘을 내려서는 안 된다.
    @Test("알림 패널이 닫혀도 Dock 아이콘을 유지한다")
    func closingAlertPanelKeepsDockIcon() {
        let recorder = PolicyRecorder()
        recorder.visibleWindows = [makeTitledWindow()]
        let controller = recorder.makeController()

        controller.settingsWindowDidAppear()
        recorder.center.post(name: NSWindow.willCloseNotification, object: makePanel())

        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
    }

    /// Sparkle의 'Checking for updates…'(`SUStatusController`)·업데이트 알림(`SUUpdateAlert`)은
    /// titled 일반 `NSWindow`라 술어만으로는 설정 창과 구분되지 않는다. 술어로 닫힘을 판정하면
    /// 업데이트 확인이 끝나는 순간 설정 창이 열려 있는데도 아이콘이 내려가고, 재승격 신호가
    /// `onAppear`뿐이라 돌아오지도 않는다.
    @Test("업데이트 확인 창이 닫혀도 Dock 아이콘을 유지한다")
    func closingOtherTitledWindowKeepsDockIcon() {
        let recorder = PolicyRecorder()
        recorder.visibleWindows = [makeTitledWindow()]
        let controller = recorder.makeController()

        controller.settingsWindowDidAppear()
        recorder.center.post(name: NSWindow.willCloseNotification, object: makeTitledWindow())

        #expect(controller.policy == .regular)
        #expect(recorder.applied == [.regular])
    }

    /// `Settings` 씬이 재오픈에서 새 `NSWindow`를 만들 수 있다 — 열림 훅이 매번 재캡처하지
    /// 않으면 두 번째 창을 닫아도 아이콘이 내려가지 않는다.
    @Test("재오픈하면 새 설정 창을 다시 잡는다")
    func reopenRecapturesNewSettingsWindow() {
        let recorder = PolicyRecorder()
        let first = makeTitledWindow()
        recorder.visibleWindows = [first]
        let controller = recorder.makeController()

        controller.settingsWindowDidAppear()
        recorder.center.post(name: NSWindow.willCloseNotification, object: first)
        #expect(controller.policy == .accessory)

        let second = makeTitledWindow()
        recorder.visibleWindows = [second]
        controller.settingsWindowDidAppear()
        #expect(controller.policy == .regular)

        recorder.center.post(name: NSWindow.willCloseNotification, object: second)
        #expect(controller.policy == .accessory)
        #expect(recorder.applied == [.regular, .accessory, .regular, .accessory])
    }

    /// 설정 창을 못 잡았을 때의 방향 — 승격은 하되 어떤 창이 닫혀도 강등하지 않는다.
    /// 아이콘이 남는 쪽이 fail-safe다 (술어 폴백을 두면 Sparkle 창 버그가 되살아난다).
    @Test("설정 창을 못 잡으면 강등하지 않는다")
    func missingCaptureNeverDemotes() {
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

//
//  DockIconController.swift
//  VimAction
//

import AppKit
import Foundation

/// Dock 아이콘 노출 정책 — 평소에는 `LSUIElement` 그대로 백그라운드(`.accessory`)이고,
/// 설정 창이 열려 있는 동안에만 `.regular`로 올려 Dock 아이콘을 노출한다. 창을 닫으면
/// 되돌린다. `LSUIElement = YES`는 "시작 시 `.accessory`"를 뜻할 뿐이라 런타임 전환이
/// 가능하다.
///
/// `.regular`는 Dock 아이콘과 **상단 앱 메뉴가 한 세트다** — 아이콘만 켜는 API는 없다.
/// 설정 창이 떠 있는 동안 앱 메뉴가 나타나고 ⌘Tab 목록에도 들어가는 것은 수용된 대가다.
///
/// 열림·닫힘 신호가 **비대칭인 것은 실측 결과다**. 열림은 SwiftUI의 `onAppear`가 유일하게
/// 신뢰할 수 있는 신호다: 메뉴바에서 'Preferences…'를 눌러도 앱이 활성화되지 않아 설정
/// 창은 보이기만 하고 key가 되지 않으며(`.accessory` 앱의 정상 동작), 그래서
/// `NSWindow.didBecomeKeyNotification`은 **오지 않는다**. 반대로 닫힘은 `willClose`를
/// 쓴다 — `onDisappear`는 리렌더에도 뜰 수 있어 설정 창이 열린 채 Dock 아이콘이
/// 사라질 수 있다. `onAppear`가 재오픈에도 매번 오는 것은 실기기에서 확인했다.
@MainActor
final class DockIconController {
    /// Dock 아이콘을 계속 붙잡아 둘 이유가 되는 창인가 — 닫힘 판정 전용이다. 이 앱이
    /// 만드는 창 중 설정 창만 해당한다: 메뉴바 상태 항목 창은 titled가 아니고,
    /// 'Reload Config' 실패 `NSAlert`는 `NSPanel`이다. 패널을 거르지 않으면 설정 창이
    /// 열린 채 알림만 닫아도 Dock 아이콘이 사라진다.
    /// 순수 판정이라 알림 배선 없이 테스트한다 (`FrontmostAppGate.isDisabled`와 같은 분리).
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
    }

    /// 프로덕션 컨트롤러 생성. 단위 테스트(TEST_HOST=앱 프로세스)와 SwiftUI 프리뷰에서는
    /// 라이브 창 알림을 구독하지도, 정책을 뒤집지도 않는다 — 테스트가 만든 창 하나에 앱이
    /// 통째로 `.regular`가 되면 안 되고, 프리뷰 캔버스가 `SettingsView`를 렌더하면
    /// `onAppear`가 떠서 Xcode 프리뷰 에이전트가 Dock에 나타난다
    /// (`FrontmostAppGate.forCurrentEnvironment`와 같은 이유·같은 형태).
    static func forCurrentEnvironment() -> DockIconController {
        let isInert =
            isRunningUnderXCTest()
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        return isInert
            ? DockIconController(
                setPolicy: { _ in }, activate: {}, notificationCenter: NotificationCenter())
            : DockIconController()
    }

    /// 현재 적용된 정책. 초기값 `.accessory`는 `LSUIElement = YES`의 시작 상태와 같다.
    /// 읽기는 테스트 검증용으로 연다.
    private(set) var policy: NSApplication.ActivationPolicy = .accessory

    private let setPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private let activate: @MainActor () -> Void
    /// 옵저버 해제를 `deinit`(nonisolated)에서 하므로 격리 밖에서 읽혀야 한다.
    /// `NotificationCenter`는 `Sendable`이라 `let`만으로 되고, 토큰은 `var`+비-`Sendable`
    /// 이라 `nonisolated(unsafe)`가 필요하다 — 접근이 init과 deinit 두 곳뿐이고 그 사이
    /// 경합이 없다 (`FrontmostAppGate`와 같은 근거).
    private let notificationCenter: NotificationCenter
    private nonisolated(unsafe) var observerToken: NSObjectProtocol?

    /// 정책 적용과 활성화는 주입 지점이다 — 테스트가 라이브 `NSApp`을 건드리지 않는다.
    init(
        setPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = {
            NSApp.setActivationPolicy($0)
        },
        activate: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) },
        notificationCenter: NotificationCenter = .default
    ) {
        self.setPolicy = setPolicy
        self.activate = activate
        self.notificationCenter = notificationCenter
        observerToken = notificationCenter.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            // queue: .main 배달이라 항상 메인 스레드다 (레포 표준 옵저버 패턴).
            MainActor.assumeIsolated {
                guard Self.isSettingsWindow(window) else { return }
                self?.apply(.accessory)
            }
        }
    }

    deinit {
        if let observerToken { notificationCenter.removeObserver(observerToken) }
    }

    /// 설정 창이 화면에 올라왔다 — `SettingsView.onAppear`가 부른다.
    func settingsWindowDidAppear() {
        apply(.regular)
    }

    private func apply(_ newPolicy: NSApplication.ActivationPolicy) {
        guard newPolicy != policy else { return }
        policy = newPolicy
        setPolicy(newPolicy)
        // 승격에는 activate가 따라와야 한다: 메뉴바에서 연 설정 창은 앱이 활성화되지 않은
        // 채로 뜨므로 정책만 올리면 다른 앱 뒤에 깔린 채 Dock 아이콘만 생긴다 (리로드 실패
        // 알림이 `activate`를 부르는 것과 같은 이유). 강등에는 붙이지 않는다 — 포커스는
        // 다음 앱으로 넘어가야 한다. 최전면 캐시 자기-오염은 무해하다: 실제로 최전면이 된
        // 상황이라 `NSWorkspace` 알림이 어차피 같은 값을 넣는다.
        if newPolicy == .regular { activate() }
    }
}

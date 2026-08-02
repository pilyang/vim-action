//
//  VimActionApp.swift
//  VimAction
//
//  Created by 양재필 on 7/12/26.
//

import AppKit
import SwiftUI
import VimActionConfig

@main
struct VimActionApp: App {
    @State private var appState: AppState

    /// MenuBarExtra 라벨의 `.onAppear`는 렌더 타이밍에 좌우되고 Settings 씬은 열 때만
    /// 생성되므로, 앱 시작 부트스트랩은 `App.init`이 결정적 훅이다.
    init() {
        let state = AppState()
        state.bootstrap()
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            @Bindable var eventTap = appState.eventTap
            Toggle("Enable Vim Keybindings", isOn: $eventTap.isInterceptionEnabled)
            Divider()
            // 설정 상태 상시 노출 — 시작 시 로드 에러도 여기서 보인다 (`ConfigError`는
            // 로그로 부족하다는 계약: config.yaml 통째 무효 = off 앱이 전부 켜진 상태).
            Text(
                configStatusText(
                    profileCount: appState.configStore.resolvedProfiles.count,
                    errors: appState.configStore.errors))
            Button("Reload Config") {
                guard !appState.reloadConfig() else { return }
                // 실패만 알림으로 — 클릭 직후 메뉴가 닫히므로 "클릭한 자리에서 가시화"는
                // 알림이 맡는다 (20260802_config-reload-manual-menubar-trigger).
                // LSUIElement라 activate 없이는 알림이 다른 창 뒤로 깔린다. activate가
                // 최전면 캐시를 자기 자신으로 잠시 오염시키지만 다음 앱 전환에 자가 치유되고
                // 게이트에는 무해하다(자기 bundle id는 disable 대상이 아님) — non-self 캐시는
                // PR-B2의 실기기 확인 항목.
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Config reload failed"
                alert.informativeText = appState.configStore.errors
                    .map { "\(($0.file as NSString).lastPathComponent): \($0.message)" }
                    .joined(separator: "\n\n")
                    + "\n\nThe previous valid configuration is still in effect."
                alert.runModal()
            }
            Divider()
            SettingsLink {
                Text("Preferences…")
            }
            Divider()
            Button("Quit VimAction") {
                NSApp.terminate(nil)
            }
        } label: {
            // 시각적으로는 아이콘만, VoiceOver에는 안정적인 앱 이름 + 현재 상태를 남긴다.
            // 글리프는 전부 NSImage 경로(menuBarImage)로 렌더한다 — Visual-line의
            // 커스텀 "Vl" 글리프와 SF Symbol들이 같은 심볼 설정을 공유해 크기가 통일된다.
            Label {
                Text(appState.menuBarAccessibilityLabel)
            } icon: {
                Image(nsImage: appState.menuBarImage)
            }
            .labelStyle(.iconOnly)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}

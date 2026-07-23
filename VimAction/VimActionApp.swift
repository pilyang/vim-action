//
//  VimActionApp.swift
//  VimAction
//
//  Created by 양재필 on 7/12/26.
//

import AppKit
import SwiftUI

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

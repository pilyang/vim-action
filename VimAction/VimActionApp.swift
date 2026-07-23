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
            // Visual-line은 커스텀 "Vl" 템플릿 글리프로 wise를 구분한다 — SF Symbols
            // 글자 사각형은 1글자뿐이고, 라벨 합성 밑줄은 메뉴바 템플릿 렌더에서 뭉개진다.
            Label {
                Text(appState.menuBarAccessibilityLabel)
            } icon: {
                if appState.menuBarShowsVisualLineGlyph {
                    Image(nsImage: .visualLineMenuBarGlyph)
                } else {
                    Image(systemName: appState.menuBarGlyph)
                }
            }
            .labelStyle(.iconOnly)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}

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
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            SettingsLink {
                Text("Preferences…")
            }
            Divider()
            Button("Quit VimAction") {
                NSApp.terminate(nil)
            }
        } label: {
            // 시각적으로는 아이콘만, VoiceOver에는 안정적인 앱 이름 + 현재 모드를 남긴다.
            Label("VimAction — \(appState.mode.displayName) 모드", systemImage: appState.mode.menuBarGlyph)
                .labelStyle(.iconOnly)
        }

        Settings {
            SettingsView()
        }
    }
}

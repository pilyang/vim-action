//
//  VimActionApp.swift
//  VimAction
//
//  Created by 양재필 on 7/12/26.
//

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
            Image(systemName: appState.mode.menuBarGlyph)
        }

        Settings {
            SettingsView()
        }
    }
}

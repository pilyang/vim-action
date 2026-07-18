//
//  SettingsView.swift
//  VimAction
//

import SwiftUI

/// 설정 창. 권한 온보딩 섹션 + 앱 정보. 키맵 설정은 다음 마일스톤에서 채운다.
struct SettingsView: View {
    let appState: AppState

    /// Normal 탈출 옵션 — 값의 SSOT는 UserDefaults이고, 엔진 반영은 `onChange`의
    /// `updateConfiguration` 주입 (EventTapController는 init에서 같은 키를 읽는다).
    @AppStorage(PreferenceKeys.normalModeEscapeEnabled)
    private var normalModeEscapeEnabled = PreferenceKeys.normalModeEscapeEnabledDefault

    /// 번들 Info.plist의 실제 버전(`CFBundleShortVersionString` = MARKETING_VERSION). 하드코딩 드리프트 방지.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("VimAction") {
                LabeledContent("Version", value: appVersion)
            }
            Section("Behavior") {
                Toggle("Exit Normal mode on ⌘/⌥ shortcuts", isOn: $normalModeEscapeEnabled)
                Text("After a Command or Option shortcut (Spotlight, Raycast, …), VimAction returns to Insert mode so your next typing isn't blocked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if appState.permissionMonitor.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Required")
                            .foregroundStyle(.secondary)
                    }
                }
                if !appState.permissionMonitor.isTrusted {
                    Button("Request Permission…") {
                        appState.permissionMonitor.requestWithPrompt()
                    }
                    Button("Open System Settings") {
                        appState.permissionMonitor.openSystemSettings()
                    }
                    Text("Once granted, VimAction detects it automatically and activates without relaunching.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Event Tap", value: appState.eventTap.status.displayName)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
        .onChange(of: normalModeEscapeEnabled) { _, newValue in
            // 알려진 한계: 엔진 반영 경로는 이 onChange와 컨트롤러 init 두 곳뿐이라,
            // 설정 창 밖에서 키를 바꾸면(외부 defaults write 등) 다음 실행까지 엔진에
            // 반영되지 않는다. 이 키의 writer를 추가한다면 updateConfiguration 호출까지 챙길 것.
            appState.eventTap.updateConfiguration(
                makeConfiguration(normalModeEscapeEnabled: newValue))
        }
    }
}

/// 설정 창에 표시할 탭 상태 문구 — macOS 표현은 앱 레이어에만 둔다.
private extension EventTapController.Status {
    var displayName: String {
        switch self {
        case .waitingForPermission: "Waiting for Permission"
        case .running: "Running"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }
}

#Preview {
    // 프리뷰에서는 bootstrap()을 호출하지 않는다 — 탭 설치/폴링 부작용 방지.
    SettingsView(appState: AppState())
}

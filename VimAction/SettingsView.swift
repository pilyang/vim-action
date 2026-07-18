//
//  SettingsView.swift
//  VimAction
//

import SwiftUI

/// 설정 창. 권한 온보딩 섹션 + 앱 정보. 키맵 설정은 다음 마일스톤에서 채운다.
struct SettingsView: View {
    let appState: AppState

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
                // 값·엔진 반영 모두 컨트롤러 프로퍼티(didSet)가 책임진다 — 가로채기 토글과 동일 모델.
                Toggle("Exit Normal mode on ⌘/⌥ shortcuts", isOn: Binding(
                    get: { appState.eventTap.isNormalModeEscapeEnabled },
                    set: { appState.eventTap.isNormalModeEscapeEnabled = $0 }
                ))
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

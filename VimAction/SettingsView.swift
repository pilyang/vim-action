//
//  SettingsView.swift
//  VimAction
//

import SwiftUI
import VimActionConfig

/// 설정 창. 권한 온보딩 섹션 + 앱 정보. 키맵 설정은 다음 마일스톤에서 채운다.
struct SettingsView: View {
    let appState: AppState

    /// 번들 Info.plist의 실제 버전(`CFBundleShortVersionString` = MARKETING_VERSION). 하드코딩 드리프트 방지.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        @Bindable var eventTap = appState.eventTap
        Form {
            Section("VimAction") {
                LabeledContent("Version", value: appVersion)
            }
            Section("Behavior") {
                // 값·엔진 반영 모두 컨트롤러 프로퍼티(didSet)가 책임진다 — 가로채기 토글과 동일 모델.
                Toggle("Exit Normal mode on ⌘/⌥ shortcuts", isOn: $eventTap.isNormalModeEscapeEnabled)
                Text("After a Command or Option shortcut (Spotlight, Raycast, …), VimAction returns to Insert mode so your next typing isn't blocked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // 읽기 전용이 계약이다 — UI는 YAML을 쓰지 않는다 (Yams가 주석을 보존하지 못해
            // UI 쓰기는 사용자의 주석·서식을 파괴한다, 20260801_settings-ui-read-only-yaml).
            Section("Configuration") {
                LabeledContent(
                    "Status",
                    value: configStatusText(
                        profileCount: appState.configStore.resolvedProfiles.count,
                        errors: appState.configStore.errors))
                ForEach(appState.configStore.errors, id: \.self) { error in
                    Text("\((error.file as NSString).lastPathComponent) — \(error.message)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !appState.configStore.warnings.isEmpty {
                    Text(
                        "\(appState.configStore.warnings.count) invalid entries ignored — details in log (category \"config\")."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                LabeledContent(
                    "Disabled Apps", value: disabledAppsText(appState.configStore.disabledBundleIDs))
                LabeledContent(
                    "Profiles", value: profilesText(appState.configStore.appliedSnapshot.profiles))
                Button("Open config.yaml") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: ConfigPaths.configPath))
                }
                Button("Open Config Folder") {
                    NSWorkspace.shared.selectFile(
                        nil, inFileViewerRootedAtPath: ConfigPaths.directory)
                }
                Text("Edit the files directly, then use \"Reload Config\" in the menu bar to apply.")
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
                LabeledContent(
                    "Event Tap",
                    value: eventTapStatusText(
                        status: eventTap.status, interceptionEnabled: eventTap.isInterceptionEnabled))
                LabeledContent(
                    "Kill Switch",
                    value: killSwitchStatusText(
                        installation: appState.killSwitch.installation,
                        isTrusted: appState.permissionMonitor.isTrusted))
                Text(
                    "Press ⌃⌥⌘⎋ (Control-Option-Command-Escape) to turn interception off — it works even if VimAction stops responding. Turn it back on from the menu bar."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 560)
    }
}

/// "Event Tap" 행 문구를 (설치 상태, 가로채기 토글)에서 파생한다. `.running`은 탭
/// 설치·헬스가 정상이라는 뜻일 뿐 가로채기 여부와 무관하므로, off일 땐 "Disabled"로
/// 표시해야 실제 상태와 어긋나지 않는다 (AppState.menuBarGlyph의 파생과 같은 우선순위).
/// status를 인자로 받는 순수 함수라 단위 테스트가 전 분기를 커버할 수 있다.
func eventTapStatusText(status: EventTapController.Status, interceptionEnabled: Bool) -> String {
    switch status {
    // .secureInput도 토글 off면 "Disabled" — 사용자가 끈 상태가 OS 일시 억제 표시보다
    // 우선한다 (AppState.menuBarGlyph와 같은 우선순위).
    case .running, .secureInput:
        interceptionEnabled ? status.displayName : "Disabled"
    default: status.displayName
    }
}

/// "Disabled Apps" 행 문구 — 순수 함수라 단위 테스트가 전 분기를 커버한다
/// (`eventTapStatusText`와 같은 패턴).
func disabledAppsText(_ bundleIDs: Set<String>) -> String {
    bundleIDs.isEmpty ? "None" : bundleIDs.sorted().joined(separator: "\n")
}

/// "Profiles" 행 문구 — bundle id에 프로파일 표시 이름을 병기한다.
func profilesText(_ profiles: [String: AppProfile]) -> String {
    guard !profiles.isEmpty else { return "None" }
    return profiles.sorted { $0.key < $1.key }
        .map { id, profile in profile.name.map { "\(id) (\($0))" } ?? id }
        .joined(separator: "\n")
}

/// "Kill Switch" 행 문구 — 안전장치 탭이 어느 지점에 설치됐는지 보여준다. 안전장치가
/// 조용히 부재하는 것이 가장 위험한 실패 모드라, 로그를 보지 않고도 알 수 있어야 한다.
/// `Session (fallback)`은 HID 생성이 거부된 상태로 우선순위가 밀릴 수 있음을 뜻한다.
/// 미설치는 권한 대기와 실제 실패를 구분한다 — `eventTapStatusText`와 같은 파생 패턴이다.
func killSwitchStatusText(installation: KillSwitchTap.Installation, isTrusted: Bool) -> String {
    switch installation {
    case .hid: "Active (HID)"
    case .session: "Active (Session fallback)"
    case .failed: "Failed (tap inactive)"
    case .notInstalled: isTrusted ? "Unavailable" : "Waiting for Permission"
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
        case .secureInput: "Secure Input"
        }
    }
}

#Preview {
    // 프리뷰에서는 bootstrap()을 호출하지 않는다 — 탭 설치/폴링 부작용 방지.
    SettingsView(appState: AppState())
}

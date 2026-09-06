//
//  SettingsView.swift
//  VimAction
//

import Sparkle
import SwiftUI
import VimActionConfig

/// 설정 창 탭. 성격이 다른 세 가지를 분리한다 — 자주 보는 것(앱별 설정 접근), 한 번 보고 마는
/// 것(권한), 참조용(버전·링크).
private enum SettingsTab: Hashable {
    case general, apps, about
}

/// 설정 창. 탭 전환만 하고 내용은 각 탭이 소유한다.
struct SettingsView: View {
    let appState: AppState

    /// 기본은 Apps — 실사용에서 다시 여는 이유가 거의 항상 설정 파일 상태 확인이다.
    /// 탭 **순서**는 macOS 관례대로 General이 먼저다.
    @State private var selection: SettingsTab

    /// 런치 온보딩으로 열리는 첫 창만은 General이어야 한다 — 그 창을 띄운 목적이 권한 블록을
    /// 보여주는 것이기 때문이다. 플래그는 `onAppear`에서야 내려가므로 여기서 아직 참이다.
    init(appState: AppState) {
        self.appState = appState
        _selection = State(initialValue: appState.needsOnboardingPresentation ? .general : .apps)
    }

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppsTab(appState: appState)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.apps)
            AboutTab(updater: appState.updater)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        // 탭마다 내용 높이가 다르지만 창은 한 크기로 고정한다 — 탭을 옮길 때마다 창이
        // 리사이즈되는 편보다 자리가 안 움직이는 편이 낫다. 넘치는 내용(Diagnostics를
        // 펼친 General)은 그룹 Form 자체가 스크롤한다.
        .frame(width: 460, height: 560)
        // 설정 창이 열려 있는 동안만 Dock 아이콘을 노출한다. `onAppear`가 유일하게
        // 신뢰할 수 있는 열림 신호인 이유(창이 key가 되지 않는다)와 닫힘을 창 알림이
        // 맡는 이유는 `DockIconController`에 있다. 닫힘 쪽 짝은 `onDisappear`가 아니다.
        // 닫힘 판정의 기준 창은 아래 reader가 별도로 넘긴다 — `onAppear` 시점에는 창이
        // 아직 `isVisible`이 아닐 수 있어 여기서 열거로 잡으면 빈손이 난다.
        //
        // **TabView 루트여야 한다** — 탭 하나 안에 두면 다른 탭이 기본으로 열릴 때 훅이
        // 뜨지 않아 창이 열려도 Dock 아이콘이 안 나온다. 재호출은 무해하다(창 전달은
        // 대입뿐이고, 정책 재적용은 `apply` 동등성 가드가 막는다).
        .background(SettingsWindowReader { appState.settingsWindowDidConnect($0) })
        .onAppear { appState.settingsWindowDidAppear() }
    }
}

/// 설정 창 전달 통로 — 뷰가 창에 붙는 순간(`viewDidMoveToWindow`) 자기 `NSWindow`를
/// 넘긴다. 뷰가 설정 창 안에 있으므로 넘어오는 창이 곧 설정 창이다 — `NSApp.windows`를
/// 술어로 뒤지는 방식과 달리 추정이 없고, `onAppear`와 달리 창 상태 타이밍에도 안 걸린다.
/// 창에서 떨어질 때(`window == nil`)는 아무것도 하지 않는다 — 닫힘 처리는
/// `NSWindow.willCloseNotification`의 몫이다.
private struct SettingsWindowReader: NSViewRepresentable {
    let onConnect: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onConnect = onConnect
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onConnect = onConnect
    }

    final class ReaderView: NSView {
        var onConnect: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onConnect?(window) }
        }
    }
}

/// 권한 상태 + 동작 옵션 + (접힌) 진단.
private struct GeneralTab: View {
    let appState: AppState

    var body: some View {
        @Bindable var eventTap = appState.eventTap
        @Bindable var modeIndicator = appState.modeIndicator
        Form {
            // 미허용이면 최상단 — 이 상태에서는 다른 무엇보다 이것부터 해결해야 한다.
            // 허용된 뒤에는 한 줄짜리 확인 표시라 Behavior 아래로 내려간다.
            if !appState.permissionMonitor.isTrusted { permissionSection }
            Section("Behavior") {
                // 저장된 설정이 아니라 시스템 등록 상태를 비추는 토글이라 `@Bindable`이 아니다 —
                // 쓰기는 register/unregister 시도이고, 표시값은 그 뒤 재조회한 status가 정한다
                // (실패하면 여기서 토글이 그대로 되돌아온다).
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { appState.launchAtLogin.isEnabled },
                        set: { appState.launchAtLogin.setEnabled($0) }))
                if let message = appState.launchAtLogin.failureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    Text("VimAction starts in the background when you log in — menu bar only, no window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // 값·엔진 반영 모두 컨트롤러 프로퍼티(didSet)가 책임진다 — 가로채기 토글과 동일 모델.
                Toggle("Exit Normal mode on ⌘/⌥ shortcuts", isOn: $eventTap.isNormalModeEscapeEnabled)
                Text(
                    "After a Command or Option shortcut (Spotlight, Raycast, …), VimAction returns to Insert mode so your next typing isn't blocked. When off, those shortcuts still pass through to the app — you just stay in Normal mode."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                // 값·영속·표시 반영 모두 컨트롤러 프로퍼티(didSet)가 책임진다 — 위 토글과 동일 모델.
                Toggle("Show on-screen mode indicator", isOn: $modeIndicator.isEnabled)
                Text(
                    "A label appears next to the focused text field when the mode changes, and a small badge stays while you're in Normal or Visual mode."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section("Updates") {
                UpdaterSettingsToggle(updater: appState.updater)
                Text("VimAction periodically checks GitHub for new versions and always asks before installing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if appState.permissionMonitor.isTrusted { permissionSection }
            Section {
                // 정상 동작 중에는 볼 이유가 없고, 무언가 이상할 때만 필요한 정보다.
                DisclosureGroup("Diagnostics") {
                    LabeledContent(
                        "Event Tap",
                        value: eventTapStatusText(
                            status: eventTap.status,
                            interceptionEnabled: eventTap.isInterceptionEnabled))
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
        }
        .formStyle(.grouped)
    }
}

private extension GeneralTab {
    /// 허용 전/후 두 자리에서 같은 섹션을 쓴다 — 위치만 다르고 내용은 하나다.
    @ViewBuilder var permissionSection: some View {
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
        }
    }
}

/// 설정 파일 상태 — **읽기 전용이다.** 설정 편집은 파일이 소유한다. UI가 쓰는 것은 메뉴바의
/// 앱별 토글 하나뿐이고, 그마저도 재직렬화가 아니라 그 앱의 줄만 고치는 라인 편집이다
/// (20260809_config-yaml-line-edit-writes).
private struct AppsTab: View {
    let appState: AppState

    var body: some View {
        Form {
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
                LabeledContent("Disabled Apps") {
                    ScrollingValueList(
                        text: disabledAppsText(appState.configStore.disabledBundleIDs))
                }
                LabeledContent("Profiles") {
                    ScrollingValueList(
                        text: profilesText(appState.configStore.appliedSnapshot.profiles))
                }
                Button("Open config.yaml") { appState.openConfigFile() }
                Button("Open Config Folder") {
                    NSWorkspace.shared.selectFile(
                        nil, inFileViewerRootedAtPath: ConfigPaths.directory)
                }
                Text("Edit the files directly, then use \"Reload Config\" in the menu bar to apply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 버전 + 업데이트 확인 + 외부 링크.
private struct AboutTab: View {
    let updater: SPUUpdater

    /// 번들 Info.plist의 실제 버전(`CFBundleShortVersionString` = MARKETING_VERSION). 하드코딩 드리프트 방지.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("VimAction") {
                LabeledContent("Version", value: appVersion)
                CheckForUpdatesView(updater: updater)
            }
            Section("Links") {
                Link("GitHub Repository", destination: AboutLinks.repository)
                Link("Report an Issue", destination: AboutLinks.issues)
                Link("Keybindings Reference", destination: AboutLinks.keybindings)
            }
        }
        .formStyle(.grouped)
    }
}

/// 리터럴 URL 상수 — 여기서만 만들어지므로 항상 유효하다 (`NSImage.menuBarSymbol`과 같은 근거).
private enum AboutLinks {
    static let repository = URL(string: "https://github.com/pilyang/vim-action")!
    static let issues = URL(string: "https://github.com/pilyang/vim-action/issues")!
    static let keybindings = URL(
        string: "https://github.com/pilyang/vim-action/blob/main/docs/KEYBINDINGS.md")!
}

/// "Event Tap" 행 문구를 (설치 상태, 가로채기 토글)에서 파생한다. `.running`은 탭
/// 설치·헬스가 정상이라는 뜻일 뿐 가로채기 여부와 무관하므로, off일 땐 "Disabled"로
/// 표시해야 실제 상태와 어긋나지 않는다 (`MenuBarIndicator.resolve`와 같은 우선순위).
/// status를 인자로 받는 순수 함수라 단위 테스트가 전 분기를 커버할 수 있다.
///
/// **앱별 disabled는 여기 들어오지 않는다** — 이 행은 탭 설치·헬스라는 전역 상태를 말하고,
/// 앱별 off는 Apps 탭의 off 앱 목록과 메뉴바 글리프가 보여준다.
func eventTapStatusText(status: EventTapController.Status, interceptionEnabled: Bool) -> String {
    switch status {
    // .secureInput도 토글 off면 "Disabled" — 사용자가 끈 상태가 OS 일시 억제 표시보다
    // 우선한다 (`MenuBarIndicator.resolve`와 같은 우선순위).
    case .running, .secureInput:
        interceptionEnabled ? status.displayName : "Disabled"
    default: status.displayName
    }
}

/// 항목 수만큼 세로로 자라는 값 행(disable 앱 목록·프로파일 목록)을 앞 몇 줄 높이로
/// 묶고 나머지는 스크롤시킨다. 묶지 않으면 행 하나가 섹션 전체를 밀어낸다.
///
/// 높이를 **숨긴 앞줄 템플릿으로** 잡는 이유는 둘 다 실측 결과다: 그룹 Form 행 안에서
/// `ScrollView`에 건 `.frame(maxHeight:)`는 클램프되지 않아 목록이 그대로 다 나오고,
/// pt 상수로 박자니 SwiftUI `Text`의 줄 높이(16pt)가 같은 폰트의 NSFont 메트릭(19pt)과
/// 달라 줄 수가 어긋난다. 같은 폰트로 렌더한 앞 N줄이 SwiftUI 기준의 정확한 자다.
private struct ScrollingValueList: View {
    let text: String

    private static let maxVisibleRows = 5

    var body: some View {
        Text(template)
            .hidden()
            .overlay {
                ScrollView {
                    Text(text).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .foregroundStyle(.secondary)
    }

    /// 실제 앞 N줄 — 줄 수가 그보다 적으면 그만큼만 차지한다(빈 자리를 남기지 않는다).
    private var template: String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(Self.maxVisibleRows)
            .joined(separator: "\n")
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

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
            // 미허용은 **가장 위**에 온다 — 권한이 없으면 아래 마스터 토글부터 무의미하다.
            // `isTrusted`가 @Observable이라 부여 순간(1초 폴링) 이 블록이 사라진다.
            if !appState.permissionMonitor.isTrusted {
                Text("⚠ Accessibility permission required")
                Button("Grant Permission…") { appState.permissionMonitor.requestWithPrompt() }
                // 프롬프트는 TCC 상태당 1회만 뜬다 — 두 번째 클릭이 조용한 무동작이 되지
                // 않도록 항상 열리는 경로를 나란히 둔다 (설정 창 Permissions와 같은 짝).
                Button("Open System Settings") { appState.permissionMonitor.openSystemSettings() }
                Divider()
            }
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
                // 최전면 캐시를 자기 자신으로 덮지만, 아래 편의 기능이 겨누는 것은
                // `FrontmostAppGate`의 비자신 캐시라 대상 앱은 그대로 유지된다.
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
            Button("Open config.yaml") { appState.openConfigFile() }
            Divider()
            // 최전면 앱 편의 기능 — 설정의 모든 진입점이 bundle id인데 그것을 조회하기가
            // 어렵다는 마찰을 없앤다 (20260802_menubar-frontmost-app-conveniences).
            // 대상은 비자신 캐시라 메뉴를 여는 행위가 자기 자신을 최전면으로 만들어도 유지된다.
            if let bundleID = appState.frontmostTargetBundleID {
                Text("Frontmost: \(bundleID)")
                // 그 앱의 실행 전략 판정 — auto 기본화 이후 "이 앱 지금 뭘로 돌아?"의 최소
                // 진단 수단이다. 판정 캐시·게이트가 @Observable이라 판정 전이·앱 전환이
                // 메뉴가 열린 중에도 이 줄을 갱신한다
                // (20260813_auto-trusted-runtime-demotion-and-observability).
                Text(appState.strategyStatusLine(for: bundleID))
                // 실사용의 주력 플로우 — 이것 없이는 "이 앱에서 Vim 끄기"가 에디터 왕복
                // 7단계다. 상태의 출처는 계속 config.yaml 하나이고(체크마크는 로드된
                // 스냅샷의 파생), 클릭은 그 파일의 그 줄만 고친다.
                //
                // **끄는 쪽이 체크된다** — 기본이 on이고 사용자가 하는 일은 쓰지 않을 앱을
                // 골라 끄는 것이라, 체크마크가 "이 앱은 내가 손대 둔 앱"을 뜻해야 목록을
                // 훑을 때 읽힌다. config.yaml의 `apps:`도 같은 방향이다(적힌 앱 = 예외).
                Toggle(
                    "Disable for This App",
                    isOn: Binding(
                        get: { appState.configStore.disabledBundleIDs.contains(bundleID) },
                        set: { appState.setAppEnabled(bundleID, enabled: !$0) })
                )
                // 에러 상태에서는 스토어가 쓰기를 거부한다 — 클릭 전에 그것을 보여준다.
                .disabled(!appState.configStore.errors.isEmpty)
                Button("Copy Bundle ID") { Clipboard.write(bundleID) }
                // 제목이 사실과 일치하도록 파일 존재를 매번 묻는다 — 메뉴 본문 평가마다
                // fileExists 1회이고, 그 평가는 앱 전환 등 관찰 무효화 때만 돈다.
                Button(appState.hasProfile(for: bundleID) ? "Open Profile" : "Create Profile") {
                    appState.openProfile(for: bundleID)
                }
            } else {
                Text("Frontmost: unknown")
            }
            Divider()
            SettingsLink {
                Text("Preferences…")
            }
            CheckForUpdatesView(updater: appState.updater)
            Divider()
            Button("Quit VimAction") {
                NSApp.terminate(nil)
            }
        } label: {
            MenuBarLabel(appState: appState)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}

/// 메뉴바 라벨 — 아이콘 렌더 + **런치 시 온보딩 오픈의 유일한 호출 지점**.
///
/// `openSettings`는 SwiftUI 환경 액션이라 실제로 렌더된 뷰 안에서만 동작한다(`App`이나
/// `AppState`에서는 부를 수 없다). `MenuBarExtra`의 **메뉴 콘텐츠**는 사용자가 메뉴를 열기
/// 전까지 생성조차 되지 않아 훅이 뜨지 않지만, **라벨은 글리프를 그려야 하므로 런치 때
/// 렌더된다** — 그래서 이 자리가 유일하게 쓸 수 있는 뷰 컨텍스트다.
///
/// (macOS 13까지 쓰이던 `NSApp.sendAction(Selector(("showSettingsWindow:")))`는 macOS 14부터
/// 무동작이라 대안이 아니다.)
private struct MenuBarLabel: View {
    let appState: AppState

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // 시각적으로는 아이콘만, VoiceOver에는 안정적인 앱 이름 + 현재 상태를 남긴다.
        // 글리프는 전부 NSImage 경로(menuBarImage)로 렌더한다 — Visual-line의
        // 커스텀 "Vl" 글리프와 SF Symbol들이 같은 심볼 설정을 공유해 크기가 통일된다.
        Label {
            Text(appState.menuBarAccessibilityLabel)
        } icon: {
            Image(nsImage: appState.menuBarImage)
        }
        .labelStyle(.iconOnly)
        .task {
            guard appState.needsOnboardingPresentation else { return }
            // 뷰가 트리에 붙은 **다음 틱**이어야 한다. 같은 틱에 부르면 아직 연결된 씬이
            // 없어 조용한 무동작이 된다.
            await Task.yield()
            // 플래그는 여기서 내리지 않는다 — `SettingsView`가 이 값을 읽어 열릴 탭을
            // 고르고, 창이 실제로 뜬 뒤(`onAppear`)에야 내려간다. 오픈이 조용히 실패하면
            // 플래그가 남아 다음 실행에 다시 시도한다(성공한 적이 없으므로 그게 맞다).
            openSettings()
        }
    }
}

//
//  AppState.swift
//  VimAction
//

import AppKit
import Foundation
import Observation
import os
import Sparkle
import VimEngine

/// 앱 셸이 관찰하는 UI 상태와 전역 컴포넌트(권한 모니터, 이벤트 탭, 설정 스토어)의 소유자.
@Observable
final class AppState {
    let permissionMonitor = AccessibilityPermissionMonitor()
    let eventTap: EventTapController
    /// 안전장치 킬스위치 탭 — 메인 탭과 생명주기를 공유하지 않는다. 발동 효과는 여기서
    /// 주입한다: 킬 탭은 무엇이 꺼지는지 모르고, off 의미론은 전부 컨트롤러가 소유한다.
    let killSwitch: KillSwitchTap
    /// `~/.config/vim-action` 설정의 소유자. init은 IO를 하지 않는다 — 실제 시딩·로드는
    /// bootstrap(XCTest 가드 뒤)에서만.
    let configStore: ConfigStore
    /// 게이트를 AppState가 직접 만들어 컨트롤러에 주입한다 — 설정 로드·리로드 때
    /// disable 집합을 푸시할 핸들이 필요해서다 (컨트롤러는 설정 계층을 모른다).
    private let frontmostAppGate: FrontmostAppGate
    /// 설정 창이 열린 동안만 Dock 아이콘을 노출한다. 열림은 `SettingsView.onAppear`가
    /// 알려주고 닫힘은 컨트롤러가 창 알림으로 스스로 잡으므로, `bootstrap`이 아니라 여기
    /// 생성 시점이 배선의 전부다.
    let dockIcon = DockIconController.forCurrentEnvironment()
    /// 로그인 시 자동 시작 토글의 소유자. 상태를 저장하지 않고 시스템 등록 상태를 그대로
    /// 비추므로, 배선은 생성과 창 열림 훅의 `refresh()`가 전부다 (bootstrap에 할 일 없음).
    let launchAtLogin = LaunchAtLoginController()
    /// Sparkle 자동 업데이트. 생성만 하고 시동하지 않는다(`startingUpdater: false`) —
    /// 시동은 bootstrap(XCTest 가드 뒤)에서만. 테스트·프리뷰가 업데이트 확인 스케줄러를
    /// 돌리거나 네트워크로 appcast를 조회하면 안 된다 (init은 IO 없음 관례와 동일).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    /// 메뉴바·설정 UI가 쓰는 업데이트 핸들 — 수동 확인 트리거와 자동 확인 설정의 진입점.
    var updater: SPUUpdater { updaterController.updater }

    /// 런치 시 설정 창을 한 번 밀어 올려야 하는가 — 메뉴바 라벨(`MenuBarLabel`)이 소비한다.
    /// `openSettings`는 SwiftUI 환경 액션이라 뷰 밖에서 호출할 수 없어서, `bootstrap()`은
    /// 신호만 세우고 실제 오픈은 렌더된 뷰가 맡는다.
    private(set) var needsOnboardingPresentation = false

    init() {
        let gate = FrontmostAppGate.forCurrentEnvironment()
        let store = ConfigStore()
        frontmostAppGate = gate
        configStore = store
        let eventTap = EventTapController(
            frontmostAppGate: gate,
            profileProvider: { [weak store] bundleID in
                // 스토어가 사라진 뒤(= 앱 해체) 오는 조회다 — "프로파일 부재"가 아니라 "설정
                // 계층 없음"이라 번들 기본 전략이 아니라 `.empty`가 맞다.
                store?.resolvedProfile(for: bundleID) ?? .empty
            })
        self.eventTap = eventTap
        killSwitch = KillSwitchTap { eventTap.triggerKillSwitch() }
    }

    /// 앱 시작 시 1회: 설정 시딩·로드 → 권한 확인 → 탭 설치 시도, 미허용이면 부여 감지 폴링 시작.
    func bootstrap() {
        // TEST_HOST로 launch된 단위 테스트 실행 중에는 시동하지 않는다 —
        // 테스트가 라이브 이벤트 탭을 설치하거나 권한 폴링을 돌리면 안 되고,
        // 설정 시딩이 실제 `~/.config`를 만지면 안 된다.
        if isRunningUnderXCTest() {
            // 이 변수가 일반 launch에 새어 들어오면 앱이 통째로 비활성이 되므로 흔적을 남긴다.
            Logger.eventTap.notice("XCTest 환경변수 감지 — bootstrap 생략 (탭 설치·권한 폴링 비활성)")
            return
        }
        // 설정이 탭 설치보다 **먼저다** — 게이트의 disable 집합이 빈 채로 탭이 서면
        // TCC가 이미 부여된 재실행에서 disable 앱이 잠깐 게이트 없이 노출된다.
        configStore.seedAndLoad()
        frontmostAppGate.update(disabledBundleIDs: configStore.disabledBundleIDs)
        // 메인 탭 설치 성공마다 킬 탭 설치를 잇는다 — 순서 계약(킬 탭이 나중에
        // head-insert)이 호출 순서가 아니라 구조로 지켜지고, bootstrap 시점에 킬 탭
        // 생성이 실패했던 경우의 유일한 재시도 경로가 된다. 킬 탭 설치는 멱등이다.
        eventTap.onTapInstalled = { [killSwitch] in
            killSwitch.startIfPermitted()
        }
        permissionMonitor.onGranted = { [eventTap, killSwitch] in
            // 순서가 계약이다 — KillSwitchTap.startIfPermitted 주석 참고 (세션 폴백 시
            // 나중에 head-insert된 쪽이 먼저 받으므로 킬 탭이 뒤에 와야 한다).
            // 메인 탭 설치가 성공하면 위 훅이 이미 킬 탭을 세우고, 아래 호출은 메인 탭
            // 설치가 실패한 경우에도 킬 탭만은 세우기 위한 것이다 (둘 다 멱등).
            eventTap.startIfPermitted()
            killSwitch.startIfPermitted()
        }
        permissionMonitor.refresh()
        // 미허용이어도 항상 호출한다 — "설치 보류" 로그가 launch 시 관측 가능해야 한다.
        // 위 onGranted와 같은 순서 계약을 따른다.
        eventTap.startIfPermitted()
        killSwitch.startIfPermitted()
        if !permissionMonitor.isTrusted {
            permissionMonitor.startPollingUntilGranted()
        }
        // 업데이트 확인 시동 — 입력 파이프라인과 무관한 부수 기능이라 핵심(설정·탭) 뒤에 온다.
        // Info.plist의 SUFeedURL·SUPublicEDKey를 읽고, 자동 확인이 동의된 상태면 스케줄러가 돈다.
        updaterController.startUpdater()
        needsOnboardingPresentation = shouldPresentOnboarding(
            isTrusted: permissionMonitor.isTrusted, defaults: .standard)
    }

    /// 설정 창이 화면에 올라왔다 — 그것이 온보딩이었다면 여기서 마무리한다. 값이 아니라 키의
    /// **존재**가 판정 기준이므로(`shouldPresentOnboarding`) 여기서 반드시 써야 한다.
    ///
    /// 오픈을 지시한 자리가 아니라 **창이 실제로 뜬 자리**에서 내린다 — 그 사이에
    /// `SettingsView`가 플래그를 읽어 열릴 탭을 고르고, 오픈이 조용히 실패하면 플래그가 남아
    /// 다음 실행에 다시 시도한다. 설정 창을 여는 모든 경로가 부르므로 멱등이어야 한다.
    func settingsWindowDidAppear() {
        dockIcon.settingsWindowDidAppear()
        // 로그인 항목은 사용자가 시스템 설정에서 통지 없이 끌 수 있다 — 창을 열 때마다
        // 다시 물어야 토글이 실제 상태와 어긋나지 않는다 (미러를 두지 않는 이유 그 자체).
        launchAtLogin.refresh()
        guard needsOnboardingPresentation else { return }
        needsOnboardingPresentation = false
        UserDefaults.standard.set(true, forKey: PreferenceKeys.didShowOnboarding)
    }

    /// 설정 뷰가 자기 창에 붙었다 — Dock 아이콘 닫힘 판정의 기준 창을 넘긴다
    /// (`SettingsWindowReader`가 부른다).
    func settingsWindowDidConnect(_ window: NSWindow) {
        dockIcon.settingsWindowDidConnect(window)
    }

    /// 메뉴 'Reload Config' 진입점 — 로드 결과를 게이트에 반영까지 해야 한 번의 리로드다.
    /// 반환 false = 파일 통째 에러 존재(직전 유효 설정 유지됨) — 호출자(메뉴)가 사용자에게
    /// 보인다. 프로파일 쪽은 푸시가 필요 없다 — 디스패치가 `configStore`를 매 키마다
    /// 조회한다 (`profileProvider`).
    func reloadConfig() -> Bool {
        let succeeded = configStore.reload()
        frontmostAppGate.update(disabledBundleIDs: configStore.disabledBundleIDs)
        return succeeded
    }

    /// 메뉴 편의 기능이 겨누는 앱 — 최전면 캐시가 아니라 **비자신 캐시**다. 메뉴를 여는
    /// 행위 자체가 VimAction을 최전면으로 만들 수 있어 `frontmostBundleID`는 쓸 수 없다.
    var frontmostTargetBundleID: String? { frontmostAppGate.lastNonSelfBundleID }

    /// 메뉴 항목 제목이 'Open Profile'인지 'Create Profile'인지.
    func hasProfile(for bundleID: String) -> Bool { configStore.hasProfile(for: bundleID) }

    /// 메뉴 '프로파일 열기' — 없으면 주석뿐인 scaffold를 만든 뒤 연다.
    /// 두 실패 모두 폴백이 있다: 클릭이 조용한 무동작이 되면 안 된다.
    func openProfile(for bundleID: String) {
        guard let path = configStore.prepareProfileFile(for: bundleID) else {
            // 생성 실패는 사용자가 알아야 한다 — 'Reload Config' 실패와 같은 형태로 알린다.
            warn(
                "Couldn't create the profile file",
                "VimAction could not write \(configStore.profilePath(for: bundleID)).\n\nCheck the folder's permissions — details are in the log (category \"config\")."
            )
            return
        }
        openFile(at: path)
    }

    /// 메뉴 'Enable for This App' — `config.yaml`의 그 앱 항목만 고치고 바로 반영한다.
    ///
    /// 쓸 수 없는 상황(에러 상태·안전하게 편집할 수 없는 파일·권한)에서는 **알림 + 파일 열기**로
    /// 폴백한다. 토글 클릭이 조용한 무동작이 되면 사용자는 앱이 고장 났다고 읽는다.
    func setAppEnabled(_ bundleID: String, enabled: Bool) {
        // 쓰기와 반영이 **둘 다** 성공해야 한 번의 변경이다 — 쓰고 나서 리로드가 실패하면
        // 체크마크는 그대로인데 파일만 바뀐 상태라, 그것도 사용자가 파일을 봐야 하는 경우다.
        if configStore.setAppEnabled(bundleID, enabled: enabled), reloadConfig() { return }
        warn(
            "Couldn't update config.yaml",
            "VimAction did not apply \"\(bundleID): \(enabled)\" — details are in the log (category \"config\").\n\nOpening \(ConfigPaths.configPath) so you can set it under \"apps:\" yourself, then use \"Reload Config\"."
        )
        openConfigFile()
    }

    /// 메뉴·Settings 공용 'config.yaml 열기'.
    func openConfigFile() {
        openFile(at: ConfigPaths.configPath)
    }

    /// .yaml에 기본 앱이 없으면 `open`이 조용히 실패한다 — 그때는 Finder로 짚어 준다.
    private func openFile(at path: String) {
        if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: ConfigPaths.directory)
        }
    }

    /// 사용자에게 보여야 하는 실패. LSUIElement라 `activate` 없이는 알림이 다른 창 뒤로 깔린다.
    private func warn(_ message: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    /// 메뉴바가 표시하는 상태 — 우선순위 사다리는 `MenuBarIndicator.resolve` 하나가
    /// 소유하고, 아래 셋은 그 결과의 파생일 뿐이다.
    ///
    /// 앱별 disable 여부는 **비자신 캐시 축**으로 묻는다 — 아이콘 클릭이 VimAction을
    /// 최전면으로 만들어도 표시가 흔들리지 않고 메뉴 체크마크와 항상 일치한다.
    var menuBarIndicator: MenuBarIndicator {
        .resolve(
            status: eventTap.status,
            isInterceptionEnabled: eventTap.isInterceptionEnabled,
            isTargetAppDisabled: frontmostAppGate.isTargetAppDisabled,
            mode: eventTap.mode)
    }

    /// 메뉴바 글리프 (PRD §7.7 최소 구현).
    var menuBarGlyph: String { menuBarIndicator.glyph }

    /// Visual-line일 때만 참 — 메뉴바 라벨이 커스텀 "Vl" 글리프로 wise를
    /// 구분한다 (fill 축은 "차단 여부"라 wise에 재사용할 수 없음).
    var menuBarShowsVisualLineGlyph: Bool { menuBarIndicator.showsVisualLineGlyph }

    /// 메뉴바 라벨이 그리는 최종 글리프 이미지. 모든 상태 글리프를 같은 심볼
    /// 설정으로 렌더해 크기를 통일한다 — SF Symbol은 SwiftUI 폰트 유래 크기,
    /// 커스텀 "Vl"은 고정 크기로 렌더 경로가 갈리면 크기가 어긋난다.
    var menuBarImage: NSImage {
        menuBarShowsVisualLineGlyph
            ? .visualLineMenuBarGlyph
            : .menuBarSymbol(named: menuBarGlyph)
    }

    /// VoiceOver 등 사람이 읽는 메뉴바 상태 문구.
    var menuBarAccessibilityLabel: String { menuBarIndicator.accessibilityLabel }
}

extension Mode {
    /// 메뉴바 아이템에 표시할 SF Symbol 이름. macOS 표현은 앱 레이어에만 둔다
    /// (엔진 `Mode`는 플랫폼을 모른다). fill은 "키 차단 여부" 축이다 — 차단
    /// 모드(Normal/Visual)는 fill, 통과 모드(Insert)는 미채움. Visual-line은
    /// 커스텀 "Vl" 템플릿 글리프(`NSImage.visualLineMenuBarGlyph`)가 대신 표시되며
    /// 여기 값은 폴백이다 (`AppState.menuBarShowsVisualLineGlyph`).
    var menuBarGlyph: String {
        switch self {
        case .normal: "n.square.fill"
        case .insert: "i.square"
        case .visualChar, .visualLine: "v.square.fill"
        }
    }

    /// 접근성 레이블 등 사람이 읽는 모드 이름.
    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .insert: "Insert"
        case .visualChar: "Visual"
        case .visualLine: "Visual Line"
        }
    }
}

extension NSImage {
    /// 메뉴바 글리프 공통 심볼 설정 — 모든 상태 글리프가 같은 크기로 렌더되도록
    /// 한 곳에서 고정한다.
    private static let menuBarSymbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: 15, weight: .regular
    )

    /// SF Symbol을 메뉴바 공통 설정으로 렌더한다. 이름은 이 파일의 상수에서만
    /// 오므로 항상 유효하다.
    static func menuBarSymbol(named name: String) -> NSImage {
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        return symbol.withSymbolConfiguration(menuBarSymbolConfiguration) ?? symbol
    }

    /// Visual-line 전용 메뉴바 글리프 — SF Symbols의 글자 사각형은 1글자뿐이라
    /// (vl.square 부재) "Vl"을 채운 사각형에서 뚫어낸 커스텀 템플릿 이미지를 그린다.
    /// 실제 `square.fill` 심볼(공통 설정)을 바탕으로 그려 다른 모드 글리프와
    /// 크기·모서리·비율이 일치하며, isTemplate이라 라이트/다크 외양은 시스템이 입힌다.
    static let visualLineMenuBarGlyph: NSImage = {
        let base = menuBarSymbol(named: "square.fill")
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            // 0.62·-0.4는 SF 글자 심볼의 컷아웃 메트릭에 맞춘 값 — v.square.fill의
            // 글자 bbox(높이 7.5pt, y 4.5)와 픽셀 스캔으로 일치를 확인했다.
            let text = NSAttributedString(
                string: "Vl",
                attributes: [
                    .font: NSFont.systemFont(ofSize: rect.height * 0.62, weight: .bold),
                    .foregroundColor: NSColor.black,
                ]
            )
            let textSize = text.size()
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
            text.draw(
                at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2 - 0.4)
            )
            return true
        }
        image.isTemplate = true
        return image
    }()
}

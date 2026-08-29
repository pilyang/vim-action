# 앱 셸

- **Last updated**: 2026-08-20 (문서 분할 — [system-overview.md](system-overview.md)의 "관련" 섹션에서 이관, 내용 변경 없음)

## 현재 구조

`LSUIElement` 메뉴바 백그라운드 앱이다 — SwiftUI `MenuBarExtra` + `Settings` 씬. 평소에는 Dock 아이콘·앱 메뉴가 없다. 메뉴바 글리프·메뉴 항목은 [reentrancy-and-safety.md](reentrancy-and-safety.md)(글리프 우선순위)와 [profiles-and-config.md](profiles-and-config.md)(설정 관련 메뉴)가 다룬다.

### Dock 아이콘 — 설정 창이 열려 있는 동안만

설정 창이 열려 있는 동안에만 `DockIconController`가 activation policy를 `.regular`로 올려 Dock 아이콘과 앱 메뉴를 함께 노출한다(분리 불가능한 한 세트). 신호는 셋으로 갈린다:

- **승격**: `SettingsView.onAppear` — `.accessory` 앱이라 창이 key가 되지 않아 `didBecomeKey`가 오지 않고, 재오픈마다 오는 유일한 열림 신호다.
- **기준 창 캡처**: `SettingsWindowReader`(`NSViewRepresentable`, `TabView` 루트 `.background`)가 `viewDidMoveToWindow`에서 자기 `NSWindow`를 `settingsWindowDidConnect(_:)`로 직접 전달한다(`weak` 보관 — 뷰가 그 창 안에 있으므로 정의상 설정 창, 술어·열거·타이밍 추정 없음).
- **강등**: `NSWindow.willCloseNotification`이되 닫히는 창이 **넘겨받은 바로 그 창일 때만**이다 — Sparkle이 titled 일반 `NSWindow`를 띄우므로 술어 판정은 오탐한다. 창을 못 넘겨받았으면 강등하지 않는다(아이콘이 남는 쪽이 fail-safe).

([20260802_dock-icon-while-settings-open.md](../../decisions/references/20260802_dock-icon-while-settings-open.md), [20260812_dock-icon-close-signal-window-identity.md](../../decisions/references/20260812_dock-icon-close-signal-window-identity.md), [20260812_dock-icon-settings-window-handoff.md](../../decisions/references/20260812_dock-icon-settings-window-handoff.md))

열림 훅의 앱측 진입점은 `AppState.settingsWindowDidAppear()`이고 reader와 함께 **`TabView` 루트에 붙는다** — 탭 하나 안에 두면 다른 탭이 기본으로 열릴 때 훅이 뜨지 않는다. 이 메서드는 Dock 훅·온보딩 마무리·로그인 항목 상태 재조회를 겸하므로 **멱등**이다.

### 설정 창 — `TabView` 3탭, 460×560 고정

**General**(권한 상태 + Behavior[로그인 시 자동 시작·Normal 탈출] + Updates 토글 + 접힌 `DisclosureGroup` "Diagnostics") / **Apps**(설정 파일 상태 — [profiles-and-config.md](profiles-and-config.md)) / **About**(버전 + 업데이트 확인 + 링크). 탭 순서는 General이 먼저지만 **기본 선택은 Apps**이고, 권한 섹션은 미허용이면 General 최상단·허용되면 아래쪽(Behavior·Updates 뒤)에 한 줄로 자리를 옮긴다. 높이를 명시하지 않으면 greedy한 grouped `Form` 때문에 창이 임의 높이로 굳는다 ([20260809_settings-window-three-tabs.md](../../decisions/references/20260809_settings-window-three-tabs.md)).

### 로그인 시 자동 시작 — `SMAppService.mainApp`

`LaunchAtLoginController`(`@MainActor @Observable`, seam 3종 `currentStatus`/`register`/`unregister`). **opt-in이며 묵시적 등록 경로가 없다**(General > Behavior 토글). **상태 SSOT는 `SMAppService.mainApp.status` 하나로, UserDefaults 미러를 두지 않는다** — 사용자가 시스템 설정에서 통지 없이 끌 수 있어 미러는 반드시 어긋난다. `.enabled`만 on이고, 토글 쓰기의 결과도 요청값이 아니라 **재조회한 status**가 정한다(실패 시 토글 원위치 + 인라인 사유 + 로그). 재조회 지점은 `settingsWindowDidAppear()`(창 열림마다, 멱등) ([20260812_launch-at-login-smappservice-status-ssot.md](../../decisions/references/20260812_launch-at-login-smappservice-status-ssot.md)).

### 자동 업데이트 — Sparkle 2.x

앱 타깃의 첫 원격 SPM 의존, 2.9.5 고정. `SPUStandardUpdaterController`는 `AppState`가 소유하되 **생성만 하고**(`startingUpdater: false`) 시동은 `bootstrap()`의 XCTest 가드 뒤에서만 — 테스트·프리뷰는 appcast 조회를 하지 않는다(init 무IO 관례). 피드·공개키는 부분 Info.plist(`VimAction/Info.plist`, `GENERATE_INFOPLIST_FILE`과 병합)가 소유한다: `SUFeedURL`은 GitHub Releases 고정 URL, `SUPublicEDKey`는 EdDSA 공개키(개인키는 로그인 키체인 — 레포 커밋 금지). UI는 공용 확인 버튼(메뉴바 메뉴 + About 탭, `canCheckForUpdates` KVO를 Combine으로 구독)과 General 탭 자동 확인 토글(값 영속은 Sparkle 소유)이고, 확인 이후 플로우는 전부 Sparkle 표준 UI다. 자동 확인 기본값은 Sparkle 표준 동의 프롬프트에 맡긴다 ([20260810_sparkle-auto-update.md](../../decisions/references/20260810_sparkle-auto-update.md), [20260810_appcast-hosting-github-releases.md](../../decisions/references/20260810_appcast-hosting-github-releases.md), [20260811_sparkle-updater-ui-and-consent.md](../../decisions/references/20260811_sparkle-updater-ui-and-consent.md)).

### 권한과 온보딩

권한은 빌드 엔타이틀먼트가 아니라 런타임 TCC이며, 온보딩은 **Accessibility만** 요청한다(General 탭 권한 섹션 + 1초 폴링으로 부여 감지 후 재시작 없이 탭 설치). active tap은 AX만으로 설치되며, Input Monitoring은 필요가 입증될 때만 추가한다 ([20260712_active-tap-ax-only-onboarding.md](../../decisions/references/20260712_active-tap-ax-only-onboarding.md)). App Sandbox는 해제(Developer ID 직접 배포) — CGEventTap/AX가 샌드박스 불가 ([20260712_disable-sandbox-developer-id.md](../../decisions/references/20260712_disable-sandbox-developer-id.md)).

미허용 상태의 **발견성은 밀어내기(push) 2종**이다 — 런치 시 **1회** 설정 창 자동 오픈(General 탭)과, 미허용인 동안 메뉴 최상단에 상시 뜨는 권한 경고 행(`Grant Permission…`/`Open System Settings`). 자동 오픈은 `@Environment(\.openSettings)`를 `MenuBarExtra`의 **`label:` 뷰**(`MenuBarLabel`)에서 부른다 — 환경 액션이라 렌더된 뷰가 필요하고, 메뉴 콘텐츠는 열기 전엔 생성되지 않지만 라벨은 런치 때 렌더된다. (`NSApp.sendAction(Selector(("showSettingsWindow:")))`는 macOS 14부터 무동작.) 1회성은 `UserDefaults`의 `didShowOnboarding` **키 존재**로 판정하며(`shouldPresentOnboarding`), 플래그는 지시 자리가 아니라 **창이 뜬 자리**에서 내려간다 — 그 사이에 `SettingsView.init`이 읽어 General 탭으로 열지 정한다 ([20260809_permission-discoverability-push.md](../../decisions/references/20260809_permission-discoverability-push.md)).

## 불변식·계약

- Dock 아이콘 강등은 넘겨받은 창의 동일성으로만 판정한다 — 술어·열거 판정 금지, 실패 방향은 "아이콘이 남는" 쪽.
- 시스템이 소유하는 상태(로그인 항목 status, Sparkle 자동 확인)는 앱이 미러를 두지 않는다 ([profiles-and-config.md](profiles-and-config.md) UserDefaults↔YAML 경계).
- `AppState` init은 IO를 하지 않는다 — 시동·IO는 `bootstrap()`의 XCTest 가드 뒤.

## 근거 요약

백그라운드 유틸리티라 "필요할 때만 보이는" 것이 원칙이다 — Dock 아이콘은 설정 창과 수명을 같이하고, 권한 요청은 최소(AX만)로, 시스템이 소유한 상태는 미러 없이 재조회로 읽는다.

## 관련

- 시스템 내 위치: [system-overview.md](system-overview.md)
- 메뉴바 글리프 우선순위·킬스위치 노출: [reentrancy-and-safety.md](reentrancy-and-safety.md)
- 설정 파일 상태 표시·메뉴 항목: [profiles-and-config.md](profiles-and-config.md)

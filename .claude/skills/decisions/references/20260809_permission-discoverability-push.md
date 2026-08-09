# 미허용 발견성은 push 2종 — 런치 1회 자동 오픈 + 메뉴 상시 경고 행

- **결정일**: 2026-08-09

## 결정

Accessibility 미허용 상태의 발견성을 **밀어내기(push) 두 가지**로 해결한다.

1. **런치 시 1회 설정 창 자동 오픈** — 미허용이고 아직 한 번도 안 띄웠으면 General 탭으로 창을 연다. 판정은 순수 함수 `shouldPresentOnboarding(isTrusted:defaults:)`이고, "띄운 적 있음"은 `UserDefaults`의 `didShowOnboarding` **키 존재**로 본다.
2. **메뉴바 최상단 경고 행 상시** — 미허용인 동안 `⚠ Accessibility permission required` + `Grant Permission…` + `Open System Settings`가 마스터 토글 **위**에 온다.

호출 메커니즘은 **`@Environment(\.openSettings)`를 `MenuBarExtra`의 `label:` 뷰에서** 부르는 것이다(`MenuBarLabel`). `.task`에서 `await Task.yield()`로 다음 틱까지 미룬 뒤 호출한다.

플래그는 **창이 실제로 뜬 자리**(`SettingsView.onAppear` → `AppState.settingsWindowDidAppear()`)에서 내린다.

## 배경·근거 (왜)

`LSUIElement`라 실행해도 창이 안 뜨고, 미허용 신호는 메뉴바 글리프 `square.dashed` 하나뿐이었다. 사용자는 "뭔가 회색이네" 이상으로 읽지 못하고, **권한이 필요한 줄 모르면 설정 창을 열 이유 자체가 없다.** 탭을 정리해도(→ [20260809_settings-window-three-tabs.md](20260809_settings-window-three-tabs.md)) 안 눌러 보는 탭은 없는 것과 같으므로, 발견성은 UI 정리가 아니라 밀어내기로만 풀린다.

**둘 다 필요한 이유**: 자동 오픈은 1회성이라(닫고 나면 다시 안 뜬다) 상시 신호가 못 된다. 메뉴 경고 행이 그 상시 신호를 맡고, 부여 즉시 사라진다(`isTrusted`가 `@Observable`, 1초 폴링이 부여를 감지).

**호출 메커니즘 조사 결과 — 프롬프트가 상정한 경로는 이미 죽어 있었다.**

| 방법 | 상태 |
|---|---|
| `NSApp.sendAction(Selector(("showSettingsWindow:")))` | **macOS 14부터 무동작.** *"Please use SettingsLink for opening the Settings scene."* 경고만 남긴다. macOS 26에서 복구됐다는 보고 없음 |
| `@Environment(\.openSettings)` (macOS 14+, 공식) | 동작. 단 **실제로 렌더된 뷰 안**에서만 — `App`·`AppState`에서는 못 부른다 |

배포 타깃이 macOS 26.5라 가용성 가드는 필요 없다. `MenuBarExtra`의 **메뉴 콘텐츠**는 사용자가 메뉴를 열기 전까지 생성되지 않아 훅이 뜨지 않지만, **라벨은 글리프를 그려야 하므로 런치 때 렌더된다** — 그래서 라벨이 유일하게 쓸 수 있는 뷰 컨텍스트다. 실기에서 동작을 확인했다.

창을 앞으로 끌어오는 문제는 이미 풀려 있었다 — `SettingsView.onAppear` → `DockIconController.apply(.regular)` + `activate()`가 커뮤니티가 권하는 시퀀스 그대로다([20260802_dock-icon-while-settings-open.md](20260802_dock-icon-while-settings-open.md)).

**플래그를 지시 자리가 아니라 창이 뜬 자리에서 내리는 이유가 둘이다.** (a) 그 사이에 `SettingsView.init`이 플래그를 읽어 **General 탭으로 열지** 정한다 — 기본 탭은 Apps라, 안 그러면 권한 블록이 없는 탭이 열려 밀어내기의 목적을 놓친다(실측으로 잡은 결함이다). (b) 오픈이 조용히 실패하면 플래그가 남아 다음 실행에 다시 시도한다 — 성공한 적이 없으므로 그게 맞다.

**키 존재로 판정하는 이유**: `defaults.bool(forKey:)`는 미설정 키에도 `false`를 준다. 값을 보고 판정하면 "false로 기록됨"과 "미설정"이 구분되지 않아 매 실행 창이 뜬다. 레포의 알려진 단언 함정이라 유닛 테스트가 이 케이스를 명시적으로 고정한다.

## 검토한 대안

- **숨은 1×1 `Window` 씬을 `openSettings` 호출 호스트로**: 커뮤니티에서 더 견고하다고 보고된 패턴(`Settings` **앞에** 선언해야 함). 라벨 `.task`가 실기에서 동작해 채택하지 않았다 — 씬이 하나 늘고 `NotificationCenter` 트리거가 붙는다. 라벨 경로가 깨지면 여기로 강등한다.
- **온보딩 전용 창 + 전용 UI**: 범위가 커지는데, 조사 결과 필요 없다 — 열려야 하는 것은 설정 창 그 자체지 새 UI가 아니다.
- **메뉴 경고 행을 `Grant Permission…` 하나로**: 프롬프트의 원안. `requestWithPrompt()`는 TCC 상태당 다이얼로그를 1회만 띄우므로 **두 번째 클릭이 조용한 무동작**이 된다 — 이 레포가 명시적으로 피하는 실패 모드라(`setAppEnabled`·`openProfile`의 폴백과 같은 이유) 항상 열리는 경로를 나란히 뒀다.
- **기본 탭을 신뢰 상태에서 파생(미허용이면 General)**: 온보딩 배선이 필요 없어지지만, 탭 기본값이 상태에 따라 바뀌는 것을 사용자가 예측하기 어렵다.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) (앱 셸 — 온보딩)
- `VimAction/Preferences.swift` — `PreferenceKeys.didShowOnboarding` + 순수 함수 `shouldPresentOnboarding(isTrusted:defaults:)`. 이 키만은 `EventTapController`가 아니라 `AppState`가 소유한다.
- `VimAction/AppState.swift` — `needsOnboardingPresentation`(`bootstrap()`이 세움, XCTest 조기 반환 뒤라 테스트 오염 없음) + `settingsWindowDidAppear()`(Dock 훅 + 온보딩 마무리, **멱등**이어야 한다 — 설정 창을 여는 모든 경로가 부른다).
- `VimAction/VimActionApp.swift` — 메뉴바 라벨이 `MenuBarLabel` 별도 `View`로 분리됐다. `@Environment(\.openSettings)`가 뷰 컨텍스트를 요구하는 것이 분리의 유일한 이유다.
- `VimActionTests/OnboardingPresentationTests.swift` — 진리표 4케이스.

# 설정 창은 3탭 — General / Apps / About

- **결정일**: 2026-08-09

## 결정

단일 `Form` 4섹션이던 설정 창을 `TabView` 3탭으로 나눈다. **General**(권한 상태 + Behavior + 접힌 Diagnostics), **Apps**(기존 `Configuration` 섹션 전체), **About**(버전 + 외부 링크). 탭 **순서**는 macOS 관례대로 General이 먼저지만 **기본 선택은 Apps**다.

세부 규칙 셋:

- **권한 섹션은 신뢰 상태에 따라 자리를 옮긴다** — 미허용이면 General 최상단(경고 + `Request Permission…` + `Open System Settings`), 허용되면 Behavior 아래 `Granted ✓` 한 줄. `@ViewBuilder` 계산 프로퍼티 하나를 두 자리에서 쓴다.
- **진단(Event Tap / Kill Switch / 킬 콤보 안내)은 `DisclosureGroup`으로 접는다** — 정상 동작 중에는 볼 이유가 없고 무언가 이상할 때만 필요한 정보다.
- **창 크기는 460×560 고정이다** — 탭마다 내용 높이가 달라도 창은 움직이지 않는다.

권한을 독립 탭으로 빼지 않는다 — 부여 후엔 한 줄이라 탭 하나를 차지할 값이 없고, 부여 **전**의 발견성은 탭 정리로 풀리는 문제가 아니다([20260809_permission-discoverability-push.md](20260809_permission-discoverability-push.md)).

## 배경·근거 (왜)

한 창에 성격이 다른 셋이 뭉쳐 있었다: 자주 보는 것(앱별 설정 접근), 한 번 보고 마는 것(권한 부여), 참조용(버전·링크). 같은 스크롤에 있으니 자주 쓰는 것을 보려고 매번 나머지를 지나쳐야 했다.

기본 탭이 Apps인 것은 **재방문 이유가 거의 항상 설정 파일 상태 확인**이기 때문이다 — 권한은 최초 1회, About은 사실상 안 본다. 탭 순서까지 바꾸지 않은 것은 General이 첫 탭인 것이 macOS 관례라서다.

**창 크기 고정에는 함정이 하나 있다.** `.formStyle(.grouped)` Form은 세로로 greedy해서 고유 높이를 보고하지 않으므로, `TabView`에 **높이를 주지 않으면** Settings 창이 임의의 한 높이(실측 450pt)로 굳고 내용이 더 긴 탭이 **스크롤도 없이 잘린다** — General 미허용 상태에서 Behavior 각주와 Diagnostics 전체가 사라졌다. 명시 높이를 주면(560) 그 문제가 사라진다.

560은 실측 내용 높이에서 나왔다: 미허용 General 452, Apps 422, About 275, Diagnostics 펼친 General 533. 가장 긴 것(533)을 담고도 남는 값이라 어느 탭에서도 잘리지 않는다. About이 아래를 크게 비우는 것은 수용한 대가다.

## 검토한 대안

- **폭만 고정하고 높이는 탭마다 자연 크기** (각 탭 `Form`에 `.fixedSize(horizontal: false, vertical: true)`): 실제로 동작한다 — 탭 전환마다 창이 리사이즈되고(540/510/363) `DisclosureGroup`을 펼칠 때도 따라 자란다(540→621). About이 빈 공간으로 뜨지 않는 것이 장점이지만, **탭을 옮길 때마다 창이 움직이는 편보다 자리가 고정된 편이 낫다**고 판단해 기각했다.
- **권한을 독립 탭으로**: 부여 후 `Granted ✓` 한 줄만 남아 탭 하나 값을 못 한다. 부여 전 발견성도 "탭을 눌러야 보인다"라 애초에 안 풀린다.
- **권한 섹션을 늘 최상단 고정**: 조건 분기가 없어 코드는 가장 단순하지만, 허용된 뒤(=평생 대부분) 한 줄짜리 확인 표시가 맨 위를 차지한다.
- **탭 순서를 Apps/General/About으로 (selection 상태 없이 첫 탭이 곧 기본)**: 코드 3줄이 줄지만 General이 첫 탭이 아닌 설정 창은 macOS에서 낯설다.
- **Apps 탭에 실행 중인 앱 목록 + 토글**: 실사용 플로우는 메뉴바 토글이 이미 덮는다([20260809_config-yaml-line-edit-writes.md](20260809_config-yaml-line-edit-writes.md)). 필요가 실증된 뒤 결정할 일이다.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) (앱 셸), [profiles-and-config.md](../../architecture/references/profiles-and-config.md) (설정 UI가 보여주는 값들 → Apps 탭)
- `VimAction/SettingsView.swift` — `SettingsView`가 탭 전환만 하고 `GeneralTab`/`AppsTab`/`AboutTab`이 내용을 소유한다. 순수 문구 함수(`eventTapStatusText`·`killSwitchStatusText`·`disabledAppsText`·`profilesText`·`configStatusText`)와 `ScrollingValueList`는 **시그니처·동작 불변**이라 기존 유닛 테스트가 그대로 유효하다.
- **`.onAppear { appState.settingsWindowDidAppear() }`는 `TabView` 루트에 있어야 한다** — 탭 하나 안에 두면 다른 탭이 기본으로 열릴 때 훅이 뜨지 않아 창이 열려도 Dock 아이콘이 안 나온다([20260802_dock-icon-while-settings-open.md](20260802_dock-icon-while-settings-open.md)). 재호출은 무해하다(`DockIconController.apply`의 동등성 가드).
- Apps 탭은 여전히 **읽기 + 파일 열기까지다** — UI 쓰기 경로는 메뉴바 토글 하나뿐이라는 계약이 유지된다.

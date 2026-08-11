# Dock 아이콘 기준 창은 설정 뷰가 직접 넘겨준다

- **결정일**: 2026-08-12

## 결정

닫힘 판정의 기준이 되는 설정 창 캡처를 **열거 방식에서 뷰 직접 전달로** 바꾼다.
`SettingsView`의 TabView 루트에 `SettingsWindowReader`(`NSViewRepresentable`)를 붙여, 뷰가
창에 붙는 순간(`viewDidMoveToWindow`) 자기 `NSWindow`를 `AppState.settingsWindowDidConnect(_:)`
→ `DockIconController.settingsWindowDidConnect(_:)`로 넘긴다. `NSApp.windows`를 술어
(`isVisible && titled && !NSPanel`)로 뒤지던 캡처, `windows` 주입 seam, 찾기 술어
`isSettingsWindow`는 모두 제거한다.

닫힘 판정(캡처한 창과의 `willClose` 동일성)과 fail-safe 방향(못 받으면 강등 안 함), 승격 신호
(`onAppear`)는 그대로다. `settingsWindowDidAppear()`는 승격 전용이 된다.

## 배경·근거 (왜)

전날 결정(창 동일성 판정)이 도그푸딩에서 바로 예고된 실패 모드로 드러났다: **설정 창을 닫아도
Dock 아이콘이 내려가지 않는다** — 캡처가 빈손일 때의 fail-safe 그대로다. 열림 훅이
`SettingsView.onAppear`인데, 그 시점의 창 상태에 기대는 열거 캡처가 매치를 못 찾은 것이다
(개연성 높은 원인은 `onAppear`가 창의 `orderFront`보다 먼저 와서 `isVisible == false`인 것 —
어느 조건이 빈손을 만들었는지는 개별 확정하지 않았다).

전날 결정 문서가 이 상황의 탈출구를 이미 지정해 두었다: "열거 방식으로 실측 문제가 드러나면
`WindowAccessor`로 옮긴다." 이 결정이 그 이행이다. 뷰 직접 전달은 넘어오는 창이 정의상 설정
창이므로(뷰가 그 창 안에 있다) **추정도 타이밍 의존도 없다** — 어느 세부 조건이 열거를
깨뜨렸는지와 무관하게 캡처 실패라는 실패 모드 자체가 소멸한다. 전날 수용했던 엣지(Sparkle
다이얼로그가 떠 있는 채로 설정 창을 열면 첫 매치가 엉뚱한 창)도 함께 사라진다.

비용은 전날 문서가 예상한 그대로다: `SettingsView`에 셸 타입(`SettingsWindowReader`) 하나와
`AppState` 두 번째 진입점(`settingsWindowDidConnect`)이 생긴다. 열림(`onAppear` = 승격)과
캡처(`viewDidMoveToWindow` = 기준 창 전달)가 두 신호로 갈라지지만, 승격 신호를
`viewDidMoveToWindow`로 합치지 않는 이유는 재오픈 시 재발화가 보장되지 않기 때문이다
(창·뷰 계층이 재사용되면 안 올 수 있다; `onAppear`는 재오픈마다 오는 것이 실기기 실측이다).
캡처는 재발화가 안 와도 무해하다 — 같은 창이 재사용된 것이므로 `weak` 참조가 그대로 유효하다.

## 검토한 대안

- **술어에서 `isVisible`만 빼기 / 캡처 실패 시 다음 런루프 틱에 재시도**: `onAppear` 시점 창
  상태에 대한 추정을 하나 더 쌓는 것 — 전날 "술어를 더 좁히는 방향"을 기각한 것과 같은 이유로
  기각. 정확한 실패 조건을 확정하지 못한 채 타이밍을 땜질하면 다음 macOS에서 또 옮겨 다닌다.
- **참조를 못 잡았을 때 옛 술어로 폴백**: Sparkle 창 버그가 되살아나고 실패가 조용해진다 —
  전날과 동일하게 기각.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) —
  "앱 셸" 불릿의 캡처 서술.
- `VimAction/DockIconController.swift` — `windows` seam·`isSettingsWindow` 제거,
  `settingsWindowDidConnect(_:)` 신설, `settingsWindowDidAppear()` 승격 전용화.
- `VimAction/SettingsView.swift` — `SettingsWindowReader` 신설, TabView 루트 `.background` 부착.
- `VimAction/AppState.swift` — `settingsWindowDidConnect(_:)` 라우팅.
- `VimActionTests/DockIconControllerTests.swift` — 열거 seam 기반 테스트를 전달 기반으로 재작성,
  찾기 술어 테스트 삭제.

## Supersedes

- [20260812_dock-icon-close-signal-window-identity.md](20260812_dock-icon-close-signal-window-identity.md) —
  **부분**. 캡처 방식(열거 + `windows` seam + 찾기 술어)만 뒤집는다. 동일성 판정 자체, fail-safe
  방향, 승격 신호는 그대로 유효하다.

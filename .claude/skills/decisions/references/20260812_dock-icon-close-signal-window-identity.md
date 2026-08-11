# Dock 아이콘 닫힘 신호는 설정 창 동일성

- **결정일**: 2026-08-12

## 결정

Dock 아이콘 강등(`.accessory`)의 판정을 술어에서 **창 동일성**으로 바꾼다. 열림 훅
(`settingsWindowDidAppear()`)에서 현재 창들 중 설정 창을 찾아 `weak`으로 잡아 두고,
`NSWindow.willCloseNotification`은 닫히는 창이 **잡아 둔 바로 그 창일 때만** 강등한다.
기존 술어 `isVisible && titled && !(window is NSPanel)`은 닫힘 판정에서 빠지고 **찾기 용도**로만
남는다. 창 열거는 주입 seam(`windows: @MainActor () -> [NSWindow]`, 기본 `{ NSApp.windows }`)으로 연다.

**설정 창을 못 잡으면 강등하지 않는다** — 아이콘이 남는 쪽이 fail-safe다.

승격 쪽(열림 = `onAppear`, 동반 `NSApp.activate`, `.regular`가 앱 메뉴를 함께 켜는 대가)은 그대로다.

## 배경·근거 (왜)

기존 술어는 "이 앱이 만드는 titled 창은 설정 창뿐"이라는 가정 위에 서 있었고, 그 가정은 참일 때만
성립하는 지름길이었다. Sparkle 2.9.5 통합으로 가정이 깨졌다:

- 'Check for Updates…' → `SPUStandardUserDriver`가 띄우는 'Checking for updates…'
  (`SUStatusController`) 창은 **titled 일반 `NSWindow`다** — `NSPanel`이 아니다 (SUStatus.xib 확인).
  업데이트가 발견되는 경로의 `SUUpdateAlert`도 같다.
- 확인이 끝나 Sparkle이 그 창을 닫으면 `willClose` → 술어 통과 → 설정 창이 열려 있는데 아이콘이
  내려간다. 게다가 재승격 신호가 `SettingsView.onAppear` 하나뿐이라, 설정 창이 계속 떠 있는 한
  아이콘은 그 세션 내내 돌아오지 않는다.
- Sparkle 자체는 activation policy를 건드리지 않는다 (소스 확인) — 원인은 전적으로 이쪽 판정이다.

술어를 더 좁히는 방향(예: Sparkle 창 클래스·창 제목 제외)은 같은 종류의 추정을 하나 더 쌓는 것이라
택하지 않았다. 이 앱이 아이콘을 붙잡아 두는 이유는 "titled 창이 있다"가 아니라 "**그** 설정 창이
열려 있다"이므로, 판정도 그 창을 직접 가리켜야 한다.

fail-safe 방향을 "못 잡으면 강등 안 함"으로 둔 이유: 두 실패 모드는 대칭이 아니다. 아이콘이 남는 것은
거슬리는 정도지만, 설정 창이 열려 있는데 아이콘이 사라지면 다른 앱으로 전환한 사용자가 창으로
돌아올 경로를 잃는다(이 기능이 존재하는 이유 자체가 그것이다). 실패를 감추지도 않는다 — 설정 창을
닫아도 아이콘이 안 내려가는 형태로 도그푸딩에서 즉시 드러난다.

수용한 엣지 하나: 찾기 술어는 Sparkle 창도 통과시키므로, Sparkle 다이얼로그가 떠 있는 채로 설정 창을
새로 여는 드문 순서에서는 첫 매치가 엉뚱한 창일 수 있다. 설정 창을 닫았다 다시 열면 재캡처로 자가
복구된다.

## 검토한 대안

- **남은 창 개수로 파생** (닫힘 후 술어에 걸리는 창이 없으면 강등): 캡처가 필요 없어 매력적이지만
  Sparkle 창을 "아이콘을 붙잡아 둘 이유"로 취급한다 — Sparkle 다이얼로그가 떠 있는 동안 설정 창을
  닫으면 아이콘이 내려가지 않는다. 동일성 판정보다 엄격히 나쁘다.
- **`WindowAccessor`(`NSViewRepresentable`)로 SwiftUI가 실제 창을 넘겨주기**: 추정도 타이밍 리스크도
  없는 가장 정확한 방법이지만, `SettingsView`에 새 셸 타입과 두 번째 진입점이 생긴다. 열거 방식으로
  실측 문제가 드러나면 그때 옮길 탈출구로 남긴다.
- **참조를 못 잡았을 때 옛 술어로 폴백**: 캡처가 실패하는 상황에서 정확히 오늘 고친 버그가 되살아나고,
  실패가 조용해져 관측되지 않는다.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) —
  "앱 셸" 불릿의 닫힘 신호 서술.
- `VimAction/DockIconController.swift` — `windows` 주입 seam, `weak var settingsWindow`, 닫힘 핸들러,
  타입·술어 문서 주석. `VimAction/SettingsView.swift`는 주석 1곳(멱등 근거에 재캡처 추가).
- `VimActionTests/DockIconControllerTests.swift` — 회귀 3종 추가(다른 titled 창 닫힘 / 재오픈 재캡처 /
  캡처 실패 fail-safe), 기존 테스트는 새 seam 반영.

## Supersedes

- [20260802_dock-icon-while-settings-open.md](20260802_dock-icon-while-settings-open.md) — **부분**.
  닫힘 판정 술어만 뒤집는다. 승격 신호(`onAppear`), 동반 `activate`, `.regular`의 앱 메뉴 동반 수용,
  `onDisappear`를 쓰지 않는 이유는 그대로 유효하다.

# Normal 모드 modifier 탈출 옵션

- **결정일**: 2026-07-14

## 결정

Normal 모드에서 지정한 modifier(기본 `Cmd`/`Option`) 중 하나라도 포함한 미매핑 콤보가 오면 pending을 폐기하고 **Insert로 탈출시킨 뒤 그 키를 통과**시킨다. 대상 modifier 셋은 엔진이 하드코딩하지 않고 `Configuration.normalModeEscapeModifiers`로 주입받으며, 빈 셋이면 기존 동작(콤보 미탈출)을 그대로 유지한다. 앱은 사용자 설정(기본 on)을 `on → [.command, .option]` / `off → []`로 번역해 주입한다.

## 배경·근거 (왜)

Spotlight·Raycast·AeroSpace 등 macOS 런처/윈도우 매니저는 `Cmd`/`Option` 단축키를 광범위하게 쓴다. 사용자가 Normal 모드에 있는 채 `Cmd+Space`로 Spotlight를 열고 검색어를 타이핑하면, 그 텍스트가 Normal 모드 키로 해석돼 입력이 막힌다 — "단축키를 눌렀으니 이제 타이핑 맥락"이라는 사용자의 기대와 어긋난다. 이 콤보들을 Insert 탈출 신호로 삼으면 단축키 직후 타이핑이 자연스럽게 흐른다.

- **`Ctrl`은 기본 탈출 modifier에서 제외**한다. 향후 `Ctrl-d`(반 페이지 스크롤) 등 Vim 키가 `Ctrl` 콤보를 매핑으로 소비할 것이라, `Ctrl`을 탈출 신호로 두면 그때 충돌한다.
- **pending 엣지 (사용자 확정 2026-07-14)**: `g` 같은 pending 상태에서 탈출 콤보가 와도 pending을 버리고 탈출한다 (`g` 직후 `Cmd+Space`가 Spotlight를 못 열면 탈출 옵션의 취지가 깨진다). 그래서 탈출 콤보 판정을 `step`(커맨드 진행) *진입 전* cross-cutting 규칙으로 둔다 — Esc 정확 매치 폐기와 같은 계층.
- **대상 셋을 `Configuration` 주입으로** 둔 이유: 엔진은 순수 Swift 결정론 타깃이라 UserDefaults·설정 UI를 몰라야 한다. 앱이 설정을 번역해 주입하면 엔진은 "이 modifier들이 탈출 신호"라는 값만 알면 된다. 앱 계층의 소유·영속 모델은 [20260718_interception-toggle-semantics.md](20260718_interception-toggle-semantics.md)와 통일했다.

## 검토한 대안

- **탈출 대상 modifier를 엔진에 하드코딩**: 사용자가 끄거나 조정할 수 없고, 엔진이 제품 정책(어떤 런처를 쓰는가)을 알게 된다. 주입으로 분리해 기각.
- **콤보를 통과시키되 모드는 Normal 유지**: 단축키는 동작하지만 직후 타이핑이 여전히 Normal에 막혀 문제의 절반만 푼다. 탈출(Insert 전이)까지 해야 기대와 맞다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md) (Normal 규칙 ①·`isEscapeCombo`·`EscapeModifierFixtures`는 반영 완료 — 이 문서로 결정 링크 연결)
- 엔진: `Configuration.normalModeEscapeModifiers`, `VimEngine.isEscapeCombo`, `handleNormal`의 취소 최우선 분기.
- 앱: `EventTapController.isNormalModeEscapeEnabled`(설정 프로퍼티) → `makeConfiguration` 번역 주입.
- 취소 순서 자체의 전제는 별도 결정 [20260717_cancellation-first-ordering-premise.md](20260717_cancellation-first-ordering-premise.md).

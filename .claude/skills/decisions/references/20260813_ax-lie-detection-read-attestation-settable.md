# AX 거짓말 감지 — 거부 목록 + 읽기·settable 실증, 값 변경 왕복 없음

- **결정일**: 2026-08-13

## 결정

auto 프로브의 판정 계층은 default-deny다 — 전부 통과해야 trusted:

1. **거부 목록** ([20260813_ax-trust-deny-list-code-constant.md](20260813_ax-trust-deny-list-code-constant.md)) — 목록에 있으면 AX 접촉 없이 즉시 untrusted(재시도 없음).
2. **요소 실증** — 포커스 요소가 존재하고 `AXSelectedTextRange`를 속성 목록에 노출. 리졸버 family **값은 재사용하지 않는다** — family의 실패 폴백은 `.textArea`(허용 방향)라 재사용하면 요소 미노출 앱이 통과한다. 같은 검사를 default-deny 방향으로 다시 한다.
3. **읽기·쓰기 가능성 실증** — AX 경로가 실제로 소비할 프리미티브의 값 왕복: `selectedRange` 값 읽기 + `characterCount` 읽기 + `StringForRange` 창 읽기, 그리고 **`AXUIElementIsAttributeSettable(selectedTextRange)`** (값을 바꾸지 않는 쓰기 축 질의). 경계 정합(`location+length ≤ characterCount`)은 참고 신호로만 본다.

**값을 바꾸는 쓰기 왕복 테스트는 프로브에 넣지 않는다.**

## 배경·근거 (왜)

- **왕복 제외의 근거는 무결성 비용이다**: 쓰기가 실제 *적용*되는지 증명하려면 값을 바꿔야 하고(멱등 재쓰기는 무시당해도 되읽기가 통과), 값을 바꾸는 순간 캐럿 이동·활성 선택 파괴·IME 조합 중 개입·타이핑 레이스가 전부 프로브의 위험이 된다. ±1 이동 변형은 UTF-16 단위라 서로게이트 한가운데를 밟는데 Notion이 mid-pair 쓰기를 무보정으로 받는 것이 실측돼 있다(D1a ③). **"실측 판별력 0"은 근거로 채택하지 않는다** — 세션 0 표본(TextEdit·Notion)에는 "읽기는 되고 쓰기는 안 되는 앱"이 0개라 그 가설을 검정하지 못한다 (독립 검토가 반증).
- **settable 검사가 그 공백의 대부분을 무돌연변이로 덮는다**: 읽기 전용이지만 선택 가능한 텍스트 뷰(Mail 본문·PDF·콘솔류)는 계층 2·3의 읽기를 전부 통과하면서 쓰기가 막히는 실재 앱군인데, settable 질의는 값을 바꾸지 않고 이를 가른다. 실패 방향이 "keyboard = 현행과 동일"이라 판별력 입증 없이도 채택이 우세하고, "프로브는 실행이 쓸 프리미티브의 실증"이라는 원칙상 실행 수단(`AXSelectedTextRange` **쓰기**)의 실증이 빠져 있으면 원칙 위반이다 (독립 검토 제안 수용). settable=true가 적용까지 보장하지는 않는다 — 그 잔여 축은 런타임(되읽어 검증 + 강등)이 담당한다.
- **visible 정합 검사는 넣지 않는다** — `visible ≥ count`는 정당한 전체 표시 문서에서 오탐이 실측됐고(세션 0 ⓑ, Slack 65자 컴포저에서도 재현), 오보의 실제 소비자(스크롤)는 `provenViewport` 가드가 하류에서 이미 자른다.
- **선택 보고 진실성 축은 프로브가 원리적으로 못 본다** — 20260810 결정이 D2에 넘긴 판정 축("AX가 선택을 사실대로 보고하는가", Notion 블록 경계 `[0,0)`)은 프로브 시점에 살아 있는 선택이 없어 증명 불가다. 검출자는 런타임 Visual 자가 검증(+ [20260813_visual-selection-edit-pre-delegation-guard.md](20260813_visual-selection-edit-pre-delegation-guard.md))이고, 그 스킵 로그가 거부 목록 승격 데이터다.
- 계층 2·3을 통과하고도 남는 거짓말(오프셋 공간이 다른데 자기 일관적인 앱 등)의 최악은 "그 앱에서 키 무동작"이며, 파괴 직전 단계는 되읽어 검증·Visual 가드가 막는다. 그 무동작의 회복은 런타임 강등([20260813_auto-trusted-runtime-demotion-and-observability.md](20260813_auto-trusted-runtime-demotion-and-observability.md))이 담당한다 — "관측 먼저, 데이터로 승격"(`.illegalArgument` 전례)이 거부 목록 성장의 메커니즘이다.

## 검토한 대안

- **값 변경 왕복(캐럿 ±1 후 복원)**: 무결성 비용 + 서로게이트 실측 충돌 + 실패 시 사용자 가시 캐럿 훼손. 기각.
- **리졸버 family 값 재사용**: 폴백 방향이 반대(허용). 기각 — 사실상 강제다.
- **visible 정합 검사**: 오탐 실측 + 하류 중복 방어. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 프로브 판정 순수 함수(계층 표 테스트), 탈락 계층이 판정 전이 로그에 실림.

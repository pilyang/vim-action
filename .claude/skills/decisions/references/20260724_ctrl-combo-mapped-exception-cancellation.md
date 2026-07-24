# Ctrl 매핑과 취소 최우선 순서의 충돌 해소 — 매핑 예외 셋 (Normal 전용, 키 단위)

- **결정일**: 2026-07-24

## 결정

취소 최우선 순서(Esc 정확 매치 → 탈출 콤보 → step)는 유지하되, **엔진에 매핑된 Ctrl 콤보 키(`normalCtrlCombos`의 키)는 handleNormal의 탈출 콤보 판정에서 제외**한다. 매핑된 키는 Vim 기능이 항상 이기고, 그 외 Ctrl 콤보는 (사용자가 Ctrl을 탈출 modifier로 설정했다면) 여전히 탈출로 동작한다. 예외 셋(`mappedComboKeys`)은 매핑 테이블의 키에서 파생해 단일 소스를 유지한다 — 매핑 추가 시 예외 동기화는 자동이다.

예외의 스코프를 명시한다:

- **Normal 전용**: `isEscapeCombo` 자체는 수정하지 않고 handleNormal 호출부에서만 제외한다. handleVisual은 그대로 — Visual에는 Ctrl 매핑이 없으므로, Ctrl 탈출 설정 시 Visual의 Ctrl-d는 여전히 탈출이어야 "매핑된 키만 예외" 원칙과 정합한다. (향후 Visual 스크롤을 실제로 매핑하면 그때 자연히 예외가 된다.)
- **키 단위, pending-상태 단위 아님**: Ctrl 탈출 설정에서 `d` 후 Ctrl-d는 탈출이 아니라 op 화이트리스트 밖 invalid swallow다 (`do`/`du` 선례 — 매핑 키의 "Vim 동작"이 invalid인 것도 Vim 동작이다).

## 배경·근거 (왜)

[20260717_cancellation-first-ordering-premise.md](20260717_cancellation-first-ordering-premise.md)가 명시한 전제 — "탈출 콤보 판정을 모든 매핑보다 선행시키는 순서는 매핑 테이블에 modifier 콤보 키가 없다는 사실 위에서만 동치" — 가 Ctrl 콤보 묶음(Ctrl-d/u/f/b/r) 추가로 깨졌다. 그 문서가 요구한 재검토의 해소가 이 결정이다. 사용자가 Ctrl을 탈출 modifier로 설정하면 기존 순서로는 취소 분기가 매핑을 가로채 Ctrl-d가 영원히 동작하지 않는다.

매핑 예외 셋을 선택한 이유: 취소 분기가 한 곳(handleNormal 진입부)에 유지되고, 변경이 국소적이며(`!mappedComboKeys.contains(key)` 조건 하나), pending 중 탈출(`d` 후 Cmd+V 등) 엣지의 기존 동작이 전부 보존되고, 픽스처로 검증하기 쉽다.

파생 트레이드오프(수용): Ctrl 탈출 설정 사용자에게 같은 Ctrl-d가 Normal에서는 스크롤, Visual에서는 Insert 탈출로 모드마다 다르게 동작한다. Ctrl 탈출은 비기본 설정(기본 Cmd/Opt, [20260714_normal-mode-escape-modifiers.md](20260714_normal-mode-escape-modifiers.md))의 엣지 케이스이고, 원칙의 단순성(예외 = 매핑된 키, 단일 소스)이 우선한다 — `CtrlComboFixtures.swift`가 이 비대칭을 의도로 핀한다.

## 검토한 대안

- **매핑 조회 우선 (step에서 미매핑 콤보로 떨어질 때만 탈출 판정)**: 구조적으로 가장 일반적이지만 취소·모드 전이 로직이 step 내부 폴스루로 흩어지고, pending 중 탈출 엣지 케이스 전부를 재검증해야 한다. 기각.
- **교집합 금지 (Ctrl을 탈출 modifier 셋에서 금지)**: 가장 단순하고 충돌을 원천 차단하지만 사용자 설정 자유도를 영구히 제한한다. 기각.
- **Visual에도 예외 적용**: 모드 간 일관성은 생기지만 매핑도 없는 모드에 예외를 적용해 "매핑된 키만 예외" 원칙이 흐려진다. 기각 (사용자 확인).

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `handleNormal`·`normalCtrlCombos`·`mappedComboKeys`
- 픽스처: `CtrlComboFixtures.swift` (매핑 예외·Visual 스코프·키 단위 예외 핀), `EscapeModifierFixtures.swift`·`CancellationFixtures.swift`는 "미매핑 콤보" 픽스처의 키를 Ctrl+d → Ctrl+t로 교체해 의도 보존
- [20260717_cancellation-first-ordering-premise.md](20260717_cancellation-first-ordering-premise.md)의 재검토 조건을 해소한다 — 그 문서의 순서 자체(Esc 정확 매치 → 탈출 콤보 → step)는 계속 유효하다

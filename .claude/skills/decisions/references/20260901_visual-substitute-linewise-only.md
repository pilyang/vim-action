# Visual S는 linewise 세션 한정 — charwise는 이연

- **결정일**: 2026-09-01

## 결정

Visual `S`는 **visualLine 세션에서만** 지원한다(출력은 `c`와 동일한 `.edit(.change, .selection)`). visualChar 세션의 `S`는 **미매핑 swallow**로 두고, 사용자는 `V` 후 `S`/`c`로 같은 결과를 낼 수 있다.

## 배경·근거 (왜)

Vim의 `v_S`는 선택이 덮은 **줄들을** linewise로 change한다. visualLine 세션은 이미 줄 단위라 `c`와 같은 출력이 정확하지만, charwise 세션에는 그 의미를 낼 단일 액션 어휘가 없다.

가장 값싼 표현은 2액션 합성 `[.switchSelectionWise(linewise: true), .edit(.change, .selection)]`이다 — 사용자가 `V` 후 `c`를 친 것과 출력이 같아 새 어휘·새 어댑터 규칙이 0이고, `[edit(.yank, .selection), .clearSelection]` 선례도 있다. 그런데 **액션 사이에는 페이싱이 없다**(5ms 간격은 그룹 *내부* 전용). 이 조합은 재앵커 다타 시퀀스 직후에 `Cmd-X`가 나가는 형태라, [20260831_edit-group-stroke-pacing.md](20260831_edit-group-stroke-pacing.md)가 Notion 실측으로 잡은 "선택이 착지하기 전 오퍼레이터" 실패 클래스와 **같은 축이고 파괴적**이다.

즉 charwise `S`만 도그푸딩 검증을 요구하는데, 나머지 셋(Normal `s`·`S`, Visual `s`)은 기존 출력과 바이트 동일이라 검증 부담이 없다. 안전한 셋을 위험한 하나에 묶어 지연시키지 않기 위해 분리한다.

**재개 조건**: 액션 간 정착(또는 합성 그룹의 페이싱 편입)이 확인되고, 버스트에 취약한 앱(Notion 등)에서 도그푸딩으로 선택 착지가 실증되면 합성 경로로 지원한다.

## 검토한 대안

- **charwise `S`를 그냥 `c`(charwise change)로 매핑**: 덮인 줄 전체가 아니라 선택 범위만 지워지는 **오해석**이며, 파괴적 편집이다. `d3G`·`3diw`를 invalid로 이연한 것과 같은 기준으로 기각.
- **지금 2액션 합성으로 지원**: 위 실패 클래스 때문에 도그푸딩 없이는 낼 수 없다. 기각이 아니라 이연이다.
- **새 범위 케이스 `.selectionLinewise` 신설**: 결과는 합성과 같은데 엔진 어휘 + 양 어댑터(keyboard 반올림 시퀀스, AX `Span` 산출)를 모두 확장해야 한다. 비용만 크다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift` — `visualStep`의 mode 게이트 분기.
- 픽스처: `VisualFixtures.swift`(visualLine 지원 / visualChar swallow 양쪽).
- 문서: `docs/KEYBINDINGS.md`에 🚧로 명시.
- 어휘 자체의 근거는 [20260901_substitute-shorthand-s-S.md](20260901_substitute-shorthand-s-S.md).

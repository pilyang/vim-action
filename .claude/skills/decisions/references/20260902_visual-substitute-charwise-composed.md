# Visual S는 charwise도 2액션 합성으로 지원

- **결정일**: 2026-09-02

## 결정

Visual `S`는 **양쪽 wise 모두** 지원한다. visualLine 세션은 `c`와 동일한 `.edit(.change, .selection)` 단일 출력, visualChar 세션은 **2액션 합성 `[.switchSelectionWise(linewise: true), .edit(.change, .selection)]`** — 사용자가 `V` 후 `c`를 친 것과 같은 액션열이라 새 어휘·새 어댑터 규칙이 0이다. 액션 간 페이싱 규칙은 추가하지 않는다.

## 배경·근거 (왜)

Vim의 `v_S`는 선택이 덮은 **줄들을** linewise로 change한다. visualLine 세션은 이미 줄 단위라 `c`와 같은 출력이 정확하지만, charwise 세션에는 그 의미를 낼 단일 액션 어휘가 없다. 합성 출력에는 `[.edit(.yank, .selection), .clearSelection]` 선례가 있다.

이 합성은 재앵커 다타 시퀀스 직후에 `Cmd-X`가 나가는 형태라, [20260831_edit-group-stroke-pacing.md](20260831_edit-group-stroke-pacing.md)가 Notion 실측으로 잡은 "선택이 착지하기 전 오퍼레이터" 실패 클래스와 같은 축이다. 그래서 같은 PR 안에서 하루 이연하고 도그푸딩을 선행시켰다. 액션 사이의 실제 간격은 keyboard 어댑터 `flush()`의 `chunkInterval`(2ms — 재앵커 그룹은 `postPaced`, 뒤따르는 오퍼레이터 1타는 pending 누적 후 flush)이고, 20260831이 그룹 내부에 실측으로 요구한 5ms보다 짧아 검증 없이는 낼 수 없었다.

**도그푸딩 결과(2026-09-02, 판정 근거)**: 가장 취약한 조합인 Notion keyboard 경로(번들 프로파일이 Visual을 keyboard로 고정)에서 `v`+모션+`S` 반복 시 파괴적 실패(선택 착지 전 잘림, 블록 통째 소실) **0건** — 2ms 간격으로 충분함이 실증됐다. 관측된 편차는 Notion 블록 모델로 인한 줄 선택 범위 부정확뿐이며, 이는 `V` 계열 전반에서 이미 수용한 기존 편차다. AX 경로는 `Cmd-X` 위임 직전 선택 재검증 가드(20260813)가 이 실패 클래스를 원천 차단한다.

## 검토한 대안

- **charwise `S`를 그냥 `c`(charwise change)로 매핑**: 덮인 줄 전체가 아니라 선택 범위만 지워지는 **오해석**이며, 파괴적 편집이다. `d3G`·`3diw`를 invalid로 이연한 것과 같은 기준으로 기각.
- **새 범위 케이스 `.selectionLinewise` 신설**: 결과는 합성과 같은데 엔진 어휘 + 양 어댑터(keyboard 반올림 시퀀스, AX `Span` 산출)를 모두 확장해야 한다. 비용만 크다.
- **액션 간 5ms 페이싱 규칙을 지금 추가**("직전 액션이 페이싱 그룹이면 뒤따르는 오퍼레이터도 5ms 뒤에"): 실측이 2ms로 충분하다고 나온 이상 미검증 코드가 된다. 이후 다른 앱에서 이 실패 클래스가 재현되면 그때 어댑터 결정으로 추가한다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift` — `visualStep`의 `S` 분기(wise별 출력).
- 픽스처: `VisualFixtures.swift`(visualLine 단일 출력 / visualChar 합성 출력 양쪽).
- 어휘 자체의 근거는 [20260901_substitute-shorthand-s-S.md](20260901_substitute-shorthand-s-S.md).

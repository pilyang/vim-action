# linewise TextRange — additive .linewiseMotion + 절대 모션 카운트 invalid

- **결정일**: 2026-07-19

## 결정

`TextRange`에 **additive 케이스 `linewiseMotion(Motion, count: Int)`**를 추가해 오퍼레이터 뒤 줄 단위 모션(`dj`/`dk`/`dG`/`dgg` + c/y 조합)을 표현한다. 기존 `.motion` 계약은 불변 — charwise 화이트리스트와 소비자 동작이 그대로 유지된다. "총 몇 줄인지"(`dj` = 현재+아래 줄)의 해석은 어댑터 몫이다.

**화이트리스트는 charwise와 별도**: `j`→lineDown, `k`→lineUp, `G`→documentEnd, `gg`→documentStart.

**카운트 규칙이 상대/절대에서 갈린다**:
- 상대 모션(j/k)은 기존 곱 규칙 그대로 카운트 적용 (`2d3j` = `.linewiseMotion(.lineDown, count: 6)`).
- **절대 모션(G/gg)은 카운트가 하나라도 있으면 invalid** — Vim의 `d3G`는 "3번 줄까지"라는 절대 줄 의미인데 count 슬롯으로 표현할 수 없고, 반복으로 수용하면 "3줄 삭제 ≠ 3번 줄까지 삭제"라는 파괴적 오해석이 된다. 절대 모션은 항상 `count: 1`로만 출력된다.
- **모션 `3G`의 반복-수용과 기준이 다른 이유**: 커서 이동의 반복은 멱등·무해(documentEnd ×3 = documentEnd)라 Vim 의미와 다름을 인지한 채 수용했지만, 편집은 파괴적이라 오해석을 수용할 수 없다.

**`dgg` 문법**: op-pending 상태에서 `g` 키가 prefix `.g`로 extend되도록 허용한다 (기존에는 `op == nil` 전용). prefix `.g` 완결 시 `op != nil`이면 linewise documentStart, `op == nil`이면 기존 모션 gg. **카운트 invalid 판정은 extend 시점이 아니라 완결 시점(둘째 g)** — extend에서 거르면 `d3g` invalid 직후의 `g`가 새 `.g` pending을 열어 잔류 상태가 생긴다. prefix 상태에서는 digit이 카운트로 누적될 수 없으므로(prefix 분기가 최우선) 완결 시점의 count/opCount 검사로 충분하다.

## 배경·근거 (왜)

`dj`/`dG`는 Vim에서 linewise 범위(두 줄 통삭제)인데 `TextRange.motion`에 charwise/linewise 구분이 없어 어댑터가 의미를 복원할 수 없었고, 그래서 invalid로 이연되어 있었다 ([20260717_vimaction-edit-output-shape.md](20260717_vimaction-edit-output-shape.md)의 부속 확정). 구분을 추가하는 시점에, 기존 `.motion` 소비자를 건드리지 않는 additive 케이스가 병렬 작업(Plan-1) 안전성과 회귀 없음을 동시에 만족한다.

## 검토한 대안

- **`.motion`에 linewise 플래그/연관값 추가**: 기존 계약 변경 — 모든 charwise 소비 경로와 픽스처가 영향받고, Plan-1과의 병렬 안전이 깨진다. 기각.
- **`d3G`를 `.linewiseMotion(.documentEnd, count: 3)` 반복 의미로 수용**: "3번 줄까지"라는 Vim 의미와 다른 파괴적 오해석. 기각.
- **절대 줄 목표 케이스(`lineTarget(Int)`) 즉시 추가**: `d3G`를 정확히 표현할 수 있지만 어댑터의 절대 줄 탐색 구현이 전제 — 필요 시점에 additive로 추가 가능. 기각(이연).
- **op-pending `g`를 extend 시점에 카운트로 거름**: invalid 직후 `g`가 새 pending을 여는 잔류 상태 발생. 완결 시점 판정으로 통일. 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimAction.swift`(TextRange), `VimEngine.swift`(operatorLinewiseRelativeMotions 테이블, G/g 분기, prefix .g 완결 분기)
- 어댑터 구현 시 linewise 범위(줄 경계 확장) 실행을 정의해야 한다 (아직 미구현).

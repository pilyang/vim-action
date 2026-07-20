# 오퍼레이터 모션 디스패치 단일 테이블 통합 — kind로 규칙 구분

- **결정일**: 2026-07-19

## 결정

오퍼레이터 뒤 단일 키 모션 화이트리스트를 **kind 딸린 단일 테이블 `opMotions: [Key: (motion, kind)]`**로 통합한다. kind는 `charwise` / `linewiseRelative` / `linewiseAbsolute` 셋이며, 출력 범위(`.motion`/`.linewiseMotion`)와 카운트 규칙(곱 적용 vs 카운트 시 invalid)을 kind가 정한다. 디스패치는 테이블 조회 + kind switch 한 분기다.

**카운트 규칙·출력 형태는 기존 결정 그대로다** — 바뀐 것은 내부 디스패치 구조(테이블 2벌 + G 수기 분기 → 테이블 1벌)뿐이다. 멀티키인 `gg`는 단일 키 테이블에 들어갈 수 없으므로 prefix 메커니즘(`.g`)에 의도적으로 남긴다.

## 배경·근거 (왜)

코드리뷰(2026-07-19, 워크플로 기반)에서 "operator 뒤 motion" 하나의 개념이 4갈래(charwise 테이블, linewise 상대 테이블, `G` 수기 분기, `gg` prefix 분기)로 분산되어 있음이 지적됐다. 다음 모션을 추가할 때 넷 중 어디에 넣을지 골라야 하고, 잘못 고르면 linewise 의미가 조용히 틀어진다. 단일 키 모션 셋을 한 테이블로 모으면 "모션 추가 = 테이블 한 줄 + kind 선택"이 되어 이 선택 오류 여지가 사라진다.

## 검토한 대안

- **현행 유지 (다음 모션 추가 시점으로 이연)**: 동작은 정확하므로 미룰 수 있으나, 분산 구조가 굳을수록 통합 비용이 커진다. 테스트가 전부 갖춰진 지금이 가장 싼 시점. 기각.
- **`gg`까지 통합 (prefix 완결부의 절대 카운트 가드를 테이블로 흡수)**: prefix 메커니즘은 멀티키 문법상 필수라 완전 통합이 불가능하고, 억지로 우회하면 오히려 구조가 복잡해진다 — over-engineering. 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift` (`opMotions` 테이블 + `OpMotionKind`, 기존 `operatorMotions`/`operatorLinewiseRelativeMotions`/`G` 분기 제거)
- 카운트 의미·출력 계약은 [20260719_linewise-textrange-absolute-count-invalid.md](20260719_linewise-textrange-absolute-count-invalid.md), [20260717_vimaction-edit-output-shape.md](20260717_vimaction-edit-output-shape.md) 그대로 (이 결정은 supersede 아님).

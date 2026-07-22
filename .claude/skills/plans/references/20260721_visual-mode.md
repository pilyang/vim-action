# Visual 모드 구현 (`v`/`V`) — 세부 플랜

<!-- 상위 개요 플랜: 20260721_engine-vocabulary-completion-overview.md 의 항목 ①.
     완료 시 개요 플랜 체크 후 이 문서는 삭제한다. -->

- **생성일**: 2026-07-21
- **갱신일**: 2026-07-22

## 목표

엔진이 Visual-char/Visual-line 상태 머신을 갖추고 PRD §7.2 Visual 동작(`y d x c` + 모션 선택 확장 + 카운트)을 해석하는 상태. 전부 픽스처 단위 테스트로 커버(`swift test` GREEN), 새 출력 계약은 decisions 기록 + `mode-engine.md` 갱신.

## 완료된 것

- [x] **1. 출력 계약 설계·결정** (2026-07-22) — selection 케이스 신설안 채택: `extendSelection(Motion)`(카운트는 반복 출력), `beginSelection(linewise:)`/`clearSelection`(명시 진입·이탈 신호, wise는 세션 속성), `TextRange.selection`(`y d x c`, `x`≡`d`), 앵커·범위는 어댑터 상태. pending 상호작용은 특례 없음(`3v` 카운트 무시 진입, `dv` invalid no-op). decisions: [20260722_visual-mode-output-contract.md](../../decisions/references/20260722_visual-mode-output-contract.md), [20260722_visual-entry-pending-interaction.md](../../decisions/references/20260722_visual-entry-pending-interaction.md)

- [x] **2. 모드 전이** (2026-07-22): visualChar/visualLine 추가, `v`/`V` 진입·이탈·전환, Insert에서 `v`는 통과. `ModeTransitionTests` 확장 (커밋 660fa16).
- [x] **3. 모션 → 선택 확장 + 카운트** (2026-07-22): 기존 모션 전부 `extendSelection` 반복 출력, 0-규칙·클램프 공유, `VisualFixtures.swift` 신설 (커밋 b241e56).
- [x] **4. 선택 동작 `y d x c`** (2026-07-22): `.edit(op, .selection)` 즉시 완결, `x`≡`d`, `c`→Insert, 카운트+오퍼레이터 invalid (커밋 54ff33f).
- [x] **5. 엣지·취소 규칙 + 문서 갱신** (2026-07-22): Esc/탈출 콤보·미매핑·`3v`/`dv` 픽스처, `mode-engine.md` 최종 상태 갱신.

## 남은 것

- [ ] 완료 확인 후 정리: 개요 플랜 항목 ① 체크 + 이 문서 삭제 (스킬 워크플로우 4 — 사용자 확인 필요).

## 진행 중 컨텍스트

- 범위 제한: PRD v1의 Visual 동작은 `y d x c`가 전부 — Visual에서 오퍼레이터+모션/텍스트 오브젝트(`vi(` 류)는 범위 밖. 카운트는 모션에만.
- Vim 의미론 참고: visual-char에서 `v`는 이탈·`V`는 line 전환(반대도 동일 패턴). 이 문서의 의미론이 Vim과 다르게 결정되면 decisions에 남길 것.
- 엔진 불변식 준수: macOS import 금지, 실행 방법 무지(선택 범위 계산은 어댑터 몫), `VimAction` 소비자는 exhaustive switch 금지(케이스 추가에 견딤 — 케이스 신설 시 이 계약 덕에 기존 소비자 무해).
- 병행 안전: 순수 엔진 작업이라 스톨 측정 창과 무관. 구현 브랜치는 착수 시 신규 생성(기존 워크트리 없음).

## 관련 링크

- 상위 플랜: [20260721_engine-vocabulary-completion-overview.md](20260721_engine-vocabulary-completion-overview.md)
- 요구사항: 워크스페이스 `docs/prd.md` §7.1(모드 전환표), §7.2(Visual 동작)
- architecture: [mode-engine.md](../../architecture/references/mode-engine.md)
- decisions: [20260714_multikey-command-grammar-builder.md](../../decisions/references/20260714_multikey-command-grammar-builder.md), [20260717_vimaction-edit-output-shape.md](../../decisions/references/20260717_vimaction-edit-output-shape.md), [20260719_change-insert-transition-and-cw-deferral.md](../../decisions/references/20260719_change-insert-transition-and-cw-deferral.md), [20260717_cancellation-first-ordering-premise.md](../../decisions/references/20260717_cancellation-first-ordering-premise.md)

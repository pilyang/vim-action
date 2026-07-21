# Visual 모드 구현 (`v`/`V`) — 세부 플랜

<!-- 상위 개요 플랜: 20260721_engine-vocabulary-completion-overview.md 의 항목 ①.
     완료 시 개요 플랜 체크 후 이 문서는 삭제한다. -->

- **생성일**: 2026-07-21
- **갱신일**: 2026-07-21

## 목표

엔진이 Visual-char/Visual-line 상태 머신을 갖추고 PRD §7.2 Visual 동작(`y d x c` + 모션 선택 확장 + 카운트)을 해석하는 상태. 전부 픽스처 단위 테스트로 커버(`swift test` GREEN), 새 출력 계약은 decisions 기록 + `mode-engine.md` 갱신.

## 완료된 것

- (착수 전)

## 남은 것

<!-- 위에서부터 순서대로. 1이 선행 결정이라 가장 먼저 — 이후 단계의 출력 형태가 여기 걸려 있다. -->

- [ ] **1. 출력 계약 설계·결정** — "모션이 이동이 아니라 선택 확장"임을 어댑터에 어떻게 전달할지: `VimAction`에 selection 계열 케이스 신설 vs `EngineOutput`에 모드 문맥 동봉 vs 어댑터가 `mode`로 해석 분기. 선택 앵커·실제 범위는 텍스트를 모르는 엔진이 가질 수 없으므로 어댑터 상태라는 경계도 함께 확정. `c`의 Insert 전이(기존 `complete` 헬퍼)와 `x`≡`d` 동치 처리 포함. → **decisions 기록 후 다음 단계 진행**.
- [ ] **2. 모드 전이**: `Mode`에 visual(char/line) 추가, Normal→`v`/`V` 진입, 이탈(`Esc`, 같은 키 재입력)·전환(`v`↔`V`) 의미론, Insert와의 전이 매트릭스. `ModeTransitionTests` 확장.
- [ ] **3. 모션 → 선택 확장 + 카운트**: 기존 모션 전부의 Visual 해석(1단계 계약대로 출력), 선행 카운트(`3j`) 적용. Visual 전용 픽스처 파일 신설.
- [ ] **4. 선택 동작 `y d x c`**: 선택 범위에 대한 오퍼레이터 출력, `c`→Insert / `y d x`→Normal 복귀, `x`≡`d`. 픽스처 추가.
- [ ] **5. 엣지·취소 규칙 정리 + 문서 갱신**: Visual에서의 탈출 modifier 콤보, 미매핑 키 처리(swallow/passthrough), Normal의 `pending`과의 상호작용(Visual 진입 시 pending 폐기 등), `mode-engine.md` 갱신, 개요 플랜 체크.

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

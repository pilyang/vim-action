# M3 단계 4 선행 — Normal Esc passthrough + D/C 키 추가

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-01
- **갱신일**: 2026-08-01 (구현·문서·검증 완료 — PR 병합 대기)

## 목표

M3 단계 4(게이트 심사) **전에** 어휘·동작 변경 2건을 끝낸다: ① Normal 모드 Esc가 앱으로 전달되고(Esc 연타로 "Normal 진입 → 앱에 취소 전달"이 가능), ② `D`/`C`(커서부터 줄 끝까지 삭제/change)가 실행된다. 단계 4의 스킵 로그 전수 확인은 어휘가 확정된 뒤에 돌아야 하므로 이 작업이 선행이다. 상위 플랜: [20260726_m3-keyboard-edit-visual-resolver.md](20260726_m3-keyboard-edit-visual-resolver.md).

## 완료된 것

- [x] 가능성 체크 완료 (2026-08-01): 둘 다 엔진 중심 변경으로 어댑터·게시 인프라 무변경, 단계 3 도그푸딩 결과(리졸버·계열 분류)와 상호작용 없음 확인.
- [x] **① Normal Esc passthrough** (2026-08-01): pending 없을 때만 `.passthrough`, pending 있으면 현행(폐기+swallow — 사용자 확인 완료된 결정). 기존 픽스처는 `CtrlComboFixtures`의 정규화 선행 핀 1건만 갱신(판별 신호를 finalMode로 교체 — CancellationFixtures의 Esc는 전부 pending 취소 케이스라 무변경), 신규 핀 3건(빈 상태 Esc/연속 Esc/빈 상태 Ctrl-[).
- [x] **② D/C 추가** (2026-08-01): 최상위에서 `d$`/`c$` 동일 출력으로 완결, 카운트는 invalid. 픽스처 5건(D/C 완결·전이, 3D/3C invalid, dD 회귀 핀).
- [x] **결정 문서 2건 + architecture 갱신** (2026-08-01): [20260801_normal-esc-passthrough-when-empty.md](../../decisions/references/20260801_normal-esc-passthrough-when-empty.md)(20260717 부분 supersede 표기 포함), [20260801_line-end-shorthand-d-c.md](../../decisions/references/20260801_line-end-shorthand-d-c.md). `mode-engine.md` 처리 규칙 ①·키셋 갱신, decisions 인덱스 반영.
- [x] **검증 3종 그린** (2026-08-01): 엔진 42 테스트 / 앱 VimActionTests TEST SUCCEEDED / CODE_SIGNING_ALLOWED=NO BUILD SUCCEEDED.

## 남은 것

- [ ] **PR 병합** → 병합 후 이 플랜 완료 처리(삭제), M3 플랜의 단계 4 착수.

## 진행 중 컨텍스트

- 브랜치 `esc-passthrough-and-dc-keys`에서 커밋 3개(엔진 Esc / 엔진 D·C / 문서)로 구현 완료, PR 생성됨 — 병합만 남음.
- 단계 4와의 순서: **이 플랜이 닫히기 전에 단계 4를 시작하지 말 것.**

## 관련 링크

- architecture: [mode-engine.md](../../architecture/references/mode-engine.md) (Normal 처리 규칙 ① 취소 최우선, opMotions 화이트리스트)
- decisions: [20260717_cancellation-first-ordering-premise.md](../../decisions/references/20260717_cancellation-first-ordering-premise.md)

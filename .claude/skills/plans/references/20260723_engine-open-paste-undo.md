# 엔진 소형 묶음 — o/O · p/P · u (세부 플랜)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-23
- **갱신일**: 2026-07-23

## 목표

[개요 플랜](20260721_engine-vocabulary-completion-overview.md) 항목 ②: Normal 모드에서 `o`/`O`(새 줄 열고 Insert), `p`/`P`(뒤/앞 붙여넣기), `u`(네이티브 undo 위임)를 엔진이 해석하고, `swift test` 픽스처로 커버된 상태. 순수 엔진 작업 — 어댑터 실행은 디스패처 마일스톤 몫.

**범위 밖**: `Ctrl-r`(개요 항목 ③ — 취소 최우선 전제 재검토와 함께), Visual 모드의 `o`(앵커 스왑)/`p`(선택 대체)/`u`(소문자화) — PRD v1 Visual 어휘 밖, 미매핑 swallow 유지. 레지스터 없음(시스템 클립보드 전제).

## 완료된 것

- [x] 범위 확정 + 출력 계약 결정 3건 기록 (2026-07-23, 관련 링크 참조) — `openLine(above:)`+Insert 전이+카운트 무시 / `paste(before:count:)` 단일 액션 count / `undo` 반복 출력

## 남은 것

<!-- 다음에 할 것이 맨 위. 인계 단위(세션/마일스톤 수준)로 — 함수 단위 세부 todo는 세션 내 TodoList의 몫. -->

- [ ] 엔진 구현: `VimAction` 케이스 3종 신설 + `step` 최상위 매핑 (계약·카운트 정책은 결정 문서 3건이 SSOT)
- [ ] 픽스처: 기본 동작, 카운트 3정책(`3o` 무시 / `3p` count / `3u` 반복), 오퍼레이터 대기 중 invalid(`do`/`dp`/`du` — 기존 화이트리스트가 이미 처리, 픽스처로 고정만), Visual 미매핑 swallow(`o O p P u`), Esc 취소 상호작용(`3p` 누적 중 Esc 등)
- [ ] 마무리: mode-engine.md 갱신(구현된 키셋·출력 계약 반영), 개요 플랜 ② 체크, PR 생성 — 병합 후 이 플랜 삭제(워크플로우 4)

## 진행 중 컨텍스트

- 작업 브랜치: `feat/engine-open-paste-undo` (worktree). 구현 미착수 — 코드 변경 없음.
- `P`/`O`는 shift 흡수 문자로 정규화되어 들어온다 (`.char("P")`) — Key 계약 그대로, 별도 처리 불필요.
- 배선 계층은 replace 삼킴 과도기 규칙 하에 있음 — 새 액션도 실행 없이 삼켜지고 DEBUG 로그만 남는 게 정상.

## 관련 링크

<!-- 진행 중 내려진 결정은 여기 링크만 — 내용은 decisions 문서에. 이 문서는 삭제될 문서라 여기 적힌 결정은 함께 사라집니다. -->

- 상위 플랜: [20260721_engine-vocabulary-completion-overview.md](20260721_engine-vocabulary-completion-overview.md)
- architecture: [mode-engine.md](../../architecture/references/mode-engine.md)
- decisions: [20260723_openline-output-contract.md](../../decisions/references/20260723_openline-output-contract.md), [20260723_paste-output-contract.md](../../decisions/references/20260723_paste-output-contract.md), [20260723_undo-output-contract.md](../../decisions/references/20260723_undo-output-contract.md)
- 요구사항: 워크스페이스 `docs/prd.md` §7.2

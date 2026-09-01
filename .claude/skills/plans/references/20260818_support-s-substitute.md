# `s` / `S` 동작 지원

- **생성일**: 2026-08-18
- **갱신일**: 2026-09-01

## 목표

현재 지원하지 않는 `s`, `S` 키의 동작을 지원한다.

## 완료된 것

- 동작 정의 확정 + 조사: `s`=`cl`, `S`=`cc`, Visual `s`=`c`, Visual `S`=`V` 후 `c`(linewise). 넷 중 셋이 **기존 출력과 바이트 동일**이라 어댑터 변경 0.
- 엔진 구현: Normal `s`/`S`(`x` 옆 `switch key` 케이스, 카운트 유효), Visual `s`(`visualOperatorKeys`), Visual `S`(visualLine 한정 분기).
- 픽스처 10건 (`EditFixtures.substituteFixtures` 6 + `VisualFixtures` 4) — 엔진 테스트 101건 통과, 앱 빌드 통과.
- 문서: `docs/KEYBINDINGS.md`(Actions·Visual 표 + 클립보드 경고), `README.md` 키 표.
- 결정 기록: [20260901_substitute-shorthand-s-S.md](../../decisions/references/20260901_substitute-shorthand-s-S.md), [20260901_visual-substitute-linewise-only.md](../../decisions/references/20260901_visual-substitute-linewise-only.md) + `architecture/mode-engine.md` 갱신.

## 남은 것

- [ ] PR 생성·머지 (브랜치 미생성 — 현재 변경은 워킹트리에 있음)
- [ ] **charwise Visual `S`** — 이연분. `[.switchSelectionWise(linewise: true), .edit(.change, .selection)]` 2액션 합성으로 낼 수 있으나, 액션 사이에는 페이싱이 없어(5ms는 그룹 내부 전용) 재앵커 다타 직후 `Cmd-X`가 나가는 형태다. 착수하려면 액션 간 정착 확보 + Notion 등 버스트 취약 앱 도그푸딩이 선행돼야 한다.

## 진행 중 컨텍스트

지원분(Normal `s`/`S`, Visual `s`, visualLine `S`)은 구현·검증 완료. 남은 것은 PR 처리와, 별도 작업으로 분리한 charwise Visual `S`뿐이다. 분리 근거와 재개 조건은 [20260901_visual-substitute-linewise-only.md](../../decisions/references/20260901_visual-substitute-linewise-only.md)에 있다.

## 관련 링크

- 페이싱 실패 클래스의 선례: [20260831_edit-group-stroke-pacing.md](../../decisions/references/20260831_edit-group-stroke-pacing.md)

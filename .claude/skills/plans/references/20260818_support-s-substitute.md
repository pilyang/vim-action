# `s` / `S` 동작 지원

- **생성일**: 2026-08-18
- **갱신일**: 2026-09-02

## 목표

현재 지원하지 않는 `s`, `S` 키의 동작을 지원한다.

## 완료된 것

- 동작 정의 확정 + 조사: `s`=`cl`, `S`=`cc`, Visual `s`=`c`, Visual `S`=`V` 후 `c`(linewise). 넷 중 셋이 **기존 출력과 바이트 동일**이라 어댑터 변경 0.
- 엔진 구현: Normal `s`/`S`(`x` 옆 `switch key` 케이스, 카운트 유효), Visual `s`(`visualOperatorKeys`), Visual `S`(visualLine은 `c`와 동일 출력, charwise는 [switchWise, change] 2액션 합성 — 어댑터 변경 없이).
- 픽스처 10건 (`EditFixtures.substituteFixtures` 6 + `VisualFixtures` 4) — 엔진 테스트 101건 통과, 앱 빌드 통과.
- 도그푸딩 완료 (2026-09-02): 지원분 전체 + Notion에서 charwise `vS` 반복 — 파괴적 실패 0건, 액션 간 2ms 간격 충분 실증.
- 문서: `docs/KEYBINDINGS.md`(Actions·Visual 표 + 클립보드 경고), `README.md` 키 표.
- 결정 기록: [20260901_substitute-shorthand-s-S.md](../../decisions/references/20260901_substitute-shorthand-s-S.md), [20260902_visual-substitute-charwise-composed.md](../../decisions/references/20260902_visual-substitute-charwise-composed.md) + `architecture/mode-engine.md` 갱신.

## 남은 것

- [ ] PR [#64](https://github.com/pilyang/vim-action/pull/64) 머지 (ready 전환까지 완료)

## 진행 중 컨텍스트

전체 어휘(Normal `s`/`S`, Visual `s`, Visual `S` 양쪽 wise) 구현·도그푸딩 검증 완료. PR 머지만 남았다 — 머지되면 이 플랜은 완료 처리(삭제) 대상이다.

## 관련 링크

- 페이싱 실패 클래스의 선례: [20260831_edit-group-stroke-pacing.md](../../decisions/references/20260831_edit-group-stroke-pacing.md)

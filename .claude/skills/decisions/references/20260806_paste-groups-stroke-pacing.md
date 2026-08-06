# `.paste` 그룹도 스트로크 페이싱 대상이다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

`.paste`의 그룹을 페이싱 대상(`Mapping.groups(paced: true)`)에 넣는다 — 접두 다타 그룹(linewise `p` 4타 등)이 스트로크 사이 5ms(`pacedStrokeInterval`, Visual 정확화와 같은 상수)로 게시된다. 후속 `Cmd-V` 반복 그룹은 1타라 기존 규칙(2타 미만은 일반 경로)에 의해 자연히 페이싱 밖이고, 스크롤·카운트 버스트·폴백 경로의 타이밍 현행 유지는 그대로다.

## 배경·근거 (왜)

도그푸딩 실측: Notion에서 `dd` 후 `p`가 **기억 델타 1로 linewise 시퀀스가 정상 게시됐는데도**(로그 판독 확정) 내용이 줄 끝에 붙고 아래 빈 줄이 생겼다. linewise `p`의 접두 `Cmd-→, →, Cmd-←`가 0간격 버스트로 나가면 Notion이 화살표를 소화하지 못해 캐럿이 다음 줄로 가기 전에 `Cmd-V`가 터지는 것으로, [Visual 정확화 그룹 페이싱](20260805_visual-refined-group-stroke-pacing.md)이 실측으로 확정한 것과 같은 약점(0간격 버스트 드롭, 이벤트당 5ms에서는 완전 정상)이 paste 접두에서 재현된 것이다 — 같은 약점에는 같은 대응을 쓴다.

## 검토한 대안

- **Notion 붙여넣기 시맨틱 수용**: wise 판정이 로그로 정상 확정된 이상, 남는 유일한 교란은 게시 타이밍이다. 페이싱은 이미 있는 기계의 재사용이고 비용이 접두 몇 타 × 5ms라 시도하지 않을 이유가 없다. 페이싱 후에도 재현되면 그때 앱 시맨틱 수용으로 넘어간다 — 보류.

## Supersedes

- [20260805_visual-refined-group-stroke-pacing.md](20260805_visual-refined-group-stroke-pacing.md) **부분** — "페이싱 범위는 정확화 그룹 한정" 문언에 `.paste`가 추가된다. 스크롤·카운트 버스트·폴백 타이밍 현행 유지 원칙과 5ms 상수·원자 그룹 규칙은 유효.

## 영향 범위

- `KeyboardAdapter` `.paste` 분기: `.groups(groups, paced: true)`
- 기존 테스트 무수정 통과 (페이싱은 게시 순서·키코드를 바꾸지 않는다)
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

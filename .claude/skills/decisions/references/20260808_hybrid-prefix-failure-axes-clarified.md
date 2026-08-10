# "접두 AX 실패 = keyboard 낙하" 문언의 지시 대상 고정 — `unproven` 축 전용

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1b 세션 0 — 해석 고정)

## 결정

위임 표 결정의 "접두 AX 실패 시 그 액션을 통째로 keyboard 경로로 낙하시킨다" 문언은 **오프셋 증명 실패(`unproven`) 축에만** 적용된다. 하이브리드 접두의 실패 세 축은 각각 이미 확정된 결정을 따른다:

| 축 | 시점 | 처리 | 근거 결정 |
|---|---|---|---|
| 오프셋 증명 실패(`unproven`) | 쓰기 시도 전 | **keyboard 위임** (액션 통째 — 맨 `Cmd-V`/`Return` 금지) | [위임 표](20260808_ax-delegation-table-single-driver.md) |
| 요소·읽기 실패 | 쓰기 시도 전 | `.axUnavailable` 스킵 + execute 잔여 접기 | [쓰기 전 단계 실패](20260808_ax-pre-write-failure-ends-execute.md) |
| 접두 쓰기 시도 후 비-`.success`·검증 실패 | 쓰기 시도 후 | **폴백 없음** — 화이트리스트 처리 + 무동작 + execute 잔여 접기 | [화이트리스트·폴백 없음](20260808_ax-write-failure-whitelist-no-fallback.md), [수렴 폴링](20260808_ax-readback-verify-convergence-poll.md) |

"낙하" 문장의 존속 목적은 후반부 — **부분 실행 금지**(접두 없이 맨 위임 키만 내보내지 않는다) — 다.

## 배경·근거 (왜)

- 플랜·위임 표·architecture에 남은 "접두 실패 = 액션 통째 keyboard 낙하" 문언을 그대로 읽으면 쓰기 시도 후 실패까지 낙하 대상이 되어 [폴백 없음 결정]과 정면 충돌한다. D1b 파악 세션의 판정: **모순이 아니라 층위 차이**이며, 문언이 쓰인 설계 세션 시점에는 요소·읽기 실패 축의 처리가 미정(이후 D1a 구현 결정이 `.axUnavailable`로 확정)이라 지시 대상이 넓어 보였을 뿐이다.
- 쓰기 시도 후 낙하가 위험한 근거는 접두에도 그대로 성립한다: `.cannotComplete`는 "이미 캐럿·선택을 옮겼는데 응답만 유실"일 수 있고, keyboard 접두는 캐럿 **상대** 시퀀스라 그 위에서 재실행하면 엉뚱한 위치에서 파괴 단계가 나간다 — 이중 실행 축.
- 해석을 문서로 고정하지 않으면 다음 작업자가 `.hybrid` 분기를 구현하며 "접두 실패 → keyboard 재시도"를 넣는 것이 문언상 자연스러워진다 — 이 문서가 그 자리를 막는다.

## 검토한 대안

- **기록 없이 architecture 문언만 정리**: 결정 문서(위임 표)의 원문이 남아 히스토리 조회 시 같은 오독이 재발한다 — 부분 supersede 마킹이 필요하고, 마킹은 근거 문서를 요구한다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (하이브리드 문단의 실패 축 문언)
- 플랜 문서의 PR-D1b 항목 문언("접두 실패 = 액션 통째 keyboard 낙하")도 같은 독해로 갱신.

## Supersedes

- [20260808_ax-delegation-table-single-driver.md](20260808_ax-delegation-table-single-driver.md) — **부분**: "접두 AX 실패 시 그 액션을 통째로 keyboard 경로로 낙하" 문언의 적용 범위를 `unproven` 축으로 한정(부분 실행 금지 취지는 유효). 표·골격·나머지 규칙은 유효.

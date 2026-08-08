# AX 경로의 collapse는 게시 `←` 유지 — AX 캐럿 쓰기 기각 (동기 쓰기 상시 선착 실측)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1b 세션 0 — 실측 후 결정)

## 결정

AX 경로의 collapse 계열 둘 — **yank collapse**(Normal AX yank의 범위 시작 복귀)와 **`.clearSelection`**(Visual 이탈) — 은 AX 캐럿 쓰기가 아니라 **현행 게시 `←`** 로 실행한다. yank는 위임 오퍼레이터와 같은 게시 스트림(`Cmd-C` 뒤 `←`), `.clearSelection`은 현행 keyboard 시퀀스 그대로다. 위임 표의 두 행("`.clearSelection` = AX 캐럿 쓰기", "yank collapse는 AX 캐럿 쓰기")을 이 결정이 대체한다.

## 배경·근거 (왜)

- **실측이 위험을 "미확정 방향"에서 "상시 역전"으로 바꿨다.** D1a는 "게시 → 동기 AX 쓰기"의 소비 순서를 미확정으로 두고 DEBUG 감사 로그만 심었는데, 세션 0 프로브(선택 수립 → `Cmd-C` 게시 → 즉시 동기 AX 캐럿 쓰기 → 클립보드 판정)의 결과는 레이스가 아니라 사실상 결정적이었다:

  | collapse 지연 | TextEdit | Notion |
  |---|---|---|
  | 없음(컨트롤 — `Cmd-C`만) | 복사 10/10 | 복사 5/5 |
  | **0ms (즉시 동기 쓰기)** | **복사 0/30** | **복사 1/30** |
  | 5ms / 10ms | 2/10 / 8/10 | — |
  | 20ms | 10/10 | **9/10** |

  게시 이벤트의 앱 소비는 양 앱 모두 게시 후 ~25ms(착지 p50 기준)인데 동기 AX 쓰기 효과는 그보다 항상 빠르다. `[.edit(.yank, .selection), .clearSelection]`에서 `.clearSelection`이 AX면 **빈 복사가 상시**이고, Normal AX yank의 collapse를 AX 캐럿 쓰기로 하면 같은 문제가 모든 yank에 내재한다.
- **게시 `←`는 순서가 구조로 보장된다** — 같은 키보드 큐의 FIFO라 `Cmd-C`가 항상 먼저 소비된다.
- **정확화 손실이 없다.** AX 편집은 범위를 이미 정확히 선택해 두므로 `←`의 착지가 곧 범위 시작(Vim 정답)이다 — AX 캐럿 쓰기가 노리던 정확화가 정확한 선택 위의 `←`로 공짜로 달성된다. 현행 `←` collapse의 앱 시맨틱 의존은 신규 위험이 아니다(현행과 동일 의존).
- 부수 효과: 이 결정으로 Visual `y` 조합이 전부 게시 스트림에 남아, D1a의 "한 execute는 전부 AX이거나 전부 위임" 감사 전제가 D1b에서도 깨지지 않는다(하이브리드의 "쓰기 → 게시" 방향만 남는다).

## 검토한 대안

- **조합 인지 강등**(게시가 선행한 경우만 `←`, 단독 `.clearSelection`은 AX 유지): 단독 이탈의 collapse는 어차피 왼쪽 끝 패리티라 AX로 지킬 정확화 가치가 없다 — 특례 복잡성만 산다.
- **고정 지연 후 AX 쓰기**: 실측 기각 — Notion은 20ms 지연에도 1/10이 새고(5~15ms는 비결정 구간), 앱별로 다를 값이라 계약화할 수 없다.
- **게시 소비 확인 후 쓰기**(changeCount 폴링 등): yank에만 신호가 있고 `.clearSelection` 단독(Esc 이탈)에는 확인할 신호 자체가 없다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (위임 표 두 행)
- PR-D1b 편집 하이브리드·Visual 배선: yank collapse·`.clearSelection`은 현행 keyboard 시퀀스 재사용 — AX 신규 코드가 두 자리만큼 준다.
- 세션 0 실측의 부수 확인: 컨트롤(AX 선택 → `Cmd-C`)이 두 앱 모두 선택을 정확히 소비했다 — 편집 하이브리드의 기본 전제("AX 쓰기 → 게시" 방향 안전) 실증. 적용 지연의 정밀 문언은 [20260808_ax-readback-verify-convergence-poll.md](20260808_ax-readback-verify-convergence-poll.md).

## Supersedes

- [20260808_ax-delegation-table-single-driver.md](20260808_ax-delegation-table-single-driver.md) — **부분**: `.clearSelection` 행(AX 캐럿 쓰기 → 게시 `←` 유지)과 편집 행의 "yank collapse는 AX 캐럿 쓰기" 문언. 표의 나머지와 골격 규칙·단일 드라이버는 유효.
- [20260808_ax-edit-select-then-operator-delegate.md](20260808_ax-edit-select-then-operator-delegate.md) — **부분**: "yank의 collapse는 `←` 대신 AX 캐럿 쓰기(범위 시작)로 정확화한다" 문언. 편집 형태(선택 + 오퍼레이터 위임)·되읽어 검증은 유효.

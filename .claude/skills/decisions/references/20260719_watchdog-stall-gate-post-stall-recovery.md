# 워치독 스톨 게이트 — 목적을 "스톨 종료 후 복구"로 확정

- **결정일**: 2026-07-19

## 결정

탭 워치독의 목적을 **"정지/스톨이 풀린 뒤에도 죽은 채 방치되는 탭의 자동 복구"** 로 확정하고, 메인 스레드 스톨 "중"에는 재활성화를 **보류**한다(스톨 게이트). 스톨 신호는 직전 status 홉의 미소비(pending) — bg 틱은 pending이면 틱을 통째로 건너뛴다(재활성화 보류 + 홉 미적재, pending ≤1건). 부수 규칙: status 홉은 FIFO가 보장되는 `DispatchQueue.main.async`로 하고, 토글 off의 최종 `tapEnable(false)`는 워치독 시리얼 큐 뒤에 걸어 in-flight 틱 경합을 큐 순서로 봉인한다.

## 배경·근거 (왜)

PR #13 코드리뷰(워크플로 high)의 CONFIRMED finding: 탭의 run-loop 소스가 메인 런루프에 있으므로([20260712_main-runloop-tap-attachment.md](20260712_main-runloop-tap-attachment.md)), 메인 스톨 중 워치독이 탭을 되살려도 콜백이 돌지 못해 키는 처리되지 않는다. 오히려 살아난 탭이 키를 ~1초씩 잡아두다 OS 타임아웃으로 다시 꺼지는 루프가 되어, 스톨 내내 2초 주기로 타이핑 지연만 반복하며 OS의 보호적 자동 비활성화와 싸운다. 꺼진 탭은 키를 즉시 통과시키므로 **스톨 중에는 꺼진 채 두는 것이 올바른 degrade**다.

워치독 도입의 실측 근거([20260713_tap-reenable-watchdog-polling.md](20260713_tap-reenable-watchdog-polling.md) — SIGSTOP 중 `tapDisabledByTimeout` 통지 유실, SIGCONT 후에도 탭 죽은 채 방치)는 "스톨 종료 후 복구" 시나리오이며 이 목적은 현 구조로 정상 달성된다 — 기존 주석의 "메인 스레드 스톨 복구가 존재 이유"라는 서술이 실제 전달 능력과 어긋나 있었을 뿐이다. 스톨 게이트는 실측 시나리오의 커버리지를 유지하면서 스톨 중의 적극적 해악만 제거한다.

같은 리뷰의 부수 findings 반영:

- **홉 FIFO**: unstructured `Task { @MainActor }`는 실행 순서 보장이 없어 탭 flap 시 낡은 dead 홉이 최신 홉을 덮어써 status가 잘못 래치될 수 있다 → GCD 메인 큐(FIFO)로 교체. 스톨 게이트의 pending ≤1건과 합쳐 이중 봉인.
- **off 경합 봉인**: `stopWatchdog()`의 cancel은 in-flight 틱을 기다리지 않고, 기존 보정(`applyWatchdogResult` off 가드)은 메인 홉 의존이라 메인 스톨과 겹치면 "사용자는 off, 탭은 on"이 유지됐다 → off 경로가 워치독 시리얼 큐 *뒤에* 최종 disable을 추가 게시해 "마지막 동작은 반드시 disable"을 메인 무관하게 보장.
- **[weak self] + 틱 판정 순수 함수 추출**(`watchdogTick`, CGEvent 클로저 주입): 좀비 워치독 누수 클래스 제거 + TEST_HOST 포트 nil로 CI 도달 불가였던 폴링 판정 로직의 단위 테스트 확보. enable+verify 쌍은 `enableAndCheck` nonisolated static 단일 지점으로 수렴(메인 헬퍼·bg 틱 공유).

## 검토한 대안

- **스톨 중에도 재활성화 유지(현상 유지)**: 스톨 중 복구라는 목적을 달성하지 못하면서 타이핑 지연 루프·OS와의 싸움이라는 해악만 있음을 리뷰가 확인. 기각.
- **전용 CFRunLoop 스레드로 탭 이전(스톨 중에도 키 처리)**: 유일한 진짜 "스톨 중 복구" 해법이나 엔진 접근 격리 전체를 손대는 아키텍처 변경 — 이 PR 범위가 아니며 별도 플랜으로 분리([플랜 문서](../../plans/references/20260719_dedicated-tap-runloop-thread.md)). 그 전환이 오면 스톨 게이트의 전제(탭 소스=메인 런루프)가 바뀌므로 이 결정을 재검토한다.
- **mach 타임스탬프 기반 메인 응답성 측정**: pending 플래그(홉 미소비 = 메인 ≥1 폴링 주기 적체)가 같은 신호를 추가 상태 없이 제공. 기각.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 ⑥ 워치독 목적·게이트 서술)
- 코드: `VimAction/EventTapController.swift` (startWatchdog 핸들러·watchdogTick·applyWatchdogResult·didSet off 분기), `VimActionTests/TapWatchdogTests.swift`
- [20260713_tap-reenable-watchdog-polling.md](20260713_tap-reenable-watchdog-polling.md)는 뒤집지 않는다 — 워치독 존재·폴링 방식은 유지, 이 문서는 목적 서술과 스톨 중 동작을 확정.

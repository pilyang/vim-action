# 전용 CFRunLoop 스레드 재검토 — 탭을 메인 런루프에서 분리

- **생성일**: 2026-07-19
- **갱신일**: 2026-07-19

## 목표

탭 run-loop 소스를 메인 런루프에서 전용 CFRunLoop 스레드로 옮길지 **결정**하고, 옮긴다면 구현까지: 메인 스레드 스톨 중에도 키 이벤트가 처리(또는 즉시 통과)되어 시스템 전역 키보드가 앱 상태에 인질로 잡히지 않는 상태. 옮기지 않기로 하면 그 근거를 decisions에 기록하고 이 플랜을 정리한다.

## 완료된 것

- [x] 재검토 필요성 확정 (2026-07-19, PR #13 코드리뷰): 메인 런루프 부착([결정](../../decisions/references/20260712_main-runloop-tap-attachment.md))은 "엔진 연결 전 재검토" 조건부였는데 엔진은 이미 연결됨. 리뷰 CONFIRMED finding — 현 구조에서는 메인 스톨 중 키 처리가 원리적으로 불가능(워치독도 못 덮음). 과도기 대응으로 워치독 스톨 게이트 적용([결정](../../decisions/references/20260719_watchdog-stall-gate-post-stall-recovery.md)) — "스톨 중 복구"는 이 플랜의 전용 스레드 전환이 유일한 해법.

## 남은 것

- [ ] **판단 데이터 수집·결정**: 실사용에서 `tapDisabledByTimeout` 재활성화·워치독 복구 로그 빈도 확인(메인 런루프 부착 결정이 예약한 판단 기준). AX 호출이 콜백 경로에 들어오는 디스패처 마일스톤과 시점 조율 — 원 결정의 재검토 지점이자 스톨 위험이 실제로 커지는 시점. 결론을 decisions에 기록.
- [ ] (전환 결정 시) **설계**: 전용 스레드의 CFRunLoop 수명 관리, 콜백의 `MainActor.assumeIsolated` 제거와 엔진 접근 격리 재설계(엔진 소유를 스레드로 이전 vs 락 vs actor), `mode` 관찰 프로퍼티의 메인 반영, KeyTranslator `@MainActor`(TIS 요구)와의 정합.
- [ ] (전환 결정 시) **구현·검증**: 워치독 스톨 게이트 전제(탭 소스=메인)가 바뀌므로 게이트 재설계 포함. 실기기에서 메인 스톨 유도 후 키 처리 지속 확인.

## 진행 중 컨텍스트

- 미착수 (결정 대기 단계). 착수 전 이 플랜과 [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md)·[20260719_watchdog-stall-gate-post-stall-recovery.md](../../decisions/references/20260719_watchdog-stall-gate-post-stall-recovery.md)를 함께 읽을 것 — 전환 시 깨지는 가정(콜백 `assumeIsolated`, 워치독 스톨 게이트, KeyTranslator 메인 스레드)이 이 문서들에 명시돼 있다.
- 콜백이 무거워지는 디스패처 마일스톤(AX 프로브 3ms 캡이 콜백 경로에 들어옴) 전에 결정하는 것이 안전 — 그 후엔 스톨 가능성 자체가 커진다.

## 관련 링크

- architecture: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md), [system-overview.md](../../architecture/references/system-overview.md)
- decisions: [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md), [20260713_tap-reenable-watchdog-polling.md](../../decisions/references/20260713_tap-reenable-watchdog-polling.md), [20260719_watchdog-stall-gate-post-stall-recovery.md](../../decisions/references/20260719_watchdog-stall-gate-post-stall-recovery.md)

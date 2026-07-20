# 전용 CFRunLoop 스레드 재검토 — 탭을 메인 런루프에서 분리

- **생성일**: 2026-07-19
- **갱신일**: 2026-07-20

## 목표

탭 run-loop 소스를 메인 런루프에서 전용 CFRunLoop 스레드로 옮길지 **결정**하고, 옮긴다면 구현까지: 메인 스레드 스톨 중에도 키 이벤트가 처리(또는 즉시 통과)되어 시스템 전역 키보드가 앱 상태에 인질로 잡히지 않는 상태. 옮기지 않기로 하면 그 근거를 decisions에 기록하고 이 플랜을 정리한다.

## 완료된 것

- [x] 재검토 필요성 확정 (2026-07-19, PR #13 코드리뷰): 메인 런루프 부착([결정](../../decisions/references/20260712_main-runloop-tap-attachment.md))은 "엔진 연결 전 재검토" 조건부였는데 엔진은 이미 연결됨. 리뷰 CONFIRMED finding — 현 구조에서는 메인 스톨 중 키 처리가 원리적으로 불가능(워치독도 못 덮음). 과도기 대응으로 워치독 스톨 게이트 적용([결정](../../decisions/references/20260719_watchdog-stall-gate-post-stall-recovery.md)) — "스톨 중 복구"는 이 플랜의 전용 스레드 전환이 유일한 해법.

## 남은 것

- [ ] **판단 데이터 수집**: 재활성화·워치독 복구 로그는 전부 `.info` 레벨이라 **디스크에 안 남는다**(Logging.swift 주석) — 과거 `log show` 조회 불가, 측정 창을 새로 열어야 함. 방법: `sudo log config --mode "persist:info" --subsystem dev.pilyang.VimAction`으로 영속화 후 실사용 → `log show --predicate 'subsystem == "dev.pilyang.VimAction"' --info`로 "탭 재활성화"·"워치독 — 비활성 탭 복구" 빈도 집계 (또는 `log stream` 백그라운드 수집).
- [ ] **결정**: 실측 빈도 + 전략 요인(디스패처 마일스톤에서 AX 프로브 3ms 캡이 콜백 경로에 들어와 스톨 위험이 커짐 — 빈도가 0이어도 선제 전환할지) 종합해 전환/유지 결정, decisions에 기록. 유지 결정 시 이 플랜 완료 처리로 종료.
- [ ] (전환 결정 시) **설계** — 깨지는 가정 4개 각각: ① 전용 스레드·CFRunLoop 수명(소스 add/remove는 탭 스레드 런루프에서, startIfPermitted/stop()/토글 didSet의 스레드 경계) ② 콜백 `MainActor.assumeIsolated` 제거 + 엔진 접근 격리(엔진 소유를 탭 스레드로 이전 vs 락 vs actor — 콜백이 동기 반환이라 actor는 부적합 가능성) + `mode` 관찰 프로퍼티 메인 홉 반영 ③ KeyTranslator `@MainActor`(TIS 요구) — 레이아웃 캐시의 탭 스레드 읽기 경로 ④ 워치독 스톨 게이트 전제(탭 소스=메인) 소멸 — 게이트 재설계·20260719 결정 재검토.
- [ ] (전환 결정 시) **구현·검증**: 기존 유닛 테스트 GREEN(TapWatchdogTests는 게이트 재설계 반영 수정), 실기기에서 메인 스톨 유도(디버그 임시 트리거) 후 키 처리 지속 확인, architecture references(system-overview·reentrancy-and-safety) 갱신.

## 진행 중 컨텍스트

- 2026-07-20 착수 — 워크트리 `dedicated-tap-runloop-thread`에서 작업 (`.claude/worktrees/` 하위). 플랜 인덱스 갱신은 메인 체크아웃에서 유지.
- 콜백 코드 현황: `EventTapController.swift` — `CFRunLoopGetMain()` 부착(startIfPermitted), 콜백 `assumeIsolated`(파일 하단 `eventTapCallback` 주석에 가정 명시), 워치독 스톨 게이트(`watchdogHopPending`). 착수 전 이 플랜과 [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md)·[20260719_watchdog-stall-gate-post-stall-recovery.md](../../decisions/references/20260719_watchdog-stall-gate-post-stall-recovery.md)를 함께 읽을 것 — 전환 시 깨지는 가정(콜백 `assumeIsolated`, 워치독 스톨 게이트, KeyTranslator 메인 스레드)이 이 문서들에 명시돼 있다.
- 콜백이 무거워지는 디스패처 마일스톤(AX 프로브 3ms 캡이 콜백 경로에 들어옴) 전에 결정하는 것이 안전 — 그 후엔 스톨 가능성 자체가 커진다.

## 관련 링크

- architecture: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md), [system-overview.md](../../architecture/references/system-overview.md)
- decisions: [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md), [20260713_tap-reenable-watchdog-polling.md](../../decisions/references/20260713_tap-reenable-watchdog-polling.md), [20260719_watchdog-stall-gate-post-stall-recovery.md](../../decisions/references/20260719_watchdog-stall-gate-post-stall-recovery.md)

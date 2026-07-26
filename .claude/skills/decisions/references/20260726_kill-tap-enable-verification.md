# 킬 탭 활성화 검증과 `Installation.failed` — 재시도 타이머는 기각

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

킬 탭의 두 활성화 지점(전용 스레드의 최초 `tapEnable(true)`, `reenableAfterDisable`) 모두에서 **`tapIsEnabled`로 검증**한다. 메인 탭의 `enableAndCheck`와 같은 계약이다.

검증 실패 시:
1. `Logger.eventTap.fault`를 **킬 스레드에서 직접** 남긴다 (메인이 굳어도 기록은 남아야 한다).
2. `main.async` 홉으로 `Installation.failed`로 강등한다. UI 갱신은 부차 채널 — Settings 자체가 메인 구동이라 홉이 못 가는 상황에서는 어차피 볼 수 없고, `async`라 킬 스레드를 붙잡지 않는다.

`Installation`에 **`case failed`를 신설**한다. Settings "Kill Switch" 행은 `"Failed (tap inactive)"`.

**재시도 타이머는 두지 않는다.** [킬 탭 전용 워치독 기각](20260726_kill-switch-dedicated-runloop-thread.md)은 유지하며, 그 자리를 메우는 것은 폴링이 아니라 검증이다.

## 배경·근거 (왜)

기존 코드는 `installation = .hid`와 "설치 완료" 로그를 **전용 스레드가 돌기도 전에** 확정하고, 실제 `tapEnable(true)`는 검증 없이 지나갔다. `reenableAfterDisable`도 `tapEnable(true)` 후 무조건 "재활성화" 로그를 남겼다. 활성화가 먹지 않으면 Settings가 세션 내내 "Active (HID)"를 주장하는 채로 안전장치만 부재한다 — [파일 헤더가 스스로 최악의 실패 모드로 지목한 상태](20260726_kill-switch-hid-tap-session-fallback.md)("안전장치가 조용히 부재하는 것이 최악")가 그대로 실현된다.

**재활성화 지점에서 특히 중요한 이유 — 실측**: `tapDisabledBy*` 통지는 **평생 한 번뿐**이다. 콜백을 3초 스톨시켜 timeout-disable을 유발한 뒤 재활성화하지 않고 10초간 이벤트를 계속 넣었으나 통지는 1건에서 늘지 않았다(꺼진 탭은 이벤트를 받지 못하므로 두 번째 통지의 계기가 없다). 워치독도 없으므로 여기서 실패를 놓치면 **복구 기회가 영영 없다**.

**왜 워치독이 아니라 검증인가**: [전용 워치독 기각](20260726_kill-switch-dedicated-runloop-thread.md)의 논거는 "스톨로 통지가 유실되는 실패 모드가 이 콜백엔 없다"였다. 그 논거는 여전히 옳고, 더 강한 논거가 하나 더 있다 — 메인 탭의 재활성화는 **게이트가 걸려 있어**(킬 래치·토글 off) 의도적으로 건너뛴 재활성화를 나중에 폴링이 풀어 줘야 하는데, 킬 탭의 `reenableAfterDisable`에는 게이트가 하나도 없어 "보류됐다 잊히는" 상태 자체가 존재하지 않는다. 남은 실패 모드는 "통지는 왔는데 활성화가 거부됨"이고, 그건 폴링이 아니라 검증으로 닫는다.

**`.notInstalled` 재사용을 피하는 이유**: 강등 상태로 `.notInstalled`를 쓰면 `startIfPermitted`의 `guard installation == .notInstalled` 설치 가드가 **다시 열리는데** `portBox`에는 살아 있는 포트가 남아 있다. 권한 재부여 경로가 두 번째 탭을 만들고 첫 탭을 고아로 남긴다. 새 케이스가 3줄이면 충분하고 enum이 정직한 SSOT로 남는다.

## 검토한 대안

- **`CFRunLoopTimer`로 유계 재시도**: 킬 스레드에 이미 런루프가 있어 구현은 가능하다. 그러나 **반복 타이머는 런루프를 영구히 붙잡아** `stop()`의 `CFMachPortInvalidate`로 소스가 사라지면 스레드가 끝난다는 수명 계약을 깬다 — 실험으로 재현했다(타이머 없음: `CFRunLoopRun` 반환 후 스레드 종료 / 타이머 있음: 3초 후에도 스레드 생존). 일회성 자기 재예약 체인 + `stop()`의 타이머 무효화로 우회할 수는 있으나, **거부는 일시적이 아니라 영구적(포트 무효/코드 신원)** 성격이라 재시도의 기대값이 거의 없다. 투기적 복잡도로 기각.
- **활성화 실패 시 스레드를 즉시 종료**: 소스가 붙은 뒤 실패한 것이므로 종료해도 무방하나, "포트 invalidate → 스레드 종료"라는 단일 수명 계약에서 벗어난다. 실패해도 `CFRunLoopRun()`을 그대로 돌려 계약을 일관되게 유지한다.
- **`installation` 확정을 스레드 활성화 이후로 미루기**: 보고와 실제가 동기화되지만 `startIfPermitted`가 비동기가 되어 `AppState.bootstrap`의 순서 계약이 흐려진다. 낙관적으로 게시하고 실패 시 강등하는 쪽을 택했다.

## 영향 범위

- 코드: `VimAction/KillSwitchTap.swift`(`Installation.failed` 신설, 스레드 활성화 검증, `reenableAfterDisable` 검증, `reportEnableFailure` 헬퍼), `VimAction/SettingsView.swift`(`killSwitchStatusText`의 `.failed` 분기)
- 테스트: `VimActionTests/KillSwitchTests.swift` — `failedIsNotReportedAsActive`("Active"를 포함하지 않음까지 단언)
- 함께 들어간 인접 수정: 스레드의 `CFMachPortCreateRunLoopSource` nil 가드. 반환형·파라미터가 모두 Optional이라 무효 포트의 NULL이 Swift 검사 없이 C로 건너가 널 역참조로 프로세스가 죽는다(재현 확인). 창은 극히 좁다 — `bootstrap`은 SwiftUI Scene과 Quit 버튼이 생기기 전에 돌아 앱 내 트리거가 사실상 없다.

## Supersedes

없음. [20260726_kill-switch-dedicated-runloop-thread](20260726_kill-switch-dedicated-runloop-thread.md)의 워치독 기각 결정을 **유지·보강**하며(그 자리를 검증이 메운다), [20260726_kill-switch-hid-tap-session-fallback](20260726_kill-switch-hid-tap-session-fallback.md)의 `Installation` 노출 결정을 케이스 하나로 **확장**한다.

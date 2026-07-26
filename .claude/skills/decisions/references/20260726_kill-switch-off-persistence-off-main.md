# 킬스위치 off 영속은 메인 홉과 독립 — defaults의 두 번째 writer 허용

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

킬스위치 발동은 off 상태를 **메인 홉과 무관하게 직접 영속**한다. 영속 단일 지점을 `nonisolated static func persistInterceptionEnabled(_:to:)`로 빼고, `isInterceptionEnabled`의 didSet과 `triggerKillSwitch`가 **같은 함수를 공유**한다.

호출 위치는 `triggerKillSwitch`의 **맨 마지막** — 래치 설정 → `tapEnable(false)` → fault 로그 → `main.async` 홉 **뒤**다. 이 호출만 `cfprefsd`로 나가는 XPC라 유일하게 블록될 수 있으므로, 안전장치의 핵심 동작이 그것을 기다려서는 안 된다.

이를 위해 `defaults`는 `nonisolated(unsafe) let`, `PreferenceKeys`는 `nonisolated enum`으로 연다.

## 배경·근거 (왜)

[20260726_kill-switch-trigger-semantics](20260726_kill-switch-trigger-semantics.md) 2항은 영속을 포함한 모든 후속 효과를 ②(메인 홉의 didSet)에 위임했다. 그런데 **킬스위치가 존재하는 시나리오는 "메인이 굳었다"** 이고, 그 상태에서 `main.async` 블록은 영원히 착지하지 않는다. 결과:

1. 메인 데드락 → 콤보 → ①이 실행되어 키는 풀림 ✅
2. ②는 메인 큐에 쌓인 채 실행 안 됨 → `defaults.set` 도달 못 함
3. 사용자가 굳은 앱을 강제 종료
4. 재실행 → `init`이 `interceptionEnabled`를 여전히 `true`로 읽음 → 탭 다시 켜짐

즉 안전장치가 **정확히 자기 존재 이유인 상황에서만** 재시작을 넘기지 못했다.

**영속이 강제 종료를 견디는가** — 이 결정의 성립 여부가 여기 달려 있어 실측했다. `UserDefaults.set`은 반환 전에 `cfprefsd`로 **동기 XPC 왕복**을 하므로, 반환 시점에 값은 이미 다른 프로세스 소유다. 지연 0으로 `kill(getpid(), SIGKILL)` 직후 재기동해 읽기: 5/5 생존(독립 검증 100/100, 왕복 ~120µs). Apple 문서의 "writes the value to disk asynchronously"는 *cfprefsd → 디스크*(~10초 코얼레스)를 말하는 것이지 *프로세스 → cfprefsd*가 아니며, `synchronize()` 권고는 10.7 이전 유물이다.

**소유 모델을 무르게 하는 대가**: [20260718_interception-toggle-semantics](20260718_interception-toggle-semantics.md)는 "런타임 SSOT는 프로퍼티, defaults는 didSet이 쓰는 팔로워"를 세웠다. 이 결정은 writer를 하나 더 만든다. 완화책으로 **두 경로가 같은 함수를 부르게** 해서 "영속 단일 지점"이라는 정신은 유지한다. 홉이 정상 착지하는 일반 경우에는 didSet이 같은 값을 멱등하게 다시 쓸 뿐이라 어긋나지 않는다.

**심각도**: 덫이 아니라 한 번의 추가 사이클이다 — 재실행 후 콤보를 다시 누르면 이번엔 정상 영속되고, 실제 스톨 중에는 macOS가 응답 없는 탭을 스스로 끈다(`tapDisabledByTimeout`). 그래도 "안전장치를 눌렀는데 재시작하면 원상복귀"는 사용자가 안전장치를 신뢰할 수 없게 만드는 종류의 실패라 고친다.

**전제(현재 유효)**: off-main 쓰기가 안전한 것은 이 코드베이스에 `@AppStorage`도 `UserDefaults` KVO 옵저버도 **없기 때문**이다(grep 확인). 누군가 `interceptionEnabled`에 `@AppStorage`를 물리면 이 결정을 재검토해야 한다.

## 검토한 대안

- **홉 앞에서 영속**: 처음 제안한 위치. XPC 왕복이 래치·`tapEnable(false)`·홉보다 앞서게 되어 안전장치 핵심 경로에 블로킹 가능 호출을 심는다. 순서를 뒤로 옮겨 기각.
- **별도 `killSwitchFired` 플래그를 킬 스레드가 쓰고 init이 확인**: 소유 모델을 건드리지 않지만 상태가 둘로 늘어 동기화 문제가 새로 생긴다. 기각.
- **수용 + 문서화**: 존재 이유와 정면 충돌한다. 기각.

## 영향 범위

- 코드: `VimAction/EventTapController.swift`(`persistInterceptionEnabled` 신설·didSet 경유·`triggerKillSwitch` 말미 호출·`defaults` 격리 완화), `VimAction/Preferences.swift`(`nonisolated enum PreferenceKeys`)
- 테스트: `VimActionTests/KillSwitchTests.swift` — `triggerPersistsOffWithoutMainHop`(홉을 배수하지 않고 영속 검증). mutation 확인: 직접 영속 호출을 제거하면 이 테스트만 RED.
- **부수 발견 — 공허한 단언**: `defaults.bool(forKey:)`는 미설정 키에도 `false`를 주므로 `#expect(bool(forKey:) == false)`는 영속 코드를 통째로 지워도 통과한다. 이 갭이 "커버된 것처럼 보이는 테스트"와 함께 출시된 원인이라, 4곳(`KillSwitchTests`·`SafetyToggleTests`×2·`FailureBurstCounterTests`)에 `object(forKey:) != nil` 존재 확인을 앞세웠다.

## Supersedes

- [20260726_kill-switch-trigger-semantics.md](20260726_kill-switch-trigger-semantics.md) — **부분 supersede**. 2항 중 "②의 didSet이 …영속…을 전담한다"만 뒤집는다(영속은 킬 경로도 직접 수행). 2겹 효과 구조, "자동/외부 off 전용 경로를 만들지 않는다"는 규칙, 나머지 후속 효과(엔진 리셋·워치독 정지·경합 봉인·메뉴바)의 didSet 위임은 유효하다.
- [20260718_interception-toggle-semantics.md](20260718_interception-toggle-semantics.md) — **부분 supersede**. "defaults는 didSet이 쓰는 팔로워"라는 단일 writer 모델만 완화한다(킬 경로가 두 번째 writer, 단 같은 함수 공유). 토글 off/on 의미론, 프로퍼티 SSOT, `.running`이 설치 헬스라는 정의는 모두 유효하다.

두 옛 문서 모두 유효한 조항이 대부분이므로 인덱스에 남긴다.

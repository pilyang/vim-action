# ActionExecutor는 타입 단위 nonisolated + Sendable, 게시 클로저는 @Sendable

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

`SyntheticEventMarker`와 `ActionExecutor`는 **타입 단위 `nonisolated`** 로 선언한다 — 멤버별이 아니라 타입에 붙여 저장 프로퍼티(`magic`, `postEvent`)까지 기본 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)에서 벗어나게 한다. `ActionExecutor`는 **`Sendable`을 명시적으로 선언**하고, 주입되는 게시 클로저의 계약은 **`@Sendable (CGEvent) -> Void`** 다.

`CGEvent`가 `Sendable`이 아닌 데 대한 답은 어노테이션 우회가 아니라 계약이다: **합성 `CGEvent`는 `post`를 호출하는 그 컨텍스트(직렬 큐)에서 만든다.** 어댑터가 큐 위에서 시퀀스를 생성하면 격리 경계를 건너는 비-`Sendable` 값이 애초에 존재하지 않는다.

## 배경·근거 (왜)

`ActionExecutor` 신설(`5b71e94`) 당시 격리는 **함수에만** 붙어 있었다 — `mark`/`isMarked`/`init`/`post`가 `nonisolated`인데 그들이 만지는 데이터는 표시가 없어 MainActor 소속으로 남았다. 그 모순이 빌드 경고 4건이었고, 그중 `nonisolated init`에서 MainActor 프로퍼티를 변이하는 건은 컴파일러가 *"this is an error in the Swift 6 language mode"* 로 명시했다.

방향은 "MainActor로 되돌리기"가 아니라 "끝까지 nonisolated"다 — [콜백 경량 불변식](20260725_callback-light-invariant.md)이 **실행을 탭 콜백 밖 직렬 큐**로 밀어내기 때문이다. `ActionExecutor`는 정의상 비메인에서 호출될 타입이고, 마커 판독자인 킬 탭 콜백도 이미 [전용 런루프 스레드](20260726_kill-switch-dedicated-runloop-thread.md)에서 메인 격리를 가정하지 않은 채 `SyntheticEventMarker.isMarked`를 부른다.

`@Sendable`을 지금 붙이는 이유는 M2 배선의 선반영이다. 없으면 `postEvent`가 비-`Sendable`이라 `ActionExecutor` 전체가 비-`Sendable`이 되고, M2가 이 값을 `DispatchQueue.async`(=`@Sendable` 클로저)에 캡처하는 순간 같은 문제를 다시 만난다. `KillSwitchTap.onTrigger`가 이미 같은 계약(`@Sendable () -> Void`)을 쓴다.

`Sendable` 준수를 **추론에 맡기지 않고 명시**한 것은, 이 타입의 존재 이유가 "큐를 건너간다"이기 때문이다 — 나중에 누가 비-`Sendable` 저장 프로퍼티를 추가하면 M2 호출부가 아니라 **그 자리에서** 컴파일 에러가 나야 한다.

**타이밍**: 호출자가 0명인 지금이 가장 싼 시점이다. M2가 게시를 배선한 뒤에는 같은 정리가 호출부 연쇄 수정을 동반한다.

## 검토한 대안

- **멤버별 `nonisolated` 유지하고 데이터에만 추가**: 경고는 사라지지만 "이 타입은 어디서든 쓸 수 있다"는 의도가 선언 4곳에 흩어져 남는다. `KillSwitchTap`의 멤버별 `nonisolated`와 달리 — 그쪽은 `@MainActor` 클래스의 **일부 멤버만** 비메인이라 멤버 단위가 정확하다 — 여기는 타입 전체가 비메인이라 타입 단위가 의도를 그대로 표현한다.
- **`ActionExecutor`를 `@MainActor`로 고정**: 경고는 없어지지만 콜백 경량 불변식과 정면 충돌한다. 게시가 메인에 묶이면 실행을 콜백 밖으로 밀어낸 의미가 사라진다.
- **`nonisolated(unsafe)`·`@unchecked Sendable`로 덮기**: 지금은 필요조차 없었다(정리 후 새 Sendable 경고 0건). 필요해 보였더라도 이건 검사를 끄는 것이지 계약을 정하는 것이 아니다.
- **테스트 수집기를 잠금 기반으로 교체**: `@Sendable` 명시가 기존 `nonisolated(unsafe) var posted` 캡처를 깨뜨릴 것을 대비했으나 실제로는 무변경이었다(`SWIFT_APPROACHABLE_CONCURRENCY`의 `InferSendableFromCaptures`가 이미 그 클로저 리터럴을 `@Sendable`로 추론하고 있었다). 깨지지 않은 것을 고치지 않는다.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 코드: `VimAction/ActionExecutor.swift` (기능 변화 0 — 격리 선언만). 테스트·호출부 변경 없음.
- **빌드 경고 기준선이 4건 → 0건**이 됐다. 이후 마일스톤은 0을 기준으로 비교한다.
- **Swift 6 모드 프로브 결과**(2026-07-26, `SWIFT_VERSION=6.0` 명령줄 오버라이드): `ActionExecutor.swift`는 진단 0건으로 깨끗하다. 앱 타깃 전체로는 `AccessibilityPermissionMonitor.swift:35`가 유일하게 남는다 — `kAXTrustedCheckOptionPrompt`(전역 `var`) 참조가 Swift 6 모드에서만 에러이고 Swift 5 모드에선 경고조차 없다. Swift 6 언어 모드 전환 시 처리해야 할 **유일한** 잔여 항목이다.
- M2 인계: 어댑터는 **직렬 큐 위에서** CGEvent 시퀀스를 만들고 같은 컨텍스트에서 `post`를 호출한다. 탭 콜백(메인)에서 만든 CGEvent를 큐로 넘기는 형태를 택하면 비-`Sendable` 값이 격리를 건너게 되고, 그 순간 필요한 것은 우회 어노테이션이 아니라 이 결정의 재검토다.

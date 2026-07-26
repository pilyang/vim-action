# M2 실행 배선 형태 — sink 클로저가 게시 큐를 소유

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

`EventTapController`는 실행 계층을 **주입된 sink 클로저 하나**(`@Sendable ([VimAction]) -> Void`)로만 안다. 프로덕션 기본값을 만드는 팩토리(`keyboardActionSink()`)가 게시 직렬 큐(`dev.pilyang.VimAction.execution`, `qos: .userInitiated`)와 `KeyboardAdapter`를 캡처하므로, 큐의 소유자·수명은 그 클로저(= 컨트롤러의 저장 프로퍼티)다. 별도 디스패처 객체를 두지 않는다.

**기본 팩토리는 XCTest 하위에서 무해한 것으로 바꿔치기한다**: 실행 sink는 no-op이 되고, 앱 게이트(`FrontmostAppGate.forCurrentEnvironment()`)는 실제 최전면 앱을 조회하지 않는다(격리된 `NotificationCenter` + `nil` 시드). 게이트·배선 **동작을 검증**하는 테스트는 init으로 자기 것을 명시 주입한다.

## 배경·근거 (왜)

- **큐를 클로저가 들게 한 이유**: 컨트롤러가 큐와 어댑터를 각각 `private let`으로 들면 소유자는 더 드러나지만, 배선을 검증하는 테스트가 큐 홉을 넘어야 해 단언이 비동기가 된다(세마포어·`confirmation`). 클로저 주입은 `ActionExecutor.postEvent`와 **같은 seam**이라, 테스트가 동기 수집기를 넣어 "무엇이 실행 계층으로 넘어가는가"만 즉시 단언한다. 저장소의 기존 분리 원칙(순수 판정은 단위 테스트, 큐·타이머 결합은 실기기 GREEN — `watchdogTick` 선례)과 같은 선택이다.
- **어댑터 호출이 큐 클로저 *안*인 것이 계약**: `CGEvent`는 비-`Sendable`이라 생성과 게시가 같은 컨텍스트여야 한다([20260726_action-executor-nonisolated-sendable.md](20260726_action-executor-nonisolated-sendable.md)). 큐가 **직렬**인 것도 계약이다 — 키 입력 여러 건의 키스트로크 순서가 섞이면 캐럿이 엉뚱한 곳으로 간다.
- **XCTest 가드가 필요한 이유는 두 가지고, 둘 다 실제 사고다**:
  1. TEST_HOST가 앱 프로세스라 가드가 없으면 `.replace`를 만드는 기존 테스트(`EventTapDecisionTests`의 "Normal: h")가 **개발자 머신에 실제 화살표 키를 주입**한다 — 포커스된 아무 앱에나 들어간다.
  2. 게이트 기본값이 실제 최전면 앱을 읽으면 **Ghostty에서 `xcodebuild test`를 돌릴 때**(disable 목록에 있는 이유가 곧 주력 터미널이라는 것이므로 정상 워크플로우다) 게이트가 켜진 채 모든 `handleKeyDown` 테스트가 "통과"로 뒤집힌다. 머신 상태에 따라 GREEN이 흔들리는 부류다.
  `bootstrap`·`startIfPermitted`가 라이브 탭 설치를 같은 방식으로 막는 선례가 있어, 새 규칙이 아니라 기존 규칙의 적용이다.
- **실패 보고는 배선하지 않았다**: Keyboard 게시 경로(`ActionExecutor.post` → `CGEvent.post`)는 오류를 돌려주지 않아 접을 실패가 없다([20260726_execution-failure-report-granularity.md](20260726_execution-failure-report-granularity.md)의 "첫 호출자에서의 도달 범위 주의"). 따라서 그 문서의 **M2 항목 1**(백그라운드 큐에서의 보고 배선)은 이 결정으로 닫히지 않고 열린 채 남으며, [20260725_failure-burst-autodisable-shape.md](20260725_failure-burst-autodisable-shape.md) **4항(카운터는 MainActor 전용)을 supersede할 필요도 없다** — 실행 큐는 생겼지만 카운터를 건드리는 코드가 생기지 않았다. 보고 형태는 `AXError`를 돌려주는 M5 AX 어댑터가 실제 실패를 만든 뒤 정한다.

## 검토한 대안

- **컨트롤러가 큐·어댑터를 직접 `private let`으로 소유** (`watchdogQueue` 선례): 소유자가 코드에서 가장 잘 드러나지만 배선 검증이 비동기 단언이 된다. 큐 홉의 존재는 어차피 실기기 검증 몫이라 그 비용만 남는다. 기각.
- **별도 `ActionDispatcher` 객체를 AppState가 소유·주입**: M3·M5의 전략 디스패처 자리를 미리 만드는 셈인데, 지금 호출 지점은 `.replace` 한 곳뿐이라 단일 사용처 추상화다. 디스패처가 실제로 앱/요소별 분기를 갖게 될 때 만든다. 기각.
- **기본값은 항상 실경로 + `.replace`를 만드는 테스트마다 sink 주입 의무**: 명시적이지만, 앞으로 추가되는 테스트가 빠뜨리는 순간 개발자 머신에 키가 새어 나간다. 안전 기본값이 옳은 방향이다. 기각.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (과도기 문단 — 실행 계층에 호출자가 생겼다)
- 앱: `EventTapController`(주입 3종 + `keyboardActionSink`, `.replace` 분기가 `dispatchActions` 호출), 신규 `FrontmostAppGate`(`forCurrentEnvironment`).
- 테스트: `ExecutionWiringTests`(게이트 통과·모드 동결·sink 전달), `FrontmostAppGateTests`. 기존 컨트롤러 테스트는 기본값이 무해해져 변경 없이 통과한다.
- 관련 결정: [20260725_callback-light-invariant.md](20260725_callback-light-invariant.md)(실행은 콜백 밖), [20260726_m2-app-gate-pre-engine-passthrough.md](20260726_m2-app-gate-pre-engine-passthrough.md)(게이트 위치), [20260726_motion-keystroke-mapping-contract.md](20260726_motion-keystroke-mapping-contract.md)(큐 위에서 변환).

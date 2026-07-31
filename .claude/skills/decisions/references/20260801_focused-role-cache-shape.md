# focusedRole 캐시 형태 — AX 읽기는 메인 밖, 3ms 캡은 리졸버에 쓰지 않는다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

`FocusedElementResolver`는 `@MainActor` 캐시이고 탭 콜백은 캐시만 읽는다(앱 게이트와 같은 형태). 갱신은 다음과 같다:

1. **트리거 2경로** — `NSWorkspace` 앱 활성화 알림(옵저버를 새 앱으로 갈아탐)과 `AXObserver`의 `kAXFocusedUIElementChangedNotification`(런루프 소스는 메인).
2. **AX 호출은 전용 직렬 큐 위에서만** 한다. 메인 스레드는 AX를 **아예 호출하지 않는다**.
3. **메시징 타임아웃은 50ms** — 리졸버 경로에는 3ms 캡을 쓰지 않는다.
4. 큐로 넘기는 것은 **`pid_t` 하나**다. `AXUIElement`를 격리 경계로 넘기지 않는다.
5. 앱 전환 순간 캐시를 **즉시 폴백(`.textArea`)으로 리셋**하고, 읽기 결과가 나중에 정정한다.
6. 늦게 착지한 읽기는 **토큰 비교로 폐기**한다.
7. 계열은 **키 입력 시점에 콜백이 읽어** 디스패치 페이로드로 실린다 — 게시 큐가 나중에 읽지 않는다.

## 배경·근거 (왜)

### ③ 3ms를 안 쓰는 이유 — 실측

[AX 감지 하드 타임아웃 3ms](20260712_ax-probe-hard-timeout-3ms.md)는 스스로 "실기기 계측 없이 정한 초기 추정값이며 오폴백이 관찰되면 재검토한다"고 명시했다. **관찰됐다.** 장수 프로세스 하나가 앱 6종을 순회하며 `AXFocusedUIElement`를 읽은 결과(2026-08-01):

| | 3ms 캡 | 500ms 캡 |
|---|---|---|
| **앱 최초 접촉** (Finder·TextEdit·Notion·Chrome·VS Code·Slack **전부**) | `kAXErrorCannotComplete` — **6/6 실패** | 성공, 17~21ms |
| 웜(같은 앱 재조회) | 성공, 0.2~1.7ms | 성공, 0.1~1.2ms |

즉 3ms를 지키면 **앱을 바꿀 때마다 첫 판정이 반드시 폴백**이 된다. 그리고 focusedRole은 앱 전환 직후가 정확히 가장 중요한 순간이다 — Finder로 넘어가 `p`를 누르는 흐름이 바로 그 시나리오다. 3ms 캡을 지킨 리졸버는 겨냥한 위험을 **구조적으로 놓친다**.

### ② 읽기를 메인 밖으로 빼는 이유

그렇다고 50ms 호출을 메인에 두면 안 된다. 메인 런루프에는 이벤트 탭이 붙어 있어([탭 메인 런루프 유지](20260725_tap-main-runloop-retention.md)), 앱 전환마다 ~20ms 블로킹은 그만큼 키 배달을 미룬다. 3ms 캡이 존재했던 목적 자체가 "블로킹 AX가 탭을 멈추게 하지 마라"인데, **캡을 늘리는 대신 호출을 메인에서 빼면 그 목적이 더 강하게 달성된다** — 메인이 AX를 아예 안 하므로 타임아웃 값이 탭 안정성과 무관해진다. [콜백 경량 불변식](20260725_callback-light-invariant.md)이 요구한 것보다 강한 보장이다(그 결정은 콜백만 제한했고, 알림 처리 쪽 AX는 허용했다).

### ④ pid만 넘기는 이유

`AXObserver` 콜백은 바뀐 요소를 직접 건네주므로 그것을 쓰면 왕복 한 번을 아낀다. 그러나 `AXUIElement`는 비-`Sendable`이라 큐 경계를 넘기려면 `@unchecked Sendable` 상자가 필요하다. 웜 재조회가 1ms 미만(실측)이므로 **아낄 왕복보다 "격리를 건너는 값이 애초에 없다"가 싸다** — `CGEvent`를 게시 큐 위에서 만드는 [ActionExecutor 계약](20260726_action-executor-nonisolated-sendable.md)과 같은 규칙이다.

### ⑤ 전환 시 폴백 리셋

읽기가 비동기라 앱 전환과 결과 착지 사이에 ~20ms 공백이 있다. 그 사이 **이전 앱의 계열을 들고 있으면** Finder(`.nonText`)에서 편집기로 넘어온 직후 편집 어휘가 통째로 죽는다 — 폴백 결정이 막으려던 바로 그 고장이다. 폴백으로 리셋하면 반대 방향(편집기→Finder)에 ~20ms의 위험 창이 남지만, 그것은 "영원히 안 걸러짐"에서 "20ms 안 걸러짐"으로 줄어든 것이라 방향이 옳다.

### ⑦ 계열을 콜백에서 읽는 이유

게시 큐 위에서 캐시를 읽으면 버스트 도중 포커스가 옮겨간 경우 **이미 결정된 시퀀스가 다른 요소를 기준으로** 걸러지거나 통과한다. 키 입력 시점 스냅샷이 유일하게 일관된 값이라 `dispatchActions`의 시그니처를 `([VimAction], ElementFamily) -> Void`로 넓혔다.

## 검토한 대안

- **3ms 유지 + 콜드 실패 수용**: 앱 전환 직후가 정확히 리졸버가 필요한 순간이라 기각(위 표).
- **3ms로 먼저 시도하고 실패 시에만 비동기 재시도**: 경로가 둘이 되고 얻는 것은 웜 상태의 홉 한 번뿐이다 — 웜 읽기는 어차피 알림 시점이라 급하지 않다. 기각.
- **`AXObserver`를 전용 런루프 스레드에**(킬 탭 선례): 콜백이 AX를 읽지 않으므로 메인 런루프로 충분하다. 스레드 하나를 아낀다.
- **캐시를 nonisolated 잠금 상자로 두고 게시 큐가 직접 읽기**: ⑦의 스냅샷 일관성을 잃는다 — 기각.

## 남은 재검토 항목

[3ms 캡 결정](20260712_ax-probe-hard-timeout-3ms.md)은 **`strategy: auto`의 AX 프로브**를 규율한다. 그 코드 경로는 아직 존재하지 않지만(MVP 이후), 이번 실측은 그 값이 **콜드에서 6/6 실패**함을 보여준다. 그 결정을 supersede할지, 아니면 프로브도 이 결정처럼 비동기 캐시 갱신으로 재설계할지는 M5 AX 착수 시 판단한다 — 지금 뒤집으면 존재하지 않는 코드에 대한 결정을 미리 하는 것이라 보류한다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [system-overview.md](../../architecture/references/system-overview.md)
- 신규 `VimAction/FocusedElementResolver.swift`, `EventTapController`의 소유·주입 및 sink 시그니처
- 관련: [분류표](20260801_element-family-classification-table.md), [폴백 기본값](20260801_resolver-fallback-defaults-to-text-area.md), [M2 앱 게이트](20260726_m2-app-gate-pre-engine-passthrough.md)(같은 캐시 형태)

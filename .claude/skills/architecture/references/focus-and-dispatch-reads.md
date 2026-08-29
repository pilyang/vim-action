# 포커스 리졸버와 디스패치 경로 AX 읽기

- **Last updated**: 2026-08-20 (문서 분할 — [strategy-dispatch.md](strategy-dispatch.md)에서 이관 + 파생 질의 수를 코드 실제(22종 — Visual 선택 질의 8종 포함)로 갱신)

## 현재 구조

### 포커스/컨텍스트 리졸버

`FocusedElementResolver`(`@MainActor`)가 포커스 요소의 계열(`ElementFamily`)을 캐싱해 키 입력마다 AX를 재탐지하지 않는다. **탭 콜백은 캐시만 읽고**, 계열은 `.replace` 시점에 콜백이 읽어 디스패치 페이로드로 실린다 — 게시 큐가 나중에 읽으면 버스트 도중 옮겨간 포커스 기준으로 걸러진다.

갱신 트리거는 둘이다: `NSWorkspace` 앱 활성화 알림(옵저버를 새 앱으로 갈아탄다)과 `AXObserver`의 `kAXFocusedUIElementChangedNotification`(런루프 소스는 메인) — 후자가 앱 내부 포커스 이동까지 잡아 캐시만으로 충분함이 확인됐다 ([20260801_cache-only-callback-confirmed-sufficient.md](../../decisions/references/20260801_cache-only-callback-confirmed-sufficient.md)). **AX 호출은 전용 직렬 큐 위에서만** 하고 메인 스레드는 AX를 호출하지 않는다 — 탭 생존을 지키는 것은 타임아웃 값이 아니라 이 배치다. 타임아웃은 **50ms**(콜드 앱 최초 접촉을 흡수하는 값 — [20260802_ax-read-timeout-50ms-supersedes-3ms.md](../../decisions/references/20260802_ax-read-timeout-50ms-supersedes-3ms.md)). 큐로 넘기는 값은 `pid_t` 하나뿐이라 비-`Sendable` `AXUIElement`가 격리를 건너지 않는다. 앱 전환 순간 캐시는 **즉시 리셋**되고(이전 앱 계열이 남으면 편집기 진입 직후 편집이 통째로 죽는다) 늦게 착지한 읽기는 토큰 비교로 폐기된다 ([20260801_focused-role-cache-shape.md](../../decisions/references/20260801_focused-role-cache-shape.md)). 리셋이 채우는 값은 폴백이 아니라 `.unresolved`이며, 읽을 앱이 없을 때(pid `nil`)만 폴백이 곧 최종 판정이다.

**계열 판정은 role이 아니라 `AXSelectedTextRange` 노출 여부**다 — `AXUIElementCopyAttributeNames` 목록에 있는가로 보며, 값 조회는 판별자가 못 된다(비텍스트 요소도 `.success`를 돌려준다). role은 텍스트 판정 뒤 TextArea/TextField를 가르는 데만 쓴다(role 화이트리스트는 실측 붕괴로 기각 — [20260801_element-family-classification-table.md](../../decisions/references/20260801_element-family-classification-table.md)). 어느 단계에서 실패하든 **폴백은 `.textArea`** — 걸러내기는 확실한 보고에만 발동한다 ([20260801_resolver-fallback-defaults-to-text-area.md](../../decisions/references/20260801_resolver-fallback-defaults-to-text-area.md)). `selectedRange`는 캐싱하지 않는다 — 키마다 변해 캐시가 원리적으로 불가하며, 아래 디스패치 경로 읽기가 담당한다.

### 디스패치 경로 AX 읽기

정확 오프셋이 필요한 시퀀스(단어 경계, 경계 포화, Visual 앵커 등)를 위해 **게시 직렬 큐 위에서** 동기 AX 읽기를 한다. 콜백·메인 스레드는 계속 AX 무접촉이다 ([20260802_dispatch-read-on-posting-queue.md](../../decisions/references/20260802_dispatch-read-on-posting-queue.md), [20260802_focused-text-read-api-shape.md](../../decisions/references/20260802_focused-text-read-api-shape.md)).

- **lazy 읽기**: `KeyboardAdapter.execute`가 **액션마다** `FocusedTextSnapshot`을 새로 만들고, 처음 물을 때 읽어 그 액션 동안 기억한다 — 같은 버스트의 앞 액션이 캐럿을 옮기므로 실행 직전 값만 정확하고, 한 액션 안의 여러 소비자가 왕복을 곱하지 않는다. **실패도 기억한다** — 아니면 타임아웃 나는 앱에서 물음 수만큼 캡을 문다.
- **pid는 키 입력 시점 스냅샷** — `DispatchContext.processID`, 출처는 `FocusedElementResolver.observedProcessID`(같은 곳에서 나온 `family`와 짝이라 둘이 다른 앱을 가리킬 수 없다). `AXUIElement`는 큐 위에서 생성한다.
- **프리미티브는 `AXSelectedTextRange` + `AXNumberOfCharacters` + `AXStringForRange`(캐럿 ±256, 문서 경계 clamp; 선택이 범위면 양 끝 바깥으로)**. `AXValue` 전체 읽기는 키당 경로 금지 — 비용이 문서 크기에 비례한다. 반환 타입 `FocusedText`는 `selection`·`characterCount`·`window`·`windowRange` 넷이다 — 마지막이 없으면 절대↔상대 오프셋 변환이 안 된다.
- **실패·타임아웃은 현행 무상태 시퀀스로 폴백** — 정확화만 포기하고 실행은 한다. **스킵도, 실행 실패 보고도 아니다**(폭주 자동 off의 트립와이어에 걸리지 않는다). 실패는 단계·에러코드를 가리지 않는 **단일 `nil`**(pid 없음도 같다) — 소비자의 폴백이 하나뿐이라 갈라 봐야 쓸 데가 없다. 포커스 요소를 노출하지 않는 앱은 이 폴백이 상시 경로다.

리더(`FocusedTextReader`)는 어댑터에 주입한다(골든 테스트가 실기기 AX 없이 읽기 결과를 주입하는 seam). 타임아웃과 포커스 요소 조회는 **`AXRead`가 단독 소유**해 리졸버 경로와 디스패치 경로가 같은 상수를 쓰는 것이 코드로 강제된다.

### 파생 질의 — `FocusedTextAnalysis`

읽은 것에서 사실을 뽑는 파생 질의는 `FocusedText`의 extension(`FocusedTextAnalysis.swift`, `nonisolated`)이며 읽기와 파일이 나뉜다. **스물둘**이다 — 캐럿 질의 열넷(절대↔창 내 상대 오프셋 변환, 문서 시작/끝, 캐럿 기준 줄 시작/끝, 줄 끝/줄 시작까지 남은 문자 수, 캐럿 위의 줄 수, 마지막 줄 여부, 캐럿 뒤 단어 시작 부재 증명, 캐럿이 줄의 첫 비공백인가, 단어 런 셋: 런이 1자인가·캐럿이 런의 마지막 글자인가·줄 끝일 때 직전 글자의 런 클래스)에, M5 Visual 앵커 작업이 더한 **선택 질의 여덟**(캐럿이 단어 시작인가, 선택 끝 다음 문자 실재 증명, 선택 끝의 줄 시작 여부, 선택 내부 개행 수, 선택 시작/끝 이후 개행 거리, 선택 끝에서 줄 시작까지 문자 수, 선택 마지막 줄 길이 — 소비자는 `VisualKeyMapper`, [keyboard-adapter.md](keyboard-adapter.md)).

- **증명하지 못하면 전부 `false`/`nil`**(= 정확화하지 않음 = 현행 시퀀스) — 그래서 `hasWordStartAhead`가 아니라 `provesNoWordStartAhead`다: `false`가 항상 "정확화 안 함"이라야 확장의 보수 방향이 균일하다.
- 오프셋 단위는 **UTF-16** — `Character` 단위 인덱싱은 이모지가 있는 창에서 "잘못 정확화"라는 안전하지 않은 방향으로 틀린다.
- `isAtDocumentEnd`는 `>=`가 아니라 `==`이며 창이 문서 끝에 닿았다는 방증까지 요구한다(`AXNumberOfCharacters` 오보 앱에서 `>=`는 편집 키를 영구히 삼킨다). 줄 거리·줄 수 질의도 같은 규칙 — 창 안에 개행이 없으면 문서 경계에 닿은 방향으로만 답하고, 닿지 않았으면 `nil`이다.
- 단어 시작의 정의는 "공백류(space·tab·개행) 다음의 비공백"으로 macOS `Opt-→`보다 **좁게** 잡는다 — 좁게 보면 "있다고 보고 정확화를 포기하는" 쪽으로 틀린다.

**단어 런 질의는 오프셋을 만들지 않는다** — 캐럿 **±1자**의 로컬 술어다. 런 클래스는 넷(`blank` = space·tab / `keyword` = ASCII 영숫자·`_` / `punctuation` = 그 외 ASCII / `other` = 비ASCII)이고 **개행은 어느 런에도 속하지 않는 종결자**다(`blank`에 개행이 없다 — 런에 넣으면 줄 끝 `iw`가 개행을 지워 줄이 병합된다). 로컬 술어라 창 가장자리 난점이 없고, 정확화 가지가 클래스 무관한 `Shift-→`·`Shift-←`라 우리 정의를 macOS와 맞출 필요가 없다. 비ASCII가 `other`인 것은 보수 방향(포기 쪽으로 떨어짐) 때문이다 ([20260803_word-run-local-predicates-no-offsets.md](../../decisions/references/20260803_word-run-local-predicates-no-offsets.md)).

### 소비 지점

`mapping`의 `.edit` 분기·Visual 세션 분기·`.paste` 분기 세 곳이다(`.scroll` 분기도 읽지만 대상이 `FocusedText`가 아니라 `ViewportReader`의 뷰포트 줄 수 — [keyboard-adapter.md](keyboard-adapter.md)). 편집은 `EditKeyMapper.consultsFocusedText(_:)`가 "이 범위가 묻는가"를 답하는 **범위 술어**(범위 표가 어댑터로 복사되지 않는다), Visual은 앵커 상태의 수립·검증 때문에 세션 액션마다 읽는 **세션 술어**, 붙여넣기는 `pasteConsultsFocusedText`(charwise `p`만 참)다. 묻지 않는 어휘(모션·`P`·linewise paste·undo)는 AX 왕복이 0건이다. 묻는 범위는 `.motion` 전체 + `.linewiseMotion(.lineUp)`·`.linewiseMotion(.documentStart)` + `iw`이며, `.line`(`dd`)과 `.linewiseMotion(.lineDown)`(`dj`)은 **일부러 빠져 있다** — 소프트 랩이 이 읽기로 해소되지 않아 물을 이유가 없고, 읽기 비용은 액션 수만큼 곱해진다 ([20260802_read-consumption-via-mapper-predicates.md](../../decisions/references/20260802_read-consumption-via-mapper-predicates.md)).

읽은 값은 `EditKeyMapper.keyStrokes(..., text:)`로 들어가 시퀀스를 재조립한다([keyboard-adapter.md](keyboard-adapter.md)의 정확화 표). `.skipped`의 자체 로그는 `op`·`range`·액션을 다 아는 `.edit` 분기에 남아 판정과 로그가 갈라질 자리가 없다. `recordEdit`은 `.groups`일 때만 불리므로 무효로 스킵된 편집은 붙여넣기 단위 기억도 남기지 않는다 ([20260803_edit-keystrokes-takes-focused-text.md](../../decisions/references/20260803_edit-keystrokes-takes-focused-text.md)).

## 불변식·계약

- **AX 호출은 콜백·메인 스레드에 들어오지 않는다** — 리졸버는 전용 큐, 디스패치 경로 읽기는 게시 큐. 메시징 타임아웃은 경로 불문 50ms 단일 상수이며 병적 정지를 자르는 차단기다 ([20260802_ax-read-timeout-50ms-supersedes-3ms.md](../../decisions/references/20260802_ax-read-timeout-50ms-supersedes-3ms.md)).
- `AXValue` 전체 읽기는 키당 경로에 넣지 않는다 — 비용이 문서 크기에 비례한다.
- 파생 질의의 보수 방향은 균일하다 — 증명 실패는 항상 "정확화 안 함"이지 절대 "잘못 정확화"가 아니다.

## 근거 요약

키 입력마다 라이브 AX를 읽으면 탭이 죽고, 아예 안 읽으면 정확화가 불가능하다 — 그래서 계열은 알림 기반 캐시로, 오프셋은 게시 큐 위 lazy 창 읽기로 갈라 "콜백 경량"과 "실행 직전 신선함"을 동시에 지킨다.

## 관련

- 소비자: [keyboard-adapter.md](keyboard-adapter.md) (정확화), [ax-adapter.md](ax-adapter.md) (확대 창 4096·`AXWindowSnapshot`)
- 계열의 용도(걸러내기): [keyboard-adapter.md](keyboard-adapter.md)
- 탭 생존 불변식: [reentrancy-and-safety.md](reentrancy-and-safety.md)

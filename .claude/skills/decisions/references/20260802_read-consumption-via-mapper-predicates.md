> Superseded (부분) by [20260803_edit-keystrokes-takes-focused-text.md](20260803_edit-keystrokes-takes-focused-text.md) — 결정 1(`keyStrokes` 시그니처 무변경)과 `collapsesToNothing`의 존재가 뒤집힘 / ②·③·④(cw 리타깃 공유, `consultsFocusedText`가 매퍼 소속인 이유, 파생 질의 파일 분리)는 유효

# 읽기 소비 형태 — 매퍼 술어 2함수, `keyStrokes`는 무변경

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

[캐럿 주변 읽기](20260802_focused-text-read-api-shape.md)를 매퍼가 소비하는 **형태**를 확정한다.

1. **`EditKeyMapper.keyStrokes`의 시그니처는 바뀌지 않는다.** 읽기는 같은 매퍼의 **별도 순수 함수 2개**로 들어간다:
   - `consultsFocusedText(_ range:) -> Bool` — 이 범위가 읽기를 묻는가
   - `collapsesToNothing(op:range:text:) -> Bool` — 읽기가 무엇을 증명했는가

   둘 다 `FocusedText`를 **값으로** 받는다. `FocusedTextSnapshot`(가변 memo를 든 클래스)은 매퍼에 들어가지 않는다 — 매퍼 순수성이 유지되고 골든 테스트가 값을 직접 주입한다.
2. **어댑터는 `consultsFocusedText`를 보고 읽을지 정한다.** 범위 표가 어댑터로 복사되지 않고 매퍼에 남는다.
3. **소비 지점은 `mapping`의 `.edit` 분기 한 곳**이며, `actions:` disable·걸러내기 게이트·레이아웃 게이트 **뒤**다. `classify`·`Mapping`·`execute`는 무변경이다.
4. **파생 질의는 `FocusedText`의 extension**(`FocusedTextAnalysis.swift`)에 두고 읽기(`FocusedTextReader.swift`)와 파일을 나눈다.

## 배경·근거 (왜)

### ① `keyStrokes`에 `text:`를 넣지 않는 이유

가장 곧은 형태는 `keyStrokes(for:range:family:profile:text:)`가 포화 시 `nil`을 내는 것이다. 이것이 무너지는 지점이 셋이다.

- **`nil`의 의미가 둘이 된다.** 매퍼의 `nil`은 "이 계열에서 미지원"이고, 어댑터는 그것을 `.unsupported`로 집계해 릴리스 게이트 심사자가 전수 확인한다. 여기에 "0폭 포화"가 섞이면 **구현된 어휘가 미구현으로 읽힌다** — 스킵 3종 분리가 막으려던 바로 그 실패다.
- **되돌이 조회로 분리해야 한다.** `classify`가 프로파일 disable을 가르는 방식(`.empty`로 재조회)을 흉내내 `text: nil`로 한 번 더 물으면 갈리기는 한다. 그러나 프로브가 **세 개**가 되고 순서가 계약이 된다: 텍스트 프로브가 `builtIn`보다 앞이어야 하고 `builtIn`은 절대 `text`를 받으면 안 된다. 둘 중 하나만 어겨도 포화가 미지원으로 집계된다. 인접한 두 줄에 같은 인자를 넘기지 않는 것에 의존하는 계약은 감사할 수 없다.
- **`classify`는 사유를 모르는 자리다.** `op`도 `range`도 액션도 받지 않는다. `.skipped`의 계약은 "**사유를 아는 자리에서 자체 로그를 이미 남겼다**"인데, 여기서는 그것이 원리적으로 불가능하다.

술어를 밖에 두면 셋이 한꺼번에 사라진다. `nil`은 계속 "미지원" 하나이고, 프로브는 그대로 둘이며, 로그는 `op`·`range`·액션을 다 아는 `.edit` 분기에서 나간다.

### ② 그런데도 매퍼 소속인 이유

판정을 어댑터에 두면 `cw` 리타깃(`.change`+`.wordForward` → `.wordEndForward`)이 **두 곳으로 갈라진다**. 시퀀스는 매퍼가 리타깃한 모션으로 만들고 판정은 원래 모션으로 하면, `cw`의 판정이 실제로 나갈 시퀀스와 다른 모션을 본다. 리타깃을 `retargeted(_:for:)` 하나로 뽑아 시퀀스와 판정이 **같은 함수를 거치게** 하는 것이 이 배치의 값이다.

### ③ 어댑터가 아니라 매퍼가 "묻는가"를 아는 이유

읽기 1회는 Notion에서 7ms이고 액션 수만큼 곱해진다. 그래서 묻지 않는 범위에서는 왕복이 없어야 하는데, "어느 범위가 묻는가"는 매퍼의 지식이다. 어댑터에 `if case .selection` 같은 조건을 두면 세션 2·3이 범위를 늘릴 때 두 곳을 함께 고쳐야 하고, 빠뜨리면 **억제가 코드에 있는 채로 영원히 발동하지 않는다**(조용한 사문화). 테스트가 이 짝을 고정한다: `consultsFocusedText`가 거짓인 범위에서는 `collapsesToNothing`이 참일 수 없다.

### ④ 파일을 나눈 이유

`FocusedTextReader.swift`는 "무엇을 어떻게 읽는가"이고, 파생 질의는 "읽은 것에서 무엇을 아는가"다. 소비자가 늘어나는 쪽은 후자다 — 세션 2(경계 포화 4종·소프트 랩)와 세션 3(단어 경계)이 전부 여기에 얹힌다.

## 검토한 대안

- **`keyStrokes`에 `text:` 인자 + `classify` 세 번째 프로브**: 위 ①의 세 가지. 기각.
- **판정을 어댑터에 두기**(`KeyboardAdapter`의 private static): 매퍼를 아예 안 건드리지만 `cw` 리타깃이 갈라진다(②). 기각.
- **매퍼가 3-케이스 열거형을 반환**(`.strokes` / `.unsupported` / `.emptyRange`): 의미가 정직하게 갈리지만 `EditKeyMapper`의 모든 호출부와 골든 픽스처(`expected: [KeyStroke]?`)가 바뀐다 — 시퀀스가 하나도 안 바뀌는 변경치고 파장이 크다. 세션 2가 **시퀀스 재조립**을 하게 되면 그때는 `keyStrokes`가 `text`를 받아야 하므로, 그 시점에 ①의 제약(텍스트 프로브가 `builtIn`보다 앞, `builtIn`은 text 미수신)을 알고 설계하는 편이 낫다. 지금은 보류.
- **파생 질의를 `FocusedText`가 아닌 별도 네임스페이스 enum**: 정적 함수 나열이 되어 호출부가 길어지고, 값 타입의 파생 프로퍼티라는 실체와 어긋난다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (디스패치 경로 AX 읽기 절 — "소비자 미배선" 과도기 표기 해제, `EditKeyMapper` 문단)
- 신규 코드: `VimAction/FocusedTextAnalysis.swift` (`extension FocusedText` — `caretOffsetInWindow`, `isAtDocumentStart/End`, `isAtLineStart/End`)
- `EditKeyMapper`: `consultsFocusedText`·`collapsesToNothing`·`retargeted` 추가 (`keyStrokes` 시그니처 무변경)
- `KeyboardAdapter`: `mapping`의 `.edit` 분기 한 곳
- 테스트: `readerIsNotConsultedYet` → `onlyMotionRangeEditsConsultTheReader`로 교체 (PR-A가 심어 둔 트립와이어의 정상 소멸). 폴백 계약 테스트는 유지하되 vocabulary에 `.motion` 범위 편집을 추가 — 없으면 새 소비 경로를 하나도 지나지 않아 공허하게 통과한다.
- 상위 결정: [읽기 API 모양](20260802_focused-text-read-api-shape.md), [게시 큐 위 읽기](20260802_dispatch-read-on-posting-queue.md)
- 첫 소비자의 내용은 별건: [0폭 포화 억제](20260802_empty-selection-edit-suppression.md)

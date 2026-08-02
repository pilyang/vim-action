# `EditKeyMapper.keyStrokes`가 `text:`를 받는다 — 편집 분류는 3-프로브

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-03

## 결정

1. **`EditKeyMapper.keyStrokes`가 마지막 인자로 `text: FocusedText? = nil`을 받는다.** 읽기가
   증명한 만큼 시퀀스를 다시 조립하고, 증명하지 못하면 지금까지의 무상태 시퀀스를 그대로 낸다.
2. 세션 1의 `collapsesToNothing`은 **없어지고** `keyStrokes` 안으로 접힌다 — 억제(무효 →
   `nil`)와 재조립(다른 시퀀스)이 한 축에 놓여야 어댑터가 한 경로로 다룬다.
   `consultsFocusedText(_:)`는 남는다(어댑터가 읽을지 정하는 근거).
3. 매퍼의 `nil`이 두 뜻("미지원" / "읽기가 증명한 무효")을 갖게 되므로, 어댑터에 **편집 전용
   분류 함수 `classifyEdit`** 를 신설해 프로브를 셋으로 늘린다. **순서가 계약이다**:
   1. `keyStrokes(profile:text:)` → 값이 있으면 `.groups`
   2. **텍스트 프로브** `keyStrokes(profile:)` (text 없이) → 값이 있으면 `.skipped`
   3. **builtIn 프로브** `keyStrokes(profile: .empty)` (**text를 절대 받지 않는다**) →
      값이 있으면 `.disabledByProfile`, 없으면 `.unsupported`
4. **`.skipped`의 자체 로그는 어댑터의 `.edit` 분기**에 남는다 — `classifyEdit`은 사유를 알지만
   액션을 모른다.

## 배경·근거 (왜)

### ① 세션 1이 보류했던 조건이 충족됐다

[읽기 소비 형태](20260802_read-consumption-via-mapper-predicates.md) ①은 `keyStrokes`에 `text`를
넣는 것을 세 이유로 기각하면서, 마지막에 이렇게 남겼다 — "세션 2가 **시퀀스 재조립**을 하게
되면 그때는 `keyStrokes`가 `text`를 받아야 하므로, 그 시점에 ①의 제약을 알고 설계하는 편이 낫다."

세션 1의 정확화는 "게시할지 말지"만 갈랐기 때문에 술어 2함수로 충분했다. 세션 2는 **어떤
시퀀스를 낼지**를 가르므로 술어로 표현할 수 없다: 재조립 결과가 곧 반환값이다.

### ② 프로브 순서를 주석이 아니라 구조로 강제한 이유

세션 1이 이 형태를 기각한 핵심 근거는 "**인접한 두 줄에 같은 인자를 넘기지 않는 것에 의존하는
계약은 감사할 수 없다**"였다. 기존 `classify(_:builtIn:)`는 스트로크 값과 클로저를 받는 범용
함수라, 호출부가 `text`를 어느 프로브에 넘기든 컴파일이 통과한다. 순서가 하나만 어긋나면
정확화 결과가 `.unsupported`로 집계되고, 릴리스 게이트 심사자는 **구현된 어휘를 미구현으로 읽는다**
(스킵 4종 분리가 막으려던 바로 그 실패다).

그래서 편집만 전용 함수로 빼고 `text`를 받는 자리를 그 안 한 곳으로 닫았다. 이제 순서를 어기려면
함수 본문을 고쳐야 하고, 그것은 코드 리뷰에서 보인다. 나머지 세 매퍼는 `classify`를 그대로 쓴다 —
그쪽은 `text`가 애초에 없어 프로브가 둘이면 충분하다.

### ③ `.skipped` 로그가 어댑터에 남는 이유

세션 1의 근거가 그대로 적용된다: `.skipped`의 계약은 "**사유를 아는 자리에서 자체 로그를 이미
남겼다**"인데, `classifyEdit`은 `op`·`range`는 알아도 `VimAction` 자체는 모른다. `.edit` 분기는
셋을 다 알고, 이미 거기서 `p`의 빈 클립보드 스킵과 같은 형태로 로그를 낸다.

분류 결과를 보고 로그하는 형태(`if case .skipped = result`)라 **판정과 로그가 갈라질 수 없다** —
세션 1처럼 판정 조건을 로그 자리에서 다시 쓰면 둘이 어긋날 자리가 생긴다.

### ④ `recordLinewiseEdit`은 손대지 않았다

붙여넣기 단위 기억은 이미 `.groups`일 때만 남긴다. 엣지 2(`dk` 무효)가 그 구조에서 자동으로
옳게 동작한다 — 게시하지 않은 줄 단위 편집은 기억도 남기지 않으므로 다음 `p`의 wise가
오염되지 않는다. 프로파일 disable 스킵과 같은 규칙이고, 테스트가 이것을 직접 고정한다.

### ⑤ 남는 한계 — 분류 자체는 DEBUG로만 관측된다

`.skipped`와 `.unsupported`는 둘 다 아무것도 게시하지 않으므로, 분류가 어긋나도 **동작으로는
드러나지 않는다**(요약 로그만 달라진다). 그래서 테스트는 분류를 직접 단언하는 대신 그것을
성립시키는 조건을 고정한다: 무효 판정이 나는 모든 픽스처에서 `keyStrokes(text: nil)`이 값을
낸다는 것 — 즉 텍스트 프로브가 반드시 걸린다는 것을 표가 보장한다.

## 검토한 대안

- **`classify`를 확장해 프로브 3개를 클로저로 받기**: 호출부가 `text`를 잘못 넘기는 실패가
  그대로 남는다(②). 기각.
- **매퍼가 3-케이스 열거형을 반환**(`.strokes`/`.unsupported`/`.invalid`): 의미가 가장 정직하지만
  `EditKeyMapper`의 모든 호출부와 골든 픽스처(`expected: [KeyStroke]?`)가 바뀐다. 세션 1이
  같은 이유로 미뤘고, 지금도 얻는 것이 "어댑터 프로브 1개 절약"뿐이라 값이 비용에 못 미친다.
  기각(재검토 여지 있음 — 세션 3이 `.textObject`까지 정확화하면 프로브 비용이 늘어난다).
- **`collapsesToNothing`을 남겨 억제와 재조립을 따로 두기**: 어댑터가 두 경로를 다뤄야 하고,
  "억제인가 재조립인가"가 매퍼 밖에서 갈려 범위 표가 다시 두 곳으로 흩어진다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (디스패치 경로 읽기 절, `EditKeyMapper` 문단)
- 코드: `EditKeyMapper.keyStrokes`(시그니처)·`textAreaSelection`, `KeyboardAdapter.classifyEdit`·`mapping`의 `.edit` 분기
- 테스트: `EditCollapseTests` → `EditRefinementTests`. `.unchanged` 행을 무상태 호출과 **직접
  비교**하는 형태라 두 표가 갈라지지 않는다.
- 세션 3(`iw`·`cw`→`ce`)이 이 시그니처를 그대로 쓴다.

## Supersedes

- [20260802_read-consumption-via-mapper-predicates.md](20260802_read-consumption-via-mapper-predicates.md)
  — **부분**. 결정 1(`keyStrokes` 시그니처 무변경)과 `collapsesToNothing`의 존재만 뒤집는다.
  ②(`cw` 리타깃이 시퀀스와 판정에서 같은 함수를 거쳐야 하는 이유)·③(`consultsFocusedText`가
  매퍼 소속인 이유)·④(파생 질의 파일 분리)는 그대로 유효하며, 그 문서가 기각 근거로 남긴
  세 제약이 이 결정의 설계 입력이었다. 인덱스에 남긴다.

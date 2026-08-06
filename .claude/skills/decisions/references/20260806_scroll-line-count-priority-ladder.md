# 스크롤 줄 수 우선순위 사다리 — 프로파일 명시값 > AX 뷰포트 > 코드 상수

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

스크롤 반복 줄 수의 출처는 **프로파일 명시값 > AX 뷰포트 정확값 > 코드 상수 15/30** 순이다.
extent별로 독립이다 — `halfPageLines`만 명시된 프로파일에서 half는 프로파일 값, full은 AX 값을
쓴다. AX 읽기 실패의 폴백은 현행 사다리(프로파일 → 상수)와 **바이트 동일**이다.

따라서 술어 `CommandKeyMapper.scrollConsultsViewport(extent:profile:)`는 **그 extent의
프로파일 명시값이 있으면 거짓**이다 — 우선순위상 AX 값이 어차피 지므로 어댑터가 왕복
자체를 생략한다 (`pasteConsultsFocusedText`와 같은 자리의 읽기 술어).

## 배경·근거 (왜)

- **사용자가 적은 값은 언제나 이긴다.** 프로파일 scroll 값은 M4에서 "근사 조절값"으로
  태어났지만, M5부터는 AX가 틀리는 앱의 **명시적 워크어라운드**이기도 하다 (번들 Notion
  프로파일이 실사례 — visible 오보 앱에서 조율값 12/24가 유일하게 신뢰되는 출처다).
  AX가 프로파일을 이기면 이 방어선이 사라진다.
- **읽기 생략은 사다리의 코드 측 귀결이다.** 명시 extent에서 읽어 봐야 결과에 반영되지
  않으므로, 술어가 왕복을 생략하면 오보 앱의 헛 읽기(~웜 1ms + 콜드 수십 ms)도 함께
  사라진다.
- 폴백 바이트 동일은 M5 읽기 공통 계약(무상태 폴백)의 반복이다 — 읽기 실패가 스크롤을
  죽이면 안 된다.

## 검토한 대안

- **AX > 프로파일**: "실측이 조절값보다 정확하다"는 논리지만, AX가 틀리는 앱(Notion 실측)에서
  사용자가 고칠 수단이 사라진다. 기각.
- **프로파일에 "AX 우선" 스위치 추가**: 스키마 확장은 PR-E 몫이고, 필요 사례가 아직 없다. 기각.

## 영향 범위

- `CommandKeyMapper.lineCount(for:profile:viewportLines:)` — 사다리가 매퍼 한 곳에 닫힌다.
  `scrollConsultsViewport` 신설. `KeyboardAdapter`의 `.scroll` 분기가 술어로 읽기를 게이팅.
- 프로파일 scroll 값의 의미가 "근사 조절값"에서 "AX보다 우선하는 명시값"으로 확장 —
  `profiles-and-config.md` 갱신.
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md),
  [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- 관련: [20260730_scroll-arrow-repetition.md](20260730_scroll-arrow-repetition.md) (화살표 반복
  구조는 불변 — 이 결정은 반복 **줄 수의 출처**만 정한다),
  [20260806_viewport-lines-via-line-for-index.md](20260806_viewport-lines-via-line-for-index.md)

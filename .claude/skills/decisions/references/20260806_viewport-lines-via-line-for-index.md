# 뷰포트 줄 수는 `AXLineForIndex` 표시 줄 차 — 문서 전체 가시는 오보로 기각

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

뷰포트 줄 수는 `AXVisibleCharacterRange` **양 끝의 `AXLineForIndex` 줄 번호 차 + 1**로 읽는다
(표시 줄 단위). 읽기 전에 **문서 전체 가시 가드**를 둔다: `visible.length >= characterCount`면
증명 실패(`nil` → 폴백)다. 개행 세기(`AXStringForRange`) 방식은 기각한다.

## 배경·근거 (왜)

2026-08-06 프로브 실측 (스크래치 CLI, 프로덕션과 같은 50ms 타임아웃, 웜 비용 전부 1ms 미만):

| 앱 | `AXVisibleCharacterRange` | (a) 개행 세기 | (b) `AXLineForIndex` 차 |
|---|---|---|---|
| TextEdit (비랩 500줄) | 뷰포트 규모 {0, 6372}/doc 27000, 스크롤 추종 확인 | 118줄 | 118줄 (일치) |
| TextEdit (소프트 랩) | 정상 | **20줄 — 6× 과소** | **120줄 — 화면과 일치** |
| Notes (본문 포커스) | 정상 | 정상 | 정상 |
| Notion | **문서 전체로 오보** ({0, 5486} = doc 전체, 198줄 — 한 화면 불가) | 미지원(noValue) | 동작하나 오보가 전파 |
| Slack·VS Code | 포커스 요소 미노출 → 자연 폴백 | — | — |

- **표시 줄이 옳은 단위다.** 스크롤 실행은 `↓`/`↑` 화살표 반복이고 화살표는 시각(표시) 줄을
  걷는다. `AXLineForIndex`의 "line"이 NSTextView 계열에서 표시 줄인 것은
  [20260803_soft-wrap-linewise-not-resolved-by-window-read.md](20260803_soft-wrap-linewise-not-resolved-by-window-read.md)가
  **논리 줄이 필요한 자리(linewise 편집)에서 기각한 이유** 그 자체다 — 이번엔 그 성질이
  정확히 필요한 성질이라 충돌하지 않는다 (그 결정은 유효하며 supersede하지 않는다).
- **개행 세기는 소프트 랩에서 6× 과소**다 — 방향은 "덜 스크롤"이라 무해하지만, 120줄 창에서
  `Ctrl-d`가 10줄이면 정확화의 목적 자체가 무너진다. 또 visibleRange를 문서 크기로 오보하는
  앱에서 `AXStringForRange(visibleRange)`는 금지된 "크기 비례 읽기"를 뒷문으로 되들여
  길이 캡이 별도로 필요했다 — (b)는 문자열을 안 읽어 캡 자체가 불필요하다.
- **문서 전체 가시 가드가 오보를 자른다.** Notion의 전체 오보는 클램프(200)만으로는
  198줄 `Ctrl-f`가 나가 실패 방향이 **"과다 스크롤"**이 된다 — M5 읽기 계약에서 유일하게
  위험한 방향이라 전용 가드가 필요하다. 정말 문서 전체가 보이는 짧은 문서도 함께 폴백되지만,
  그런 문서에서는 화살표가 문서 끝에서 포화해 스크롤 정밀도가 애초에 의미 없다 — 놓치는
  방향이라 안전하다. 가드는 순수 함수 `ViewportReader.provenViewport`로 뽑아 표로 검증한다
  (`FocusedTextReader.window(around:)` 선례).

## 검토한 대안

- **(a) `AXStringForRange(visibleRange)` 개행 세기**: 위 소프트 랩 과소 + 비용 역수입. 기각.
- **(b)→(a) 폴백 체인**: 프로브에서 "(b)만 실패하고 (a)가 되는" 앱이 관측되지 않았다
  (둘 다 되거나 둘 다 안 됨) — 복잡도만 증가. 기각.

## 영향 범위

- 신규 `VimAction/ViewportReader.swift` — `ViewportReader`(주입 seam, 반환 `Int?` — 변환이
  리더 안에 닫혀 매퍼는 읽기 방법을 모른다) + `provenViewport` + `ViewportSnapshot`.
  `AXRead` 소유 규칙·50ms 단일 타임아웃·실패도 memo 계약 준수.
- 번들 Notion 프로파일의 scroll 블록(12/24)은 **유지** (사용자 확인) — 명시값이 술어를 닫아
  오보 앱의 헛 읽기까지 생략되는 이중 방어선이다
  ([20260806_scroll-line-count-priority-ladder.md](20260806_scroll-line-count-priority-ladder.md)).
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

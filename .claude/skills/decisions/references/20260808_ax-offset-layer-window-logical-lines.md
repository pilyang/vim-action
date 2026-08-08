# AX 오프셋 계층은 창 순수 함수 + 확대 반경 — 논리 줄 채택, 파라미터화 속성 기각

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 D1-설계 세션, 결정 ④·쟁점 4)

## 결정

AX 쓰기의 오프셋/범위 산출은 **새 순수 함수 계층 `FocusedTextOffsets`**(별도 이름공간 — `FocusedTextAnalysis` extension 확장 금지)가 담당한다.

- **입력은 `FocusedText` 창이며, AX 쓰기 경로 전용으로 반경을 키운다** (초기값 4096 UTF-16 — 도그푸딩 조절값, 착수 시 `AXStringForRange` 대반경 비용 실측으로 확정). keyboard/혼용 경로의 256은 그대로다.
- **파라미터화 속성(`AXLineForIndex`/`AXRangeForLine`)은 채택하지 않는다** — 표시 줄(소프트 랩 반영) 시맨틱이 실측 확정돼 있는데(20260806) 편집이 원하는 것은 논리 줄이다. 비용을 내고 틀린 단위를 사는 구조.
- **반환은 3상태**(`EditKeyMapper.Refinement` 동형): `.invalid`(Vim 자체가 무효 → 정직한 스킵) / 범위(증명 → AX 쓰기) / `.unproven`(창이 답 못 함 → **keyboard 위임**). 2상태로 뭉치면 첫 줄 `dk` 같은 "무동작이 정답"인 자리가 위임돼 시각 행 하나를 지운다.
- **linewise는 논리 줄이다** — 소프트 랩 문단에서 `dd`/`cc`/`yy`/`Vd`가 논리 줄(개행 사이 전체 = Notion에선 블록) 단위로 동작한다. M3부터 유일하게 미해소였던 수용 엣지의 AX 경로 해소이며, `j`/`k`는 시각 행 위임이 확정이라 **`dj` ≠ `d`+`j` 편차를 명시 수용**한다(Vim 자신도 `wrap`에서 `j`/`gj`를 가른다).
- 안전 규칙: 산출은 항상 **grapheme cluster 경계 위**(서로게이트 쌍·ZWJ 이모지·결합 문자 한가운데 산술 금지 — 창 텍스트에서 경계 배열 1회 산출), 줄 종결자는 `\r\n`·`\n`·`\r`·U+2028/2029(`\n` 단독 스캔은 `\r\n` 문서에서 떠돌이 `\r`를 남긴다), 경계 불변식(`location ≥ 0`, `upperBound ≤ characterCount`)은 순수 함수 테스트로 고정, `AXNumberOfCharacters` 단위 오보 앱은 `isAtDocumentEnd`와 같은 방증 요구로 방어(실패 방향은 "덜 지움"·"거절" — 비파괴 수용). UTF-16 배관(`offsetInWindow` 등, 특히 `window.utf16.count == windowRange.length` 가드)은 internal 승격으로 **공유**하되, **`RunClass`는 별도 정의다** — Analysis는 비ASCII를 `other`(포기 방향 보수)로 두지만 오프셋 계층은 `keyword`로 넣어야 CJK 문서의 `w`/`diw`가 살고, 같은 extension에 두 `runClass`가 공존하면 호출부가 조용히 잘못 고른다.
- "읽기는 분기의 근거이지 스트로크 수의 근거가 아니다" 불변식은 **keyboard 경로 전용으로 한정**을 명시한다 — AX 경로는 읽기·쓰기가 같은 큐에서 동기라 낡은 읽기 창이 구조적으로 없고, 오프셋이 실행 수단 그 자체다.
- 파일 위치는 앱 타깃 유지(SPM 승격 기각 — M5 한복판의 동작 가치 0 리팩터). 재개 조건: 표 주도 테스트가 커져 `xcodebuild test` 루프가 실병목이 되면 `FocusedText`+`Analysis`+`Offsets`를 통째로 SPM 타깃으로 승격.

## 배경·근거 (왜)

- **keyboard가 반경 확대를 기각했던 세 사유 중 둘이 AX에서 소멸한다**([20260803_soft-wrap-linewise-not-resolved-by-window-read.md](20260803_soft-wrap-linewise-not-resolved-by-window-read.md)): 원자 그룹 폭증(AX 쓰기는 범위 크기와 무관하게 호출 수가 상수)·낡은 읽기의 오프셋 비례 파괴(동기라 부재). 남는 사유 ①(증명 불성립 — 랩 문단 > 반경)은 반경 확대가 직접 해소하는 유일한 항목이고, 그 문서 스스로 "비용상 가능(창 읽기는 크기 무관 ~0.2ms)"을 인정했다. 같은 조치가 keyboard에선 쓸모없고 AX에선 결정적 — 반경 상수를 경로별로 가르는 이유다.
- **창 밖 사유는 실질적으로 "논리 줄이 반경보다 길다" 하나다.** `dgg`/`dG`는 문서 규모 문제가 아니다 — AX 쓰기는 범위의 **끝점 두 개**만 필요하고(`0`·`characterCount`는 공짜, 나머지 끝점은 현재 줄 로컬), 범위 크기는 비용이 아니다. 이 관측이 파라미터화 속성(문서 규모 커버)의 존재 이유 대부분을 제거한다.
- **`AXValue` 전체 읽기 금지가 금지하는 것은 문서 크기 비례다** — 고정 반경 8192단위는 상수 상한이라 원칙 위반이 아니며, 현행 `window(around:)`가 이미 선택 크기 비례로 읽는 선례("필요 비례 허용, 문서 비례 금지")가 코드에 있다.
- 논리 줄이 개선인 근거: Vim 시맨틱이 논리 줄이고, 현행 시각 줄 `dd`는 플랜 문서 스스로 "문단 중간을 뜯는 현상"이라 부르며 매번 "버그로 오인 금지"를 붙여 온 자리이며, 랩 문단은 화면에서도 한 덩어리로 보인다(Notion은 논리 줄 = 블록 = 사용자가 보는 단위). 실패 방향도 안전하다 — 1 undo 단위, 화면이 한 번에 바뀌어 즉시 가시.

## 검토한 대안

- **A. 반경 256 유지 + 창 밖 전부 위임**: 더 단순하지만 AX 쓰기가 keyboard가 이미 잘하던 자리에서만 정확해지고, 유일 미해소 엣지(소프트 랩 논리 줄)에서 현행으로 퇴각 — AX 어댑터의 사용자 가치 상당 부분이 사라진다. 반경은 상수 1개로 그 가치를 산다.
- **B. 파라미터화 속성 적극 사용**: 표시 줄 답 = `dd`가 현행과 같은 동작을 왕복 비용을 내고 사는 순 손해. 앱 구현 편차(Notion visible 오보 실측)로 새 오보 가드도 필요해진다.
- **적응적 창 확장(2배씩 재읽기)**: 왕복 log n회 + 성공 반경이 상태가 되어 테스트 표가 곱해진다. 크기가 비용을 지배하지 않으므로 적응성이 사는 것이 없다.
- **`j`/`k`까지 논리 줄**: 800자 문단에서 `j` 한 번에 문단을 건너뛰어 macOS 근육 기억·keyboard 경로 앱 모두와 어긋난다. 위임 확정([20260808_ax-delegation-table-single-driver.md](20260808_ax-delegation-table-single-driver.md)).

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 신규 코드(PR-D1a 기초·D1b 완성): `VimAction/FocusedTextOffsets.swift` + 표 주도 픽스처·경계 불변식 스윕·어휘 전수 스윕·창 절단 픽스처·UTF-16 픽스처 5종. 위임 케이스 테스트는 AX 쓰기 seam **무호출 단언**으로(내용 비교 금지 — CLAUDE.md 함정).
- 착수 시 실측: `AXStringForRange` 8192단위 웜 p50(Notion·TextEdit — 반경 확정), 서로게이트 한가운데 범위 쓰기의 앱별 동작(되읽어 검증이 흡수하는지 확인).

## Supersedes

- [20260728_linewise-visual-line-wrap-accepted-edge.md](20260728_linewise-visual-line-wrap-accepted-edge.md) — **부분**: AX 전략 경로에서는 논리 줄로 해소(D1b 구현 시 발효). keyboard 경로의 수용(시각 줄 유지·창 읽기 해소 불가)은 그대로 유효.

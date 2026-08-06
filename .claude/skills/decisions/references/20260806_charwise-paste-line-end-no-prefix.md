# 줄 끝이 증명된 charwise `p`는 `→` 접두를 생략한다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

charwise `p`의 위치 접두 `→`는 읽기가 **캐럿(길이 0)이 줄 끝**임을 증명하면 생략한다 — 빈 줄·문서 끝도 같은 판정에 덮인다. 증명하지 못하면(읽기 실패·pid 없음·살아 있는 선택) 현행 `→` 그대로다. 이로써 붙여넣기가 **읽기의 세 번째 소비 지점**이 된다: 술어는 `CommandKeyMapper.pasteConsultsFocusedText(before:wise:)`(charwise `p`만 참)이고, `P`·linewise는 AX 왕복 0건이 유지된다. 프로브는 그대로 둘이다 — 이 정확화는 접두를 비울 뿐 `nil`을 새로 만들지 않아 편집·Visual의 3-프로브 사유가 발생하지 않는다.

## 배경·근거 (왜)

도그푸딩 실측: TextEdit 줄 끝에서 `x` 후 `p`를 하면 잘라낸 글자가 **다음 줄 시작**에 붙었다 (외부 복사를 줄 끝에서 붙일 때도 같다). 로그 판독으로 wise 판정(charwise, 기억 델타 1)과 `x`의 정확화(마지막 글자 삭제)는 모두 정상임이 확인됐고, 원인은 접두 `→`가 줄 끝에서 **다음 줄 시작으로 포화**하는 것이었다.

Vim 커서 모델로 보면 줄 끝의 캐럿은 마지막 글자 **위**의 커서다 — `p`의 "커서 뒤"는 곧 지금 캐럿 자리이므로 접두가 없어야 맞고, `xp`(마지막 두 글자 교환) 같은 관용구가 Vim과 동일해진다. [줄 끝 charwise Vim 커서 모델](20260803_line-end-charwise-vim-cursor-model.md)이 `charRight`(엣지 1)·[단어 어휘 `iw`·`cw`](20260803_line-end-cursor-model-for-word-objects.md)에 적용한 것과 같은 규칙의 네 번째 적용이며, 재조립 원칙(위치 상대·현행의 부분집합 — 접두 1타 제거)도 그대로 만족한다. 이 결정 전까지 "charwise `p`는 줄 끝에서 다음 줄 시작에 붙여넣는다"는 명시 수용 편차였다 ([명령 매퍼 신설](20260730_command-key-mapper-scope.md)) — 읽기 기반이 생긴 지금은 증명 가능한 경우를 정확화하고, 편차는 읽기 실패 폴백 전담으로 강등된다.

## 검토한 대안

- **수용 편차 유지**: 읽기 실패 앱에서는 어차피 남는 편차지만, TextEdit·Notion처럼 읽기가 되는 앱에서 `xp`가 매번 틀리는 것은 가장 기본 관용구의 상시 오동작이다. 수정이 접두 분기 하나(상수)라 비용도 없다 — 기각.

## 영향 범위

- `CommandKeyMapper`: `pasteConsultsFocusedText` 신설, `pasteStrokeGroups(text:)`·`prefix(text:)` 확장
- `KeyboardAdapter` `.paste` 분기: 술어 참일 때만 `text.value()` 소비
- 어댑터 테스트 +2 (줄 끝 증명 접두 생략·줄 중간 현행 유지), 소비 지점 계약 테스트 5→6 왕복 갱신
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

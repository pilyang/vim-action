# linewise 세션의 charwise 모션은 범위 무변화 스킵

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-04

## 결정

상태가 wise = linewise를 알고 [자가 검증](20260804_visual-anchor-read-self-validation.md)이 서 있으면, `V` 세션의 charwise 모션 확장(`h l w b e 0 ^ $`)은 **게시 없이 스킵**한다(`.skipped` 계열 — 지원하되 이번엔 게시할 것이 없음, 자체 로그). Vim에서 이 모션들은 V 세션의 **범위를 바꾸지 않으므로**(커서 열만 움직인다) 무게시가 곧 정확 동작이다. 범위를 바꾸는 것은 `j k gg G`뿐이며 그쪽은 [재앵커](20260804_visual-backward-keyboard-reanchor.md)·현행 시퀀스가 담당한다.

상태 부재·읽기 실패 시에는 현행 무상태 시퀀스(Shift+모션) 그대로다 — 폴백 계약 공통.

## 배경·근거 (왜)

[무상태 확장 결정](20260728_visual-extend-stateless-no-linewise-rounding.md)의 편차 표에서 `V` 세션의 파괴적 행 대부분(`l`·`w`·`^`·`$` — 다음 줄로 새거나 들여쓰기·내용이 붙는)이 바로 이 모션들이다. 그 문서는 `linewise: Bool` 상자를 두면 이 편차를 없앨 수 있음을 알면서도 상태를 들지 않기로 했고, "단계 2.5 재검토 후보 — 지금 닫는 문이 아니다"로 남겨 두었다. 앵커 상태가 wise를 들게 된 지금([협력자](20260804_visual-anchor-state-collaborator.md)) 그 문이 열렸다 — 별도 상자 없이 같은 상태로 판정한다.

- **desync 실패 모드가 무해하다**: 상태가 어긋난 채 스킵하면 "모션이 no-op이 된다"로 끝난다 — 원 문서가 이미 짚은 그대로이고, 파괴적 방향이 없다.
- **분류는 `.skipped`다**: 미지원(`nil`)이 아니다 — 이 어휘는 지원되며, Vim 정확 동작이 "게시할 것 없음"일 뿐이다. 빈 클립보드 `p`·읽기가 증명한 무효 편집과 같은 편이고, "지원 ⟹ 빈 시퀀스 아님" 불변식은 스킵 분류로 지켜진다(빈 배열을 반환하지 않는다).

## 검토한 대안

- **현행 유지 (Shift+모션 그대로)**: `V` 뒤 `$`·`w`가 다음 줄을 오염시키는 파괴적 편차가 그대로 남는다. 상태가 공짜로 생긴 지금 유지할 이유가 없다. 기각.
- **`0`/`^`/`h`/`l`만 스킵하고 단어 모션은 유지**: 단어 모션이 가장 파괴적인 축(다음 줄 단어 중간으로 샌다)이라 반쪽 해소다. 기각.

## 수용 편차

Vim은 이 모션들에서 **커서 열이 움직인다** — 이후 `V`→`v` 전환이나 이탈 시 캐럿 위치에 영향을 준다. 우리는 완전 무동작이라 그 열 이동이 없다. 파급이 캐럿 위치뿐이고 범위(= 오퍼레이터의 피연산자)는 정확하므로 수용한다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/VisualKeyMapper.swift`·`VimAction/KeyboardAdapter.swift` Visual 분기(스킵 분류) — 구현은 후속 세션
- 도그푸딩 오인 금지: `V` 후 `h l w b e 0 ^ $`가 (읽기 성공 앱에서) 아무 일도 안 하는 것이 **의도**다
- 관련: [무상태 확장](20260728_visual-extend-stateless-no-linewise-rounding.md) — 편차 표의 원 기록

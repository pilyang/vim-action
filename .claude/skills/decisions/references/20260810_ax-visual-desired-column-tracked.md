# charwise Visual 세션의 `j`/`k`는 희망 열을 상태로 추적해 AX가 계산한다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10 (M5 PR-D1b 세션 4)

## 결정

AX로 고정된 charwise Visual 세션의 `j`/`k`(`extendSelection(.lineUp/.lineDown)`)는 **위임이 아니라 AX 범위 쓰기**다. Vim의 curswant에 대응하는 **희망 열**을 `VisualAnchorState.desiredColumn`에 싣고, 수평 모션마다 갱신하며 `j`/`k`는 물려받는다.

- 포커스 = **줄 시작 + `min(희망 열, 줄 길이)`** — 열이 줄을 넘으면 종결자 위에 서고, 그 개행까지 문다([inclusive 끝 정정](20260810_visual-inclusive-end-bites-terminator.md)).
- `$`(`.lineEnd`/`.lineEndForAppend`) 뒤의 열은 **줄 끝 고정** sentinel(`FocusedTextOffsets.lineEndColumn` = `Int.max`)이다. 산술이 항상 `min` 우선이라 오버플로가 없다.
- 열을 모르면(`gg`/`G` 경유 등) 근사하지 않고 **정직한 스킵**이다.
- keyboard 경로는 이 필드를 쓰지 않는다(기본값 `nil`) — 희망 열의 주인이 앱이므로 `nil`이 그 경로의 정확한 값이다.

## 배경·근거 (왜)

두 결정이 이 자리에서 서로를 배제했다: [오프셋 계층 결정](20260809_ax-span-vim-exact-where-table-is-silent.md)은 "charwise 세션의 `j`/`k`는 그대로 위임"(희망 열 소실)이라 했고, [경로 고정 결정](20260808_ax-visual-session-path-pinning.md)은 AX 세션 중간의 위임을 금지했다. [재정의 모션 스킵](20260808_ax-visual-overridden-motion-honest-skip.md)과 같은 종류의 교차점이며, 방치하면 **`vj`가 AX 앱에서 통째로 무동작**이 된다.

- **Normal `j`/`k`의 위임 사유가 여기서는 성립하지 않는다.** Normal에서 위임이 옳은 이유는 대안(오프셋 대입)이 희망 열을 잃는데 **화살표 위임은 앱이 그 열을 정확히 유지**하기 때문이다. AX Visual 세션에서는 위임 자체가 금지라 대안이 "무동작"이고, 비교 대상이 완전히 달라진다.
- **열은 추정이 아니라 계산이다.** 창이 포커스 줄 시작을 답하므로 열 = 포커스 − 줄 시작이고, 세션이 그 값을 들고 다니면 Vim curswant와 같은 의미가 된다. 실측이 그 모델을 확인했다: `4lvjj`가 짧은 줄 `xy`를 지나 **열 5를 복원**했고(`'<`=1:5 `'>`=3:5), `llvjd`는 짧은 줄에서 종결자까지 물어 줄을 병합했으며(`"abghi"`), `v$j`는 다음 줄 끝에 붙었다(레지스터 `"abcdef\nxyz\n"`).
- **모르면 스킵이 이미 계약이다.** `gg`/`G` 뒤 열 미상은 keyboard ⑦이 같은 이유로 스킵하는 자리다 — 새 규칙이 아니라 같은 규칙의 이식이다.

## 검토한 대안

- **정직한 스킵(위임 문언 유지)**: 가장 작지만 `vj`·`vk`가 AX 앱에서 무동작이 된다. 실사용 어휘 중 가장 흔한 축이라 수용 불가.
- **그 액션만 위임**: 경로 고정 결정의 뿌리(무상태 시퀀스 금지)를 정면 위반. AX가 쓴 범위 위의 `Shift-↓`는 앱이 어느 끝을 포커스로 보는지 미정의라 파괴 방향이 불확정이다.
- **열을 매번 포커스에서 다시 세기(curswant 미추적)**: 짧은 줄을 지나면 열이 영구히 깎여 Vim과 갈린다 — 실측 `4lvjj`가 정확히 그 차이를 드러낸다.

## 수용 편차

- `v$` 뒤 커서가 **이미 줄 끝**이면 범위가 안 바뀌어 무게시(`.invalid`)로 접히고, 그 액션의 열 갱신(줄 끝 고정)도 함께 버려진다. 다음 `j`가 옛 열을 쓴다. 무게시 자리에 상태만 남기려면 산출 케이스가 하나 더 필요해 수용한다.
- `G`(`documentEnd`) 뒤에는 열이 미상이다 — 마지막 줄 시작을 세려면 창이 문서 끝에 닿아야 하는데 그 보장이 없다. 이어지는 `j`/`k`가 정직하게 스킵된다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (Visual 확장·산출 함수 표)
- `VimAction/VisualAnchor.swift`(`desiredColumn`), `VimAction/FocusedTextOffsets.swift`(`charwiseExtension`·`movedFocus`·`focusOnLine`·`lineEndColumn`)
- 도그푸딩 판독: AX 앱에서 `vj`가 짧은 줄에 내려갈 때 **개행까지 잡히는 것**과, 그 아래 긴 줄에서 **원래 열로 돌아오는 것**이 정답이다.

## Supersedes

- [20260809_ax-span-vim-exact-where-table-is-silent.md](20260809_ax-span-vim-exact-where-table-is-silent.md) — **부분**: "charwise 세션의 `j`/`k`는 그대로 위임" 문언만. `V` 세션의 `j`/`k`가 위임이 아니라는 판정과 나머지 실측·규칙은 유효하다.

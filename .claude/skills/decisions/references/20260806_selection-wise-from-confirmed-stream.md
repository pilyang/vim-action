# Visual `.selection` 편집의 wise는 게시 확정 스트림에서 온다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

`.edit(op, .selection)`(Visual `d`/`y`/`c`)의 wise 기록은 어댑터가 **게시가 확정된(`.groups`)** `beginSelection(linewise:)`·`switchSelectionWise(linewise:)`의 값을 추적해서 쓴다. 추적 값(`selectionWise`)은 `PasteWiseResolver`의 별도 필드에 산다 — `noteSelectionWise(_:)`로 note하고 `recordSelectionEdit()`이 소비한다. 미상이면(begin 없이 온 편집) 기록하지 않고 휴리스틱에 맡긴다.

"begin = 리셋"(엔진 계약)은 코드로 복원한다: `beginSelection` **액션마다, 게이트·게시 확정과 무관하게** `forgetSelectionWise()`를 부른다. note가 게시 확정에 게이팅되므로 걸러진 begin(`.nonText`·`.unresolved`)은 note를 못 남기는데, 그때 옛 세션의 wise가 살아남으면 뒤따르는 `.selection` 편집이 이전 세션의 wise로 기록된다 — 앱 전환 콜드 창의 `v` 뒤 `d`가 낡은 linewise로 줄을 쪼개는, 휴리스틱이었다면 맞았을 자리를 틀리게 만드는 신규 오판이다(3-에이전트 리뷰 발견). 망각은 기록이 아니라서 "게이트가 부수효과보다 앞" 계약을 깨지 않는다 — 오염 방향이 없고 틀려봐야 휴리스틱 폴백이다.

## 배경·근거 (왜)

Notion `V` 세션의 `d` 뒤 `p`는 [`ddp`와 정확히 같은 오판 클래스](20260730_paste-wise-from-our-own-edit.md)다 — 블록 내용에 끝 개행이 없어 휴리스틱이 charwise로 판정하고 `p`가 줄을 쪼갠다. 20260730은 `.selection`을 "Visual의 wise는 어댑터가 들고 있지 않다"며 범위 밖으로 미뤘는데, 그 전제가 바뀌었다: PR-C1이 어댑터 상태 협력자 선례(`VisualAnchorTracker`)를 세웠고, 무엇보다 **wise는 AX 없이도 엔진 액션 스트림에 이미 실려 온다**.

핵심은 **엔진 상태가 아니라 화면 진실을 추적하는 것**이다. 스킵된 전환(`V`→`v` 폴백은 매퍼 `nil` — 정직한 스킵)은 화면 선택이 줄 단위 그대로인데 엔진 wise는 charwise로 넘어가 있다. 이때 `d`가 자르는 내용은 줄 단위이므로, **게시가 확정된 전환만** 따라가는 추적이 내용과 일치한다. 이 규칙은 상태 갱신의 기존 계약("`.groups` 확정 후에만" — `recordEdit`·`VisualAnchorUpdate`와 동일)을 그대로 재사용한다.

거처가 `PasteWiseResolver`인 이유: 붙여넣기 wise 기억이 이 타입의 존재 이유이고, 게시 직렬 큐 단독 소유 계약도 그대로다. 수명이 단순한 것도 근거다 — 소비자는 `.selection` 편집뿐이고 엔진이 begin 선행을 보장하므로, 낡은 값이 소비될 경로가 없다.

## 검토한 대안

- **엔진 `VimAction` 확장 (`.selection`에 linewise 동봉)**: 데이터 흐름은 단순하지만 엔진 API 변경이고, 스킵된 `V`→`v`에서 엔진 wise ≠ 화면 wise라 오히려 틀리는 케이스가 생긴다 — 기각.
- **`VisualAnchorTracker`에 병합**: 앵커 상태의 `.discard`는 자가 검증 실패에서도 발생하는데 그때 화면 세션은 살아 있다 — wise까지 지우면 틀리므로 폐기 규칙을 갈라야 하고, 그러면 계약이 복잡해진다. 또 앵커 수립은 읽기 성공이 전제라 Slack·VS Code 폴백 경로에서는 아예 상태가 없다 — 기각.
- **`.selection`도 휴리스틱 유지**: Notion `Vd` 후 `p`가 깨진 채 남는다 — 이 세션의 해소 대상 그 자체라 기각.

## Supersedes

- [20260730_paste-wise-from-our-own-edit.md](20260730_paste-wise-from-our-own-edit.md) **부분** — 검토한 대안의 "`.selection`까지 기억은 범위 밖" 항목만. 본 결정의 나머지는 [20260806_paste-wise-memory-covers-all-edits.md](20260806_paste-wise-memory-covers-all-edits.md) 참조.

## 영향 범위

- `PasteWiseResolver`: `selectionWise` 필드 + `noteSelectionWise(_:)`/`recordSelectionEdit()`
- `KeyboardAdapter` Visual 분기: `.groups` 확정 시 begin/switch의 wise를 note
- 어댑터 테스트: Visual 세션 wise 3건 + 스킵 전환 1건 + 무기억 1건
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

# paste wise 기억을 클립보드 쓰기 편집 전반으로 확장

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

`PasteWiseResolver`의 wise 기억을 linewise 편집 한정에서 **클립보드를 쓰는 편집 전부**로 확장한다 — delete/change는 `Cmd-X`, yank는 `Cmd-C`라 모든 편집이 클립보드를 쓴다. `recordLinewiseEdit()`은 `recordEdit(_ wise:)`로 일반화되고, 어댑터가 게시 확정(`.groups`) 시 아래 표대로 기록한다. 델타-1 규칙(붙여넣기 시 `changeCount`가 기록 시점 대비 정확히 +1일 때만 기억 사용)은 불변이고, 끝 개행 휴리스틱은 **외부 복사 전담**으로 완전히 물러난다.

| 편집 | 기록 wise |
|---|---|
| `op ≠ change`, `.line`/`.linewiseMotion` (`dd`·`yy`·`dj`·`dG`) | linewise (기존 유지) |
| `.change`, `.line`/`.linewiseMotion` (`cc`·`cgg`) | **charwise** (신규) |
| `.motion`/`.textObject`, 전 op (`x`·`dw`·`diw`·`y$`·`cw`…) | **charwise** (신규) |
| `.selection` (Visual `d`/`y`/`c`) | **세션 wise** ([20260806_selection-wise-from-confirmed-stream.md](20260806_selection-wise-from-confirmed-stream.md)) |
| 미지의 `TextRange` 케이스 | 기록 안 함 → 휴리스틱 (보수 방향) |

## 배경·근거 (왜)

[20260730_paste-wise-from-our-own-edit.md](20260730_paste-wise-from-our-own-edit.md)가 세운 원칙 — "우리가 낸 편집은 추론할 필요가 없다" — 을 linewise에만 적용하고 있었다. 휴리스틱 오판은 양방향이다:

- **linewise → charwise 오판** (기존 해소): Notion은 블록을 잘라내도 끝 개행을 붙이지 않는다.
- **charwise → linewise 오판** (이번 해소): 줄 끝 `x`가 개행을 잘라내면 내용이 개행으로 끝나고, Visual charwise 선택이 개행을 물고 끝나도 같다 — `p`가 엉뚱하게 줄 단위로 붙여넣는다.

`cc`를 **charwise로 기록**하는 것은 20260730의 제외 근거를 뒤집는 게 아니라 완성하는 것이다: 그때는 "linewise로 기억하면 안 된다"까지만 정했고(기억 안 함 = 휴리스틱), 이제 그 내용이 실제로 charwise(줄 유지 반올림 — 개행 없음)라는 사실 자체를 기록한다. `.selection`의 change만 예외로 세션 wise를 따른다 — 선택을 그대로 자르므로 줄 유지 반올림이 없어 내용이 곧 선택이다.

기록 시점(게시 확정 후)·게이트 순서(부수효과보다 앞)·드롭 방어(게시가 드롭되면 `Cmd-X`가 안 나가 `changeCount`가 안 올라 델타-1이 기억을 무효화)는 전부 기존 구조를 그대로 상속한다 — 이 확장이 값 하나(`Bool` 판정 → `PasteWise?` 판정)의 일반화로 끝나는 이유다.

## 검토한 대안

- **charwise는 계속 휴리스틱에 맡기기**: charwise 내용은 대개 개행으로 안 끝나 휴리스틱이 맞긴 하다. 그러나 줄 끝 `x`·개행 포함 선택에서 결정적으로 틀리고, "우리가 아는 것 먼저" 원칙의 예외를 유지할 이유가 없다 — 기각.

## Supersedes

- [20260730_paste-wise-from-our-own-edit.md](20260730_paste-wise-from-our-own-edit.md) **부분** — "기억 대상은 `op != .change` && `.line`/`.linewiseMotion`" 한정과 change 제외("그렇게 붙여넣는 것이 맞다"는 유효 — 이제 휴리스틱이 아니라 기록으로 그렇게 붙인다)를 대체한다. 기억 우선·델타-1 규칙·휴리스틱 폴백 구조는 유효.

## 영향 범위

- `PasteWiseResolver`(`Clipboard.swift`): `recordEdit(_ wise:)` 일반화
- `KeyboardAdapter`: `isLinewise` → `contentWise(_:_:) -> PasteWise?`, `.groups` 확정 시 기록
- 어댑터 테스트 +7 (charwise·cc·Visual 3종·스킵 전환·무기억), 기존 3건 무수정 통과
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

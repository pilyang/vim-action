# 편집 키스트로크 매핑 계약 — 선택 후 오퍼레이터 1타

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-27

## 결정

Keyboard 어댑터의 편집 실행은 **신규 순수 매퍼 `EditKeyMapper`** 가 담당한다. 시그니처는 `(op, range, family) → [KeyStroke]?`이며, `nil`은 "이 계열에서 미지원"(어댑터의 스킵+로그 대상)이라는 뜻이다 — 빈 배열과 구분되어야 무로그 삼킴이 생기지 않는다.

모든 편집은 **한 형태**다: 범위를 Shift+모션으로 선택한 뒤 오퍼레이터 1타.

- `delete`/`x`, `change` → `Cmd-X`
- `yank` → `Cmd-C` + collapse
- `change`는 오퍼레이터 뒤에 붙일 키가 없다 — 엔진이 완결 시 이미 Insert로 전이한다.

선택 스트로크는 **모션 매핑의 재사용**으로 전부 나온다: `MotionKeyMapper.keyStrokes(for:)`의 각 스트로크 flags에 `.maskShift`를 얹는다. 앵커가 고정된 채 엔드포인트만 캐럿처럼 움직이므로 `w`(`Opt-→,Opt-→,Opt-←`)·`^`(`Cmd-←,Opt-→,Opt-←`)의 3타 조합도 특례 없이 선택 확장으로 성립한다.

테이블 형태는 `(op, range, family)`로 분기하는 **switch 함수**(total function)다. 요소 계열(`ElementFamily`)은 지금 `.textArea` 하나뿐이고 어댑터가 고정 주입하지만, 키에 처음부터 포함시킨다.

단계 1의 지원 범위: charwise(`x`, d/c/y + `h l w b e 0 ^ $`), `cw`→`ce` 특례, linewise(`dd/cc/yy`, `j k`, `G gg`), word 텍스트 오브젝트 근사(`Opt-←` 후 `Shift-Opt-→`). 미지원(`nil`): `aw`·따옴표·괄호쌍 오브젝트, Visual `.selection`.

## 배경·근거 (왜)

엔진은 M1 시점부터 `.edit(Operator, TextRange)`를 정확히 내고 있었지만 어댑터가 `.move`만 실행해, 릴리스 빌드에서 편집 키가 무로그로 삼켜지는 "죽은 키"가 남아 있었다 ([20260726_release-block-gate-moves-to-m3.md](20260726_release-block-gate-moves-to-m3.md)). 이 결정이 그 실행 본체다.

"선택 후 오퍼레이터"를 택한 이유는 캐럿 모델에서 **범위를 표현할 수단이 선택뿐**이기 때문이다. macOS에는 "여기서 저기까지 지워라"라는 프리미티브가 없고, Shift+모션이 정확히 그 역할을 한다. 단계 0의 undo 실측이 이 형태를 뒷받침한다: 선택+잘라내기 계열은 **1 undo 단위**라 사용자가 `u` 한 번으로 되돌린다 ([20260726_undo-unit-cmdz-policy.md](20260726_undo-unit-cmdz-policy.md)).

`change`도 `Cmd-X`인 것은 v1의 "시스템 클립보드 = 무명 레지스터" 설계와 맞는다 — Vim에서도 `c`/`d`/`x`는 무명 레지스터를 덮어쓰고, 그래야 뒤이은 `p`가 방금 지운 것을 붙여넣는다 ([20260723_paste-output-contract.md](20260723_paste-output-contract.md)).

매핑의 재사용(`select(_:)`)이 구조의 핵심이다. 모션 매핑이 개선될 때마다(예: `w`의 3타 조합) 편집 시퀀스가 **자동으로 따라온다** — 두 표를 따로 관리하면 `dw`가 `w`와 다른 곳에서 멈추는 어긋남이 생긴다. 그래서 편집 매퍼에는 모션별 특례가 `cw`→`ce` 하나뿐이다.

`family`를 처음부터 키에 넣는 것은 단계 3(focusedRole 리졸버 + TextField 분기) 재작업 봉쇄용이다. 반대로 **모션 매퍼에는 넣지 않는다** — 화살표 이동은 계열이 갈리지 않고, 갈리는 것은 편집 시퀀스뿐이다(`delete(.line)`이 TextArea에서는 줄 선택 후 잘라내기, TextField에서는 `Cmd-A, Delete`).

## 검토한 대안

- **`MotionKeyMapper` 확장(같은 타입에 편집 진입점 추가)**: 파일은 안 늘지만 타입명이 실제 책임과 어긋나고, 리네임하면 M2 결정 문서·architecture 문구·테스트로 diff가 번져 "기존 모션 매핑 무변경" 조건과 충돌한다. 단계 3 변경 지점의 국소성은 신규 파일과 동일해 실질 이득이 없다. 기각.
- **어댑터에 인라인**: `CGEvent` 없이 검증할 대상이 사라져 골든 테스트가 불가능해지고, "매퍼는 `[KeyStroke]`까지만"이라는 계약([20260726_motion-keystroke-mapping-contract.md](20260726_motion-keystroke-mapping-contract.md))을 깬다. 기각.
- **리터럴 딕셔너리 테이블 `[Slot: (Int) -> [KeyStroke]]`**: `count`가 `TextRange`의 연관값이라 키로 쓸 수 없어 `count`를 뗀 그림자 enum(`RangeKind`)과 `Slot` 키 타입을 새로 만들어야 한다. 누락 방어력은 switch와 같은데(둘 다 컴파일러가 못 잡는다) 타입 2개와 간접층이 늘고 시퀀스가 클로저 리터럴 안에 흩어진다. 기각.
- **`change`를 `Delete` 키로**(클립보드 보존): Vim 시맨틱과 어긋나고 `p`와의 정합이 깨진다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (Keyboard 어댑터 절), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (실행 범위 문단)
- 신규 `VimAction/EditKeyMapper.swift`, `VimActionTests/EditKeyMapperTests.swift`(골든 57행)
- `VimAction/KeyboardAdapter.swift` — `guard case .move`를 액션→키스트로크 분기로 교체. `MotionKeyMapper`·`ActionExecutor`·엔진 타깃은 무변경.
- 세부 반올림·collapse·레이아웃 가정은 별도 결정: [20260727_linewise-newline-rounding.md](20260727_linewise-newline-rounding.md), [20260727_yank-collapse-to-range-start.md](20260727_yank-collapse-to-range-start.md), [20260727_operator-key-ansi-layout-assumption.md](20260727_operator-key-ansi-layout-assumption.md)

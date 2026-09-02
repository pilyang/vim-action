# s / S 어휘 추가 — cl / cc 축약, 카운트는 유효

- **결정일**: 2026-09-01

## 결정

`s`·`S`를 축약 어휘로 추가한다 — Normal `s` = `cl`, `S` = `cc`, Visual `s` = `c`와 **동일 출력**으로 즉시 완결한다(Insert 전이는 기존 `complete` 헬퍼). `D`/`C`/`Y`와 달리 **카운트는 유효하다**: `3s` → `.motion(.charRight, count: 3)`, `3S` → `.line(count: 3)`.

## 배경·근거 (왜)

축약 어휘라는 점은 `D`/`C`/`Y`와 같지만 카운트 정책이 갈린다. 기준은 종전대로 **표현 가능성**이다: `3D`는 Vim 의미(줄 끝 + 아래 N-1줄)를 출력 어휘로 표현할 수 없어 invalid로 이연했지만, `3s`는 Vim에서 `c3l`, `3S`는 `3cc`라 기존 `TextRange`가 의미를 **정확히** 담는다. 오해석의 여지가 없으므로 이연할 이유가 없다.

네 경우 전부 기존에 지원되는 출력과 바이트 동일이라 **어댑터 변경이 0**이다. 부수 확인 3건:

- 빈 줄에서의 `s`: 정확화 표의 `charRight`/빈 줄 = 무효(스킵)이고 모드 전이는 그대로 일어나 **Vim과 같은 결과**(삭제 없이 Insert)가 된다.
- `ds`/`dS`: opMotion 화이트리스트 밖이라 자동으로 invalid no-op — `dD`/`dY` 선례와 같고 특례가 필요 없다.
- Normal `S`의 들여쓰기 미보존(Vim autoindent): 현행 `cc`와 같은 편차라 **새 편차가 아니다**.

구현 위치는 `lineEndShorthands` 테이블이 아니라 `x`가 있는 최상위 `switch key`다 — 두 키의 범위 형태가 갈려(`.motion` vs `.line`) 테이블화하면 값이 클로저가 되고, 그건 축약 2건에 비해 과한 구조다.

## 검토한 대안

- **`lineEndShorthands` 테이블 확장**: 그 테이블은 "오퍼레이터 → `.motion(.lineEnd)`" 단일 형태 전용이다. 범위가 갈리는 `s`/`S`를 넣으면 테이블이 클로저 맵이 되어 단일 소스의 이점이 사라진다.
- **전용 `Operator`·`Motion` 케이스 신설**: 출력이 기존 어휘와 완전히 같으므로 순수 중복이고, 소비자(어댑터·정확화 표·`PasteWiseResolver` 기록 표)에 새 분기를 퍼뜨린다.
- **카운트를 invalid로 이연** (`D`/`C`/`Y`와 통일): 정책의 기준이 "일관된 키 모양"이 아니라 "의미를 표현할 수 있는가"이므로, 표현 가능한 카운트를 버리는 것은 기준의 오적용이다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift` — Normal `switch key` 2 케이스, `visualOperatorKeys`에 `s`.
- 픽스처: `EditFixtures.swift`(`substituteFixtures`), `VisualFixtures.swift`.
- 문서: `docs/KEYBINDINGS.md`, `README.md`.
- Visual `S`의 charwise 처리는 별도 결정 — [20260901_visual-substitute-linewise-only.md](20260901_visual-substitute-linewise-only.md).

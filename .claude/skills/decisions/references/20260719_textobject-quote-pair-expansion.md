# TextObject 확장 형태 — quote·pair kind 케이스 + 카운트+오브젝트 invalid

- **결정일**: 2026-07-19

## 결정

`VimAction.TextObject`를 kind별 케이스 + `Scope` 연관값으로 확장한다: `quote(Quote, Scope)`(double/single/backtick), `pair(Pair, Scope)`(paren/bracket/brace/angle). 기존 `word(Scope)`와 같은 형태다.

**완결 키 매핑**: `"` `'` `` ` `` → quote / `(` `)` `b` → paren / `[` `]` → bracket / `{` `}` `B` → brace / `<` `>` → angle. **여닫이 양쪽 키 + Vim 별칭(b/B)을 모두 인정**하고, 어느 키로 완결해도 같은 kind다. 미매핑 완결 키는 기존 규칙대로 invalid(swallow). 경계의 실제 의미(따옴표 안/포함, 괄호 중첩 처리)는 word와 같은 원칙으로 어댑터 몫 — 엔진은 kind와 scope만 낸다.

**카운트+텍스트 오브젝트는 invalid** (`d2i(`, `3diw`, `c2a"` 등 — 선행·오퍼레이터 뒤 어느 쪽 카운트든, word 포함 전체): Vim에서 `2i(`는 괄호 중첩 2단계, `2iw`는 2단어라는 실제 의미가 있는데 count 슬롯이 없는 `.textObject` 출력으로는 표현할 수 없다. 조용히 버리면 의도(중첩 2단계)와 다른 범위(1단계)를 지우는 **파괴적 편집의 오해석**이 되므로, `d3G`와 같은 기준으로 invalid 이연한다. (그전까지는 카운트가 조용히 버려지고 있었다 — 사용자 확인으로 invalid 전환, 2026-07-19.)

## 배경·근거 (왜)

quote·pair는 kind 수(3+4)와 scope(2)의 조합이라, flat 케이스로 펼치면 케이스 폭발과 소비자 매칭 중복이 생긴다. kind enum + Scope 연관값이면 어댑터가 "kind 무관 scope 공통 처리"와 "kind별 경계 탐색"을 직교로 나눌 수 있다. 별칭까지 모두 인정하는 것은 Vim 사용자의 근육 기억(`ci(`와 `cib`를 혼용)을 그대로 받기 위함이며, 테이블 엔트리 추가만으로 비용이 없다.

## 검토한 대안

- **flat 케이스 (`doubleQuoteInner`, `parenAround`, ...)**: 3×2 + 4×2 = 14케이스로 폭발하고 scope 공통 로직이 소비자에서 중복된다. 기각.
- **카운트를 출력에 실어 어댑터 이연 (`textObject(TextObject, count:)`)**: 어댑터가 중첩 단계/단어 수 해석을 구현할 때까지는 쓰이지 않을 계약 확대 — 필요해지는 시점에 additive로 추가 가능. 기각(이연).
- **카운트 조용히 무시 (기존 동작 유지)**: 파괴적 편집의 오해석. `d3G`를 invalid로 이연한 기준과 모순된다. 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimAction.swift`(TextObject), `VimEngine.swift`(quoteObjectKeys/pairObjectKeys 테이블, textObjectScope 완결 분기 guard)
- 어댑터 구현 시 kind·scope별 경계 탐색을 정의해야 한다 (아직 미구현).

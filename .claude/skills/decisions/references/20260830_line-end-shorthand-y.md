# Y 어휘 추가 — y$ 축약(Neovim 기본), 카운트는 invalid

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-30

## 결정

Normal 최상위에 `Y`를 추가한다 — `y$`와 **동일 출력**(`.edit(.yank, .motion(.lineEnd, count: 1))`)으로 즉시 완결하며, yank는 모드를 바꾸지 않아 Normal이 유지된다. 카운트가 있으면(`3Y`) invalid다. Visual의 `Y`는 v1 어휘 밖 — 미매핑 swallow 유지(명시적 non-goal).

판정은 `D`/`C`와 함께 소형 테이블 `lineEndShorthands`(D→delete, C→change, Y→yank)로 묶어 `step` 최상위 오퍼레이터 키 블록 바로 뒤에서 본다.

## 배경·근거 (왜)

`Y`는 커서부터 줄 끝까지 yank하는 고빈도 키인데 미매핑 swallow(죽은 키)였다 — `D`/`C`가 이미 들어와 있는 "대문자 = 커서부터 줄 끝까지" 계열의 마지막 빈칸이다. `y$`가 이미 완전 실행되므로(`$`는 `opMotions` charwise 화이트리스트, `EditKeyMapper`의 `.motion` 케이스가 `.lineEnd` 처리) 동일 출력 축약으로 두면 **어댑터·게시 인프라 무변경**으로 성립한다.

카운트 invalid는 `D`/`C`의 근거를 그대로 옮긴 것이 아니다 — yank는 버퍼에 비파괴적이라 "파괴적 편집" 논거가 성립하지 않는다. 대신 오해석 회피가 근거다: `3Y`의 Vim 의미(`3y$` = 아래 N-1줄 끝까지)를 현재 출력 형태로 표현할 수 없고, 그렇다고 줄 끝까지만 복사해 **unnamed register(= 시스템 클립보드)를 사용자가 의도하지 않은 내용으로 덮는 것 역시 오해석**이다. 따라서 줄 끝 축약 계열의 규칙(카운트 invalid)을 그대로 적용한다 ([20260801_line-end-shorthand-d-c.md](20260801_line-end-shorthand-d-c.md)와 같은 결론, 다른 근거).

## 검토한 대안

- **`Y` = `yy`(Vim 기본 — 줄 전체 yank)**: 기각. `yy`는 이미 두 타로 도달 가능해 `Y`를 거기 쓰면 중복이고, 같은 계열의 `D`/`C`("대문자 = 커서부터 줄 끝까지")와 어긋난다. Neovim 기본값도 `y$`다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md) (구현된 키셋, step 내부 우선순위)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift` — `step`의 축약 판정이 최상위 switch 밖 `lineEndShorthands` 조회로 이동(D/C 포함, 동작 불변)
- 픽스처: `EditFixtures.swift` (`Y` 완결·`3Y` 카운트 invalid·`dY` op-대기 중 invalid)
- 문서: `docs/KEYBINDINGS.md`, `README.md`
- 어댑터 무변경 — 소비자는 기존 `y$` 경로를 그대로 탄다

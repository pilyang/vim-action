# openLine(o/O) 출력 계약 — 전용 케이스 + Insert 전이 + 카운트 무시

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-23

## 결정

`o`/`O`는 새 top-level `VimAction` 케이스 `openLine(above: Bool)`로 출력하고, 완결 시 엔진이 Insert로 전이한다(`a`/`A`/change와 같은 전이+출력 동시 패턴). 선행 카운트는 무시한다 (`3o` = `o`).

## 배경·근거 (왜)

PRD §7.2가 `o O`를 Insert 진입 명령으로 요구한다. "새 줄 삽입 + 그 줄로 이동"은 오퍼레이터×범위 구조(`.edit(Operator, TextRange)`)에도, 순수 이동(`.move`)에도 들어맞지 않는 복합 동작이다 — 어댑터가 "줄 열기"를 하나의 의미 단위로 받아야 들여쓰기 유지·줄 경계 처리 같은 실행 세부를 스스로 정할 수 있다.

카운트: Vim의 `3o`는 "Insert에서 입력한 텍스트를 종료 시 3줄로 반복"인데, 엔진에는 Insert 세션 기억이 없어 표현 불가다. 표현 불가한 카운트는 무시하는 `3i` 선례를 그대로 따른다 — 무시는 안전한 축소 해석(1회 실행)이고, 반복 출력(빈 줄 3개 열기)은 Vim 의미와 다른 오해석이라 배제한다(파괴적 편집의 오해석 불수용 원칙).

## 검토한 대안

- **`.move` 모션 + 전이로 합성** (예: `lineEndForAppend` + newline 삽입 액션 분해): 기각 — newline 삽입은 이동이 아니고, 분해하면 "줄 열기" 의미가 어댑터에 전달되지 않는다.
- **`.edit(.change, …)` 계열 재사용**: 기각 — 피연산 텍스트 범위가 없다.
- **카운트 반복 출력** (`3o` → openLine 3회): 기각 — 빈 줄 3개는 Vim 의미가 아닌 오해석.

## 영향 범위

- `Packages/VimActionCore` — `VimAction.swift` 케이스 신설, `VimEngine.swift` step 최상위 매핑, 픽스처.
- architecture [mode-engine.md](../../architecture/references/mode-engine.md)는 구현 완료 시 갱신 (플랜 [20260723_engine-open-paste-undo.md](../../plans/references/20260723_engine-open-paste-undo.md) 참조).

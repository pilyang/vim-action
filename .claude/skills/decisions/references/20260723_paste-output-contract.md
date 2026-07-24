# paste(p/P) 출력 계약 — 단일 액션 count, wise 판정은 어댑터

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-23

## 결정

`p`/`P`는 새 top-level `VimAction` 케이스 `paste(before: Bool, count: Int)`로 출력한다. 카운트는 반복 출력이 아니라 count 값으로 나른다 — `3p`는 "내용을 3회 연속 붙여넣기"라는 한 편집 단위다. 붙여넣을 내용의 charwise/linewise 판정(문자 위치 vs 줄 단위 배치)은 어댑터 몫이며, 엔진은 before/after 방향만 낸다. v1에 레지스터가 없으므로 시스템 클립보드(네이티브 paste) 위임을 전제한다.

## 배경·근거 (왜)

Vim의 `3p`는 붙여넣기 3회 연속이라는 표현 가능한 반복 의미가 있다 — `3o`(표현 불가→무시)와 달리 버릴 이유가 없다. 반복 출력 대신 단일 액션 count를 택한 것은 편집 카운트는 범위/액션의 count 값으로 나른다는 기존 선례(`3x` = `.motion(.charRight, count: 3)`) 때문이다: 한 편집 단위로 묶으면 어댑터가 내용×3을 단일 삽입으로 실행할 수 있어 앱 undo 1단계로 묶일 여지도 남는다.

wise 판정을 어댑터에 두는 이유: 엔진은 클립보드 내용을 모르고(상태 없음·macOS 무의존), Vim처럼 yank 시점의 wise를 기억할 레지스터도 v1에 없다. 줄 반올림을 어댑터의 실행 규칙으로 둔 Visual linewise 선례와 같은 분배다.

## 검토한 대안

- **반복 출력** (`.move` 선례, `[paste, paste, paste]`): 기각 — 합성 실행 시 앱 undo가 3단계로 갈라지고, "에디트 카운트는 count 값" 선례와 어긋난다.
- **카운트 무시**: 기각 — 표현 가능한 Vim 의미를 이유 없이 버린다 (무시는 표현 불가일 때의 원칙).
- **`Operator`에 `.paste` 추가**: 기각 — paste는 텍스트 범위를 피연산하지 않아 `.edit(Operator, TextRange)` 구조에 맞지 않는다.

## 영향 범위

- `Packages/VimActionCore` — `VimAction.swift` 케이스 신설, `VimEngine.swift` step 최상위 매핑(카운트 소비), 픽스처.
- 어댑터(디스패처 마일스톤): wise 판정·배치 규칙, count회 연속 삽입 실행 계약.
- architecture [mode-engine.md](../../architecture/references/mode-engine.md)는 구현 완료 시 갱신 (플랜 [20260723_engine-open-paste-undo.md](../../plans/references/20260723_engine-open-paste-undo.md) 참조).

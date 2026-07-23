# Visual 카운트+오퍼레이터는 카운트 무시하고 실행

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-23

## 결정

Visual에서 오퍼레이터(`y d x c`) 앞에 선행 카운트가 쌓여 있으면 **카운트를 버리고 즉시 실행**한다 (`3d` = 선택 삭제, Vim 동일). 기존의 "카운트가 있으면 invalid(swallow)" 동작을 뒤집는다.

## 배경·근거 (왜)

코드리뷰 F4: 기존 swallow는 `d3G`-invalid("절대 줄 의미를 표현할 수 없어 파괴적 편집의 오해석을 거부")를 유비로 삼았지만, 이 유비는 Visual에 적용되지 않는다 — Visual 오퍼레이터의 피연산자는 이미 확정된 **선택 범위**라 카운트가 결과를 바꿀 여지, 즉 오해석 가능성이 구조적으로 0이다. 오해석이 불가능한 곳에 오해석-거부 규칙을 적용해, `v 3 j`로 확장하다 습관적으로 `3d`를 친 사용자가 무피드백 swallow(선택은 남고 아무 일도 없음)를 겪었다.

카운트 무시 실행은 사용자 의도(선택을 지우려던 것)와 거의 항상 일치하고, Vim 실동작과도 같다. "카운트 붙은 파괴적 편집은 invalid" 계열(d3G, d2i()에 예외가 하나 생기지만, 예외의 근거(오해석 위험 0)가 명확해 원칙 자체는 훼손되지 않는다.

## 검토한 대안

- **현상 유지 + 주석의 d3G 유비만 정정**: 코드 무변경이지만 무피드백 swallow UX와 Vim과 다른 동작이 남는다. 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `VimEngine.swift`(`visualStep` 오퍼레이터 분기의 카운트 guard 제거), `VisualFixtures.swift`(3d 픽스처 갱신, 3c 픽스처 추가).
- 기존 invalid 동작은 픽스처와 mode-engine.md에만 고정되어 있었고 전용 결정 문서가 없어 Supersedes 대상 없음 (신규 결정으로 기록).

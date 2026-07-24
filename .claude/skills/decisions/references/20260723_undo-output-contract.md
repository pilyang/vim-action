# undo(u) 출력 계약 — 네이티브 위임 + 카운트 반복 출력

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-23

## 결정

`u`는 새 top-level `VimAction` 케이스 `undo`로 출력하며, 실행은 앱 네이티브 undo에 위임한다(PRD §7.2 명시). 카운트는 `.move`와 같은 반복 출력이다 — `3u` → `[undo, undo, undo]`, 어댑터는 각각 undo 1회(Cmd+Z 합성 등)로 위임한다.

`Ctrl-r`(redo)은 이 결정에 포함하지 않는다 — Ctrl 콤보 묶음에서 취소 최우선 순서 전제 재검토([20260717_cancellation-first-ordering-premise.md](20260717_cancellation-first-ordering-premise.md))와 함께 다룬다. `u`만 먼저 나가는 비대칭은 수용한다: Normal 모드에서 Cmd+Shift+Z는 탈출 콤보 passthrough라 네이티브 redo 접근이 막히지 않는다.

## 배경·근거 (왜)

undo는 피연산 범위가 없는 이산 반복 동작이라 `.edit(Operator, TextRange)`에 들어가지 않고, "N회 = 같은 동작 N번"이라는 점에서 모션의 반복 출력 선례에 정확히 부합한다(한 편집 단위로 묶을 실익이 있는 paste와 다른 지점). 앱 undo 스택의 단위는 Vim 변경 단위와 어차피 다르므로 카운트 충실도는 근사치지만, 위임 자체가 근사이고 과하게 되돌려도 앱 redo로 복구 가능(가역)하라 수용한다.

## 검토한 대안

- **`undo(count:)` 단일 액션**: 기각 — 반복 루프가 어댑터로 옮겨갈 뿐 실질 차이가 없고, 이산 반복 동작의 카운트는 반복 출력이라는 `.move` 선례와 어긋난다.
- **카운트 무시**: 기각 — 표현 가능한 반복 의미를 버린다 (무시는 표현 불가일 때의 원칙).

## 영향 범위

- `Packages/VimActionCore` — `VimAction.swift` 케이스 신설, `VimEngine.swift` step 최상위 매핑(반복 출력), 픽스처.
- 어댑터(디스패처 마일스톤): undo 1회 위임 실행(전략별 Cmd+Z 합성 또는 AX).
- architecture [mode-engine.md](../../architecture/references/mode-engine.md)는 구현 완료 시 갱신 (플랜 [20260723_engine-open-paste-undo.md](../../plans/references/20260723_engine-open-paste-undo.md) 참조).

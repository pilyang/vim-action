# Normal 빈 상태 Esc는 passthrough — 취소 Esc(swallow)는 pending 있을 때만

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

Normal 모드의 Esc 정확 매치는 pending 유무가 가른다 — 어느 쪽도 Normal 유지: **pending이 있으면 현행대로 폐기 + swallow**(취소로 소비), **없으면 `.passthrough`**(앱으로 전달). Insert의 Esc(→Normal, swallow)와 Visual의 Esc(clearSelection + Normal 복귀), 탈출 modifier 콤보 분기는 전부 현행 유지다.

## 배경·근거 (왜)

기존 의미론(Esc는 무조건 swallow + Normal 유지)에서는 Normal 모드에 있는 동안 앱이 Esc를 영원히 받지 못한다 — 모달·팝오버·자동완성을 키보드로 닫을 수 없고, 이는 M3 단계 4 게이트가 겨냥하는 "죽은 키" 그 자체다. 빈 상태 Esc는 취소할 pending이 없으므로 삼킬 이유도 없다 — 통과시키면 **Esc 연타로 "Normal 진입(Insert Esc) → 앱에 취소 전달(둘째 Esc부터)"** 이 자연스럽게 성립한다.

pending 중 Esc를 계속 삼키는 이유: 취소 Esc가 앱까지 전달되면 `d` 입력 후 마음을 바꾼 Esc가 열려 있던 앱 모달을 함께 닫는 부작용이 생긴다. 취소는 Vim 레이어 내부의 소비로 끝나야 한다. Esc 연타 시나리오는 첫 Esc가 pending을 비우므로 두 번째부터는 자동으로 passthrough라 이 유지에 영향받지 않는다.

부수 효과: Ctrl-[ 정규화 선행 핀(`CtrlComboFixtures`)은 빈 상태 출력이 passthrough로 합류하면서 탈출 콤보와 출력만으로 구분되지 않게 됐다 — 판별 신호는 **finalMode**(Esc 경로는 `.normal` 유지, 탈출 콤보는 `.insert` 전이)로 바뀌었고 픽스처 이름·주석을 그에 맞게 갱신했다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md) (Normal 처리 규칙 ①)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `handleNormal` Esc 분기
- 픽스처: `CancellationFixtures.swift`(빈 상태 Esc 신규 핀 — 기존 취소 매트릭스는 전부 pending 진입 후라 무변경), `CtrlComboFixtures.swift`(정규화 선행 핀의 판별 신호 교체)
- 앱 코드·어댑터 무변경 — passthrough는 마커·게시 인프라를 타지 않고, 래치 무효화는 결정 종류 불문이라 버스트 중단도 현행 유지

## Supersedes

- [20260717_cancellation-first-ordering-premise.md](20260717_cancellation-first-ordering-premise.md) — **부분**: "Esc → pending 폐기 + swallow + Normal 유지" 의미론만 뒤집는다. 취소 판정이 step보다 선행한다는 순서와 탈출 콤보 선행의 전제(매핑 예외 셋 포함)는 유효하게 유지된다.

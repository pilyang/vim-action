# 스크롤·redo 출력 계약 — scroll(ScrollExtent, forward:) 전용 케이스, 카운트는 반복 출력

- **결정일**: 2026-07-24

## 결정

`Ctrl-d`/`Ctrl-u`(half)·`Ctrl-f`/`Ctrl-b`(full)는 전용 케이스 **`VimAction.scroll(ScrollExtent, forward: Bool)`** 로 낸다 (`ScrollExtent`: `.halfPage`/`.fullPage`). `Ctrl-r`는 **`VimAction.redo`** — `undo`의 미러로 앱 네이티브 redo에 위임한다. 두 계약 모두 카운트는 반복 출력이다(`3<C-d>` = scroll ×3, `3<C-r>` = redo ×3 — 3u 규칙). 실제 스크롤 수단(키 합성 vs AX)과 커서 동반 이동 여부는 어댑터 몫이다.

키 매핑은 `handleNormal` 경로의 단일 테이블 `normalCtrlCombos`에 둔다 — **Normal 전용**이며 Visual에서는 미매핑 콤보 passthrough가 유지된다(v1 Visual 어휘 밖 — Vim의 "Visual 중 스크롤 = 선택 확장"은 extendSelection 계약 확장이 필요해 이연).

## 배경·근거 (왜)

- **전용 케이스 (Motion 재사용 기각)**: 스크롤은 커서 이동과 실행 의미가 다르다 — 어댑터가 PageDown 합성이나 AX 스크롤로 실행할 대상이지 캐럿 이동이 아니다. Motion에 섞으면 "모션 = 커서 이동" 의미가 흐려지고 opMotions 화이트리스트(`d`+모션)에 실수로 들어갈 표면이 생긴다.
- **shape**: extent(2)×방향(2)이 직교하므로 4케이스로 펴지 않고 방향을 Bool 파라미터로 나른다 — `openLine(above:)`/`paste(before:)`의 기존 관례.
- **카운트 = 반복 출력**: Vim의 `{count}<C-d>`는 "스크롤 줄 수 설정"(scroll 옵션 변경)인데 엔진은 이를 표현할 수 없다. 스크롤은 이산 반복·비파괴 동작이라 무시(3o 선례)가 아니라 반복(3u 선례)으로 수용한다 — 카운트 3정책의 "이산 반복 동작" 갈래. 극단 입력(`9999<C-f>` → 액션 9,999개)은 기존 모션 반복 선례·maxCount 클램프와 동일한 리스크 프로파일로 수용하고, 실행 비용은 어댑터 마일스톤에서 측정 후 판단한다(스크롤 전용 상한·count 필드화는 카운트 정책의 네 번째 예외를 만들어 기각).
- **redo를 이 문서에 함께 담는 이유**: [20260723_undo-output-contract.md](20260723_undo-output-contract.md)가 이연했던 `Ctrl-r`의 해소이며, undo 미러라는 것 외에 독립 근거가 없다.

## 검토한 대안

- **Motion 케이스 추가(halfPageDown 등) + `.move` 재사용**: 케이스 수는 적지만 위의 의미 혼선·화이트리스트 오염 표면. 기각.
- **스크롤 전용 카운트 상한 / `.scroll(…, count:)` 필드화**: 반복 폭주는 확실히 막지만 카운트 규칙이 액션별로 갈라져 계약이 복잡해진다. 기각 (사용자 확인).

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimAction.swift`(`scroll`/`redo`/`ScrollExtent`), `VimEngine.swift`(`normalCtrlCombos`, step의 조회)
- 픽스처: `CtrlComboFixtures.swift`
- [20260723_undo-output-contract.md](20260723_undo-output-contract.md)의 "Ctrl-r 이연·비대칭 수용"을 해소한다 (undo 계약 자체는 계속 유효)

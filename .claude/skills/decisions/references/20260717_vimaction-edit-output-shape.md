# VimAction 편집 출력 형태 — .edit(Operator, TextRange) 확정

- **결정일**: 2026-07-17

## 결정

엔진의 편집 출력을 `VimAction.edit(Operator, TextRange)`로 확정한다. `Operator`는 1차로 `delete`만, `TextRange`는 `motion(Motion, count: Int)` / `textObject(TextObject)` / `line(count: Int)` 세 케이스, `TextObject`는 `word(Scope)`(inner/around)만. 문법 빌더 결정 문서가 "세부 네이밍/형태는 구현 시 확정"으로 남긴 슬롯을 구현·동작 확인과 함께 못 박는 기록이다.

핵심 선택 3건:

1. **카운트 붙은 모션(`3w`)은 `.move` 반복 출력, 에디트 카운트는 `TextRange`의 `count` 값** — `.move(Motion)` 시그니처를 유지해 기존 모션 픽스처 전부가 count 1로 회귀 통과하고, 에디트는 `d3w`=6단어를 한 편집 단위로 표현한다. 비대칭이지만 각 케이스에 자연스럽고 회귀 안전.
2. **`x`는 `.edit(.delete, .motion(.charRight, count:))` 재사용** — 전용 케이스 없음. 줄 끝 문자 삭제 같은 경계는 어댑터 몫 (charRight/charRightForAppend 분리와 동일 원칙). 구현 결과 어댑터 관점 승격 필요성 없었음.
3. **텍스트 오브젝트 스코프는 `PendingCommand.prefix`에 합류** (`.textObjectScope`) — `g`(op 없음)와 스코프(op 있음)를 같은 "완결 키 하나를 기다리는 접두" 슬롯으로 통일, `op` 유무로 구분.

부속 확정: 오퍼레이터 뒤 유효 모션은 **charwise-safe 화이트리스트**(`w b e h l 0 ^ $`)만 — `dj`/`dk`/`dG`는 Vim에서 linewise 범위인데 `TextRange.motion`에 charwise/linewise 구분이 없어 어댑터가 의미를 복원할 수 없으므로 invalid로 이연. 카운트 누적은 **9,999 클램프** (Int 오버플로 트랩·반복 배열 폭주 방지). 절대 목표 모션의 카운트(`3G`)는 반복 출력 수용(멱등·무해, Vim 의미와 다름을 인지한 이연), `3gg`는 count 무시 단일 출력.

## 배경·근거 (왜)

문법 빌더 골격은 [20260714_multikey-command-grammar-builder.md](20260714_multikey-command-grammar-builder.md)에서 결정됐지만 출력 타입의 구체 형태는 구현 시점으로 미뤄져 있었다. 이 형태는 Plan-1(탭↔엔진 배선)과 공유하는 유일한 계약이라, 픽스처로 동작 확인이 끝난 시점에 고정 기록한다. enum 케이스 추가가 소비자의 exhaustive switch를 깨뜨리는 병렬 작업 리스크는 `.edit`를 무동작 발판 단계(Phase 0, PR #7)에서 선행 머지해 제거했다.

## 검토한 대안

- **`.move`에 count 슬롯 추가**: 기존 모션 픽스처 전면 수정 + 소비자(어댑터) 시그니처 변경 유발. 반복 출력이 회귀 안전.
- **`x` 전용 `TextRange.charForward(count:)` 케이스**: delete-over-motion 재사용으로 충분했고, 케이스 수만 늘린다.
- **스코프를 `PendingCommand`의 별도 필드로**: "완결 키 하나 대기"라는 동일한 상태가 두 슬롯으로 갈라져 step 분기가 중복된다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimAction.swift`, `VimEngine.swift`
- 소비자 지침: `EngineOutput.actions` 소비는 exhaustive switch 대신 `String(describing:)` 로깅 또는 `default:` 흡수 (케이스 추가에 견디게)

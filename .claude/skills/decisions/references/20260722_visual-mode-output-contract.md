# Visual 모드 출력 계약 — selection 계열 케이스 신설

> 일부 Superseded: "세션 활성 중 beginSelection 재수신 = 앵커 유지 + wise 교체" 조항은 [20260723_visual-begin-reset-switch-wise-split.md](20260723_visual-begin-reset-switch-wise-split.md)로, `y`의 출력 형태는 [20260723_visual-yank-clear-selection.md](20260723_visual-yank-clear-selection.md)로 대체됨. 그 외 계약은 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-22

## 결정

Visual 모드의 "모션은 이동이 아니라 선택 확장"이라는 의미를 **`VimAction`에 selection 계열 케이스를 신설**해 출력 자체에 담는다 (모드 문맥 동봉이나 어댑터의 엔진 상태 참조가 아니라). 구체 형태:

- `extendSelection(Motion)` — Visual에서의 모션. **카운트는 `.move`와 동일하게 반복 출력** (`3w` → 3회 출력). 케이스에 count 슬롯을 두지 않는다.
- `beginSelection(linewise: Bool)` — `v`/`V` 진입 시 명시 출력. **charwise/linewise는 세션 속성**으로 이 신호가 나르며, 개별 `extendSelection`에는 싣지 않는다. `V`의 "현재 줄 즉시 선택"도 이 액션의 실행 의미에 포함된다. 세션 활성 중 다시 수신하면(= `v`↔`V` 전환) 앵커 유지 + wise 교체·재적용이다.
- `clearSelection` — 이탈(`Esc`, 같은 키 재입력) 시 명시 출력. 화면의 선택을 실제로 해제(collapse)한다.
- `TextRange.selection` — Visual의 `y d x c`는 `.edit(Operator, .selection)`으로 낸다. `x`는 `d`와 동일 출력(전용 케이스 없음). `c`는 기존 `complete` 헬퍼로 Insert 전이를 동반한다.

선택 앵커와 실제 범위 계산은 **어댑터 상태·책임**이다 — 텍스트를 모르는 엔진은 추상 지시만 낸다.

## 배경·근거 (왜)

Normal의 `w`(이동)와 Visual의 `w`(확장)는 실행이 완전히 다르다(Keyboard: `Opt+→` vs `Shift+Opt+→`, AX: 캐럿 이동 vs 앵커 고정 확장). 이 구분을 어디에 두느냐가 문제였다.

- **자기완결성**: `VimAction`은 ""무엇을 해야 하는가"만 표현"이 존재 이유다. 케이스 신설만이 액션 단독으로 의미가 완전하고, 로그·디버깅·모든 소비자가 문맥 없이 동작한다.
- **테스트 전략 부합**: Normal `w`와 Visual `w`가 다른 출력이어야 Visual 해석 전체가 macOS 없는 픽스처 테스트로 검증된다. 다른 안들은 해석의 일부를 macOS 의존 어댑터 테스트로 밀어낸다.
- **적기**: 어댑터가 미구현이라 케이스 신설의 마이그레이션 비용이 0이다. "소비자는 exhaustive switch 금지" 계약 덕에 향후에도 케이스 추가는 무해하다.
- **어댑터 설계 문서와 정합**: strategy-dispatch.md의 AX 예시가 이미 `yank(.selection)` 형태를 가정하고 있었다.
- **카운트 반복 출력**: "모션 카운트는 반복, 에디트 카운트는 범위 내장"이라는 기존 이분법([20260717 편집 출력 형태](20260717_vimaction-edit-output-shape.md))의 대칭 적용. 선택 확장은 파괴적이지 않아 반복이 의미상 동치이고, 어느 어댑터든 한 번에 N단어를 건너뛸 방법이 없어 결국 반복 실행한다 — 카운트 루프를 엔진 한 곳에 둔다.
- **linewise는 세션 속성**: Vim의 Visual-line에서 `w`는 커서를 단어 단위로 움직이지만 선택은 줄 전체로 유지된다 — wise가 개별 모션의 속성이 아니라는 증거. 모션에 wise를 실으면 무효 조합(charwise 세션 중 linewise 액션)이 표현 가능해지고 모션 어휘가 이중화된다. 진입 신호에만 실으면 의미 구조와 표현 구조가 일치한다.
- **진입·이탈 명시 신호**: `V` 진입의 "현재 줄 즉시 선택"과 `Esc` 이탈의 "선택 해제"는 화면 변화가 있는 실제 동작이라 출력 없이는 표현 불가능하다. 암묵 규약(첫 확장 시 앵커 자동 설정 등)은 이 두 동작을 못 담고, 엣지마다 타입에 없는 규약이 어댑터 구현자 머리에만 쌓인다(어댑터 2종이라 불일치 리스크 ×2).

## 검토한 대안

- **`EngineOutput`에 모드 문맥 동봉** (액션은 `.move` 재사용): 액션 의미가 문맥 의존적이 되어 모든 소비자 시그니처에 `(action, mode)` 쌍이 전파된다. mode 필드가 해석 시점인지 전이 후인지의 시점 애매성이 본질적(Visual `c`는 액션은 Visual 의미인데 전이 후는 Insert). 기각.
- **어댑터가 엔진 `mode` 프로퍼티로 해석 분기** (출력 무변경): `handle`이 출력과 동시에 모드를 전이시키므로 실행 시점에 읽는 mode는 이미 다음 상태 — 본질적으로 racy. 전용 CFRunLoop 스레드 이행(활성 검토 중) 시 스레드 간 동기화 문제로 악화. 해석-실행 분리 불변식의 첫 예외가 됨. 픽스처가 모드 전이밖에 검증 못함. 기각.
- **`extendSelection(Motion, count:)` 내장 카운트**: 모션 카운트 규칙이 Normal(반복)과 Visual(내장)로 갈라지고, 카운트 루프가 어댑터마다 중복된다. 기각.
- **`extendSelection(Motion, wise:)` / `extendSelectionLinewise(Motion)`**: 세션 상수를 매 액션에 중복 첨부, 무효 조합 표현 가능, Visual-line의 charwise 모션(`w`)에서 "wordForward가 줄 단위"라는 뒤틀린 진술 발생. 기각.
- **진입·이탈 암묵 규약**: 이탈 시 화면 선택 해제 불가(폴링하면 기각된 mode-참조안의 결함 재유입), `V` 즉시 줄 선택 불가, `v` 직후 모션 없는 `y` 등 엣지마다 규약 증식. 기각.

## 영향 범위

- architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md) — Visual 구현 완료 시점(플랜 5단계)에 최종 상태 갱신 예정.
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimAction.swift`(케이스 신설), `Mode.swift`, `VimEngine.swift`, Visual 픽스처 테스트 신설.
- 어댑터 계약(향후 구현 시): 앵커·wise는 어댑터 상태, `beginSelection(linewise: true)`는 현재 줄 즉시 선택, 세션 중 재수신은 앵커 유지 wise 교체, `clearSelection`은 선택 해제.

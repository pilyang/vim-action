# 엔진 입력 Key는 base+modifiers 구조체, 픽스처는 Swift 코드 테이블

- **결정일**: 2026-07-12

## 결정

두 가지를 정한다.

1. **`Key` 표현**: 엔진 입력 `Key`는 `struct { base: Base; modifiers: Set<Modifier> }`. 문자 키는 `Base.char(Character)`로 일반화하고, 문자로 표현되지 않는 키만 케이스(`.escape`/`.enter`/`.tab`/`.space`)로 둔다. `Modifier`는 `.control`/`.option`/`.command`. **Shift는 modifiers에 두지 않는다** — 문자에 이미 반영된 shift(`$`, `G`, `^`)는 해당 `Character`로 들어온다.
2. **픽스처 포맷**: "키 시퀀스 → 기대 EngineOutput + 최종 모드" 픽스처 테이블을 **Swift 코드**(구조체 배열)로 정의해 `@Test(arguments:)`에 직접 물린다. 외부 리소스 파일(JSON 등)을 쓰지 않는다.

## 배경·근거 (왜)

**Key**: 문자를 `Character`로 일반화하면 지원 키가 늘어도 타입이 안 바뀌고, 임의 문자(이후 `f{char}`, 레지스터 등)도 자연히 표현된다. modifiers를 Set으로 분리하면 이후 `Ctrl-d`/`Ctrl-u` 같은 조합 확장이 케이스 폭발 없이 된다. shift를 modifiers에서 빼는 규칙은 "탭 계층이 CGEvent를 정규화한다"는 계약을 명확히 해, `$`가 `char("$")`인지 `char("4")+shift`인지 모호해지는 것을 원천 차단한다.

**픽스처**: Swift 코드 테이블이면 컴파일러가 오타·타입/계약 변경을 즉시 잡고, 리네임 리팩터링이 픽스처까지 자동 추적되며, 픽스처별 독립 리포팅(Swift Testing 파라미터라이즈드)이 그대로 된다. JSON은 코드 수정 없이 케이스를 늘릴 수 있으나 지금 규모(이동 키셋)엔 과하고, Key/VimAction의 문자열 인코딩 스키마 + 디코더를 따로 유지해야 하며 타입 변경이 컴파일 에러가 아니라 런타임 디코딩 에러로 늦게 발견된다.

## 검토한 대안

- **순수 enum `Key`** (`.h`, `.dollar`, …): 픽스처 가독성은 가장 좋으나 키셋마다 enum이 커지고(1차 이동셋만 15개+), 수정키 조합은 케이스 폭발, 임의 문자 표현이 불가해 기각.
- **외부 JSON 픽스처**: 위 근거 참고 — 현재 규모에 과하고 타입 안전·리팩터 추적을 잃어 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 생성한 코드: `Sources/VimEngine/Key.swift`, `Tests/VimEngineTests/FixtureSupport.swift`·`ModeTransitionTests.swift`
- 관련 결정: [20260712_swift-testing-for-engine-tests.md](20260712_swift-testing-for-engine-tests.md) (픽스처를 무엇으로 돌리는가), [20260712_single-core-spm-package.md](20260712_single-core-spm-package.md) (어디에 사는가)

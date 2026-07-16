# CGEvent→Key 번역 방식 — ASCII-capable 레이아웃 + shift-only base 추출

- **결정일**: 2026-07-16

## 결정

탭 계층의 CGEvent→`Key` 번역기(`KeyTranslator`, keyDown 전용)는:

1. 특수키(Esc/Return/Tab/Space)는 keycode로 먼저 판별하고,
2. 문자키는 `UCKeyTranslate` + `TISCopyCurrentASCIICapableKeyboardLayoutInputSource`로 번역하되 **modifier state에는 shift만 반영**하며(ctrl/opt/cmd/capsLock 제외), ctrl/opt/cmd는 `Set<Key.Modifier>`로 별도 전달하고,
3. 번역 불가(빈 출력·데드키 진행 중·제어문자·PUA·다중문자)는 `nil`을 반환하며 **호출측은 `nil`이면 이벤트를 무조건 통과**시킨다.
4. TIS API의 메인 스레드 요구에 따라 `KeyTranslator`는 `@MainActor`로 고정한다.

## 배경·근거 (왜)

- **ASCII-capable 레이아웃 강제**: 한글(2벌식 등) 입력 소스가 활성인 상태에서 현재 입력 소스로 번역하면 `w`가 `ㅈ`으로 나와 Normal 모드 키가 전부 안 먹는다. ASCII-capable 레이아웃(한글 사용자는 보통 ABC/US)으로 번역하면 입력 소스와 무관하게 Vim 키가 항상 동작하고, Dvorak 같은 대체 ASCII 레이아웃도 그대로 존중된다. 테스트도 로컬 입력 소스 상태와 무관해져 결정적이 된다.
- **shift-only base 추출**: 엔진 `Key` 계약은 shift를 modifiers에 두지 않고 문자에 흡수한다(`$`, `G`). 반면 ctrl/opt/cmd까지 번역에 반영하면 Ctrl-d가 제어문자(0x04), Opt-a가 `å`로 나와 base 문자를 잃는다 — 엔진의 modifier 기반 규칙(미매핑 modifier passthrough, Normal 탈출 옵션, 향후 Ctrl-d 매핑)에 정확한 base가 전달되려면 base 유도에서 이들을 벗겨야 한다. capsLock도 제외해 CapsLock+j가 `j`로 유지된다.
- **`nil` = 무조건 통과 계약**: 번역기가 정규화 못 하는 입력을 삼키면 시스템 키가 죽는다. 안전한 기본값은 통과.
- **`@MainActor` 고정**: TIS API는 메인 스레드 요구(비메인 호출 크래시 사례 다수). 탭 콜백은 이미 메인 런루프라 런타임 변화가 없고, Swift Testing의 병렬·비메인 실행에서도 테스트 스위트를 `@MainActor`로 맞춰 안전. 향후 탭을 전용 스레드로 옮기는 재검토 시 이 제약이 컴파일 에러로 드러나는 것도 의도.

## 검토한 대안

- **`CGEvent.keyboardGetUnicodeString` (현재 입력 소스 따라감)**: 플랜 초기 승인안. 코드가 가장 단순하지만 한글 입력 소스 상태에서 Normal 모드가 통째로 무력화되고, 테스트가 로컬 입력 소스에 의존해 flaky. 기각.
- **modifier 반영된 출력에서 제어문자면 `nil`**: 단순하지만 Opt 조합이 특수문자로 번역되고 modifier 기반 엔진 규칙에 base 문자가 전달되지 않음. 기각.
- **keycode→문자 고정 테이블**: 레이아웃 독립적이지만 Dvorak 등 대체 레이아웃 사용자를 깨뜨림. 기각.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) (이벤트 탭 계층에 KeyTranslator 추가)
- 코드: `VimAction/KeyTranslator.swift`, `VimActionTests/KeyTranslatorTests.swift` (테스트는 QWERTY ASCII 레이아웃 가정 명시)
- 부수: `VimActionTests`가 `VimEngine` 패키지 product에 의존(테스트에서 `Key` 직접 사용), `AppState.bootstrap()`에 XCTest 환경 가드(TEST_HOST 테스트가 라이브 탭을 설치하지 않도록)

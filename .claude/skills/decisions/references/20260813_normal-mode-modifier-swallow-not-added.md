# Normal 모드 modifier 콤보 3택(swallow) 비채택 — 2택 유지 + 토글 도움말

- **결정일**: 2026-08-13

## 결정

Normal 모드의 `Cmd`/`Option` 미매핑 콤보 처리를 "삼킴 / passthrough만 / passthrough+탈출" 3택 정책으로 확장하는 안을 **비채택**한다. 현행 2택(설정 토글 on/off)을 그대로 두고, 발견 가능성 문제는 **설정 UI 도움말 문구로만** 해소한다 — General 탭 Behavior 섹션의 "Exit Normal mode on ⌘/⌥ shortcuts" 토글 아래 보조 설명에 "꺼도 단축키는 앱으로 통과되고 Normal 모드만 유지된다"를 명시한다.

## 배경·근거 (왜)

토글 레이블만 보면 끄는 쪽이 "⌘/⌥ 단축키를 막는다"로 읽힐 수 있다. 실제 동작은 다르다 — 토글 off에서도 미매핑 modifier 콤보는 엔진의 통과 규칙([20260712_unmapped-modifier-passthrough.md](20260712_unmapped-modifier-passthrough.md))에 따라 전부 앱으로 passthrough되고, 달라지는 것은 Insert로 탈출하느냐 Normal에 남느냐뿐이다. `EscapeModifierFixtures`의 "탈출 옵션 꺼진 기본 설정에서 Cmd+Space는 통과하되 Normal 유지"가 이 동작을 핀으로 잡고 있다.

즉 진짜 문제는 정책의 부재가 아니라 **레이블이 유발하는 오해**다. 정책 축을 늘리는 대신 문구로 푸는 것이 맞다:

- **passthrough-only는 이미 존재한다** — 3택 중 가운데 값은 토글 off 상태가 그대로 제공한다. 새 정책 축이 만들어낼 새 동작은 swallow 하나뿐이다.
- **swallow는 UX 위험이 크고 실사용 동기가 없다** — 삼키면 `Cmd+Tab`·`Cmd+Space` 같은 시스템 단축키까지 막힌다. 사용자에게는 설정이 아니라 앱이 고장 난 것으로 읽히고, 이 앱을 쓰는 맥락에서 그걸 원할 이유가 확인되지 않았다.

[20260714_normal-mode-escape-modifiers.md](20260714_normal-mode-escape-modifiers.md)가 기각한 대안 "콤보를 통과시키되 모드는 Normal 유지"는 **기본값**으로서 기각된 것이며, 토글 off라는 선택지로는 계속 유효하다. 그 결정은 뒤집히지 않는다.

## 검토한 대안

- **swallow 정책 추가(3택 확장)**: 위 두 근거로 기각. 설정 스키마·엔진 계약·설정 UI가 전부 넓어지는데 유일한 새 동작(swallow)이 사용자에게 고장으로 읽힌다.
- **토글 레이블 자체를 고쳐 쓰기**: 오해의 원인이 레이블인 것은 맞지만, 한 줄에 "탈출한다/통과는 항상 된다" 두 사실을 다 담으면 레이블이 길어지고 토글 이름으로서 읽히지 않는다. 섹션의 다른 토글들도 보조 설명 한 줄을 짝으로 두는 기존 패턴이라 도움말 쪽이 일관된다.

## 영향 범위

- 갱신한 architecture reference: 없음 — 엔진·설정 스키마·디스패치 어디에도 구조 변경이 없다. 결정의 효과는 설정 UI 문구 한 줄뿐이다.
- 앱: `VimAction/SettingsView.swift` — `GeneralTab`의 Behavior 섹션, 탈출 토글 아래 보조 설명 문장 보강.
- 관련 결정: [20260714_normal-mode-escape-modifiers.md](20260714_normal-mode-escape-modifiers.md) (탈출 옵션 자체), [20260712_unmapped-modifier-passthrough.md](20260712_unmapped-modifier-passthrough.md) (통과 규칙), [20260801_userdefaults-yaml-ownership.md](20260801_userdefaults-yaml-ownership.md) (탈출 옵션이 UserDefaults 소유인 근거).

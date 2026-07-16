# KeyTranslator를 total function으로 — keyDown 외 타입은 내부 가드로 nil

- **결정일**: 2026-07-16

## 결정

`KeyTranslator.translate(_:)`는 첫 줄에서 `event.type == .keyDown`을 확인하고, 그 외 타입은 번역 불가(`nil`)를 반환한다. "keyDown 전용 — 호출측이 보장"이라는 문서 계약을 없애고, 임의의 `CGEvent`에 대해 답이 정의된 total function으로 만든다.

## 배경·근거 (왜)

PR #6 Copilot 리뷰가 "keyDown 전용이 문서에만 있고 강제되지 않는다"를 지적하며 시작된 논의. 처음에는 "타입 필터링은 배선(탭 콜백)의 라우팅 책임"이라는 관점에서 번역기 밖에 두는 방향을 검토했으나:

- 번역기는 "키 데이터 변환 유틸리티"가 아니라 **탭 경계에서 CGEvent 도메인을 엔진 도메인으로 넘기는 어댑터**다. "어떤 CGEvent가 번역 가능한가"는 호출자 단속(precondition)이 아니라 번역기 자신의 도메인 정의이며, 가드는 기존 계약("번역 불가면 nil, 호출측은 무조건 통과")을 이벤트 타입 차원까지 확장하는 것뿐이다.
- 실제 사고 여지가 있었다: 키보드 이벤트가 아닌 CGEvent에서 keycode 필드를 읽으면 0이 나오고, keycode 0은 `kVK_ANSI_A`라 `.char("a")`로 오번역된다. keyUp도 keyDown과 동일하게 번역된다.
- 탭 마스크는 keyDown + flagsChanged 둘 다 등록하므로, 배선 시 flagsChanged가 콜백에 반드시 흘러든다. 콜백의 `switch type`은 라우팅(keyDown → 번역기, flagsChanged → 향후 modifier 탈출 감지)이고 번역기의 가드는 도메인 정의 — 목적이 달라 중복이 아니다.

## 검토한 대안

- **시그니처 축소 `translate(keyCode:flags:)`**: 타입 수준에서 문제를 소멸시키지만, CGEvent 해석 지식(`.keyboardEventKeycode` 필드 등)이 콜백으로 누출되어 어댑터의 캡슐화가 깨진다. 향후 이벤트 필드(`.keyboardEventAutorepeat`, `.keyboardEventKeyboardType`)가 필요해지면 시그니처가 다시 넓어진다. 본체가 TIS/Carbon에 묶여 있어 "순수해진다"는 이득도 실질이 얇다. 기각.
- **호출측(배선) 필터링에만 의존**: 계약이 문서로만 남고, 시그니처(`CGEvent`)가 계약보다 넓은 간극이 유지된다. 기각.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) (KeyTranslator 계약 서술)
- 코드: `VimAction/KeyTranslator.swift` (타입 가드), `VimActionTests/KeyTranslatorTests.swift` (keyUp·flagsChanged → nil 테스트)
- 상위 결정 [20260716_cgevent-key-translation-ascii-layout.md](20260716_cgevent-key-translation-ascii-layout.md)의 번역 방식 자체는 그대로 유효하다 — 이 문서는 "keyDown 전용"의 강제 위치만 구체화한다.

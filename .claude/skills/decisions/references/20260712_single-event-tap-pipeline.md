# 단일 이벤트 탭 파이프라인

- **결정일**: 2026-07-12

## 결정

키 입력은 단일 `CGEventTap`(kCGSessionEventTap)으로만 진입하고, 순수 Swift 모드 엔진이 이를 추상 `VimAction`으로 해석하며, 전략 디스패처가 앱/요소별로 Accessibility 실행과 Keyboard(합성 이벤트) 실행 중 하나를 선택한다.

## 배경·근거 (왜)

- 진입점을 하나로 고정하면 그 아래 전체가 순수 Swift로 유지되어 단위 테스트가 가능하다.
- "동작 해석(엔진)"과 "동작 실행(어댑터)"을 분리하면 `VimAction`을 생성하는 곳은 하나, 소비하는 어댑터는 교체 가능한 둘이 되어 두 전략 모델(AX/Keyboard)을 다루기 쉽다.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md)
- 관련 결정: [20260712_pure-swift-mode-engine.md](20260712_pure-swift-mode-engine.md), [20260712_ax-keyboard-strategy-dispatch.md](20260712_ax-keyboard-strategy-dispatch.md)

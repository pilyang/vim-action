# AX 감지 하드 타임아웃 3ms

- **결정일**: 2026-07-12

## 결정

전략 디스패처의 AX 자동 감지(`strategy: auto`의 AXRole/AXSelectedTextRange/AXValue 탐지)에 **하드 타임아웃 3ms**를 둔다. 타임아웃 시 Keyboard 어댑터(`key-mapping` 계열)로 폴백한다.

## 배경·근거 (왜)

- 응답 없는 AX 호출이 이벤트 탭 전체를 멈추게 하면 안 된다 — 탭이 멈추면 시스템 전역 키 입력이 지연된다.
- 3ms는 초기 추정값이며, 실기기 계측 없이 정한 값이다. 오폴백(정상 앱이 타임아웃으로 Keyboard 전략에 잘못 배정)이 관찰되면 재검토한다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 목록)
- 상위 결정: [20260712_ax-keyboard-strategy-dispatch.md](20260712_ax-keyboard-strategy-dispatch.md)

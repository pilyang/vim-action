# AX/Keyboard 전략 디스패치

- **결정일**: 2026-07-12

## 결정

엔진에서 온 각 `VimAction`은 전략 디스패처가 앱별 프로파일과 AX 자동 감지(하드 타임아웃 — 값은 [별도 결정](20260712_ax-probe-hard-timeout-3ms.md))를 통해 **Accessibility 어댑터** 또는 **Keyboard 어댑터** 중 하나로 라우팅한다. Keyboard 어댑터는 `key-mapping`(요소 인식, 선호 폴백)과 `force-text`(요소 감지 우회, 최후 수단) 두 계열을 가지며, `force-text`는 프로파일에서 명시적으로만 선택하고 자동 감지로는 절대 선택하지 않는다.

## 배경·근거 (왜)

- AX 텍스트 프로토콜을 올바르게 구현하는 앱에서는 AX가 정밀하지만, **너무 많은 앱이 지원한다고 거짓말**하기 때문에 자동 감지와 Keyboard 폴백이 필요하다.
- AX 감지에 하드 타임아웃을 두는 이유: 응답 없는 AX 호출이 이벤트 탭 전체를 멈추게 하면 안 된다. (값 선정은 [20260712_ax-probe-hard-timeout-3ms.md](20260712_ax-probe-hard-timeout-3ms.md))
- `force-text`는 `AXRole`마저 거짓말하는 앱을 위한 것 — 요소 감지를 버리는 비용이 크므로 명시 선택 전용.

## 검토한 대안

- **단일 전략(AX만 또는 Keyboard만)**: AX만으로는 거짓 지원 앱에서 동작 불능, Keyboard만으로는 올바른 AX 앱에서의 정밀성을 포기하게 되어 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 프로파일 스키마의 `strategy` / `keyboard_family` 필드: [20260712_yaml-three-layer-config.md](20260712_yaml-three-layer-config.md)
- 선택 알고리즘 요구사항: 워크스페이스 `docs/prd.md` §9

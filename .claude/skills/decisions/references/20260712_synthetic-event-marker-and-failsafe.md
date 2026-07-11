# 합성 이벤트 마커와 안전장치

- **결정일**: 2026-07-12

## 결정

1. 모든 출력(AX 쓰기, 합성 이벤트 게시)은 **단일 `ActionExecutor`** 를 거친다.
2. 합성한 모든 `CGEvent`에는 게시 전에 비공개 `userData` 마커(`CGEvent.setIntegerValueField(.eventSourceUserData, …)`)를 찍고, 이벤트 탭은 마킹된 이벤트를 재해석 없이 통과시킨다.
3. 안전장치 단축키(기본 `Ctrl-Option-Cmd-Esc`)는 메인 탭과 **별도의 `CGEventTap`** 으로 `kCGHIDEventTap`에 최고 우선순위로 설치한다.

## 배경·근거 (왜)

- Keyboard 전략이 합성한 이벤트는 `CGEventTap`을 거쳐 되돌아온다. **마커를 빠뜨리면 탭이 자기 출력을 재해석해 무한 루프** — 이벤트 탭 기반 도구의 병적 루프의 가장 흔한 원인이다. 게시를 단일 실행기에 집중시키면 이 불변식을 강제하고 감사하기 쉽다.
- 버그 있는 전역 키 탭은 사용자를 키보드에서 완전히 차단할 수 있으므로, 안전장치는 타협 불가.

## 검토한 대안

- **안전장치를 메인 탭 안에서 감지**: 메인 탭이 멈추거나 버그가 나면 킬 스위치도 함께 죽는다. 별도 탭이면 메인 탭을 밖에서 해체할 수 있으므로 기각.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 합성 시퀀스를 만드는 Keyboard 어댑터: [20260712_ax-keyboard-strategy-dispatch.md](20260712_ax-keyboard-strategy-dispatch.md)

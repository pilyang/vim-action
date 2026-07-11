# 순수 Swift 모드 엔진

- **결정일**: 2026-07-12

## 결정

모드 엔진(Insert / Normal / Visual-char / Visual-line 상태 머신)은 macOS 의존성이 전혀 없는 **별도 SPM 타깃의 순수 Swift**로 만든다. 입력은 정규화된 `Key` 값, 출력은 `move(.wordForward)`, `delete(.line)` 같은 추상 `VimAction` 값이다.

## 배경·근거 (왜)

- AppKit/CoreGraphics/AX 의존이 없으면 엔진 전체가 결정론적이고, 실제 앱을 띄우지 않고 픽스처만으로 완전한 단위 테스트가 가능하다.
- 엔진이 실행 방법을 모르면 `VimAction` 생산자는 하나로 고정되고, Accessibility/Keyboard 두 어댑터를 교체 가능한 소비자로 둘 수 있다 — 두 전략 모델을 다루기 쉬운 이유의 핵심.

## 검토한 대안

- **엔진을 앱 타깃 안에 두고 AX/CGEvent를 직접 호출**: 테스트에 실제 앱·권한이 필요해지고, 실행 로직이 엔진에 스며들어 전략 교체가 어려워지므로 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 테스트 전략: 엔진은 픽스처 기반 단위 테스트로 철저히 커버 (워크스페이스 `docs/architecture.md` §7)

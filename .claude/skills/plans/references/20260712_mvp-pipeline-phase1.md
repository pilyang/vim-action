# MVP 파이프라인 1차 — 모드 엔진 + 이벤트 탭 스파이크

- **생성일**: 2026-07-12
- **갱신일**: 2026-07-12

## 목표

순수 Swift 모드 엔진 1차(이동 키셋)가 Swift Testing 픽스처 테스트로 커버된 SPM 패키지로 존재하고, 본 앱이 메뉴바 백그라운드 앱으로서 권한 온보딩을 거쳐 CGEventTap으로 키 입력을 수신·로그하는 것까지 실기기에서 검증된 상태.

**범위 밖** (다음 플랜): 엔진↔탭 연결, 전략 디스패처/AX·Keyboard 어댑터, ActionExecutor, YAML 프로파일 로더.

## 완료된 것

(아직 없음)

## 남은 것

- [ ] **엔진 SPM 패키지 스캐폴드**: 저장소 내 로컬 SPM 패키지 생성(macOS 프레임워크 import 금지 불변식 준수), Swift Testing 테스트 타깃 구성, `Key` / `VimAction` / 이벤트 결정(swallow·passthrough·replace) 타입 계약 정의. 앱 타깃에 패키지 연결.
- [ ] **Normal/Insert 상태 머신 + 이동 키셋**: Esc, i, a / h j k l / w b e / 0 ^ $ / gg G. 픽스처 기반 파라미터라이즈드 테스트로 커버 (키 시퀀스 → 기대 VimAction + 이벤트 결정).
- [ ] **앱 셸 전환**: 템플릿 윈도우 앱을 `LSUIElement` + `NSStatusItem` 메뉴바 백그라운드 앱으로 전환 (설정 창은 뼈대만).
- [ ] **CGEventTap 스파이크 (본 앱 내)**: 접근성·입력 모니터링 권한 온보딩 플로우, kCGSessionEventTap 설치, 수신 키 이벤트 로그로 동작 검증. 이 코드는 폐기하지 않고 제품 코드 위치에 스켈레톤으로 유지·발전시킨다. 검증 중 아키텍처 결정에 영향 주는 발견(탭이 안 되는 조건, 권한 이슈 등)은 decisions로 기록.

## 진행 중 컨텍스트

- 1차 키셋은 이동 최소셋이며 사용자 요청으로 `^` 포함. 편집(x, dd, o/O, u), 카운트(3w), Visual 모드는 다음 마일스톤으로 미룸.
- 스파이크 결과물 처리 방식(일회성 폐기가 아닌 본 앱 스켈레톤)은 2026-07-12 사용자 확인 사항.

## 관련 링크

- architecture: [system-overview.md](../../architecture/references/system-overview.md), [mode-engine.md](../../architecture/references/mode-engine.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [20260712_pure-swift-mode-engine.md](../../decisions/references/20260712_pure-swift-mode-engine.md), [20260712_swift-testing-for-engine-tests.md](../../decisions/references/20260712_swift-testing-for-engine-tests.md), [20260712_single-event-tap-pipeline.md](../../decisions/references/20260712_single-event-tap-pipeline.md)

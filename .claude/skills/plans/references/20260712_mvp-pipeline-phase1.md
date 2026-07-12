# MVP 파이프라인 1차 — 모드 엔진 + 이벤트 탭 스파이크

- **생성일**: 2026-07-12
- **갱신일**: 2026-07-13
- **상태**: ✅ **완료** — 전 항목 통과. 다음 작업 착수 시 정리·삭제 예정이며, 그때까지 직전 완료 기록으로 보존(사용자 지시). 스파이크에서 발견된 탭 자동복구 후속은 별도 플랜 [20260713_tap-reenable-watchdog.md](20260713_tap-reenable-watchdog.md)로 이관됨.

## 목표

순수 Swift 모드 엔진 1차(이동 키셋)가 Swift Testing 픽스처 테스트로 커버된 SPM 패키지로 존재하고, 본 앱이 메뉴바 백그라운드 앱으로서 권한 온보딩을 거쳐 CGEventTap으로 키 입력을 수신·로그하는 것까지 실기기에서 검증된 상태.

**범위 밖** (다음 플랜): 엔진↔탭 연결, 전략 디스패처/AX·Keyboard 어댑터, ActionExecutor, YAML 프로파일 로더.

## 완료된 것

- [x] **엔진 SPM 패키지 스캐폴드**: `Packages/VimActionCore` 단일 패키지에 `VimEngine` + `VimEngineTests` 타깃 생성. `Key`(base+modifiers 구조체) / `VimAction`·`Motion`(뼈대) / `EventDecision`·`EngineOutput` / `Mode` 타입 계약 정의. 워킹 스켈레톤 동작(Esc→Normal, i→Insert, 일반문자 passthrough) + Swift Testing 픽스처 테스트(`KeySequenceFixture` 코드 테이블, 파라미터라이즈드) + no-macOS-import 가드 테스트. 앱 타깃에 패키지 연결·빌드 검증 완료. 관련 결정: [single-core-spm-package](../../decisions/references/20260712_single-core-spm-package.md), [key-representation-and-fixture-format](../../decisions/references/20260712_key-representation-and-fixture-format.md).
- [x] **Normal/Insert 상태 머신 + 이동 키셋**: `Esc, i, a, I, A / h j k l / w b e / 0 ^ $ / gg G` 전부 구현·픽스처 커버 (`I`/`A`는 사용자 요청으로 추가). `gg`용 pending 상태, append 전용 모션 케이스(`charRightForAppend`/`lineEndForAppend`), 미매핑 modifier 조합 passthrough 규칙 포함. 관련 결정: [pending-invalid-sequence-noop](../../decisions/references/20260712_pending-invalid-sequence-noop.md), [unmapped-modifier-passthrough](../../decisions/references/20260712_unmapped-modifier-passthrough.md), [append-dedicated-motion-cases](../../decisions/references/20260712_append-dedicated-motion-cases.md).
- [x] **앱 셸 전환**: 템플릿 윈도우 앱을 `LSUIElement` + SwiftUI `MenuBarExtra`(모드 글리프 label, `AppState.mode`→`menuBarGlyph` 배선) + `Settings` 씬(SettingsView 뼈대)으로 전환. `ContentView` 제거, 링크 검증용 `VimEngine()` 인스턴스 → `AppState` 대체. App Sandbox 해제(`ENABLE_APP_SANDBOX = NO`) 함께 처리. 빌드 성공·앱 background-only 실행·엔진 테스트 통과 검증 완료. 관련 결정: [disable-sandbox-developer-id](../../decisions/references/20260712_disable-sandbox-developer-id.md).

- [x] **CGEventTap 스파이크 구현**: Accessibility 단독 온보딩(Settings 권한 섹션: 상태 표시 + 프롬프트/시스템 설정 딥링크 버튼, 1초 폴링으로 부여 감지 → 재시작 없이 자동 시작) + active tap(`.defaultTap`, kCGSessionEventTap) 설치·무수정 통과·os.Logger 로그(`dev.pilyang.VimAction` 서브시스템). 타임아웃 재활성화, 종료 시 정리, 메뉴바 비활성 글리프(`square.dashed`) 포함. UI 텍스트는 영어(사용자 요청). 새 파일: `Logging.swift`, `AccessibilityPermissionMonitor.swift`, `EventTapController.swift`. 관련 결정: [active-tap-ax-only-onboarding](../../decisions/references/20260712_active-tap-ax-only-onboarding.md), [main-runloop-tap-attachment](../../decisions/references/20260712_main-runloop-tap-attachment.md).
- [x] **스파이크 실기기 검증**: 권한 미허용 "설치 보류" 로그 → 허용 시 1초 내 부여 감지·재시작 없이 탭 설치(14ms) → 타 앱 타이핑 keyDown/flagsChanged 로그 + 입력 정상 통과 → 재실행 시 프롬프트 없이 즉시 설치까지 전부 확인. 타임아웃 재활성화는 `SIGSTOP`으로 유도 시 콜백 유실로 검증 불가(방법론 한계) — 이 과정에서 **탭 자동복구 부재** 발견 → 결정 기록: [tap-reenable-watchdog-polling](../../decisions/references/20260713_tap-reenable-watchdog-polling.md). Quit 정리 로그는 정상 종료 경로(NSApp.terminate)로는 미확인(검증 중 앱 hang으로 Xcode 강제종료).

## 남은 것

- (없음 — 플랜 완료 후보. 사용자 확인 후 정리)

## 주의

- Xcode 로컬 빌드가 **ad-hoc 서명("Sign to Run Locally", 팀 미설정)** 상태 — TCC가 서명 identity 기준이라 리빌드마다 권한이 무효화되고 시스템 설정 체크박스가 켜져 있어도 신뢰 안 되는 상태가 됨. 검증 중 리빌드하면 `tccutil reset Accessibility dev.pilyang.VimAction` 후 재부여 필요. 팀 설정(Apple Development 인증서)하면 해소.
- 셸 전환 시 남긴 후속 힌트: 설정 창 활성화는 `SettingsLink`로 처리했고, 필요 시 `@Environment(\.openSettings)` + `NSApp.activate` 폴백. 템플릿 `VimActionUITests`는 LSUIElement에서 플레이키해질 수 있어 그때 대응하기로 유지 중.

## 진행 중 컨텍스트

- 1차 키셋은 이동 최소셋이며 사용자 요청으로 `^` 포함. 편집(x, dd, o/O, u), 카운트(3w), Visual 모드는 다음 마일스톤으로 미룸.
- 스파이크 결과물 처리 방식(일회성 폐기가 아닌 본 앱 스켈레톤)은 2026-07-12 사용자 확인 사항.

## 관련 링크

- architecture: [system-overview.md](../../architecture/references/system-overview.md), [mode-engine.md](../../architecture/references/mode-engine.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [20260712_pure-swift-mode-engine.md](../../decisions/references/20260712_pure-swift-mode-engine.md), [20260712_swift-testing-for-engine-tests.md](../../decisions/references/20260712_swift-testing-for-engine-tests.md), [20260712_single-event-tap-pipeline.md](../../decisions/references/20260712_single-event-tap-pipeline.md)

# 온스크린 모드 인디케이터 (HUD)

- **생성일**: 2026-09-06
- **갱신일**: 2026-09-06 (PR 1 구현·도그푸딩 완료, PR 오픈)

## 목표

사용자가 메뉴바를 보지 않고도 지금 Normal·Visual 모드인지 화면에서 인지할 수 있게 한다 (PRD §7.7 "선택적 온스크린 모드 인디케이터", 로드맵 Stage 4). 오버레이 인디케이터를 앱에 추가하고 Settings에서 켜고 끌 수 있으면 완료.

## 완료된 것

- [x] 세 가지 표시안(캐럿 근처 / 포커스 요소 근처 / 화면 테두리)과 표시 정책(항시 vs 전환 시) 조사·보고 — 세 안은 배타적이 아니라 **앵커 정밀도 사다리**(캐럿 → 요소 → 창·화면 → 메뉴바)로 묶는 설계를 권장. 권장 조합: 모든 모드 전환 시 캐럿 근처 순간 표시(~1초 페이드) + Normal·Visual 동안 요소 모서리 상시 배지 + Insert는 무표시. 화면 테두리는 선택 스타일.
- [x] 구현 가능성 스파이크 (2026-09-06, 실기기·2디스플레이): AX 기하 가용성 실측 + 비활성화 NSPanel 오버레이 프로토타입 검증. 결과는 아래 "진행 중 컨텍스트".
- [x] **PR 1 구현 완료** (브랜치 `feat/mode-indicator-overlay`, Opus 워커 위임 + 감독 리뷰 + 독립 검증): 비활성화 패널·순수 레이아웃(테스트 10건)·전용 큐 기하 리더·모드 전환 훅. 실기기 도그푸딩(Developer ID Release 설치): TextEdit Esc/i/v, Chrome Esc, Slack Esc 전부 라벨 표시·최전면 불변·보조 디스플레이 정렬 확인. architecture reference [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md) 추가.
- [x] 방향 확정(2026-09-06, 권장안 채택) + decisions 4건 기록: 표시 정책 / 앵커 사다리·이벤트 기반 갱신(실측표 포함) / Chromium 스크린리더 모드 강제 안 함 / 설정은 UserDefaults·기본 on.

## 남은 것

<!-- 다음에 할 것이 맨 위. 인계 단위(세션/마일스톤 수준)로 — 함수 단위 세부 todo는 세션 내 TodoList의 몫. -->

- [ ] PR 1 머지 확인 (CI 3잡 required).
- [ ] **PR 2 — 상시 배지 + 재앵커 + Settings 토글.** Insert 외 모드 동안 요소 오른쪽 위 소형 배지, Insert 진입·사다리 상태 변화(토글 off·disabled 앱·Secure Input·탭 고장)에서 숨김. 재앵커 트리거: 포커스 요소 변경·앱 활성화(리졸버 기존 경로) + 리졸버 `AXObserver`에 `kAXWindowMoved`/`kAXWindowResized` 추가(대상 앱 종료·창 없음이면 숨김). Settings General 탭 토글(`Preferences` 키, 기본 on) — 영속 테스트는 `object(forKey:) != nil` 선행. 검증: 앱 전환 뒤 즉시 새 앱 요소로 붙는지, 창 드래그·리사이즈 추종, disabled 앱에서 사라짐.
- [ ] **PR 3 — 캐럿 정밀도 + 화면 테두리 스타일.** 순간 표시 앵커를 캐럿부터 시작: `AXBoundsForRange (loc,1)` → 문서 끝 `(loc-1,1)` → `AXSelectedTextMarkerRange`+`AXBoundsForTextMarkerRange`, 마커 결과가 요소 rect와 같으면 무효. 스타일 선택(배지 / 화면 테두리 — 포커스 창이 있는 `NSScreen` frame 패널 + 모서리 라벨). 검증: 실측표 앱들(TextEdit·Notes·Safari·Slack·Notion은 캐럿 아래, Chrome·Arc는 요소 모서리 폴백).
- [ ] 마무리: profiles-and-config reference에 UserDefaults 키 반영(PR 2), 로드맵 Stage 4 항목 체크, 플랜 완료 처리.

## 진행 중 컨텍스트

### 실측 — 최전면 앱의 포커스 텍스트 요소에서 읽은 기하 (2026-09-06)

| 앱 (텍스트 엔진) | 요소 rect | 캐럿 `AXBoundsForRange` | 캐럿 텍스트 마커 경로 | 비고 |
|---|---|---|---|---|
| TextEdit, Notes 본문 (AppKit NSTextView) | Y | Y | – | 길이 0 범위는 **한 줄 위** rect를 돌려줌 → `(loc,1)` 우선, 끝이면 `(loc-1,1)`. 줄 첫머리에서 `(loc-1,1)`은 개행 문자라 rect가 이전 줄 끝까지 넓어짐 |
| Safari 주소창 (AppKit NSTextField) | Y | Y | – | 같은 길이 0 quirk |
| Safari 페이지 input·textarea·contenteditable (WebKit) | Y | Y | Y | 길이 0도 정확 |
| Chrome·Arc input·textarea·contenteditable (Chromium 기본 AX 모드) | Y | **N** | **N** | 인라인 텍스트 박스가 로드되지 않아 inner-text 범위 rect가 비어 있음. 앱 요소에 `AXEnhancedUserInterface=true`(VoiceOver가 쓰는 스크린리더 모드)를 넣으면 input·textarea는 `AXBoundsForRange`, contenteditable은 마커 경로로 가능해짐을 확인 — 브라우저 전체를 스크린리더 모드로 바꾸는 부작용이 커서 VimAction이 강제할 일은 아님 |
| Slack 컴포저 (Electron, `AXManualAccessibility` 켠 상태) | Y | N | **Y** (0×18 정확) | contenteditable 루트라 `AXBoundsForRange`는 구조적으로 불가(Chromium `frameForRange`는 텍스트 노드·원자 필드만). 프로버가 이미 켜는 `AXManualAccessibility`가 Electron에선 완전 모드라 마커 경로가 됨 |
| Notion 블록 (Electron) | Y | N | Y | `AXStaticText` 자식에 `AXBoundsForRange`도 됨 |
| Ghostty | Y (표면 전체) | N | N | 터미널은 어차피 비활성 앱 |
| VS Code, Discord | – | – | – | 전환 시점에 에디터·컴포저가 포커스가 아니어서 미측정 |
| 포커스 창 rect (`AXFocusedWindow` 위치·크기, `CGWindowListCopyWindowInfo`) | 전 앱 Y | | | 추가 권한 불필요 |

- 읽기 비용: 요소·선택·캐럿 3변형·마커·창까지 한 번에 2~40ms (첫 접촉 30~45ms) — 50ms 타임아웃 예산 안.
- 마커 경로 edge: Chromium에서 선택이 **내용 끝**에 있으면 `AXBoundsForTextMarkerRange`가 캐럿 대신 요소 전체 rect를 돌려줌 → 결과 rect가 요소 rect와 같으면 "없음"으로 취급.
- 텍스트 마커 경로 = 요소(또는 앱)의 `AXSelectedTextMarkerRange`를 읽어 그대로 `AXBoundsForTextMarkerRange` 파라미터로 넘김. 값은 불투명 CFType, 형 변환 없이 전달.

### 오버레이 프로토타입 — 검증된 것

- `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, `isOpaque=false`·`backgroundColor=.clear`·`hasShadow=false`, `level=.statusBar`, `ignoresMouseEvents=true`, `hidesOnDeactivate=false`, `collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, 표시는 `orderFrontRegardless()`. 앱 7종을 순환하며 200ms 주기로 이동시켜도 **최전면 앱을 한 번도 빼앗지 않음**.
- 좌표 변환: AX(좌상단 원점) → AppKit은 `y' = NSScreen.screens[0].frame.maxY - (y + h)`. 주 디스플레이 왼쪽에 붙은 보조 디스플레이(AX x 음수)에서도 요소 테두리·캐럿 배지가 픽셀 단위로 정렬됨을 스크린샷으로 확인.
- 배지 배치: 캐럿 있으면 캐럿 아래(`caret.maxY + 4`), 없으면 요소 오른쪽 위 바깥, 그것도 없으면 창 오른쪽 위. 이 폴백이 Chrome(캐럿 없음)에서 실제로 작동함.
- 화면 테두리: 포커스 창 rect와 교차하는 `NSScreen`의 frame에 패널 하나 — 구현 난이도 최저.

### 스파이크 도구

- `axprobe.swift` (단일 파일, `swiftc -O`로 빌드): `scan`(실행 중인 모든 앱의 포커스 요소를 활성화 없이 훑기), `fields <bundle>`(창 AX 트리를 걸어 텍스트 요소마다 포커스·캐럿 놓고 측정), `wake <bundle>`, `enhanced <bundle> on|off`, `log [초]`, `overlay [초]`. 위치: 이 세션 scratchpad(`/private/tmp/claude-501/-Users-pilyang-Projects-vim-action-app-VimAction/5a495d1a-662b-4860-8013-80adb0cf37d0/scratchpad/`) — tmp라 사라질 수 있음. 필요하면 `Tools/`로 커밋 검토.
- 주의: 런루프 없는 CLI에선 `NSWorkspace.frontmostApplication`이 갱신되지 않음 → 시스템 와이드 요소의 `AXFocusedApplication`으로 최전면을 판별해야 함. 앱 안에서는 메인 런루프가 있어 문제없음.

### PR 1 도그푸딩에서 본 것 (PR 2·3 참고)

- 텍스트 뷰가 창 전체인 앱(TextEdit)은 "요소 위쪽 바깥" 규칙으로 배지가 타이틀바 자리에 뜬다 — 글자를 안 가려 수용. Chrome은 페이지 로드 직후 앵커가 웹 영역/창으로 잡혀 창 오른쪽 위에 뜸(폴백 정상).
- 라벨은 강조색 배경 + 흰 글씨 — 노란 강조색 사용자의 대비는 PR 2·3에서 확인.
- CLAUDE.md의 Swift 6 프로브(`SWIFT_VERSION=6.0` 오버라이드)가 이제 Yams SPM 체크아웃까지 적용돼 앱 타깃 전에 실패한다(깨끗한 HEAD도 동일). 별도 정리 필요.
- 도그푸딩 도구(scratchpad): `postkey <keycode> [shift]`(HID 탭에 키 게시, 마커 없음), `vawin`(VimAction 소유 온스크린 창 나열 → 오버레이 표시 여부 판정), `dogfood.sh`(설치→앱 순환→키 게시→캡처).

### 구조 제약 (구현 시 지킬 것)

- AX 읽기는 메인·콜백 스레드에서 금지 — 리졸버 `readQueue` 또는 게시 큐에서 읽고 pid만 넘김. 오버레이 갱신은 **이벤트 기반만**(모드 전환·포커스·앱·창 이벤트). 키마다 갱신하는 상시 캐럿 추적은 20260725 결정(메인 런루프 탭 유지)의 재검토 트리거에 해당하므로 하지 않음.
- 오버레이는 `MenuBarIndicator.resolve` 사다리를 재사용해 `.mode`일 때만 표시 (inactive·interceptionOff·appDisabled·secureInput은 숨김). 모드는 전역이라 앱 활성화 시 즉시 재앵커.
- PRD 비기능 요구: 색상만으로 구분하지 않음 → 항상 텍스트 라벨 동반.

## 관련 링크

- architecture: [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md), [app-shell.md](../../architecture/references/app-shell.md), [focus-and-dispatch-reads.md](../../architecture/references/focus-and-dispatch-reads.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions(이 플랜): [20260906_mode-indicator-hybrid-display-policy.md](../../decisions/references/20260906_mode-indicator-hybrid-display-policy.md), [20260906_mode-indicator-anchor-ladder-event-driven.md](../../decisions/references/20260906_mode-indicator-anchor-ladder-event-driven.md), [20260906_no-forced-chromium-screen-reader-mode.md](../../decisions/references/20260906_no-forced-chromium-screen-reader-mode.md), [20260906_mode-indicator-settings-in-userdefaults.md](../../decisions/references/20260906_mode-indicator-settings-in-userdefaults.md)
- decisions(전제): [20260725_tap-main-runloop-retention.md](../../decisions/references/20260725_tap-main-runloop-retention.md), [20260801_userdefaults-yaml-ownership.md](../../decisions/references/20260801_userdefaults-yaml-ownership.md)
- 외부: Chromium `ui/accessibility/platform/browser_accessibility_cocoa.mm`(`frameForRange`), Apple 캐럿 아래 인디케이터(Caps Lock·입력 소스), kindaVim Characters Window

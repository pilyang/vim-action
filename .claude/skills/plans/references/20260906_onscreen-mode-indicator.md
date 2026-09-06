# 온스크린 모드 인디케이터 (HUD)

- **생성일**: 2026-09-06
- **갱신일**: 2026-09-06 (PR 2 구현·도그푸딩 완료, PR #67 오픈, 외양 커스텀 후속 항목 추가)

## 목표

사용자가 메뉴바를 보지 않고도 지금 Normal·Visual 모드인지 화면에서 인지할 수 있게 한다 (PRD §7.7 "선택적 온스크린 모드 인디케이터", 로드맵 Stage 4). 오버레이 인디케이터를 앱에 추가하고 Settings에서 켜고 끌 수 있으면 완료.

## 완료된 것

- [x] 세 가지 표시안(캐럿 근처 / 포커스 요소 근처 / 화면 테두리)과 표시 정책(항시 vs 전환 시) 조사·보고 — 세 안은 배타적이 아니라 **앵커 정밀도 사다리**(캐럿 → 요소 → 창·화면 → 메뉴바)로 묶는 설계를 권장. 권장 조합: 모든 모드 전환 시 캐럿 근처 순간 표시(~1초 페이드) + Normal·Visual 동안 요소 모서리 상시 배지 + Insert는 무표시. 화면 테두리는 선택 스타일.
- [x] 구현 가능성 스파이크 (2026-09-06, 실기기·2디스플레이): AX 기하 가용성 실측 + 비활성화 NSPanel 오버레이 프로토타입 검증. 결과는 아래 "진행 중 컨텍스트".
- [x] **PR 1 머지 완료** ([PR #66](https://github.com/pilyang/vim-action/pull/66) → main `48cbd28`, 2026-09-06; Opus 워커 위임 + 감독 리뷰 + 독립 검증): 비활성화 패널·순수 레이아웃(테스트 10건)·전용 큐 기하 리더·모드 전환 훅. 실기기 도그푸딩(Developer ID Release 설치): TextEdit Esc/i/v, Chrome Esc, Slack Esc 전부 라벨 표시·최전면 불변·보조 디스플레이 정렬 확인. architecture reference [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md) 추가.
- [x] **PR 2 구현 완료** ([PR #67](https://github.com/pilyang/vim-action/pull/67), 브랜치 `feat/mode-indicator-persistent-badge`, Opus 워커 위임 + 감독 리뷰 + 독립 검증): 비-Insert 상시 배지(flash보다 한 단 작고 한 층 아래)·재앵커 트리거 5종(모드 전환 / 포커스·앱 활성화·창 이동·리사이즈 / 디스플레이 재구성 / 사다리 관찰 루프 / 토글)이 단일 reconcile로 합류, 순수 판정 2종(`presentation`·`needsGeometryRead`) 표 테스트, `visibleFrame` 클램프(화면 선택은 `frame`), 강조색 luminance 기반 글씨색, General > Behavior 토글(`onScreenModeIndicatorEnabled`, 기본 on). 실기기 도그푸딩: 창 이동(−900,+262)·리사이즈 추종, Chrome 전환 재앵커, disabled 앱(Terminal)에서 숨김, 복귀 시 재표시, Insert 무배지, VISUAL 배지 — 전부 확인. architecture 4종 갱신(profiles-and-config의 키 반영 포함).
- [x] 방향 확정(2026-09-06, 권장안 채택) + decisions 4건 기록: 표시 정책 / 앵커 사다리·이벤트 기반 갱신(실측표 포함) / Chromium 스크린리더 모드 강제 안 함 / 설정은 UserDefaults·기본 on.

## 남은 것

<!-- 다음에 할 것이 맨 위. 인계 단위(세션/마일스톤 수준)로 — 함수 단위 세부 todo는 세션 내 TodoList의 몫. -->

- [ ] [PR #67](https://github.com/pilyang/vim-action/pull/67) 머지 확인 (CI 3잡 required).
- [ ] **PR 3 — 캐럿 정밀도 + 화면 테두리 스타일.** 순간 표시 앵커를 캐럿부터 시작: `AXBoundsForRange (loc,1)` → 문서 끝 `(loc-1,1)` → `AXSelectedTextMarkerRange`+`AXBoundsForTextMarkerRange`, 마커 결과가 요소 rect와 같으면 무효. 스타일 선택(배지 / 화면 테두리 — 포커스 창이 있는 `NSScreen` frame 패널 + 모서리 라벨). 검증: 실측표 앱들(TextEdit·Notes·Safari·Slack·Notion은 캐럿 아래, Chrome·Arc는 요소 모서리 폴백).
- [ ] **후속 — 인디케이터 외양 커스텀(색상·투명도).** 모드 라벨 알약(flash·배지)의 **색상**과 **투명도**를 사용자가 고를 수 있게 한다. 시점은 PR 3(캐럿 위치 지정) **이후**, 또는 작업 크기가 작으면 PR 3에 **함께**. 이러면서 설정 항목이 늘어나면(on/off·스타일·색상·투명도) 설정 창에 별도 **Visual 탭**을 두는 것도 함께 검토 — 탭 구성은 [20260809_settings-window-three-tabs.md](../../decisions/references/20260809_settings-window-three-tabs.md)의 결정이라 바꾸면 decisions로 기록하고 app-shell reference를 갱신한다. 색상 커스텀에서도 라벨 텍스트는 항상 동반(색만으로 구분하지 않음 — PRD NFR)하고, 글씨색은 PR 2의 luminance 파생을 사용자 색에 그대로 적용한다. 설정 소유권은 UserDefaults([20260906_mode-indicator-settings-in-userdefaults.md](../../decisions/references/20260906_mode-indicator-settings-in-userdefaults.md)).
- [ ] 마무리: 로드맵 Stage 4 항목 체크, 플랜 완료 처리.
- [ ] 후속 검토(별도 PR 후보): **막 실행된 앱의 AXObserver 등록 실패.** 앱을 실행하며 동시에 활성화하면 리졸버의 `AXObserverCreate`/`AddNotification`이 `cannotComplete`(−25204)로 실패하고, 리졸버는 다음 pid 전환까지 재시도하지 않는다(PR 2 도그푸딩에서 TextEdit·Chrome·Terminal 콜드 실행 3건 전부 재현, 다른 앱에 갔다 오면 정상). PR 2 이전부터 있던 동작이지만 배지가 생기며 체감이 커졌다 — 그 앱에서는 앱 전환 전까지 포커스·창 이벤트 재앵커가 없고 모드 전환만 배지를 옮긴다. 후보: 등록 실패 시 짧은 지연 뒤 1회 재시도.

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
- 라벨은 강조색 배경 — 글씨색은 PR 2부터 강조색 luminance로 파생(흰 글씨 대비 3:1 미만이면 검정: 노랑·주황·초록·다크 그래파이트). 실측 대비비는 `ModeIndicatorPanel.textColor(on:)` 주석에.
- CLAUDE.md의 Swift 6 프로브(`SWIFT_VERSION=6.0` 오버라이드)가 이제 Yams SPM 체크아웃까지 적용돼 앱 타깃 전에 실패한다(깨끗한 HEAD도 동일). 별도 정리 필요.
- 도그푸딩 도구(scratchpad): `postkey <keycode> [shift]`(HID 탭에 키 게시, 마커 없음), `vawin`(VimAction 소유 온스크린 창 나열 → 오버레이 표시 여부 판정), `dogfood.sh`(설치→앱 순환→키 게시→캡처). PR 2용 `dogfood3.sh`: 앱을 먼저 띄워 웜 상태로 만들고(콜드 실행은 AX 옵저버 등록 실패) AeroSpace 창을 `aerospace layout floating`으로 풀어 창 이동을 실제로 일으킨다 — 타일링 상태에서는 `set position`이 무시된다.

### 구조 제약 (구현 시 지킬 것)

- AX 읽기는 메인·콜백 스레드에서 금지 — 리졸버 `readQueue` 또는 게시 큐에서 읽고 pid만 넘김. 오버레이 갱신은 **이벤트 기반만**(모드 전환·포커스·앱·창 이벤트). 키마다 갱신하는 상시 캐럿 추적은 20260725 결정(메인 런루프 탭 유지)의 재검토 트리거에 해당하므로 하지 않음.
- 오버레이는 `MenuBarIndicator.resolve` 사다리를 재사용해 `.mode`일 때만 표시 (inactive·interceptionOff·appDisabled·secureInput은 숨김). 모드는 전역이라 앱 활성화 시 즉시 재앵커.
- PRD 비기능 요구: 색상만으로 구분하지 않음 → 항상 텍스트 라벨 동반.

## 관련 링크

- architecture: [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md), [app-shell.md](../../architecture/references/app-shell.md), [focus-and-dispatch-reads.md](../../architecture/references/focus-and-dispatch-reads.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions(이 플랜): [20260906_mode-indicator-hybrid-display-policy.md](../../decisions/references/20260906_mode-indicator-hybrid-display-policy.md), [20260906_mode-indicator-anchor-ladder-event-driven.md](../../decisions/references/20260906_mode-indicator-anchor-ladder-event-driven.md), [20260906_no-forced-chromium-screen-reader-mode.md](../../decisions/references/20260906_no-forced-chromium-screen-reader-mode.md), [20260906_mode-indicator-settings-in-userdefaults.md](../../decisions/references/20260906_mode-indicator-settings-in-userdefaults.md)
- decisions(전제): [20260725_tap-main-runloop-retention.md](../../decisions/references/20260725_tap-main-runloop-retention.md), [20260801_userdefaults-yaml-ownership.md](../../decisions/references/20260801_userdefaults-yaml-ownership.md)
- 외부: Chromium `ui/accessibility/platform/browser_accessibility_cocoa.mm`(`frameForRange`), Apple 캐럿 아래 인디케이터(Caps Lock·입력 소스), kindaVim Characters Window

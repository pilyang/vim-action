# 온스크린 모드 인디케이터 (HUD)

- **생성일**: 2026-09-06
- **갱신일**: 2026-09-16 (색상·투명도 PR 4 착수 — 결정 기록·Opus 워커 위임; 같은 날 이전: PR #68 머지 반영)

## 목표

사용자가 메뉴바를 보지 않고도 지금 Normal·Visual 모드인지 화면에서 인지할 수 있게 한다 (PRD §7.7 "선택적 온스크린 모드 인디케이터", 로드맵 Stage 4). 오버레이 인디케이터를 앱에 추가하고 Settings에서 켜고 끌 수 있으면 완료.

## 완료된 것

- [x] 세 가지 표시안(캐럿 근처 / 포커스 요소 근처 / 화면 테두리)과 표시 정책(항시 vs 전환 시) 조사·보고 — 세 안은 배타적이 아니라 **앵커 정밀도 사다리**(캐럿 → 요소 → 창·화면 → 메뉴바)로 묶는 설계를 권장. 권장 조합: 모든 모드 전환 시 캐럿 근처 순간 표시(~1초 페이드) + Normal·Visual 동안 요소 모서리 상시 배지 + Insert는 무표시. 화면 테두리는 선택 스타일.
- [x] 구현 가능성 스파이크 (2026-09-06, 실기기·2디스플레이): AX 기하 가용성 실측 + 비활성화 NSPanel 오버레이 프로토타입 검증. 결과는 아래 "진행 중 컨텍스트".
- [x] **PR 1 머지 완료** ([PR #66](https://github.com/pilyang/vim-action/pull/66) → main `48cbd28`, 2026-09-06; Opus 워커 위임 + 감독 리뷰 + 독립 검증): 비활성화 패널·순수 레이아웃(테스트 10건)·전용 큐 기하 리더·모드 전환 훅. 실기기 도그푸딩(Developer ID Release 설치): TextEdit Esc/i/v, Chrome Esc, Slack Esc 전부 라벨 표시·최전면 불변·보조 디스플레이 정렬 확인. architecture reference [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md) 추가.
- [x] **PR 2 머지 완료** ([PR #67](https://github.com/pilyang/vim-action/pull/67) → main `4040fe4`, 2026-09-06, 브랜치 `feat/mode-indicator-persistent-badge`, Opus 워커 위임 + 감독 리뷰 + 독립 검증): 비-Insert 상시 배지(flash보다 한 단 작고 한 층 아래)·재앵커 트리거 5종(모드 전환 / 포커스·앱 활성화·창 이동·리사이즈 / 디스플레이 재구성 / 사다리 관찰 루프 / 토글)이 단일 reconcile로 합류, 순수 판정 2종(`presentation`·`needsGeometryRead`) 표 테스트, `visibleFrame` 클램프(화면 선택은 `frame`), 강조색 luminance 기반 글씨색, General > Behavior 토글(`onScreenModeIndicatorEnabled`, 기본 on). 실기기 도그푸딩: 창 이동(−900,+262)·리사이즈 추종, Chrome 전환 재앵커, disabled 앱(Terminal)에서 숨김, 복귀 시 재표시, Insert 무배지, VISUAL 배지 — 전부 확인. architecture 4종 갱신(profiles-and-config의 키 반영 포함).
- [x] **PR 3 구현·도그푸딩 완료** (브랜치 `feat/mode-indicator-caret-and-border`, Fable 워커 위임 + 감독 리뷰 + 독립 검증, [PR #68](https://github.com/pilyang/vim-action/pull/68)): flash 앵커가 캐럿부터(읽기 순서 `(loc,1)` → `(loc-1,1)` → 텍스트 마커, 유효성 규칙은 순수 계층 `isUsableCaret` 한 벌, flash 요청 때만 캐럿 읽기), 상시 표시 스타일 `onScreenModeIndicatorStyle`(배지 / 화면 테두리 — 앵커가 속한 디스플레이의 `visibleFrame` + 오른쪽 위 라벨, General 토글 아래 Picker). 실기기 도그푸딩(Developer ID Release, 2디스플레이): TextEdit·Notes는 `(loc,1)`, Safari 주소창은 `(loc-1,1)`(끝 캐럿이 필드 밖이라 첫 변형 기각), Slack·Notion은 마커 — 전부 flash가 캐럿 바로 아래(±1px); Chrome·Arc는 요소 모서리 폴백; 테두리 스타일은 창이 있는 디스플레이만 두르고 Insert에서 사라짐. architecture 3종 갱신.
- [x] **PR 3 확장 구현 완료** (2026-09-14~15, 도그푸딩 피드백, 같은 브랜치·PR #68에 커밋 3개 `7b92d9d`·`87e7529`·`2d2b738` + 문서 커밋; 이 세션이 직접 구현): ① 자기 pid 경로 토큰 무효화 + 밀린 flash 만료(Copilot 코멘트, `token`을 `private(set)`으로 열어 회귀 테스트) ② 상시 표시 on/off `onScreenModeIndicatorPersistentEnabled`(off면 flash만 — Insert 경로 재사용, "Show" Picker, 스타일 Picker는 상시 표시 없으면 비활성) ③ 상시 스타일 `windowBorder`(포커스 창 rect 테두리 + 창 안쪽 오른쪽 위 라벨, 창 rect는 `includesWindow`로 그 스타일에서만 읽음, 테두리 패널 공유 + `borderPanelStyle`로 창↔화면 전환도 즉시 숨김, 라벨은 화면·창 이중 클램프, `borderLayout` → `screenBorderLayout` 개명). decisions 1건([20260914_mode-indicator-optin-flash-only-and-window-border.md](../../decisions/references/20260914_mode-indicator-optin-flash-only-and-window-border.md)) + architecture 3종 갱신. 스크립트 도그푸딩(Developer ID Release 설치, 2디스플레이): 기본값 회귀(flash+배지), 창 테두리 bounds == TextEdit 창(이동·리사이즈 추종, Slack 전환, 최소화 시 숨김·복원 시 재표시, 보조 디스플레이 x=−2094 정합, 외양 스크린샷 확인), flash-only 두 스타일(flash만·Slack 전환 시 무표시), Insert 숨김 — 전부 수치 확인.
- [x] **Settings 창 Indicator 탭 분리** (2026-09-15, PR #68에 포함): 인디케이터 항목 셋을 General > Behavior에서 새 Indicator 탭(General 바로 뒤)으로 옮기기만 — 키·문구·기본 탭 불변. decisions [20260915_settings-window-indicator-tab.md](../../decisions/references/20260915_settings-window-indicator-tab.md)(08-09 3탭 결정 탭 수만 부분 supersede) + architecture app-shell·mode-indicator-overlay 갱신.
- [x] **PR #68 머지 완료** (→ main `b8765c8`, 2026-09-15): PR 3·확장·Indicator 탭 분리가 한 PR로 머지됐다. 사용자 직접 도그푸딩(Settings UI 경로·Indicator 탭·창 테두리 엣지)이 머지 게이트였고 별도 보고된 결함은 없다.
- [x] 방향 확정(2026-09-06, 권장안 채택) + decisions 4건 기록: 표시 정책 / 앵커 사다리·이벤트 기반 갱신(실측표 포함) / Chromium 스크린리더 모드 강제 안 함 / 설정은 UserDefaults·기본 on.

## 남은 것

<!-- 다음에 할 것이 맨 위. 인계 단위(세션/마일스톤 수준)로 — 함수 단위 세부 todo는 세션 내 TodoList의 몫. -->

- [ ] **진행 중 — PR 4: 인디케이터 모드별 색상·투명도** (2026-09-16 착수, 브랜치 `feat/mode-indicator-colors`, Herdr worktree의 Opus 워커에 위임 — feature-dev + plan mode, 브리프는 감독 세션 scratchpad). 범위는 decisions [20260916_mode-indicator-per-mode-colors.md](../../decisions/references/20260916_mode-indicator-per-mode-colors.md)로 확정: Normal/Visual 두 색(알파 포함)을 UserDefaults `#RRGGBBAA` 키 둘로, 기본 미설정=강조색, INSERT flash는 강조색 유지, Indicator 탭 ColorPicker 둘 + Reset, 색 변경은 AX 재읽기 없이 즉시 재도색. 남은 단계: 워커 플랜 검토·승인 → 구현 → 감독 독립 검증(diff·앱 테스트·경고 0) → 실기기 도그푸딩(수치 판정은 스크립트, Settings UI·외양은 사용자 체크리스트) → PR → 머지. 새 항목은 설정 창의 **Indicator 탭**에 더한다([20260915_settings-window-indicator-tab.md](../../decisions/references/20260915_settings-window-indicator-tab.md)). 색상 커스텀에서도 라벨 텍스트는 항상 동반(색만으로 구분하지 않음 — PRD NFR)하고, 글씨색은 PR 2의 luminance 파생을 사용자 색에 그대로 적용한다. 설정 소유권은 UserDefaults([20260906_mode-indicator-settings-in-userdefaults.md](../../decisions/references/20260906_mode-indicator-settings-in-userdefaults.md)).
- [ ] 마무리: 로드맵 Stage 4 항목 체크, 플랜 완료 처리.
- [ ] 후속 검토(별도 PR 후보): **막 실행된 앱의 AXObserver 등록 실패.** 앱을 실행하며 동시에 활성화하면 리졸버의 `AXObserverCreate`/`AddNotification`이 `cannotComplete`(−25204)로 실패하고, 리졸버는 다음 pid 전환까지 재시도하지 않는다(PR 2 도그푸딩에서 TextEdit·Chrome·Terminal 콜드 실행 3건 전부 재현, 다른 앱에 갔다 오면 정상). PR 2 이전부터 있던 동작이지만 배지가 생기며 체감이 커졌다 — 그 앱에서는 앱 전환 전까지 포커스·창 이벤트 재앵커가 없고 모드 전환만 배지를 옮긴다. 후보: 등록 실패 시 짧은 지연 뒤 1회 재시도.
- [ ] 후속 검토: **디스플레이 간 창 이동 직후 flash 위치 관측 1건(재현 안 됨)** — PR 3 확장 도그푸딩에서 flash가 창 오른쪽 아래(1571,1082)에 한 번 떴다. 재현되면 보고·조사.

## 진행 중 컨텍스트

### 설치 상태 (2026-09-16)

- `/Applications`에는 PR 3 확장 도그푸딩 빌드(1.0 (1), Developer ID Release, 설정은 제품 기본값으로 리셋한 상태)가 있다. 최신 릴리스 v0.4.1에는 인디케이터가 없으므로 되돌릴 이유가 없고, 색상 작업의 도그푸딩 빌드가 이를 교체한다.

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
- 도그푸딩 도구(scratchpad): `postkey <keycode> [shift]`(HID 탭에 키 게시, 마커 없음), `vawin`(VimAction 소유 온스크린 창 나열 → 오버레이 표시 여부 판정), `dogfood.sh`(설치→앱 순환→키 게시→캡처). PR 2용 `dogfood3.sh`: 앱을 먼저 띄워 웜 상태로 만들고(콜드 실행은 AX 옵저버 등록 실패) AeroSpace 창을 `aerospace layout floating`으로 풀어 창 이동을 실제로 일으킨다 — 타일링 상태에서는 `set position`이 무시된다. PR 3용 `dogfood4.sh <app>`: 앱마다 `axprobe fields`로 캐럿을 놓고 Esc 뒤 `vawin`(flash 창 bounds)과 `axprobe sample <bundle>`(캐럿 rect)을 대조해 "flash.x == caret.minX, flash.y == caret.maxY+4"를 수치로 판정, 이어서 `onScreenModeIndicatorStyle`을 `defaults write`로 바꿔 재실행해 테두리 스타일 검증(스타일은 init에서 읽으므로 실행 중 `defaults write`는 무시). `screens`는 디스플레이 frame/visibleFrame을 CG 좌표로 출력. AeroSpace에서는 floating 창도 자기 워크스페이스 모니터에 묶여 스크립트로 다른 디스플레이에 못 옮긴다 — `aerospace move-node-to-monitor --focus-follows-window <dir>`를 쓴다. **PR 3 확장 세션(2026-09-15)에서 도구를 다시 만들었다** — `postkey`·`vawin`(스타일 인자로 소유 앱 지정, CG 좌표·layer·alpha 출력)·`relaunch.sh <style> <persistent>`(설정을 `defaults write`로 바꾸고 재실행) 위치 `/private/tmp/claude-501/-Users-pilyang--herdr-worktrees-VimAction-feat-mode-indicator-caret-and-border/262bc035-2df8-4dcb-8ec5-5eaa4d2fa0f5/scratchpad/`(tmp). 하니스 주의: 한글 입력 소스가 켜져 있으면 Insert 모드에서 `postkey 34`(i)가 "ㅑ"를 타이핑해 캐럿이 옮겨진다. Settings 창은 상태 메뉴의 "Preferences…"로 연다(`System Events`로 `menu bar item 1 of menu bar 2` 클릭 → 메뉴 항목 클릭).

### 구조 제약 (구현 시 지킬 것)

- AX 읽기는 메인·콜백 스레드에서 금지 — 리졸버 `readQueue` 또는 게시 큐에서 읽고 pid만 넘김. 오버레이 갱신은 **이벤트 기반만**(모드 전환·포커스·앱·창 이벤트). 키마다 갱신하는 상시 캐럿 추적은 20260725 결정(메인 런루프 탭 유지)의 재검토 트리거에 해당하므로 하지 않음.
- 오버레이는 `MenuBarIndicator.resolve` 사다리를 재사용해 `.mode`일 때만 표시 (inactive·interceptionOff·appDisabled·secureInput은 숨김). 모드는 전역이라 앱 활성화 시 즉시 재앵커.
- PRD 비기능 요구: 색상만으로 구분하지 않음 → 항상 텍스트 라벨 동반.

## 관련 링크

- architecture: [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md), [app-shell.md](../../architecture/references/app-shell.md), [focus-and-dispatch-reads.md](../../architecture/references/focus-and-dispatch-reads.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions(이 플랜): [20260906_mode-indicator-hybrid-display-policy.md](../../decisions/references/20260906_mode-indicator-hybrid-display-policy.md), [20260906_mode-indicator-anchor-ladder-event-driven.md](../../decisions/references/20260906_mode-indicator-anchor-ladder-event-driven.md), [20260906_no-forced-chromium-screen-reader-mode.md](../../decisions/references/20260906_no-forced-chromium-screen-reader-mode.md), [20260906_mode-indicator-settings-in-userdefaults.md](../../decisions/references/20260906_mode-indicator-settings-in-userdefaults.md)
- decisions(전제): [20260725_tap-main-runloop-retention.md](../../decisions/references/20260725_tap-main-runloop-retention.md), [20260801_userdefaults-yaml-ownership.md](../../decisions/references/20260801_userdefaults-yaml-ownership.md)
- 외부: Chromium `ui/accessibility/platform/browser_accessibility_cocoa.mm`(`frameForRange`), Apple 캐럿 아래 인디케이터(Caps Lock·입력 소스), kindaVim Characters Window

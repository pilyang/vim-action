# 엔진↔탭 연결 + 탭 워치독 (MVP 파이프라인 2차)

- **생성일**: 2026-07-14
- **갱신일**: 2026-07-16

## 목표

엔진의 결정(swallow/passthrough)이 실제 키 이벤트에 적용되는 첫 통합: CGEvent→Key 번역 → `VimEngine.handle` → decision 적용(모드 글리프 실시간 반영)까지 실기기에서 동작하고, 탭이 조용히 죽는 실패 모드에 대한 `CGEventTapIsEnabled()` 폴링 워치독과 안전장치(메뉴바 토글, modifier 콤보 Normal 탈출 옵션)가 들어간 상태.

**범위 밖** (다음 마일스톤): `VimAction` 실행(커서 이동) — 이번엔 로그로만 확인. ActionExecutor·재진입 마커·전략 디스패처·AX/Keyboard 어댑터·YAML 프로파일 로더는 디스패처 마일스톤.

## 완료된 것

- [x] 플랜 수립 + 범위·결정 사용자 확인 (2026-07-14, plan mode 승인)
- [x] **엔진 — Normal 모드 modifier 탈출 옵션** (2026-07-14, 브랜치 `feat/engine-normal-escape-modifiers`): `Configuration { normalModeEscapeModifiers }` 도입 + Normal 규칙 ⑤ 확장 + pending 엣지(아래 컨텍스트 참고) + 픽스처 8건. TDD workflow(RED opus→GREEN sonnet→리뷰 패널)로 수행, 리뷰 findings(헬퍼 추출·픽스처 네이밍) 반영 완료, `swift test` 전체 통과.
- [x] **앱 — CGEvent→Key 번역기** (2026-07-16, PR #6): `VimAction/KeyTranslator.swift` — 특수키 keycode 우선, 문자키는 **UCKeyTranslate + ASCII-capable 레이아웃**(승인안 keyboardGetUnicodeString에서 변경 — 한글 입력 소스에서도 동작, [결정 기록](../../decisions/references/20260716_cgevent-key-translation-ascii-layout.md)), base 추출은 shift만 반영, `nil`=무조건 통과, `@MainActor`(TIS 메인 스레드 요구). 테스트: `VimActionTests`에 VimEngine 의존성 추가(pbxproj) + 픽스처 23건(QWERTY 가정 명시), TDD + 리뷰 에이전트 2종(correctness/silent-failure) findings 반영(UInt16 트랩 방지, 셋업 실패 1회 로그). 부수: `AppState.bootstrap()`에 XCTest 환경 가드(TEST_HOST 테스트의 라이브 탭 설치 방지).

## 남은 것

<!-- 승인된 상세 플랜의 단계 순서 그대로. 각 항목이 인계 가능한 단위. -->

- [ ] **탭↔엔진 배선**: `EventTapController`가 엔진 소유, 콜백에서 decision 적용(`.replace`는 이번엔 삼키고 actions 로그), flagsChanged 항상 통과, `private(set) var mode` 노출 → `AppState.menuBarGlyph` 배선(기존 `AppState.mode` 스켈레톤 정리), 스파이크 `logKeyEvent` TODO 제거.
- [ ] **안전장치 — 메뉴바 토글 + 설정**: `isInterceptionEnabled`(off = 전부 통과 + 엔진 `.insert` 리셋, 탭 포트 유지), 메뉴바 Toggle 항목 + off 글리프. Normal 탈출 옵션은 `@AppStorage` 토글(기본 on, cmd/opt) → 엔진 Configuration 주입.
- [ ] **탭 워치독**: `DispatchSourceTimer` 전용 백그라운드 큐, 주기 2초, desired state(설치됨 + 토글 on)일 때만 `CGEventTapIsEnabled()` 폴링 → 꺼져 있으면 재활성화 + 복구 로그. `stop()`·토글 off 시 게이팅. 콜백 재활성화는 유지(이중 안전망).
- [ ] **검증**: 엔진 `swift test` + 앱 타깃 `xcodebuild test` + 실기기 체크리스트(Insert 통과/Esc 글리프 전환, Normal 삼킴+액션 로그, Cmd-Space 후 Insert 자동 복귀 on/off, 메뉴바 토글, 워치독 복구 — 디버거 pause로 유도, SIGSTOP은 콜백 유실로 부적합).
- [ ] **기록**: decisions 4건(런루프 재검토 결과=메인 유지, modifier 탈출 옵션 — pending 엣지 포함, 토글 의미론+워치독 게이팅, replace-미실행-시-swallow 과도기 규칙 — CGEvent→Key 번역 방식은 2026-07-16 기록 완료) + architecture 갱신(mode-engine/system-overview/reentrancy-and-safety).

## 진행 중 컨텍스트

- **사용자 확정 사항 (2026-07-14)**: ① 범위는 연결만(실행은 로그) ② 메인 런루프 유지(AX가 콜백 경로에 들어오는 디스패처 마일스톤에서 재재검토) ③ 안전장치는 메뉴바 토글 + modifier 콤보(cmd/opt+키) Normal 자동 탈출 옵션(설정 가능, 기본 on). 탈출 옵션의 목적: Spotlight/Raycast/AeroSpace 등이 cmd/opt 단축키를 많이 써서, 단축키 직후 텍스트 입력이 Normal 모드에 막히지 않게 함. ctrl은 향후 Vim 키(Ctrl-d 등)와 충돌 소지로 기본 제외.
- 상세 설계 원본: plan mode 승인본이 `~/.claude/plans/2-virtual-sifakis.md`에 있음 (세션 로컬 — 이 문서가 인계 SSOT이며 핵심은 위에 반영됨).
- **pending 엣지 사용자 확정 (2026-07-14)**: pending(`g`) 상태에서 escape modifier 콤보가 오면 pending 버림 + `.passthrough` + Insert 복귀 (탈출 옵션 취지와 일관 — `g` 직후 Cmd+Space로 Spotlight가 막히지 않게). escape 교집합 없는 키는 기존 resolve 규칙 유지. → decisions 기록은 "기록" 단계에서 modifier 탈출 옵션 결정에 포함.
- 번역기는 PR #6 (`feat/app-key-translator`)으로 제출됨 — 머지 확인 후 "탭↔엔진 배선" 착수 (KeyTranslator는 배선에서 `translate` 호출만 하면 되는 상태).
- 참고: `VimActionUITests.testLaunchPerformance`(Xcode 템플릿 잔재)가 메트릭 수집 flaky로 실패함 — 이번 작업과 무관, 단위 테스트는 `-only-testing:VimActionTests`로 격리 실행.
- 주의(1차 플랜에서 승계): ad-hoc 서명 상태라 리빌드마다 TCC 무효화 — `tccutil reset Accessibility dev.pilyang.VimAction` 후 재부여 필요.

## 관련 링크

- architecture: [system-overview.md](../../architecture/references/system-overview.md), [mode-engine.md](../../architecture/references/mode-engine.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [20260713_tap-reenable-watchdog-polling.md](../../decisions/references/20260713_tap-reenable-watchdog-polling.md), [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md), [20260712_key-representation-and-fixture-format.md](../../decisions/references/20260712_key-representation-and-fixture-format.md)

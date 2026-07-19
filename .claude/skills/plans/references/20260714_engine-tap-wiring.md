# 엔진↔탭 연결 + 탭 워치독 (MVP 파이프라인 2차)

- **생성일**: 2026-07-14
- **갱신일**: 2026-07-19

## 목표

엔진의 결정(swallow/passthrough)이 실제 키 이벤트에 적용되는 첫 통합: CGEvent→Key 번역 → `VimEngine.handle` → decision 적용(모드 글리프 실시간 반영)까지 실기기에서 동작하고, 탭이 조용히 죽는 실패 모드에 대한 `CGEventTapIsEnabled()` 폴링 워치독과 안전장치(메뉴바 토글, modifier 콤보 Normal 탈출 옵션)가 들어간 상태.

**범위 밖** (다음 마일스톤): `VimAction` 실행(커서 이동) — 이번엔 로그로만 확인. ActionExecutor·재진입 마커·전략 디스패처·AX/Keyboard 어댑터·YAML 프로파일 로더는 디스패처 마일스톤.

## 완료된 것

- [x] 플랜 수립 + 범위·결정 사용자 확인 (2026-07-14, plan mode 승인)
- [x] **엔진 — Normal 모드 modifier 탈출 옵션** (2026-07-14, 브랜치 `feat/engine-normal-escape-modifiers`): `Configuration { normalModeEscapeModifiers }` 도입 + Normal 규칙 ⑤ 확장 + pending 엣지(아래 컨텍스트 참고) + 픽스처 8건. TDD workflow(RED opus→GREEN sonnet→리뷰 패널)로 수행, 리뷰 findings(헬퍼 추출·픽스처 네이밍) 반영 완료, `swift test` 전체 통과.
- [x] **앱 — CGEvent→Key 번역기** (2026-07-16, PR #6): `VimAction/KeyTranslator.swift` — 특수키 keycode 우선, 문자키는 **UCKeyTranslate + ASCII-capable 레이아웃**(승인안 keyboardGetUnicodeString에서 변경 — 한글 입력 소스에서도 동작, [결정 기록](../../decisions/references/20260716_cgevent-key-translation-ascii-layout.md)), base 추출은 shift만 반영, `nil`=무조건 통과, `@MainActor`(TIS 메인 스레드 요구). 테스트: `VimActionTests`에 VimEngine 의존성 추가(pbxproj) + 픽스처 23건(QWERTY 가정 명시), TDD + 리뷰 에이전트 2종(correctness/silent-failure) findings 반영(UInt16 트랩 방지, 셋업 실패 1회 로그). 부수: `AppState.bootstrap()`에 XCTest 환경 가드(TEST_HOST 테스트의 라이브 탭 설치 방지). Copilot 리뷰 3건 반영 후 머지 완료 (2026-07-16, squash `24271d9`): keyDown 가드로 total function화([결정 기록](../../decisions/references/20260716_keytranslator-total-function-keydown-guard.md)), QWERTY 의존 문자 픽스처를 레이아웃 판별(`.enabled` trait) 조건부 실행으로 분리, 미사용 import 제거.
- [x] **구체 구현 계획 확정** (2026-07-17) — 아래 "확정 설계". 미결이던 레이아웃 캐싱 사용자 확정(도입) 포함. 병렬 worktree 실행 착수 기준선.
- [x] **플랜 리뷰 반영** (2026-07-17): mode 대입 등가 가드, replace 로그 요약 1건(Plan-2 클램프 상호작용), 토글 on 복귀 선제 tapEnable, 워치독 cancel 경합 근거, 캐시 무효화 옵저버 격리 — 전부 위 확정 설계에 흡수됨.
- [x] **탭↔엔진 배선** (2026-07-17, PR #8 squash 머지 `4c49690`): 확정 설계대로 구현. 테스트 — `EventTapDecisionTests`(키 시퀀스 픽스처, **decision 수준만 검증** — actions 내용은 엔진 테스트 몫, Plan-2 출력 확장과 결합 방지) + 캐싱 적재→무효화→재조회 + QWERTY 판별 헬퍼 공용 추출. 앱 33건·엔진 9건 그린. 리뷰 에이전트 2종: correctness 클린, silent-failure findings 3건 반영 — ① 분산 노티 selector 기반 `.deliverImmediately` 등록(LSUIElement는 사실상 항상 비활성이라 기본 coalesce는 배달 유예 → 캐시 낡음) ② `kTISNotifyEnabledKeyboardInputSourcesChanged` 추가 관찰(무효화 축 정합) ③ `UCKeyTranslate` 실패 시 캐시 폐기(자가 치유). **실기기 GREEN 6항목 전부 확인**(사용자 동반 — hjkl/gg replace 로그·swallow·캐시 무효화 후 번역·Cmd+Space 탈출·글리프 전환, fault·탭 비활성 0건). Copilot 리뷰 1건 반영(노티 콜백 assumeIsolated → `Task { @MainActor }` 홉 — 배달 스레드 문서 보장 없음).
- [x] **안전장치 — 메뉴바 토글 + 설정** (2026-07-19, PR #10 머지 `684925f`): "안전장치" 확정 설계대로 구현 — 가로채기 토글(off=tapEnable(false)+재활성화 게이트+엔진 리셋+워치독 정지, on=tapEnable 선제) + Normal 탈출 옵션(컨트롤러 소유 통일, didSet에서 Configuration 재생성 주입) + off/부팅 글리프(`square.slash`). 코드리뷰 다수 반영(아래 진행 중 컨텍스트의 PR #10 항목들 — status/탭 상태 정합, `enableTapAndVerify`/`eventTapStatusText` 수렴, persisted-off 설치 게이트, off→on 수동 복구). **실기기 GREEN 확인**(2026-07-19, 사용자 — 토글 off 키 통과+`square.slash`·on 복귀 Insert 재시작·탈출 옵션 on/off·persisted-off 부팅). ⚠️ 검증 착수 시 ad-hoc 리빌드로 cdhash 변경 → 시스템 설정 체크박스가 켜져 보여도 낡은 항목이라 `AXIsProcessTrusted()` false(→`square.dashed`), `tccutil reset Accessibility dev.pilyang.VimAction` 후 현재 빌드 재부여로 해소(폴링이 재시작 없이 감지).

## 확정 설계 (구현 착수 기준선)

> 남은 항목을 병렬 실행자가 재량 판단 없이 착수할 수 있도록 인터페이스·판단 기준을 못 박는다. 구현 중 문제가 드러나면 조정하되, 동작 확인된 형태는 "기록" 단계에서 decisions에 확정 기록한다 (그 전까지는 제안 상태).

### 배선 — 소유 구조와 콜백 결정 매핑

```swift
// EventTapController (@MainActor @Observable — 기존 유지)
@ObservationIgnored private var engine: VimEngine   // 엔진 소유 — UI 관찰 대상 아님
private(set) var mode: Mode = .insert               // handle 후 engine.mode 복사 — 메뉴바가 관찰
```

- 배선 단계의 Configuration은 **하드코딩 기본값** `Configuration(normalModeEscapeModifiers: [.command, .option])` (제품 기본 on). 안전장치 단계에서 설정 주입으로 교체.
- 콜백 `.keyDown` 경로 (순서 고정, 실제 mutating 접근은 controller 메서드로 감쌈):

```swift
guard let key = KeyTranslator.translate(event) else { return passthrough }  // nil = 무조건 통과 (번역기 계약)
let output = engine.handle(key)
if mode != engine.mode { mode = engine.mode }  // 등가 가드 필수 — @Observable은 등가 비교 없이 대입만으로 발화하므로, 무조건 대입이면 Insert 타이핑 내내 매 keyDown마다 메뉴바 SwiftUI 무효화가 콜백 경로에서 돈다
switch output.decision {
case .passthrough: return Unmanaged.passUnretained(event)
case .swallow:     return nil
case .replace:     // 과도기 규칙: 실행 없이 삼키고 actions 로그만 → "기록" 단계에서 결정 기록
    log("replace ×\(output.actions.count): \(String(describing: output.actions.first))")  // 요약 1건 — actions forEach 로그 금지 (Plan-2 카운트 클램프로 actions가 최대 9,999개 — 콜백 내 os_log 수천 건은 탭 타임아웃을 유발해 워치독 실기기 검증을 오염시킨다)
    return nil
}
```

- **`.replace` 로그는 `switch` case 분기 없이 `String(describing:)`으로** — Plan-2(멀티키 커맨드 빌더)가 병렬 worktree에서 `VimAction`에 `.edit` 케이스를 추가 중이라, default 없는 exhaustive switch는 머지 시 충돌 마커 없이 빌드만 깨진다. (`switch`가 꼭 필요하면 `default:` 하나로 흡수.)
- `flagsChanged`는 엔진에 넣지 않고 콜백에서 **항상 통과** (모디파이어는 keyDown의 flags로 이미 엔진에 전달됨).
- `AppState.mode` 정적 스켈레톤 제거 — `menuBarGlyph`/`menuBarAccessibilityLabel`이 `eventTap.mode`를 읽도록 변경. 스파이크 `logKeyEvent`(keycode 로그) 제거, DEBUG 전용 decision 로그로 대체.

### KeyTranslator 레이아웃 캐싱 (사용자 확정 2026-07-17: 도입)

- 레이아웃 `Data`를 static lazy 캐시하고, `kTISNotifySelectedKeyboardInputSourceChanged` 분산 노티피케이션(`DistributedNotificationCenter`)으로 무효화(캐시 클리어 → 다음 키에서 재조회). 옵저버 등록은 최초 translate 시 1회 (`@MainActor`라 경합 없음). 옵저버 콜백은 **main queue 지정 + `MainActor.assumeIsolated`로 캐시 클리어** — 캐시가 `@MainActor` static이라 큐 미지정 콜백에서 직접 접근하면 격리 위반. 캐시 후 키당 비용은 nil 체크뿐.
- 단위 테스트: 무효화 → 재조회 경로 (노티 게시 시뮬레이트가 안 되면 내부 무효화 메서드 직접 호출로 검증).

### 안전장치 — 토글·설정 의미론 (2026-07-18 코드리뷰로 개정)

- `isInterceptionEnabled`는 `EventTapController` 소유(관찰 프로퍼티) + UserDefaults 영속(init 로드, didSet 저장 — `@Observable` 클래스엔 `@AppStorage` 불가). **off = `tapEnable(false)`로 스트림 해방(포트는 유지) + 콜백 최상단 전부 통과 가드(이중 방어) + 엔진 `.insert` 리셋(재생성) + 워치독 정지.**
- **off 중에는 아무도 탭을 되살리지 않는다** — 콜백 `tapDisabledBy*` 재활성화도 `isInterceptionEnabled` 게이트. (개정 근거: 비활성화 없이 통과만 하면 모든 키가 여전히 메인 스레드 콜백을 왕복해, 앱 오동작 시 끄는 안전장치 목적을 못 지킴 — 초안의 "off 중 재활성화 유지(무해한 이중 안전망)" 전제가 틀렸음을 코드리뷰가 확인.)
- **on 복귀 시 `tapEnable(true)` 1회 선제 호출** — off가 탭을 비활성화하므로 이것이 유일한 복귀 경로다 (워치독 첫 폴링을 기다리지 않음).
- 메뉴바 Toggle 항목 + off 전용 글리프 (기존 "square.dashed"는 탭 비활성 표시 — off와 구분되는 심볼 선택은 구현 재량).
- Normal 탈출 옵션: **가로채기 토글과 같은 소유 모델로 통일 (2026-07-18 개정 — 초안의 `@AppStorage`+`onChange` 이원화는 "writer가 updateConfiguration을 빼먹으면 엔진이 낡는" 함정)** — `isNormalModeEscapeEnabled` 컨트롤러 프로퍼티(관찰, init 로드) + didSet(defaults 저장 + on=`[.command, .option]` / off=`[]` Configuration 번역 후 엔진 **재생성 주입**). SettingsView는 이 프로퍼티에 바인딩. `updateConfiguration`은 private (didSet 전용 — 우회 주입 차단). 설정 변경 시 모드가 insert로 리셋되는데, 설정 조작 중이므로 수용 (판단 근거 포함해 "기록" 단계에 기재).

### 워치독 — 스레딩 규칙 (핵심 불변식)

- `DispatchSourceTimer`, 전용 백그라운드 큐(`.utility`), 주기 2초.
- **폴링·재활성화는 백그라운드 큐에서 `CGEventTapIsEnabled`/`tapEnable`을 직접 호출 — MainActor 홉 금지.** 메인 스레드 스톨 복구가 워치독의 존재 이유라([결정 문서](../../decisions/references/20260713_tap-reenable-watchdog-polling.md)), 메인 홉을 넣으면 정확히 그 실패 모드에서 무력화된다. `CFMachPort`는 스레드 안전 C API 대상이므로 `nonisolated(unsafe)`로 캡처.
- 게이팅: 탭 설치됨 && 토글 on일 때만 타이머 가동. `stop()`·토글 off에서 cancel. 복구 시 로그 1건. 콜백 재활성화는 유지(이중 안전망).
- **cancel 경합 수용 근거**: `DispatchSourceTimer.cancel()`은 in-flight 핸들러 완료를 기다리지 않는다 — `stop()`이 메인에서 포트를 invalidate하는 순간 백그라운드 핸들러가 `tapEnable`/`IsEnabled`를 호출 중일 수 있다. 핸들러가 포트를 **강캡처**하므로 메모리는 안전하고, invalidated 포트 호출은 무해한 no-op이라 이 경합은 수용한다. **약참조·매 폴링 재조회로 짜지 말 것** — 그게 오히려 nil 경합·격리 위반을 만든다.

## 남은 것

<!-- 승인된 단계 순서 그대로. 각 항목이 인계 가능한 단위 — 상세는 위 "확정 설계" 참조. -->

- [ ] **탭 워치독**: 코드·단위 테스트·리뷰(클린)·**실기기 GREEN 전부 완료 (2026-07-19, 브랜치 `feat/app-tap-watchdog`)** — 커밋/PR만 남음. GREEN 실측(사용자 동반, SIGSTOP/SIGCONT — 콜백 유실 확인돼 워치독 단독 검증으로 성립): ① SIGCONT 후 **1초 이내** "워치독 — 비활성 탭 복구"(bg 스레드 ID로 백그라운드 실행 입증), "시스템이 탭 비활성화" 로그 0건 = 콜백 유실 상황에서 워치독이 유일 복구 경로였음 ② 복구 후 가로채기 재개(swallow/replace 로그 + Normal/Insert 전환) ③ 토글 off 5.5초 동안 복구 로그 0건·키 통과(워치독 미복구), on 복귀 즉시 재활성화. `.failed` 자가 교정은 실기기 유도 곤란으로 스킵(선택 항목 — 매 폴링 홉 구조가 커버, 리뷰로 확인).
- [ ] **최종 검증**: 엔진 `swift test` + `xcodebuild test -only-testing:VimActionTests` + 위 항목별 실기기 GREEN 체크리스트 통합 재점검.
- [ ] **기록**: decisions 5건(런루프 재검토 결과=메인 유지, modifier 탈출 옵션 — pending 엣지 포함, 토글 의미론+워치독 게이팅 — **2026-07-18 개정 포함: off=tapEnable(false)+재활성화 게이트, 탈출 옵션 소유 모델 컨트롤러 통일**, replace-미실행-시-swallow 과도기 규칙 — **릴리스 무로그 삼킴 수용 조건 포함: 디스패처 마일스톤 전 릴리스 배포 금지 (silent-failure 리뷰 advisory)**, KeyTranslator 레이아웃 캐싱+무효화 — deliverImmediately·enabled 노티·실패 시 폐기 포함, CGEvent→Key 번역 방식은 2026-07-16 기록 완료) + architecture 갱신(mode-engine/system-overview/reentrancy-and-safety).

## 진행 중 컨텍스트

- **사용자 확정 사항 (2026-07-14)**: ① 범위는 연결만(실행은 로그) ② 메인 런루프 유지(AX가 콜백 경로에 들어오는 디스패처 마일스톤에서 재재검토) ③ 안전장치는 메뉴바 토글 + modifier 콤보(cmd/opt+키) Normal 자동 탈출 옵션(설정 가능, 기본 on). 탈출 옵션의 목적: Spotlight/Raycast/AeroSpace 등이 cmd/opt 단축키를 많이 써서, 단축키 직후 텍스트 입력이 Normal 모드에 막히지 않게 함. ctrl은 향후 Vim 키(Ctrl-d 등)와 충돌 소지로 기본 제외.
- 상세 설계 원본: plan mode 승인본이 `~/.claude/plans/2-virtual-sifakis.md`에 있음 (세션 로컬 — 이 문서가 인계 SSOT이며 핵심은 위에 반영됨).
- **pending 엣지 사용자 확정 (2026-07-14)**: pending(`g`) 상태에서 escape modifier 콤보가 오면 pending 버림 + `.passthrough` + Insert 복귀 (탈출 옵션 취지와 일관 — `g` 직후 Cmd+Space로 Spotlight가 막히지 않게). escape 교집합 없는 키는 기존 resolve 규칙 유지. → decisions 기록은 "기록" 단계에서 modifier 탈출 옵션 결정에 포함.
- **사용자 확정 사항 (2026-07-17)**: KeyTranslator 레이아웃 캐싱 **도입** (PR #6 리뷰 후속으로 "배선 전 결정"이던 건 — 배선 항목에 포함, 위 확정 설계 참고).
- 번역기 PR #6 머지 완료 (2026-07-16) — "탭↔엔진 배선" 착수 가능 (KeyTranslator는 배선에서 `translate` 호출만 하면 되는 상태).
- **워치독 구현·실기기 GREEN 완료 (2026-07-19, 브랜치 `feat/app-tap-watchdog` 미커밋 작업트리 — 커밋/PR 대기)**: `EventTapController.swift`에 인라인 구현(별도 타입 없음 — startWatchdog/stopWatchdog/applyWatchdogResult + didSet on/off·startIfPermitted·stop() 훅) + `TapWatchdogTests.swift` 2건(off 가드·포트 nil 늦은 홉). 앱 테스트 전체·엔진 27건 그린, 리뷰 에이전트(correctness/concurrency) 클린. 확정 설계 대비 **플랜 셀프 리뷰로 사용자 확정한 조정 4건** — "기록" 단계의 워치독 decisions에 포함할 것: ① 핸들러가 관측 liveness를 **매 폴링** fire-and-forget 홉(비활성 시에만 홉하면 낡은 `.failed` 래치를 못 고침 — 등가 가드가 과발화 흡수) ② 토글 off 경합은 `applyWatchdogResult`의 off 가드가 tapEnable(false)로 자가 치유(off 경로는 포트를 invalidate하지 않아 "invalidated no-op" 근거가 안 통함) ③ 실패 로그는 메인 전이당 1건·복구 성공 로그만 bg 직접(스팸 방지 vs 스톨 중 관측성) ④ GREEN 방법론 교정 — 디버거 pause는 콜백 유실 시 워치독 단독 검증에 유리, 선점 시 lldb 직접 비활성으로 재검증. 상세 계획: `~/.claude/plans/linear-knitting-kahan.md` (세션 로컬).
- **현재 기준선 (2026-07-19, PR #10 머지 `684925f` + 실기기 GREEN)**: 배선·안전장치 완료 — 다음은 "남은 것" 맨 위 **탭 워치독**부터 (확정 설계의 "워치독 — 스레딩 규칙" 참조). PR #10에서 `enableTapAndVerify(reason:)` @MainActor 헬퍼로 메인측 status 전이 규칙이 이미 수렴돼 있으니, 워치독은 그 상태 전이의 4번째 소비자로서 **bg poke만 별도 구현**(백그라운드 큐 직접 호출·메인 홉 금지, status 반영만 `Task { @MainActor }`)하고 finding 5(일시적 실패 자동 재확인)를 연속 폴링으로 해소한다. Debug 빌드가 실기기에서 실행 중일 수 있음(`build/Build/Products/Debug/`).
- **안전장치 브랜치 코드리뷰 반영 (2026-07-18, `feat/app-safety-toggle`, 워크플로 high)**: 구현 커밋 `4b9ab2f`에 대한 리뷰 findings 반영 완료 — ① off 의미론 강화(tapEnable(false)+재활성화 게이트) ② 탈출 옵션 소유 모델 통일(확정 설계에 개정 반영) ③ ON 복귀 tapEnable 실패 시 `status = .failed` 전이(UI 거짓 표시 제거 — 성공 시 .running 복원, 자동 복구·상태 일원화는 워치독 몫) ④ `withTemporaryDefaults` 지원 파일 분리 ⑤ 토글 바인딩 @Bindable 전환. **워치독 PR로 이관된 후속** (일부 2026-07-19 코드리뷰 반영으로 선반영됨 — 아래 참고): tapEnable+검증+로그 3중복(didSet/reenableAfterDisable/startIfPermitted)은 `enableTapAndVerify(reason:)` 헬퍼로 이미 수렴됨(커밋 `9568f2a`). **단, 이 헬퍼는 @MainActor라 워치독이 그대로 재사용 못 함** — 워치독은 백그라운드 큐에서 `tapEnable`/`tapIsEnabled`를 직접 호출하고(메인 홉 금지 불변식) status 반영만 `Task { @MainActor }`로 홉해야 한다. 즉 "공유 헬퍼로 수렴"은 메인측 status 전이 규칙(.running=설치 정상 / .failed=검증 실패)만 공유하고 bg poke는 별도 구현. 워치독이 이 상태 전이의 4번째 소비자가 되며, finding 5(일시적 실패의 자동 재확인)를 연속 폴링으로 구조적 해소한다(워치독 GREEN 항목에 포함). 단위 테스트 불가 지점(off 분기 tapEnable(false), ON/설치/재활성화 실패 status 전이 — TEST_HOST 포트 nil)은 실기기 GREEN 체크리스트에서 확인.
- **PR #10 Copilot 리뷰 반영 (2026-07-19, 커밋 `e21b399`)**: `startIfPermitted()`가 `isInterceptionEnabled`와 무관하게 무조건 `tapEnable(true)` → **설치 시점 enable을 토글 상태로 게이트**(`tapEnable(tap: port, enable: isInterceptionEnabled)`). persisted-off 부팅/지연 권한 부여 시 off인데 탭이 살아 키가 메인 스레드 콜백을 왕복하던 갭(handleKeyDown 가드로 기능은 정상이나 off 안전장치의 스트림 해방 의미론이 부팅 시점에 깨짐)을 막음. didSet off 분기와 동일 규칙(포트 유지·탭 비활성). 순수 버그 수정이라 신규 decision 없음. **이 경로도 TEST_HOST 포트 nil이라 단위 테스트 불가** — 위 "단위 테스트 불가 지점"에 합류, persisted-off 재시작 → 글리프 square.slash + 키 통과로 실기기 GREEN에서 확인. Copilot 스레드에 resolve 답글 완료.
- **PR #10 워크플로 코드리뷰 반영 (2026-07-19, high, 커밋 `ab81543`·`9568f2a`·`6c72e15`)**: 검증 통과 findings 5건 — status와 실제 탭 상태 불일치 계열. ① [CONFIRMED] tapCreate 실패(.failed) 후 off→on이 문서상 수동 복구 경로인데 didSet on 분기 `tapPort==nil` else절이 로그만 남기고 실제 복구 안 함 → `startIfPermitted()` 재시도 추가(`ab81543`). 부수: bootstrap의 XCTest 가드를 `isRunningUnderXCTest()` 공용 헬퍼(신규 `TestEnvironment.swift`)로 추출해 `startIfPermitted` 최상단에도 적용(off→on 테스트가 라이브 탭 설치하는 것 방지). ② [PLAUSIBLE×3] startIfPermitted/reenableAfterDisable/didSet-on 세 곳이 `tapEnable` 후 `tapIsEnabled` 검증 없이 `.running` 유지 → **`enableTapAndVerify(reason:)` @MainActor 헬퍼로 수렴**(`9568f2a`, 아래 워치독 이관 항목의 선반영). `.running` 의미를 "탭 설치·헬스 정상"으로 정리, persisted-off 설치는 `tapEnable(false)`+`.running`. ③ [CONFIRMED] 토글 off인데 Settings "Event Tap" 행이 "Running" 표시 → `eventTapStatusText(status:interceptionEnabled:)` 순수 함수로 파생(off→"Disabled"), 전 분기 단위 테스트(`6c72e15`). **finding 5(일시적 enable 실패의 영구 .failed 래치, 자동 재확인 없음)는 워치독으로 이관** — 이번 PR은 정직한 상태 전이 + off→on 수동 복구까지만. 순수 버그 수정이라 신규 decision 없음. 헬퍼 3지점은 TEST_HOST 포트 nil이라 단위 테스트 불가 — 실기기 GREEN(persisted-off 부팅 시 Settings "Disabled"·글리프 square.slash·키 통과)에서 확인.
- **실행 방식**: Plan-2(멀티키 커맨드 빌더)와 worktree 병렬 가능(이 플랜=앱 타깃 `VimAction/*.swift`, Plan-2=엔진 타깃 `Packages/VimActionCore/*` — 파일 교집합 없음). 단 이 플랜은 각 항목 GREEN에 **실기기 검증이 포함**되어 완전 자율 실행은 불가 — 코드·단위 테스트까지 에이전트가 진행하고 실기기 체크는 사용자와 함께 확인.
- **실기기 검증 주의**: 배선 항목 GREEN 시점엔 안전장치(토글)가 **아직 없다** — 단계 순서가 배선 → 안전장치라서. 비상 탈출 수단은 하드코딩 cmd/opt 탈출 콤보와 메뉴바 Quit뿐이므로, 검증 세션 시작 전 Quit 경로 동작을 먼저 확인하고 들어간다 (TCC 리셋 이슈와 겹치면 당황스러움).
- 참고: `VimActionUITests.testLaunchPerformance`(Xcode 템플릿 잔재)가 메트릭 수집 flaky로 실패함 — 이번 작업과 무관, 단위 테스트는 `-only-testing:VimActionTests`로 격리 실행.
- 주의(1차 플랜에서 승계): ad-hoc 서명 상태라 리빌드마다 TCC 무효화 — `tccutil reset Accessibility dev.pilyang.VimAction` 후 재부여 필요.

## 관련 링크

- architecture: [system-overview.md](../../architecture/references/system-overview.md), [mode-engine.md](../../architecture/references/mode-engine.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [20260713_tap-reenable-watchdog-polling.md](../../decisions/references/20260713_tap-reenable-watchdog-polling.md), [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md), [20260712_key-representation-and-fixture-format.md](../../decisions/references/20260712_key-representation-and-fixture-format.md)

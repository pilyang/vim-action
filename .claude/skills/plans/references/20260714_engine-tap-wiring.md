# 엔진↔탭 연결 + 탭 워치독 (MVP 파이프라인 2차)

- **생성일**: 2026-07-14
- **갱신일**: 2026-07-14

## 목표

엔진의 결정(swallow/passthrough)이 실제 키 이벤트에 적용되는 첫 통합: CGEvent→Key 번역 → `VimEngine.handle` → decision 적용(모드 글리프 실시간 반영)까지 실기기에서 동작하고, 탭이 조용히 죽는 실패 모드에 대한 `CGEventTapIsEnabled()` 폴링 워치독과 안전장치(메뉴바 토글, modifier 콤보 Normal 탈출 옵션)가 들어간 상태.

**범위 밖** (다음 마일스톤): `VimAction` 실행(커서 이동) — 이번엔 로그로만 확인. ActionExecutor·재진입 마커·전략 디스패처·AX/Keyboard 어댑터·YAML 프로파일 로더는 디스패처 마일스톤.

## 완료된 것

- [x] 플랜 수립 + 범위·결정 사용자 확인 (2026-07-14, plan mode 승인)

## 남은 것

<!-- 승인된 상세 플랜의 단계 순서 그대로. 각 항목이 인계 가능한 단위. -->

- [ ] **엔진 — Normal 모드 modifier 탈출 옵션**: `VimEngine`에 `Configuration { normalModeEscapeModifiers: Set<Key.Modifier> = [] }` 도입(빈 셋 = 기존 동작, 기존 픽스처 무수정 통과). Normal 규칙 ⑤ 확장: 콤보 modifiers가 escape 셋과 교집합이면 `.passthrough` + `mode = .insert`. 픽스처 테스트 추가(on/off × cmd/opt/ctrl × Insert 복귀).
- [ ] **앱 — CGEvent→Key 번역기** (신규 `VimAction/KeyTranslator.swift`): keyDown 전용, 특수키 keycode(Esc=53/Return=36/Tab=48/Space=49), 문자키 `keyboardGetUnicodeString`(shift 문자 흡수), modifiers는 cmd/opt/ctrl만. 정규화 불가(ctrl 제어문자 등)는 `nil` → 무조건 통과. 앱 타깃 단위 테스트(합성 CGEvent) 신규.
- [ ] **탭↔엔진 배선**: `EventTapController`가 엔진 소유, 콜백에서 decision 적용(`.replace`는 이번엔 삼키고 actions 로그), flagsChanged 항상 통과, `private(set) var mode` 노출 → `AppState.menuBarGlyph` 배선(기존 `AppState.mode` 스켈레톤 정리), 스파이크 `logKeyEvent` TODO 제거.
- [ ] **안전장치 — 메뉴바 토글 + 설정**: `isInterceptionEnabled`(off = 전부 통과 + 엔진 `.insert` 리셋, 탭 포트 유지), 메뉴바 Toggle 항목 + off 글리프. Normal 탈출 옵션은 `@AppStorage` 토글(기본 on, cmd/opt) → 엔진 Configuration 주입.
- [ ] **탭 워치독**: `DispatchSourceTimer` 전용 백그라운드 큐, 주기 2초, desired state(설치됨 + 토글 on)일 때만 `CGEventTapIsEnabled()` 폴링 → 꺼져 있으면 재활성화 + 복구 로그. `stop()`·토글 off 시 게이팅. 콜백 재활성화는 유지(이중 안전망).
- [ ] **검증**: 엔진 `swift test` + 앱 타깃 `xcodebuild test` + 실기기 체크리스트(Insert 통과/Esc 글리프 전환, Normal 삼킴+액션 로그, Cmd-Space 후 Insert 자동 복귀 on/off, 메뉴바 토글, 워치독 복구 — 디버거 pause로 유도, SIGSTOP은 콜백 유실로 부적합).
- [ ] **기록**: decisions 5건(런루프 재검토 결과=메인 유지, modifier 탈출 옵션, 토글 의미론+워치독 게이팅, CGEvent→Key 번역 방식, replace-미실행-시-swallow 과도기 규칙) + architecture 갱신(mode-engine/system-overview/reentrancy-and-safety).

## 진행 중 컨텍스트

- **사용자 확정 사항 (2026-07-14)**: ① 범위는 연결만(실행은 로그) ② 메인 런루프 유지(AX가 콜백 경로에 들어오는 디스패처 마일스톤에서 재재검토) ③ 안전장치는 메뉴바 토글 + modifier 콤보(cmd/opt+키) Normal 자동 탈출 옵션(설정 가능, 기본 on). 탈출 옵션의 목적: Spotlight/Raycast/AeroSpace 등이 cmd/opt 단축키를 많이 써서, 단축키 직후 텍스트 입력이 Normal 모드에 막히지 않게 함. ctrl은 향후 Vim 키(Ctrl-d 등)와 충돌 소지로 기본 제외.
- 상세 설계 원본: plan mode 승인본이 `~/.claude/plans/2-virtual-sifakis.md`에 있음 (세션 로컬 — 이 문서가 인계 SSOT이며 핵심은 위에 반영됨).
- 미착수 — 코드 변경 없음, 작업 브랜치 없음. 착수 시 main에서 feature 브랜치 생성.
- 주의(1차 플랜에서 승계): ad-hoc 서명 상태라 리빌드마다 TCC 무효화 — `tccutil reset Accessibility dev.pilyang.VimAction` 후 재부여 필요.

## 관련 링크

- architecture: [system-overview.md](../../architecture/references/system-overview.md), [mode-engine.md](../../architecture/references/mode-engine.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [20260713_tap-reenable-watchdog-polling.md](../../decisions/references/20260713_tap-reenable-watchdog-polling.md), [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md), [20260712_key-representation-and-fixture-format.md](../../decisions/references/20260712_key-representation-and-fixture-format.md)

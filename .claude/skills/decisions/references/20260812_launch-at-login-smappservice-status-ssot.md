# 로그인 시 자동 시작은 `SMAppService.mainApp` — 등록 상태가 SSOT

- **결정일**: 2026-08-12

## 결정

로그인 시 자동 시작을 `SMAppService.mainApp`(`register()`/`unregister()`/`status`)로 구현한다. **opt-in**이며(설정 창 General > Behavior 토글, 기본 off — 묵시적 자동 등록 경로 없음), **토글이 보여주는 값의 SSOT는 `SMAppService.mainApp.status` 하나다** — UserDefaults 미러를 두지 않고, `status == .enabled`만 on으로 파생한다. 설정 창이 열릴 때(`AppState.settingsWindowDidAppear()`) status를 다시 읽어 반영한다.

## 배경·근거 (왜)

메뉴바 백그라운드 앱이라 "로그인 시 자동 시작"은 사실상 상시 켜 두는 앱의 기본 기대치인데, 지금은 사용자가 매번 직접 실행해야 한다.

**미러를 두지 않는 것이 이 결정의 핵심이다.** 등록 상태는 앱이 단독으로 소유하지 못한다 — 사용자가 시스템 설정 > 일반 > 로그인 항목에서 언제든 직접 끌 수 있고, 그때 앱은 아무 통지도 받지 않는다. UserDefaults에 미러를 두면 그 순간부터 두 소스가 어긋나고, 토글은 on인데 실제로는 자동 시작하지 않는 상태가 된다. 이 앱에는 이미 같은 형태의 함정 기록이 있다(`defaults.bool`이 미설정 키에도 false를 주는 문제) — 여기서는 값이 "있는데 틀린" 쪽이라 더 나쁘다. 그래서 상태를 저장하지 않고 매번 시스템에 묻는다.

`.requiresApproval`·`.notFound`도 전부 off로 표시한다. 어느 쪽이든 실제로는 로그인 시 뜨지 않으므로, on으로 보여주는 것이 곧 거짓말이다.

**쓰기 결과도 요청값이 아니라 재조회한 status가 정한다.** `register()`가 던지면 토글이 원위치로 돌아가고 실패 문구가 섹션 안에 남는다 — 클릭이 조용한 무동작이 되지 않게 하는 레포 관례(`setAppEnabled`·`openProfile`의 NSAlert 폴백)를 따르되, 창이 이미 떠 있는 경로라 모달 대신 클릭한 자리에 인라인으로 보여준다.

배포 타깃이 macOS 14.0이라 `SMAppService`(13+)는 무조건 가용하고, `mainApp`은 헬퍼 앱 번들도 추가 TCC 권한도 필요 없다.

## 검토한 대안

- **UserDefaults 미러 + 시작 시 동기화**: 토글 렌더가 IO 없이 즉시라는 이점뿐인데, 위의 어긋남을 구조적으로 못 막는다. 동기화 시점을 아무리 늘려도 "설정 창이 떠 있는 동안 사용자가 시스템 설정에서 끄는" 창은 남는다.
- **로그인 아이템 헬퍼 앱(`SMAppService.loginItem(identifier:)`)**: 별도 헬퍼 번들을 만들어 임베드해야 하고, 이 앱은 자기 자신이 백그라운드 앱이라 헬퍼가 대신 띄울 것이 없다.
- **온보딩에서 자동 등록 또는 넛지**: 사용자가 요청하지 않은 로그인 항목 등록은 배신이고, 넛지는 이번 범위 밖(추후 필요가 실증되면 additive).
- **`forCurrentEnvironment()` 불활성 변형(`DockIconController`·`FrontmostAppGate` 패턴)**: 불필요하다. 테스트·프리뷰에서 도달 가능한 것은 status **읽기**뿐이고 그것은 부작용이 없다. 실제 로그인 항목을 바꾸는 `register`/`unregister`는 사용자 클릭에서만 불리며, 테스트는 주입 seam으로 가짜를 넣는다.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) (앱 셸 — 설정 창 Behavior 섹션)
- 새 코드: `VimAction/LaunchAtLoginController.swift`(`@MainActor @Observable`, seam 3종), `VimActionTests/LaunchAtLoginControllerTests.swift`
- 수정: `AppState`(컨트롤러 소유 + 창 열림 훅에서 `refresh()`), `SettingsView`의 Behavior 섹션, `Logging.swift`(카테고리 `launchAtLogin`)
- [20260801_userdefaults-yaml-ownership.md](20260801_userdefaults-yaml-ownership.md)의 경계에 **세 번째 칸이 생긴다** — 시스템이 소유하는 상태는 UserDefaults도 YAML도 아니다.

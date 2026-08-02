# 설정 창이 열린 동안만 Dock 아이콘 노출

- **결정일**: 2026-08-02

## 결정

설정 창이 열려 있는 동안에만 activation policy를 `.regular`로 올려 Dock 아이콘을 노출하고, 창이 닫히면 `.accessory`로 되돌린다. `.regular`가 Dock 아이콘과 **상단 앱 메뉴를 한 세트로** 노출하는 것은 수용한다 — 아이콘만 켜는 API는 없다.

열림·닫힘 신호는 **비대칭이다**:

- **열림** = `SettingsView.onAppear` → `.regular` + `NSApp.activate`
- **닫힘** = `NSWindow.willCloseNotification` (판정: `isVisible && titled && !NSPanel`) → `.accessory`

## 배경·근거 (왜)

`LSUIElement = YES`라 설정 창을 열어 둔 채 다른 앱으로 전환하면 되돌아올 경로가 메뉴바 아이콘뿐이었다. ⌘Tab에도, Dock에도 없어 창이 어디 있는지 찾을 수 없다. `LSUIElement`는 "시작 시 `.accessory`"를 뜻할 뿐이라 런타임 승격이 가능하다.

동반되는 앱 메뉴 노출은 대가만은 아니다 — ⌘W로 창 닫기, ⌘Q로 종료가 정상 동작하게 된다.

**신호가 비대칭인 것은 실측 결과다.** 설계 시점에는 창 알림만으로(`didBecomeKey`/`willClose`) 대칭 구성해 SwiftUI를 건드리지 않으려 했으나, 실기기에서 열림이 감지되지 않았다. 원인: 메뉴바에서 'Preferences…'를 눌러도 앱이 활성화되지 않아 설정 창은 **보이기만 하고 key가 되지 않는다**(`.accessory` 앱의 정상 동작). 로그로 확인한 알림 시퀀스는 `_NSWindowDidBecomeVisible` → `NSWindowDidOrderOnScreenAndFinishAnimating`뿐이고 `NSWindowDidBecomeKeyNotification`은 오지 않았다 — 창을 강제로 활성화하자 그때서야 도착했다. 화면에 올라온 것을 알려주는 알림은 전부 비공개 이름이라 쓸 수 없다.

따라서 열림은 SwiftUI `onAppear`가 유일하게 신뢰할 수 있는 공개 신호다. 우려했던 "`Settings` 씬이 창을 재사용하므로 재오픈 때 `onAppear`가 다시 오지 않을 수 있다"는 실측으로 기각됐다 — 열기/닫기/재열기 사이클에서 `onAppear`가 매번 도착했다.

닫힘까지 `onDisappear`로 대칭화하지 않는 이유는 반대다. `onDisappear`는 리렌더에도 뜰 수 있어, 설정 창이 열려 있는데 Dock 아이콘이 사라질 수 있다. `willClose`는 창이 실제로 닫힐 때만 온다.

판정 술어에서 `NSPanel`을 거르는 것이 핵심이다. 'Reload Config' 실패 `NSAlert`는 titled 패널이라, 거르지 않으면 설정 창이 열린 채 알림만 닫아도 Dock 아이콘이 사라진다. 메뉴바 상태 항목 창은 titled가 아니라 자동으로 걸러진다.

승격에 `NSApp.activate`가 따라붙어야 하는 이유도 위 실측과 같다 — 앱이 활성화되지 않은 채 창이 뜨므로, 정책만 올리면 창이 다른 앱 뒤에 깔린 채 Dock 아이콘만 생긴다. 강등에는 붙이지 않는다(포커스가 다음 앱으로 넘어가야 한다). 최전면 캐시 자기-오염은 무해하다: 실제로 최전면이 된 상황이라 `NSWorkspace` 알림이 어차피 같은 값을 넣는다.

## 검토한 대안

- **창 알림만으로 대칭 구성 (`didBecomeKey` + `willClose`)**: 위 실측으로 기각 — `.accessory` 앱은 창이 key가 되지 않아 열림이 감지되지 않는다.
- **`onAppear` + `onDisappear` 대칭**: 리렌더 오탐으로 기각 — 설정 창이 열린 채 아이콘이 사라질 수 있다.
- **열린 창 개수를 세어 정책 파생**: 이 앱에 설정 창 외의 titled 창이 없어 닫히는 창 하나만 보면 충분하다. 열거 로직·주입 seam이 늘 뿐 오늘 얻는 것이 없다.
- **`NSApplicationDelegate` + `applicationShouldHandleReopen`**: Dock 아이콘 클릭 시 창 전면화는 AppKit 기본 동작이 이미 한다(실기기 확인). 새 delegate 도입 없이 성립한다.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) — "Dock 아이콘·앱 메뉴 없음"이 더 이상 무조건이 아니다.
- 신규 `VimAction/DockIconController.swift`, `VimActionTests/DockIconControllerTests.swift`.
- `VimAction/AppState.swift` — `dockIcon` 소유 1줄. `VimAction/SettingsView.swift` — `.onAppear` 1줄. `bootstrap()` 배선은 없다.
- XCTest 하에서는 `forCurrentEnvironment()`가 격리 `NotificationCenter` + no-op 정책 적용을 주입한다 — TEST_HOST가 앱 프로세스라 테스트가 만든 창 하나에 앱이 통째로 `.regular`가 되면 안 된다 (`FrontmostAppGate.forCurrentEnvironment`와 같은 이유).

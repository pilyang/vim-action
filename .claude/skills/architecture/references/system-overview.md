# 시스템 개요

- **Last updated**: 2026-07-20

## 현재 구조

키 입력은 단일 `CGEventTap`(kCGSessionEventTap)으로만 진입하고, 순수 Swift 모드 엔진이 이를 추상 `VimAction`으로 해석하며, 전략 디스패처가 앱/요소별로 Accessibility 실행과 Keyboard(합성 이벤트) 실행 중 하나를 선택한다.

```mermaid
graph LR
    KB[Keyboard] --> Tap[CGEventTap<br/>kCGSessionEventTap]
    Tap --> Engine["모드 엔진<br/>(Insert/Normal/Visual)"]
    Engine -->|VimAction| Dispatcher[전략 디스패처]
    Dispatcher --> AX["Accessibility 어댑터<br/>(AXUIElement)"]
    Dispatcher --> KBD["Keyboard 어댑터<br/>(CGEvent 합성)"]
    AX --> Exec[ActionExecutor]
    KBD --> Exec
    Exec -->|"합성 이벤트 (마커 포함)"| Tap

    Resolver["포커스/컨텍스트 리졸버<br/>NSWorkspace + AXObserver"] -.-> Dispatcher
    Profile["프로파일 로더<br/>~/Library/.../VimAction/*.yaml"] -.-> Dispatcher
    Failsafe[안전장치 단축키<br/>별도 CGEventTap] -.->|모든 것을 우회| Tap
```

컴포넌트별 책임:

| 컴포넌트 | 책임 | 상세 reference |
|---|---|---|
| 이벤트 탭 | 유일한 키 입력 진입점. 마커 확인, 안전장치 우선 감지, 엔진 결정(삼키기/통과/대체) 적용 | [reentrancy-and-safety.md](reentrancy-and-safety.md) |
| 모드 엔진 | `Key` → `VimAction` 해석. 실행 방법은 전혀 모름 | [mode-engine.md](mode-engine.md) |
| 포커스/컨텍스트 리졸버 | `(bundleID, focusedRole, selectedRange)` 캐싱, 포커스 변경 시 무효화 | [strategy-dispatch.md](strategy-dispatch.md) |
| 전략 디스패처 + 어댑터 | `VimAction`마다 AX vs Keyboard 선택 후 실행 | [strategy-dispatch.md](strategy-dispatch.md) |
| ActionExecutor | 모든 출력(AX 쓰기, 이벤트 게시)의 단일 통로. 재진입 마커 강제 | [reentrancy-and-safety.md](reentrancy-and-safety.md) |
| 프로파일 로더 | YAML 계층 설정 로드/감시 | [profiles-and-config.md](profiles-and-config.md) |
| 앱 셸 | 메뉴바 `NSStatusItem`(모드 글리프), SwiftUI 설정 창, 온보딩 | — |

## 불변식·계약

- 키 입력 진입점은 메인 `CGEventTap` 하나뿐이다 (안전장치 탭은 예외 — 가로채기가 아닌 킬 스위치 전용).
- 해석(엔진)과 실행(어댑터)은 분리되어 있으며, `VimAction` 생산자는 엔진 하나다.

## 근거 요약

진입점을 하나로 고정하면 그 아래 전체가 순수 Swift로 유지되어 단위 테스트가 가능하고, 해석/실행을 분리하면 두 전략 어댑터를 교체 가능한 소비자로 둘 수 있다.

- 관련 결정: [20260712_single-event-tap-pipeline.md](../../decisions/references/20260712_single-event-tap-pipeline.md)

## 관련

- 제품 요구사항: 워크스페이스 `docs/prd.md` (§7.3, §7.4, §9, §10)
- 앱 셸: `LSUIElement` 메뉴바 백그라운드 앱(SwiftUI `MenuBarExtra` + `Settings` 씬). Dock 아이콘·앱 메뉴 없음.
- App Sandbox 해제(Developer ID 직접 배포). CGEventTap/AX가 샌드박스 불가하기 때문 — [20260712_disable-sandbox-developer-id.md](../../decisions/references/20260712_disable-sandbox-developer-id.md).
- 권한은 빌드 엔타이틀먼트가 아니라 런타임 TCC. 온보딩은 **Accessibility만** 요청한다(Settings 창 권한 섹션 + 1초 폴링으로 부여 감지 후 재시작 없이 탭 설치). active tap은 AX만으로 설치되며, Input Monitoring은 필요가 입증될 때만 추가 — [20260712_active-tap-ax-only-onboarding.md](../../decisions/references/20260712_active-tap-ax-only-onboarding.md).
- 메인 탭은 처음부터 active tap(`.defaultTap`)이며 메인 런루프에 부착돼 있다. **엔진이 배선돼 있다**(`EventTapController`): keyDown → `KeyTranslator` → `VimEngine.handle` → 결정 적용(passthrough=통과 / swallow=`nil`). `.replace`는 과도기라 실행 없이 삼키고 DEBUG 요약 로그만 남긴다(실행은 디스패처 마일스톤) — [20260717_replace-swallow-transitional-rule.md](../../decisions/references/20260717_replace-swallow-transitional-rule.md). 메뉴바 마스터 토글(`isInterceptionEnabled`)이 가로채기 on/off를 지배하고([20260718_interception-toggle-semantics.md](../../decisions/references/20260718_interception-toggle-semantics.md)), 백그라운드 워치독이 조용히 죽은 탭을 폴링·복구한다([reentrancy-and-safety.md](reentrancy-and-safety.md)). 런루프를 전용 스레드로 옮길지는 엔진 연결 후 재검토 대상으로 남아 있다(별도 플랜) — [20260712_main-runloop-tap-attachment.md](../../decisions/references/20260712_main-runloop-tap-attachment.md).
- 탭 계층의 CGEvent→`Key` 정규화는 `KeyTranslator`(앱 타깃, `@MainActor`)가 담당한다: 특수키는 keycode, 문자키는 UCKeyTranslate + ASCII-capable 레이아웃(shift만 base에 반영, ctrl/opt/cmd는 modifiers로), 번역 불가는 `nil`이며 호출측은 무조건 통과시킨다. 임의의 `CGEvent`에 대해 답이 정의된 total function이며 keyDown 외 타입은 내부 가드로 `nil`이다. 레이아웃 `Data`는 캐시하고 입력 소스 변경 분산 노티로 무효화한다(키당 TIS 조회 제거) — [20260716_cgevent-key-translation-ascii-layout.md](../../decisions/references/20260716_cgevent-key-translation-ascii-layout.md), [20260716_keytranslator-total-function-keydown-guard.md](../../decisions/references/20260716_keytranslator-total-function-keydown-guard.md), [20260717_keytranslator-layout-caching.md](../../decisions/references/20260717_keytranslator-layout-caching.md).

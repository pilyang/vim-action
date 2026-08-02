# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# VimAction

macOS 메뉴바 백그라운드 앱 — 시스템 전역 Vim 키바인딩 (Swift/SwiftUI, Xcode).

## 프로젝트 스킬 (필수 워크플로우)

- 아키텍처·구조 관련 작업(구현, 수정, 설계 질문) 전에는 반드시 **architecture 스킬**을 사용해 현재 구조(최종 상태)를 로드하세요.
- 기술 결정(아키텍처, 툴링, 라이브러리, 빌드/테스트 전략 등)이 생기거나 바뀌면 **decisions 스킬**로 기록하세요 — 결정 기록의 진입점은 항상 decisions이며, 구조에 영향이 있으면 같은 플로우에서 architecture의 최종 상태 갱신까지 이어집니다.
- 세션 시작 시나 작업을 이어받을 때는 **plans 스킬**로 활성 플랜을 먼저 확인하고, 멀티세션 작업의 플랜 기록·진행 상태 갱신·완료 정리도 plans 스킬로 관리하세요.

## 자주 쓰는 명령

```bash
# 엔진(순수 Swift) 테스트 — 가장 빠른 피드백 루프
swift test --package-path Packages/VimActionCore

# 엔진 테스트 하나만
swift test --package-path Packages/VimActionCore --filter <TestClassOrMethodName>

# 앱 유닛 테스트 (UI 테스트 제외)
xcodebuild test -project VimAction.xcodeproj -scheme VimAction \
  -destination 'platform=macOS' -only-testing:VimActionTests

# 앱 빌드만 (CI와 동일 — 서명 없이 컴파일 검증)
xcodebuild build -project VimAction.xcodeproj -scheme VimAction \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# 도그푸딩 로그 관측 — `.debug`는 로그 저장소에 남지 않아 `log show`로는 판정 불가하고,
# zsh에서 `log`가 가려져 절대 경로가 필요합니다.
/usr/bin/log stream --level debug --predicate 'subsystem == "dev.pilyang.VimAction"'
```

CI(GitHub Actions)는 위의 엔진 테스트와 앱 빌드 두 잡을 PR·main push마다 실행합니다.
**빌드 경고 기준선은 0건입니다** — 새 경고가 생기면 그 자리에서 처리하세요.

## 아키텍처 큰 그림

키 입력은 단일 `CGEventTap` 하나로만 진입 → `KeyTranslator`가 CGEvent를 `Key`로 정규화 → 순수 Swift **모드 엔진**(`Packages/VimActionCore`의 `VimEngine`, macOS 의존성 없음)이 `Key`를 추상 `VimAction`으로 해석 → **전략 디스패처**가 앱/요소별로 Accessibility(AXUIElement) 실행 vs Keyboard(합성 이벤트) 실행을 선택 → 모든 출력은 단일 `ActionExecutor`를 거치며 합성 이벤트에 재진입 마커를 붙여 무한 루프를 방지합니다.

핵심 불변식: 해석(엔진)과 실행(어댑터)은 분리 — 엔진은 실행 방법을 전혀 모릅니다. 엔진 로직은 `swift test`로 macOS 없이 테스트합니다. 상세 구조·불변식은 architecture 스킬의 references가 SSOT입니다.

## 테스트를 쓸 때 알아둘 것

**주입 seam**: 합성 출력은 `ActionExecutor(postEvent:)`에 수집기를 주입해 키코드·플래그·마커를 검증합니다 (CGEvent 생성은 TCC가 불필요해 headless로 됩니다). 설정 계층은 `ConfigLoader.FileSystem`·`ConfigSeeder.FileSystem`에 인메모리 구현을 주입합니다 — **어떤 테스트도 실제 `~/.config`를 건드리면 안 됩니다.**

**XCTest 하위에서 기본값이 바뀝니다**: 실행 sink와 `FrontmostAppGate`는 XCTest에서 무해한 것으로 바꿔치기됩니다. 그냥 두면 테스트가 실제 화살표 키를 머신에 주입하거나, Ghostty에서 테스트를 돌릴 때(주력 터미널이라 정상 워크플로우입니다) 앱 게이트가 켜져 결정 테스트가 통째로 뒤집힙니다. 동작을 검증하는 테스트는 `init`으로 자기 것을 주입하세요.

**단언 함정 — `defaults.bool(forKey:)`는 미설정 키에도 `false`를 돌려줍니다.** 영속을 검증할 때 `object(forKey:) != nil`을 앞세우지 않으면 영속 코드를 통째로 지워도 테스트가 통과합니다 (M1에서 실제로 4곳이 이 상태였습니다). 같은 이유로, 파일을 "덮어쓰지 않는다"를 검증할 때는 내용 비교가 아니라 **쓰기 seam 호출 여부**를 단언하세요 — 같은 바이트로 덮어쓰는 회귀는 내용 비교로 잡히지 않습니다.

## Swift 6 언어 모드 — 남은 항목 1건

`AccessibilityPermissionMonitor.swift`의 `kAXTrustedCheckOptionPrompt`(전역 `var`) 참조가 Swift 6 모드에서만 에러입니다. 나머지는 프로브에서 깨끗함을 확인했습니다. 프로브는 pbxproj를 고치지 말고 **명령줄 오버라이드**로 하면 되돌림 실수가 원천 봉쇄됩니다:

```bash
xcodebuild build -project VimAction.xcodeproj -scheme VimAction \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=6.0
```

## Accessibility(TCC) 권한 — 로컬 개발 시 주의

앱은 런타임 TCC로 **Accessibility 권한만** 요청합니다 (Input Monitoring 불필요, App Sandbox 해제됨). 로컬 빌드는 ad-hoc 서명이라 **리빌드마다 cdhash가 바뀌어 기존 TCC 부여가 무효화**됩니다 — 시스템 설정의 체크박스가 켜져 보여도 낡은 항목이라 `AXIsProcessTrusted()`는 false(메뉴바 글리프 `square.dashed`)일 수 있습니다.

해소 절차:

```bash
# 낡은 TCC 항목 리셋 후, 앱 실행 → 시스템 설정에서 현재 빌드에 재부여
tccutil reset Accessibility dev.pilyang.VimAction
```

재부여되면 앱 내 1초 폴링이 재시작 없이 감지해 탭을 설치합니다.

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
```

CI(GitHub Actions)는 위의 엔진 테스트와 앱 빌드 두 잡을 PR·main push마다 실행합니다.

## 아키텍처 큰 그림

키 입력은 단일 `CGEventTap` 하나로만 진입 → `KeyTranslator`가 CGEvent를 `Key`로 정규화 → 순수 Swift **모드 엔진**(`Packages/VimActionCore`의 `VimEngine`, macOS 의존성 없음)이 `Key`를 추상 `VimAction`으로 해석 → **전략 디스패처**가 앱/요소별로 Accessibility(AXUIElement) 실행 vs Keyboard(합성 이벤트) 실행을 선택 → 모든 출력은 단일 `ActionExecutor`를 거치며 합성 이벤트에 재진입 마커를 붙여 무한 루프를 방지합니다.

핵심 불변식: 해석(엔진)과 실행(어댑터)은 분리 — 엔진은 실행 방법을 전혀 모릅니다. 엔진 로직은 `swift test`로 macOS 없이 테스트합니다. 상세 구조·불변식은 architecture 스킬의 references가 SSOT입니다.

## Accessibility(TCC) 권한 — 로컬 개발 시 주의

앱은 런타임 TCC로 **Accessibility 권한만** 요청합니다 (Input Monitoring 불필요, App Sandbox 해제됨). 로컬 빌드는 ad-hoc 서명이라 **리빌드마다 cdhash가 바뀌어 기존 TCC 부여가 무효화**됩니다 — 시스템 설정의 체크박스가 켜져 보여도 낡은 항목이라 `AXIsProcessTrusted()`는 false(메뉴바 글리프 `square.dashed`)일 수 있습니다.

해소 절차:

```bash
# 낡은 TCC 항목 리셋 후, 앱 실행 → 시스템 설정에서 현재 빌드에 재부여
tccutil reset Accessibility dev.pilyang.VimAction
```

재부여되면 앱 내 1초 폴링이 재시작 없이 감지해 탭을 설치합니다.

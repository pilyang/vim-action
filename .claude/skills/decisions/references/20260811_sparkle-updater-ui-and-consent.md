# 업데이트 자동 확인은 Sparkle 표준 동의 — 노출은 3자리

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-11

## 결정

백그라운드 자동 업데이트 확인의 동의·기본값은 Sparkle 표준 플로우를 그대로 쓴다 — 두 번째 실행 시 1회 동의 프롬프트, 대답은 Sparkle이 소유·영속(`SUEnableAutomaticChecks`). 앱은 기본값을 강제하지 않는다. 노출은 3자리: 수동 확인 버튼은 **메뉴바 메뉴**("Preferences…" 아래)와 **설정 About 탭**(버전 아래), 자동 확인 토글은 **General 탭 "Updates" 섹션**.

## 배경·근거 (왜)

- 코드만 보면 "기본 켬으로 강제하지 않은 것"이 결정인지 누락인지 역추적할 수 없다 — 이 문서가 그 답이다: 사용자 동의 없는 백그라운드 네트워크 확인을 피하는 쪽을 **선택**했고, Sparkle 표준 프롬프트는 추가 코드 0으로 동의 절차를 제공한다.
- 메뉴바 상주 앱이라 메뉴가 가장 접근성 좋은 자리이고, About은 버전 정보와 붙는 관례 자리다. 같은 updater를 부르는 버튼 2개라 중복 비용이 없다.
- 토글을 노출해야 프롬프트에서 한 선택을 나중에 바꿀 자리가 생긴다. 프롬프트 전에 토글을 켜면 그 자체가 동의 기록이 되어 프롬프트는 뜨지 않는다 — 두 경로가 같은 Sparkle 영속으로 수렴하므로 상태 분기가 없다.

## 검토한 대안

- **기본 켬(묻지 않음)**: 업데이트 도달률은 높지만 동의 없는 백그라운드 네트워크 요청. 기각.
- **기본 끔(수동 확인만)**: 조용하지만 사용자가 업데이트를 놓치기 쉽다. 기각.
- **토글 비노출(프롬프트에만 맡김)**: 최초 선택을 바꿀 방법이 없다. 기각.

## 영향 범위

- `UpdaterViews.swift`(공용 확인 버튼 + 토글, Sparkle 공식 SwiftUI 패턴), 메뉴바 메뉴(`VimActionApp.swift`), 설정 General·About 탭(`SettingsView.swift`).
- updater 시동 시점은 `AppState.bootstrap()`의 XCTest 가드 뒤(생성은 `startingUpdater: false`) — init 무IO 관례의 적용이며 구조는 architecture system-overview에 반영.
- 통합 자체의 결정은 [20260810_sparkle-auto-update.md](20260810_sparkle-auto-update.md), 피드 위치는 [20260810_appcast-hosting-github-releases.md](20260810_appcast-hosting-github-releases.md).

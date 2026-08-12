# 배포 타깃은 macOS 14.0

- **결정일**: 2026-08-12

## 결정

`MACOSX_DEPLOYMENT_TARGET`을 26.5 → **14.0**으로 내린다. CI에 하한 게이트 잡(`app-build-floor`: 14.0 오버라이드 빌드 + pbxproj 값 단언)을 두어 하한이 조용히 올라가는 것을 막는다. Homebrew cask의 `depends_on macos:`는 **min-14 산출물이 담긴 첫 릴리스가 나온 뒤** `:sonoma`로 내리고, 같은 편집에서 `depends_on arch: :arm64` 가드를 추가한다.

## 배경·근거 (왜)

- 26.5는 의도된 하한이 아니라 **Xcode가 프로젝트 생성 시 넣은 당시 SDK 버전 기본값**이다. 코드에 `@available`/`if #available` 사용처가 0건이라 26.5를 요구할 근거가 없다.
- 명령줄 오버라이드 프로브 실측: `MACOSX_DEPLOYMENT_TARGET=14.0` → BUILD SUCCEEDED·경고 0건. `13.0` → `@Observable`(macOS 14+, 8개 파일)과 `@Environment(\.openSettings)`(14+)로 실패. 즉 **코드 변경 없이 도달 가능한 하한이 14.0**이다.
- 26.5 상태의 산출물은 `LSMinimumSystemVersion`·`LC_BUILD_VERSION minos`가 26.5로 박혀, 그 미만 macOS에서는 DMG 설치까지 되고 실행만 거부된다.
- appcast의 `sparkle:minimumSystemVersion`은 `generate_appcast`가 앱 번들의 `LSMinimumSystemVersion`에서 자동 파생한다(라이브 appcast v0.1.2에 26.5가 들어 있는 것으로 실측 확인) — 다음 릴리스부터 자동으로 14.0이 되므로 별도 조치가 없다.
- `Packages/VimActionCore/Package.swift`는 `platforms:` 선언이 없어 SPM 기본 하한(14보다 훨씬 낮음)이 적용된다 — 조치 불필요. `.macOS(.v14)` 추가는 지금 필요 없는 제약이라 하지 않는다.
- 릴리스 DMG의 바이너리는 arm64 전용이다(appcast `sparkle:hardwareRequirements=arm64` — `generate_appcast`가 바이너리를 검사해 넣은 값). Sonoma는 Intel Mac을 폭넓게 지원하므로 하한을 내리면 Intel 사용자가 brew 설치에 성공하고 실행만 거부되는 조용한 실패가 열린다 — cask에 arch 가드를 함께 넣는 이유. 실질 지원 대상은 **Apple Silicon + macOS 14+**.

## 검토한 대안

- **13.0 지원** (`@Observable` → `ObservableObject` 전환): 8개 파일 + `openSettings` 대체까지 코드 변경 범위가 크고 수요 근거가 없다 — 기각.
- **CI 게이트를 구버전 `macos-14` 러너 빌드로**: 그 러너의 Xcode는 `swift-tools-version: 6.2`를 파싱조차 못 한다 — 최신 러너에서 deployment target만 낮춰 빌드하는 형태로 대체. 오버라이드 빌드는 pbxproj가 드리프트해도 14.0 기준으로 신규 API 사용을 잡고, 단언 스텝은 "API는 안 쓰면서 pbxproj 값만 올라가는" 드리프트를 잡는다.
- **cask `depends_on`을 릴리스 전에 미리 변경**: min-14 산출물이 없는 상태에서 `:sonoma`로 내리면 Sonoma 사용자가 v0.1.2(minos 26.5)를 brew로 설치해 실행 거부당한다 — 릴리스 후로 순서 고정.
- **release.yml에 `depends_on` sed 자동화 추가**: 일회성 변경이라 파이프라인에 넣지 않는다 (현행 bump 스텝은 `version`·`sha256`만 교체).

## 영향 범위

- architecture reference 갱신 없음 — 구조 무변이고, architecture 문서는 배포 타깃을 언급하지 않는다.
- `VimAction.xcodeproj/project.pbxproj` — project-level Debug/Release + VimActionTests 타깃 Debug/Release 4곳 (앱·UITests 타깃은 자체 선언 없이 project-level 상속).
- `.github/workflows/ci.yml` — `app-build-floor` 잡 추가.
- 후속(릴리스 후 별도 진행): `pilyang/homebrew-tap`의 `Casks/vimaction.rb` — `depends_on macos: :sonoma` + `depends_on arch: :arm64`.
- 런타임 실측 기록(SEI 배달 억제, 킬스위치 HID 탭 등)은 전부 macOS 26.5에서 수행된 것 — 14~15에서의 동작은 VM 스모크로 별도 확인한다.

## Supersedes

부분 supersede 2건 — 결정 자체가 아니라 "배포 타깃 26.5" 전제만 무효화한다:

- [20260802_app-icon-icon-composer.md](20260802_app-icon-icon-composer.md) — "배포 타깃이 26.5라 구버전 폴백용 appiconset 불필요" 전제만 무효. `.icon` 단독 채택·appiconset 제거 결정은 유지하되, 14~15에서는 Xcode가 `.icon`에서 자동 생성하는 평면화 폴백에 의존하게 된다.
- [20260809_permission-discoverability-push.md](20260809_permission-discoverability-push.md) — "배포 타깃이 26.5라 가용성 가드 불필요" 근거만 교체. 채택한 `openSettings`가 마침 macOS 14+라 14.0 하한에서도 가드 없이 유효 — 결론 유지.

# GitHub Actions CI 도입 — 엔진 테스트 + 앱 빌드 검증

- **결정일**: 2026-07-12

## 결정

GitHub Actions로 CI를 도입한다. PR과 main push마다 `macos-26` 러너에서 두 잡을 병렬 실행: (1) `engine-tests` — `Packages/VimActionCore`에 `swift test`, (2) `app-build` — 앱 타깃 `xcodebuild build` 컴파일 검증(`CODE_SIGNING_ALLOWED=NO`). Xcode는 `DEVELOPER_DIR` 환경변수로 26.6에 고정한다.

## 배경·근거 (왜)

- 리포에 CI가 전혀 없어 엔진 테스트 회귀와 앱 컴파일 깨짐을 PR 단계에서 잡을 수 없었다.
- **리포가 public이라 GitHub 호스티드 macOS 러너가 무료** — macOS 10x 과금 배수를 고려할 필요가 없어 잡 2개 병렬 구성이 부담 없다. 엔진 테스트(~30초)가 앱 빌드보다 먼저 끝나 빠른 피드백을 준다. private 전환 시에는 잡 통합 등 재검토 필요.
- **Xcode 버전 고정**: 러너 이미지 업데이트로 기본 Xcode가 바뀌어도 빌드가 흔들리지 않게 로컬과 동일한 26.6(17F113)으로 고정. `xcode-select` 스텝 대신 워크플로 전역 `DEVELOPER_DIR` env를 사용 (sudo 불필요, 잡 전체 적용).
- **코드사이닝 off**: CI에는 인증서가 없고 컴파일 검증만 목적이므로 `CODE_SIGNING_ALLOWED=NO`가 표준 관행. 서명·공증은 배포 단계에서 별도 릴리스 워크플로로 다룬다 (이번 범위 밖).
- **공유 스킴 추가가 선행 조건이었다**: 스킴이 `xcuserdata/`(gitignored)에만 있어 CI에서 `xcodebuild -scheme`이 불가능 → `VimAction.xcodeproj/xcshareddata/xcschemes/VimAction.xcscheme` 커밋.
- UI 테스트(XCUITest)와 이벤트 탭 통합 테스트는 CI에 넣지 않는다: 러너에서 Accessibility/입력 모니터링 권한을 부여할 방법이 없고, 엔진 로직은 순수 SPM 패키지 테스트로 커버된다는 기존 구조 결정([20260712_pure-swift-mode-engine.md](20260712_pure-swift-mode-engine.md))과 정합.

## 검토한 대안

- **Ubuntu 러너에서 `swift test`** (1x 요금): 코어가 현재 stdlib-only라 가능하지만, public 리포라 비용 이점이 없고 앱 빌드용 macOS 잡이 어차피 필요하며, 툴체인을 로컬과 통일하는 편이 관리가 단순해 기각.
- **`macos-latest` + 기본 Xcode 사용**: 이미지 롤링 업데이트에 따라 빌드가 흔들릴 수 있어 기각. 명시 버전 고정이 디버깅 가능성 면에서 낫다.
- **SPM 의존성 캐시**: 외부 의존성이 없어 불필요, 생기면 그때 추가.

## 영향 범위

- 신규: `.github/workflows/ci.yml`, `VimAction.xcodeproj/xcshareddata/xcschemes/VimAction.xcscheme`
- 구조(컴포넌트 경계) 변경 없음 — architecture reference 갱신 불필요.
- 향후 Xcode/macOS 업그레이드 시 `ci.yml`의 `DEVELOPER_DIR`와 러너 라벨을 함께 올려야 함.

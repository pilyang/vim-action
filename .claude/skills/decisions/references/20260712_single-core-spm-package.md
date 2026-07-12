# 순수 Swift 코드는 단일 코어 패키지의 다중 타깃으로

- **결정일**: 2026-07-12

## 결정

엔진을 비롯한 순수 Swift 모듈들은 저장소 내 **단일 로컬 SPM 패키지** `Packages/VimActionCore`의 여러 타깃으로 둔다. 첫 타깃은 `VimEngine`(+ `VimEngineTests`)이며, 이후 ProfileKit·전략 선택 로직 등 순수 모듈도 같은 패키지의 새 타깃으로 추가한다. macOS 의존 코드(이벤트 탭, 리졸버, AX/Keyboard 어댑터, ActionExecutor, 앱 셸)는 앱 타깃에 남고 이 패키지의 소비자가 된다.

## 배경·근거 (왜)

순수 Swift 모듈이 앞으로 2~4개(VimEngine, ProfileKit, 전략 선택) 생기고 서로 타입 어휘(`VimAction` 등)를 참조할 구조다. 격리 강도(무엇을 import할 수 있는가)는 어차피 **타깃 단위**로 결정되므로, 패키지를 쪼개도 얻는 추가 격리가 없다. 반면 단일 패키지면 타깃 간 의존이 매니페스트 한 줄(`dependencies: ["VimEngine"]`)이고 Xcode 연결도 1회면 된다. 모듈마다 개별 패키지로 두면 Package.swift 작성 + 로컬 경로 상호 의존 선언 + Xcode 연결을 반복하게 되어 관리 비용만 커진다.

no-macOS-import 불변식은 패키지 경계가 아니라 타깃 의존성 미선언으로 강제되므로, 단일 패키지 안에서도 그대로 유지된다.

## 검토한 대안

- **모듈별 개별 패키지** (`Packages/VimEngine`, `Packages/ProfileKit`, …): 패키지 경계 = 모듈 경계로 의존 격리가 가장 엄격해 보이지만, 실제 import 격리는 타깃 의존성이 결정하므로 이득이 없다. 모듈 추가마다 매니페스트·Xcode 연결 반복 비용만 발생해 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 생성한 코드: `Packages/VimActionCore/` (Package.swift, `Sources/VimEngine`, `Tests/VimEngineTests`)
- `VimACtion.xcodeproj`에 로컬 패키지 참조 + 앱 타깃의 `VimEngine` 제품 의존성 추가.

# Package.resolved는 커밋한다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

`Packages/VimActionCore/Package.resolved`를 git에 커밋한다. Yams가 이 저장소의 첫 외부 의존이라 그전까지는 이 파일이 존재하지 않았다.

## 배경·근거 (왜)

- **CI와 로컬이 같은 버전을 쓴다**: `Package.swift`의 핀은 `from:` 하한이라 해석 시점에 따라 CI와 로컬이 다른 Yams를 잡을 수 있다. 파싱 강건성 테스트가 Yams의 스칼라 해석 동작에 직접 의존하므로(`node.bool`이 `yes`를 받는지 등), 버전이 갈리면 테스트 결과가 환경에 따라 달라진다.
- 이 저장소는 라이브러리가 아니라 **앱**이다 — 재현 가능한 빌드가 라이브러리 소비자의 해석 자유보다 중요하다.

## 검토한 대안

- **gitignore** (라이브러리 패키지 관례): 소비자가 버전을 자유롭게 잡을 수 있지만, 이 패키지의 유일한 소비자가 같은 저장소의 앱이라 이점이 없다.

## 영향 범위

- `Packages/VimActionCore/Package.resolved` 신규 커밋. Yams 버전을 올릴 때는 이 파일 변경이 diff에 보인다.
- Xcode가 워크스페이스에 따로 쓰는 `VimAction.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`도 같은 근거로 커밋한다 — 로컬 패키지에 원격 의존이 생기면서 `xcodebuild build`가 자동으로 만들어내므로, 두지 않으면 모든 작업자에게 추적되지 않는 파일이 남는다.

# 설정 계층은 VimActionCore의 VimActionConfig 타깃

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

순수 설정 계층(스키마 타입·Yams 파서·3계층 병합·로더)은 `Packages/VimActionCore` 패키지의 **새 타깃 `VimActionConfig`**로 둔다. 의존은 `VimEngine`(모션 어휘) + **Yams(이 타깃에만)**. 앱 타깃은 라이브러리 제품으로 병합 결과 스냅샷을 소비하며, 설정 키 표현→`CGKeyCode` 변환·파일 감시(핫 리로드)·번들 리소스 읽기는 앱 몫이다.

## 배경·근거 (왜)

- **headless 테스트 루프**: M4 세션 A의 완료 기준이 실제 `~/.config` 접근 없는 유닛 테스트다. SPM 타깃이면 엔진과 같은 `swift test --package-path Packages/VimActionCore` 최속 루프를 그대로 쓴다 — 앱 타깃이면 `xcodebuild test`가 유일한 루프가 된다.
- **Yams 의존 격리**: "설정 파서는 Yams 단일 의존" 불변식을 타깃 경계로 강제한다. 앱 타깃에 두면 Yams가 앱 전체의 의존이 된다.
- **파싱·병합은 macOS 무관**이고, 모션 어휘(`Motion`)는 이미 순수 타깃 `VimEngine`에 있어 의존이 자연스럽다. [단일 코어 SPM 패키지 결정](20260712_single-core-spm-package.md)("순수 Swift 모듈은 VimActionCore 다중 타깃")과 정합한다.

## 검토한 대안

- **앱 타깃에 두기**: 유일한 이점은 `KeyStroke`(CGKeyCode/CGEventFlags) 직접 재사용. 그러나 설정 계층은 미지 키명 검증을 위해 플랫폼 중립 키 표현(named key + modifier set)을 어차피 갖는 편이 맞고, 앱 쪽 변환은 소형 switch 하나라 이점이 작다. 피드백 루프·의존 격리 손실이 더 크다.

## 영향 범위

- `Package.swift`에 `VimActionConfig` 타깃·제품·Yams 의존 추가 (M4 세션 A).
- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md) — 미결 질문(코드 위치) 해소.

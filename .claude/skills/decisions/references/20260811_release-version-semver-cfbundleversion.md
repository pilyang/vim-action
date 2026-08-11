# 릴리스 버전은 tag semver 하나 — CFBundleVersion까지 동일 주입

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-11

## 결정

릴리스 빌드의 버전은 tag `vX.Y.Z`에서 파생한 `X.Y.Z` **하나**만 쓴다: `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`(= `CFBundleVersion`)에 같은 값을 주입하고, 별도의 단조 증가 빌드 번호 체계를 두지 않는다. 첫 릴리스는 v0.1.0.

## 배경·근거 (왜)

- Sparkle의 버전 비교 대상(`sparkle:version`)은 `CFBundleVersion`이다 — 이 값이 릴리스마다 증가해야 업데이트가 제안된다. semver 태그는 릴리스마다 증가하므로 dotted 비교에서 그대로 단조 증가 축이 된다 — 별도 카운터(GITHUB_RUN_NUMBER 등)는 관리 포인트만 늘린다.
- 값이 하나면 About 표시·appcast·파일명이 항상 일치해 버전 드리프트 표면이 없다.

## 검토한 대안

- **`CFBundleVersion`에 별도 빌드 번호(run number 등)**: 같은 semver로 재빌드해도 구분되는 장점이 있으나, 이 프로젝트는 "같은 버전 재발행" 자체를 하지 않으므로(태그 = 릴리스) 이점이 없다. 기각.

## 영향 범위

- pbxproj의 고정값(`MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`)은 로컬/CI 빌드 전용 기본값이 된다 — 릴리스 산출물에는 들어가지 않는다.
- **수용한 엣지**: 로컬 도그푸딩 빌드(`CFBundleVersion = 1`)는 `1 > 0.x.y`라 Sparkle이 업데이트를 제안하지 않는다 — 릴리스 DMG를 한 번 수동 설치하면 그 이후부터 정상 (v0.1.0에서 실제로 그렇게 전환함).

# 릴리스는 tag push 기반 GH Actions 파이프라인

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10

## 결정

배포는 release tag(`v*`) push를 트리거로 GitHub Actions에서 빌드 → Developer ID 서명 → **공증(notarytool, CI 내 수행)** → DMG 패키징 → appcast 생성 → GitHub Release 업로드까지 자동으로 수행한다. 버전은 tag에서 파생해 빌드 시 `MARKETING_VERSION`으로 주입한다.

## 배경·근거 (왜)

- 로컬 수동 릴리스는 서명 키·공증 자격증명·Sparkle 키 3종을 손으로 다루는 절차라 실수 표면이 넓다 — 재현 가능한 단일 경로가 안전하다.
- 공증은 배포물 생성과 분리할 수 없는 단계(공증 안 된 DMG는 Gatekeeper가 차단)라 CI 안에서 같이 수행하는 것이 맞다 — 조사로 확인.
- CI 공증 자격증명은 Apple ID 암호가 아닌 **App Store Connect API 키** 방식 사용(2FA 무관, 권한 스코프 좁음).
- GH Secrets 3종: Developer ID 인증서 p12, ASC API 키, Sparkle EdDSA 개인키.
- 기존 CI 결정([20260712_github-actions-ci.md](20260712_github-actions-ci.md))의 연장 — 검증(CI)과 배포(release)를 같은 인프라에서.

## 검토한 대안

- **로컬 수동 릴리스 스크립트**: 1회성 검증(첫 서명·공증 뚫기)에는 쓰지만 정규 경로로는 기각 — 자격증명 로컬 산재 + 절차 재현성 부족.

## 영향 범위

- `.github/workflows/`에 release 워크플로우 추가 (기존 `ci.yml` 무변경).
- pbxproj의 고정 `MARKETING_VERSION`은 빌드 시 명령줄 오버라이드로 대체되는 값이 된다.
- appcast.xml 호스팅 위치 등 세부는 구현 시 확정해 별도 기록.

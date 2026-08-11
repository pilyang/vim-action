# 서명 자재가 있는 CI 잡의 외부 툴은 다이제스트/SHA 핀

- **결정일**: 2026-08-12

## 결정

릴리스 파이프라인처럼 서명 자재(Developer ID 키체인, Sparkle EdDSA 개인키, ASC API 키, tap PAT)가 살아 있는 CI 잡에서 다운로드·실행되는 외부 툴/의존은 가변 참조(태그, brew 최신)가 아니라 **콘텐츠 다이제스트(SHA-256) 또는 커밋 SHA로 고정**한다. SPM 의존성이 `Package.resolved`로 핀되는 것과 같은 원칙을 파이프라인 전체에 일관 적용한다.

## 배경·근거 (왜)

- Sparkle 배포 tarball을 curl로 받아 **검증 없이** `generate_appcast`를 실행하고 있었고, 이 바이너리에 Sparkle EdDSA **개인키**가 `--ed-key-file`로 넘어간다. 상류 침해·릴리스 자산 교체 시 앱에 핀된 `SUPublicEDKey`를 통과하는 임의 업데이트 서명이 가능 — Accessibility 권한 앱이라 업데이트 채널 탈취의 영향이 심대하다.
- 같은 레포의 SPM 경로는 이미 다이제스트로 끝까지 고정되어 있었다(`Package.resolved` revision `79bc9e87…` → 그 커밋의 Sparkle Package.swift가 binary artifact checksum 보유). 같은 통제를 파이프라인 다운로드에만 빠뜨린 불일치를 해소한 것.
- 적용 3건: ① `SPARKLE_SHA256` env + tar 전 `shasum -a 256 -c` (값은 실측 + Homebrew cask 교차 확인 `015336b6…`), ② create-dmg는 brew 대신 git clone + 커밋 SHA 체크아웃(v1.3.0 = `a2b71d0…`, 셸 스크립트라 설치 불필요), ③ `actions/checkout` 풀 커밋 SHA 핀 + Dependabot(`github-actions`, weekly)으로 bump 제안 수령.
- 부수 하드닝: Developer ID 키체인은 DMG 서명 직후 삭제한다 — 이후 스텝은 키체인이 불필요함을 스텝별로 확인(notarytool=ASC API 키 파일, generate_appcast=EdDSA 키 파일, gh·git=토큰). 마지막 `if: always()` 정리는 실패 대비 백스톱으로 유지.

## 검토한 대안

- **`brew install` 유지(무핀)**: 가변 최신 소스를 서명 자재가 있는 잡에서 실행 — 기각.
- **`hdiutil create`로 create-dmg 대체**: 서드파티 코드 0이지만 DMG Finder 레이아웃(아이콘 배치·drop-link)을 잃는다 — 기각.
- **태그 핀(`@v4`, `@v1.3.0`)**: 태그는 가변(재지정 가능)이라 콘텐츠 고정이 아니다 — 풀 SHA만 인정.

## 영향 범위

- `.github/workflows/release.yml`, `.github/workflows/ci.yml`, `.github/dependabot.yml` (신규).
- 버전 bump 절차가 생김: `SPARKLE_VERSION`을 올릴 때 `SPARKLE_SHA256`을 **실측 + 독립 소스(Homebrew cask 등) 교차 확인**으로 함께 갱신해야 한다. create-dmg·checkout SHA는 Dependabot 제안 또는 수동 재resolve.
- architecture reference 갱신 없음 — 앱 구조 무관, 빌드 파이프라인 한정.

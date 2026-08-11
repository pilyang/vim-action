# Sparkle 중첩 실행물은 파이프라인에서 재서명

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-11

## 결정

릴리스 파이프라인은 빌드 직후·DMG 패키징 전에 임베드된 `Sparkle.framework`의 중첩 실행물을 **Developer ID + hardened runtime + timestamp로 재서명**한다. 순서는 Sparkle 공식 custom signing 그대로 안쪽부터: `Downloader.xpc`(`--preserve-metadata=entitlements`) → `Installer.xpc` → `Autoupdate` → `Updater.app` → 프레임워크 → 앱 번들 씰 재생성(+ `codesign --verify --deep --strict`).

## 배경·근거 (왜)

- **v0.1.0 첫 공증이 Invalid로 거부된 실측**: SPM 바이너리 아티팩트의 중첩 실행물 4종은 **adhoc 서명 + 타임스탬프 부재** 상태로 배포되고, Xcode 임베드(빌드 시 copy-sign)는 프레임워크 껍데기만 서명할 뿐 중첩 실행물을 재서명하지 않는다. notary 로그에 "not signed with a valid Developer ID certificate" + "no secure timestamp" 16건(4컴포넌트 × 2아키텍처 × 2사유).
- 1단계 공증 성공은 Sparkle 통합 **전**이라 이 표면이 없었다 — 프레임워크 임베드가 생기는 순간부터 필수 절차.
- 같은 절차를 적용한 재서명본을 로컬에서 `notarytool` 제출해 **Apple Accepted 실증** 후 채택 (submission `c5a2cb5f`).
- `Downloader.xpc`만 entitlements 보존 — 샌드박스 엔타이틀먼트를 지닌 유일한 컴포넌트라 날리면 안 된다 (Sparkle 문서 명시).

## 검토한 대안

- **`codesign --deep`로 앱을 통째 재서명**: Apple이 배포용으로 비권장(중첩 코드의 entitlements·설정을 뭉갬). 컴포넌트별 명시 서명이 Sparkle 공식 권장 절차.
- **Xcode archive/export 경로로 전환**: export가 재서명을 처리하지만 파이프라인이 archive 구조로 커지고, 1단계에서 확정한 `build` 액션 오버라이드 체계를 버려야 한다. 기각.

## 영향 범위

- `.github/workflows/release.yml`에 "Re-sign Sparkle nested components" 스텝 추가 (PR #44).
- 로컬 도그푸딩 빌드는 재서명 없이도 동작한다(quarantine이 없어 Gatekeeper 미개입) — 공증이 필요한 배포 경로에서만 필수.
- Sparkle 버전을 올려 컴포넌트 구성이 바뀌면 이 스텝의 경로 목록도 함께 점검해야 한다.

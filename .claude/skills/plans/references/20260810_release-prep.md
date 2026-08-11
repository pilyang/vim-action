# 배포 준비 (Release Prep) — 서명·공증·Sparkle·release 자동화·Homebrew tap

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-10
- **갱신일**: 2026-08-11

## 목표

M5와 병렬로, release tag를 push하면 서명·공증된 DMG가 GitHub Release로 배포되고, 설치된 앱은 Sparkle로 자체 업데이트되며, Homebrew personal tap으로 설치 가능한 상태를 만든다.

## 완료된 것

- [x] 조사·계획 수립 (2026-08-10 세션): 순서·의존성 정리, 기본 결정 확정 (MIT 라이선스, DMG 패키징, Sparkle 2.x, Homebrew personal tap)
- [x] Apple Developer Program 가입·승인 (사용자 직접 완료)
- [x] LICENSE 파일 추가 (MIT, 2026-08-10) — 레포 루트에, 저작권자 Jaepil Yang
- [x] **1단계 — 수동 서명+공증 1회 성공** (2026-08-10): Developer ID Application 인증서 발급 → Release 빌드 명령줄 오버라이드 서명 → `notarytool` Accepted(첫 제출 ~50분 소요, 정상) → `stapler` → `spctl` "Notarized Developer ID" → `/Applications` 설치 후 Hardened Runtime 하 CGEventTap/AX 정상 동작 사용자 실증 완료. 도그푸딩 TCC cdhash 문제도 함께 해소됨
- [x] **2단계 — Sparkle 2.x 통합** (2026-08-11, 브랜치 `feat/release-sparkle-integration`, PR 머지 대기): SPM 의존성 2.9.5 고정 → `generate_keys` EdDSA 키 생성(사용자 실행) → 부분 Info.plist로 `SUPublicEDKey`·`SUFeedURL` 주입 → updater 배선(메뉴바+About 확인 버튼, General 자동 확인 토글, 시동은 bootstrap XCTest 가드 뒤). Developer ID 서명 빌드 도그푸딩으로 전 항목 정상 동작 사용자 실증 완료(피드 404 에러 처리 포함). 결정·architecture·플랜 문서 갱신 포함

## 남은 것

<!-- 다음에 할 것이 맨 위. 인계 단위(세션/마일스톤 수준)로 — 함수 단위 세부 todo는 세션 내 TodoList의 몫. -->

- [ ] **3단계 — GH Actions release 파이프라인**: tag push → 빌드·서명·공증·DMG 패키징 → `generate_appcast` → GitHub Release 업로드. GH Secrets 3개: 인증서 p12, App Store Connect API 키, Sparkle EdDSA 개인키. 버전은 tag → `MARKETING_VERSION` 주입 방식. 첫 릴리스가 나가야 앱의 업데이트 확인이 실제 데이터를 받는다(2단계의 end-to-end 검증 잔여분)
- [ ] **4단계 — Homebrew personal tap**: `pilyang/homebrew-*` 레포 + cask 파일, release 워크플로우에서 자동 bump 연결. (본진 homebrew-cask는 notability 기준 미달로 추후)

## 진행 중 컨텍스트

- M5(별도 worktree)와 병렬 트랙. 1·3·4단계는 앱 코드 무변경이라 충돌 없음.
- 레포는 public, LICENSE(MIT) 있음. 현재 pbxproj: `CODE_SIGN_STYLE = Automatic`, 팀 미지정, Hardened Runtime 미설정, entitlements 파일 없음, `MARKETING_VERSION = 1.0` 고정 — 1단계는 pbxproj 무수정, 전부 명령줄 오버라이드로 수행함.
- 1단계에서 확정된 서명 오버라이드 (3단계 CI에서 그대로 사용): `CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=X6DU3VVLRZ CODE_SIGN_IDENTITY="Developer ID Application" ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp` + `-configuration Release`. **`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`가 필수** — 기본값이 `get-task-allow`를 주입해 공증이 거부됨 (archive가 아닌 `build` 액션 한정).
- 공증 자격증명: ASC API 키 `pilyang-dev-notary` (Key ID `J25P43B5G4`, Issuer `4c66c8b6-9bec-4f18-b220-a53d27eeac23`). `.p8` 원본은 `~/.appstoreconnect/private_keys/`에 보관 (재다운로드 불가 — 3단계 GH Secret 등록 시 이 원본 사용). 로컬 제출은 키체인 프로파일 `vimaction-notary`. 키는 팀 스코프라 로컬·CI 겸용.
- 키체인에 Apple WWDR G3 중간 인증서가 없어 인증서가 전부 invalid로 보이는 문제가 있었음 — `AppleWWDRCAG3.cer` 설치로 해소 (새 머신 셋업 시 재발 가능 지점).
- appcast.xml 호스팅은 GitHub Release 자산 + `releases/latest/download/appcast.xml` 고정 URL로 확정 (decisions 기록 완료). Sparkle↔Homebrew 공존도 검증 완료 — cask에 `auto_updates true` + CI 자동 bump로 충분, 추가 기능 요구 없음.
- **Sparkle EdDSA 키** (3단계 GH Secret 등록 대상): 개인키는 이 머신 로그인 키체인의 "Private key for signing Sparkle updates" 항목 — export는 `generate_keys -x <파일>` (도구는 SPM 체크아웃 `DerivedData/.../SourcePackages/artifacts/sparkle/Sparkle/bin/`에 있음, `generate_appcast`도 같은 자리). 공개키는 `VimAction/Info.plist`에 반영 완료. 등록 전까지 백업 권장(패스워드 매니저 등).
- appcast의 `latest` 고정 URL 제약: pre-release 릴리스는 `latest`가 가리키지 않음 — 정식 릴리스만 non-prerelease로 발행 (3단계 워크플로우 설계 시 반영).
- Developer ID 서명이 되면 로컬 도그푸딩의 TCC cdhash 무효화 문제(CLAUDE.md 참고)도 함께 해소됨.
- 온보딩 페이지·landing page는 지금 하지 않기로 함.

## 관련 링크

<!-- 진행 중 내려진 결정은 여기 링크만 — 내용은 decisions 문서에. 이 문서는 삭제될 문서라 여기 적힌 결정은 함께 사라집니다. -->

- decisions: [20260810_sparkle-auto-update.md](../../decisions/references/20260810_sparkle-auto-update.md), [20260810_dmg-packaging.md](../../decisions/references/20260810_dmg-packaging.md), [20260810_homebrew-personal-tap.md](../../decisions/references/20260810_homebrew-personal-tap.md), [20260810_tag-push-release-pipeline.md](../../decisions/references/20260810_tag-push-release-pipeline.md), [20260811_sparkle-updater-ui-and-consent.md](../../decisions/references/20260811_sparkle-updater-ui-and-consent.md)

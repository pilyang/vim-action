# 자동 업데이트는 Sparkle 2.x

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10

## 결정

앱 자체 업데이트(최신 버전 확인·다운로드·교체)는 Sparkle 2.x를 SPM 의존성으로 통합해 구현한다. 업데이트 피드는 appcast.xml, 무결성은 EdDSA 서명(`SUPublicEDKey`) + Apple 코드 서명 이중 검증.

## 배경·근거 (왜)

- MAS 배포를 포기하고 직접 배포로 확정한 상태([20260712_disable-sandbox-developer-id.md](20260712_disable-sandbox-developer-id.md))라 앱 스토어의 업데이트 채널이 없다 — 자체 업데이트 메커니즘이 필수.
- Sparkle은 macOS 직접 배포 앱의 사실상 표준(수천 개 앱 사용, 활발히 유지보수)이고, 서버 없이 정적 파일(appcast.xml) 하나로 업데이트 서버를 대체한다 — 인프라 비용 0.
- 이 앱은 샌드박스 해제 상태라 Sparkle의 샌드박스용 XPC 구성이 불필요 — 통합이 가장 단순한 케이스.
- CI 도구(`generate_appcast`)가 릴리스 자동화 파이프라인([20260810_tag-push-release-pipeline.md](20260810_tag-push-release-pipeline.md))과 자연스럽게 맞물린다.

## 검토한 대안

- **자체 구현(버전 체크 + 다운로드 안내)**: 다운로드·검증·교체·재실행까지 만들면 Sparkle 재발명이고, "확인만 하고 수동 설치 유도"는 UX 후퇴. 검증된 프레임워크 대비 이점 없음.
- **Homebrew 업그레이드에만 의존**: brew 미사용 설치자(DMG 직접 다운로드)가 업데이트 채널을 잃는다. Sparkle과 brew는 공존 가능(brew cask도 앱 내 업데이트와 충돌하지 않게 `auto_updates true` 선언).

## 영향 범위

- 앱 타깃: SPM 의존성 추가, Info.plist에 `SUPublicEDKey`·`SUFeedURL`, 설정 UI에 업데이트 확인 항목.
- 첫 외부 의존은 Yams였고([20260802_package-resolved-committed.md](20260802_package-resolved-committed.md)) Sparkle이 앱 타깃의 첫 외부 의존이 된다 — 버전 고정 규칙 동일 적용.
- architecture reference 갱신은 통합 구현 PR에서 (아직 구조 변경 없음).
- EdDSA 개인키는 GH Secrets + 로컬 키체인 보관 — 유출 시 위조 업데이트 서명 가능하므로 레포에 절대 커밋 금지.

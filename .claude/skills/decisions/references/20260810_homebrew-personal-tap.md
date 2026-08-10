# Homebrew 배포는 personal tap

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10

## 결정

Homebrew 배포는 개인 tap 레포(`pilyang/homebrew-*` 네이밍)에 cask를 두는 방식으로 시작한다. 본진(homebrew-cask) 제출은 notability 기준 도달 후로 미룬다.

## 배경·근거 (왜)

- 본진 homebrew-cask는 notability 기준(대략 75 stars 또는 30 forks/watchers)이 있어 신생 앱은 수용되지 않는다 — [Acceptable Casks](https://github.com/Homebrew/brew/blob/master/docs/Acceptable-Casks.md).
- 개인 tap은 `homebrew-` 접두 레포만 만들면 심사 없이 `brew install pilyang/<tap>/<cask>` 한 줄 설치가 되고, 레포가 public이라(확인: 2026-08-10) GitHub Releases 바이너리를 그대로 소스로 쓸 수 있다.
- Homebrew 5.0부터 공증 없는 cask는 본진에서 퇴출 정책(2026-09) — 공증 파이프라인이 전제라 우리 배포물은 나중에 본진 제출 시에도 요건을 이미 충족한다.

## 검토한 대안

- **본진 homebrew-cask 즉시 제출**: notability 미달로 반려 확실. 기준 도달 시 tap → 본진 이관은 흔한 경로라 지금 tap으로 시작해도 매몰 비용 없음.
- **Homebrew 생략(DMG 직접 다운로드만)**: 개발자 타깃 앱이라 brew 설치 선호층이 핵심 사용자층과 겹침 — 채널 가치가 구성 비용(cask 파일 1개 + CI bump 자동화)을 크게 상회.

## 영향 범위

- 새 레포 1개(`pilyang/homebrew-*`), cask 파일. 릴리스 파이프라인([20260810_tag-push-release-pipeline.md](20260810_tag-push-release-pipeline.md))에서 버전·sha256 자동 bump 연결.
- 앱 코드 무변경 — architecture 갱신 없음. cask에 `auto_updates true` 선언(Sparkle과 공존).

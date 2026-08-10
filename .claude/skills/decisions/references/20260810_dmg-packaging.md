# 배포 패키징은 DMG

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10

## 결정

배포 아티팩트는 DMG(끌어넣기 설치 화면 포함)로 통일한다. Sparkle 업데이트 피드와 Homebrew cask 모두 같은 DMG를 사용한다.

## 배경·근거 (왜)

- 첫 설치 UX가 결정 축 — DMG의 Applications 끌어넣기 화면이 zip(다운로드 폴더에 앱이 풀림)보다 "제대로 된 앱" 인상을 주고, 잘못된 위치(다운로드 폴더)에서 실행되는 사고를 줄인다. 이 앱은 TCC 권한 부여가 첫 경험의 핵심이라 설치 위치가 안정적인 것이 중요하다(번역: Translocation 회피에도 유리).
- Sparkle 2와 Homebrew cask 모두 DMG를 완전 지원 — 포맷 하나로 두 채널을 커버해 파이프라인이 단일화된다.

## 검토한 대안

- **zip**: 파이프라인이 더 단순(`ditto` 한 줄)하지만 설치 UX가 없다. Sparkle 내부 업데이트 전송용으로는 zip이 미세하게 유리하나, 포맷을 채널별로 나누면 릴리스 자산·공증 대상이 늘어 관리 비용이 더 크다.

## 영향 범위

- 릴리스 파이프라인([20260810_tag-push-release-pipeline.md](20260810_tag-push-release-pipeline.md))에 DMG 생성 단계(create-dmg 류 도구) 포함, DMG 자체도 서명·공증 대상.
- 코드 무변경 — architecture 갱신 없음.

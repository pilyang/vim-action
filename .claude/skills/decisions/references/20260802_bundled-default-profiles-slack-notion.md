# 번들 기본값에 Slack·Notion 기본 프로파일 동봉

> Superseded (부분) by [20260802_bundled-defaults-seeded-not-merged.md](20260802_bundled-defaults-seeded-not-merged.md) — 번들→사용자 2계층 병합이라는 전달 방식이 파일 단위 시딩으로 뒤집힘 / Slack·Notion 프로파일 동봉과 그 근거는 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

번들 기본값 계층은 config.yaml(주력 앱 + VS Code류 off 목록)만이 아니라 **기본 프로파일(Slack·Notion)도 포함**한다. 따라서 프로파일도 **번들 기본 → 사용자 파일의 2계층 키 단위 병합**이다 — 사용자 프로파일은 번들 기본 프로파일 위에 같은 키만 재정의하며, 스칼라·리스트는 키 통째 교체라 번들 값을 되돌릴 수도 있다.

## 배경·근거 (왜)

- **M4의 목표가 Slack(Return=전송)·Notion(블록 이동 충돌) 위험 해소다** — 기본 프로파일을 동봉해야 설치 즉시 해소되고, 사용자마다 프로파일을 손으로 만들게 하면 위험이 기본 상태로 남는다.
- **문서 역할** (사용자 제안): 번들 프로파일이 실물 예시가 되어, 사용자가 다른 앱 프로파일을 작성할 때 참고할 수 있다.

## 검토한 대안

- **번들 기본값은 config.yaml만**: 병합이 단순해지지만(프로파일 사용자 단일 계층) 위 두 가치를 잃어 기각.

## 영향 범위

- M4 세션 A의 병합 설계가 프로파일 2계층 병합을 지원한다.
- 번들 프로파일의 실제 내용(Slack·Notion에 무엇을 disable·재정의할지)은 세션 B 실기기 도그푸딩으로 확정한다.
- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)

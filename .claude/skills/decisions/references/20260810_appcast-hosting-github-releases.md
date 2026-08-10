# appcast.xml 호스팅은 GitHub Releases 자산

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10

## 결정

appcast.xml은 릴리스마다 GitHub Release 자산으로 첨부하고, 앱의 `SUFeedURL`은 고정 URL `https://github.com/pilyang/vim-action/releases/latest/download/appcast.xml`을 사용한다 (`latest`가 항상 최신 릴리스 자산으로 리다이렉트).

## 배경·근거 (왜)

- `SUFeedURL`은 앱 바이너리에 박히는 고정 URL이라 영구적이면서 릴리스마다 내용이 갱신되는 위치가 필요하다.
- 릴리스 파이프라인([20260810_tag-push-release-pipeline.md](20260810_tag-push-release-pipeline.md))이 어차피 DMG를 Release 자산으로 첨부하므로, appcast도 같은 자리에 첨부하면 추가 인프라·커밋이 0이다.

## 검토한 대안

- **GitHub Pages**: CI가 Pages 브랜치에 커밋해야 함 — 릴리스가 레포 커밋을 만드는 부수 효과, 파이프라인 단계 추가. 이점 없음.
- **레포 내 파일 + raw URL**: 마찬가지로 릴리스마다 main 커밋 필요. 기각.

## 영향 범위

- Info.plist `SUFeedURL` 값, 릴리스 워크플로우의 자산 업로드 목록에 appcast.xml 추가.
- 제약: pre-release로 표시한 GitHub Release는 `latest`가 가리키지 않으므로, appcast에 실을 정식 릴리스만 non-prerelease로 발행해야 한다.

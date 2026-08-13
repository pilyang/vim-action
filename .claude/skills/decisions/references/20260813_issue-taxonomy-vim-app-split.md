# 이슈 분류 체계 — vim/app × bug/feature 4분할

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-13

## 결정

이슈 템플릿은 **vim/app × bug/feature 4종** (`.github/ISSUE_TEMPLATE/`, GitHub issue forms YAML). 각 템플릿이 라벨을 자동 부착한다: 기본 `bug`/`enhancement` + 신설 `area:vim`(Vim 동작: 모션·액션·모드·텍스트 오브젝트) / `area:app`(앱 셸: 설정·메뉴바·권한·설정 파일·업데이트). Vim 계열 템플릿에는 발생 앱(버그) / 대상 앱(기능 요청) 필드를 둔다. blank issue는 허용 유지(config.yml 없음).

## 배경·근거 (왜)

- 이 프로젝트의 이슈는 자연스럽게 두 축으로 갈린다 — Vim 동작(엔진·어휘·앱별 대응)과 앱 셸(설정·메뉴바·권한·업데이트). 담당 코드 영역과 트리아지 방식이 달라 라벨로 자동 분류되는 것이 유용하다.
- 계열마다 actionable한 리포트에 필요한 필드가 다르다: Vim 버그는 앱·키 시퀀스·모드·키보드 레이아웃(Unicode Hex Input 알려진 한계)이 핵심이고, 앱 버그는 재현 절차가 핵심이다. GitHub issue forms는 조건부 필드가 없어, 템플릿을 나눠야 각 폼의 필수 필드를 강제할 수 있다.
- Vim 기능 요청 템플릿에는 KEYBINDINGS.md(계획·out-of-scope 목록) 선확인 안내를 넣어 중복·범위 밖 요청을 셀프 필터링한다.
- 라벨은 area 2종 최소로 시작 — 앱별 라벨(`app:notion` 등)은 특정 앱 이슈가 쌓이면 그때 ad hoc으로 추가한다.

## 검토한 대안

- **2종 템플릿(bug/feature) + 카테고리 드롭다운**: 기각 — 드롭다운으로는 계열별 필수 필드를 강제할 수 없어 폼이 어느 쪽 계열에도 느슨해진다.
- **blank issue 차단(config.yml)**: 기각 — 질문 등 4분류에 안 들어가는 이슈가 갈 곳이 없어진다.

## 영향 범위

- `.github/ISSUE_TEMPLATE/1-vim-bug.yml` · `2-app-bug.yml` · `3-vim-feature.yml` · `4-app-feature.yml` (신규), GitHub 라벨 `area:vim`·`area:app` (신설).
- 정책 차원(이슈 우선·PR 사전 논의)은 별도 결정: [20260813_external-contribution-policy.md](20260813_external-contribution-policy.md).
- architecture reference 갱신 없음 (코드 구조 무관).

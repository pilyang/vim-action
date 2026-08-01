# D/C 어휘 추가 — d$/c$ 축약, 카운트는 invalid

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

Normal 최상위에 `D`/`C`를 추가한다 — `d$`/`c$`와 **동일 출력**(`.edit(.delete/.change, .motion(.lineEnd, count: 1))`)으로 즉시 완결하며, `C`의 Insert 전이는 기존 `complete` 헬퍼가 담당한다. 카운트가 하나라도 있으면(`3D`/`3C`) invalid다. Visual의 `D`/`C`는 v1 어휘 밖 — 미매핑 swallow 유지(명시적 non-goal).

## 배경·근거 (왜)

`D`/`C`는 커서부터 줄 끝까지 삭제/change하는 고빈도 Vim 키인데 미매핑 swallow(죽은 키)였다 — M3 단계 4 게이트 전에 어휘를 확정하는 선행 작업의 일부다. `d$`/`c$`가 이미 완전 실행되므로(`$`는 `opMotions` charwise 화이트리스트, `EditKeyMapper`의 `.motion` 케이스가 `.lineEnd` 처리) 동일 출력 축약으로 두면 **어댑터·골든·게시 인프라 무변경**으로 성립한다. `cw` 특례는 `wordForward`에만 걸려 `C`(lineEnd)와 충돌하지 않는다.

카운트 invalid의 근거는 파괴적 편집 원칙이다: Vim의 `3D`는 "줄 끝 + 아래 2줄"이라는 복합 의미인데 현재 출력 형태로 표현할 수 없다 — 파괴적 편집은 오해석 대신 invalid로 이연한다 (`d3G`·`d2i(`와 같은 기준, [20260719_linewise-textrange-absolute-count-invalid.md](20260719_linewise-textrange-absolute-count-invalid.md)).

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md) (구현된 키셋)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `step` 최상위 switch
- 픽스처: `EditFixtures.swift` (D/C 완결·전이·카운트 invalid·op-대기 중 invalid)
- 어댑터 무변경 — `EditKeyMapper` 등 소비자는 기존 `d$`/`c$` 경로를 그대로 탄다

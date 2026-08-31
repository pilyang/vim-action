# 편집 그룹도 스트로크 페이싱 — 단일 청크 한정

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-31

## 결정

keyboard 편집 그룹(`classifyEdit`의 `.groups`)을 **단일 청크(≤ `chunkStrokes` = 8타)에 담기는
경우에 한해** 페이싱 대상(`paced: true`)에 넣는다 — 판정은 순수 함수
`KeyboardAdapter.editGroupPaced(strokeCount:)` 하나다. 카운트 버스트(`500x` = 501타 단일
그룹)는 "카운트 버스트·스크롤 타이밍 현행 유지" 제약대로 페이싱 밖에 남고, 하이브리드
위임분(`[Cmd-X]`/`[Cmd-C, ←]` — 접두가 AX 쓰기 + 되읽어 검증이라 버스트 취약 축이 없다)과
`.edit(_, .selection)` 1타 그룹(게시 쪽 "2타 미만은 일반 경로" 규칙)도 현행 그대로다.

## 배경·근거 (왜)

`Y`(=`y$`) 도그푸딩 실측: Notion에서 `y$`/`Y`가 커서 오른쪽이 아니라 **줄 전체를 복사**했다
(Apple Notes는 정상). 판별 실측 2건 — ① `y$`도 동일 재현(Y 매핑 무관), ② 손 입력
`Shift-Cmd-→` → `Cmd-C`는 정상 — 으로 시맨틱 충돌이 아니라 **간격 문제로 확정**됐다.
재앵커([20260805](20260805_visual-refined-group-stroke-pacing.md))·paste
접두([20260806](20260806_paste-groups-stroke-pacing.md))와 같은 약점·같은 대응이다.

메커니즘: 편집 그룹은 오퍼레이터의 의미가 직전 선택 스트로크의 착지에 의존하는 형태인데
(`[Shift-Cmd-→, Cmd-C, ←]`), 0간격 버스트에서 선택이 착지하기 전에 `Cmd-C`가 처리되면
Notion의 **"선택 없는 `Cmd-C` = 블록 전체 복사"** 자체 의미론이 발동한다. 같은 축이
`d$`/`c$`(`D`/`C`)에서는 **블록 전체 잘라내기라 파괴적**이다 — 수용이 아니라 수정 대상.

이는 20260805의 "무상태 다타(`dd` 3타 등)는 Notion 포함 실사용에서 드롭이 관측된 적 없어
페이싱하지 않는다" 전제의 **첫 반례**다. 관측 공백의 이유도 설명된다 — linewise 편집
(`yy`/`dd`)에서는 선택이 유실돼도 블록 전체 복사/잘라내기가 의도 결과와 거의 같아 증상이
가려졌고, charwise mid-line yank(`y$`)가 처음으로 가시화했다.

경계를 청크 폭으로 한정한 이유: 그룹 전체 무조건 페이싱은 `500x`가 501타 × 5ms ≈ 2.5s로
기존 제약과 정면 충돌한다. 청크 폭 재사용은 무상태 편집 시퀀스 전부(최대 5~6타)를 덮으면서
비용 상한이 7 × 5ms = 35ms이고, 임의 상수를 새로 만들지 않는다. 경계 밖(9타 이상 —
카운트 곱 편집)은 무페이싱 = 현행 동작이라 회귀 방향이 없다.

## 검토한 대안

- **오퍼레이터 경계만 페이싱(suffix)**: 카운트 무관 균일하지만 `Mapping`에 suffix 표현을
  신설해야 하고, `dd`/`yy`의 이질적 선택 접두(collapse → 이동 → Shift 확장 — 20260805가
  실측한 실패 형태 그대로)는 미방어로 남는다. 기존 paced 기계 재사용이 더 작고 넓다.
- **Notion 프로파일 한정 적용**: 페이싱은 프로파일 어휘가 아니고, 20260805·20260806 선례가
  전역 적용이다(수 타 × 5ms는 어디서나 무해).
- **앱 시맨틱 수용**: `D`/`C`의 블록 잘라내기라는 파괴 축이 있어 불가.

## 영향 범위

- `VimAction/KeyboardAdapter.swift`: `classifyEdit`의 `paced` 판정, `editGroupPaced` 신설,
  `Mapping.groups`·`pacedStrokeInterval`·하이브리드 위임분 주석 갱신
- 테스트: `KeyboardAdapterEditPacingTests` (경계표 + 페이싱 게시 배선의 경과 시간 하한 단언)
- 갱신한 architecture reference: [keyboard-adapter.md](../../architecture/references/keyboard-adapter.md)

## Supersedes

- [20260805_visual-refined-group-stroke-pacing.md](20260805_visual-refined-group-stroke-pacing.md)
  **부분** — "무상태 다타는 드롭 미관측이라 페이싱하지 않는다" 문언에 편집 그룹이 반례로
  추가된다. 5ms 상수·정확화 그룹 페이싱·스크롤/카운트 버스트 타이밍 현행 유지 원칙은 유효.

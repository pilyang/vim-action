# 프로파일 모션 재정의는 AX보다 우선 — 항목이 있으면 그 모션은 keyboard 경로

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1a 세션 2, 구현 수준 판단)

## 결정

`strategy: accessibility` 앱이라도 **그 프로파일의 `motions:`에 항목이 있으면 그 모션은 keyboard 경로**로 간다. 재정의(`strokes`)든 `disabled`든 같다.

술어는 하나다 — `profile.motionOverrides[motion] == nil`이 AX 실행 계획의 조건 중 하나이며, 걸리면 기존 `classify` 경로가 그대로 돌아 재정의는 그 시퀀스를 내고 disable은 `.disabledByProfile`로 정직하게 집계된다.

## 배경·근거 (왜)

- 위임 표([20260808_ax-delegation-table-single-driver.md](20260808_ax-delegation-table-single-driver.md))는 `actions:` 훅만 다뤘다("AX 행은 문자 키를 안 쓰므로 해당 없음") — `motions:`는 언급이 없어 구현 시점에 정해야 했다.
- **재정의의 의미가 "이 앱에서 이 모션을 달성하는 방법"이다** ([20260801_profile-motion-override-unit.md](20260801_profile-motion-override-unit.md)). 사용자가 그것을 적는 이유는 대개 그 앱의 고유 사정(Notion `Shift-Cmd-↑` 충돌 회피처럼 "이 키를 쓰지 마라")이고, AX가 조용히 덮어쓰면 그 지시가 **반증 불가능하게** 무시된다 — 파일에 적었는데 아무 로그도 없이 다른 일이 일어난다.
- 스크롤 사다리가 이미 같은 우선순위를 세워 뒀다: **프로파일 명시값 > AX 정확값 > 코드 상수** ([20260806_scroll-line-count-priority-ladder.md](20260806_scroll-line-count-priority-ladder.md)). 새 규칙이 아니라 그 규칙을 모션 축으로 옮긴 것이다.
- disable을 같은 술어로 접는 것이 부수 이득이다. 별도 분기를 두면 AX 경로에서 disable이 "미지원 스킵"으로 잘못 집계될 수 있는데, 기존 경로로 보내면 `.disabledByProfile` 버킷이 공짜로 유지된다 — "사용자 설정이 만든 무동작을 버그로 읽지 않게" 라는 기존 계약이 그대로 산다.
- 비용은 사실상 0이다. 재정의를 적는 앱은 드물고, 적은 모션 하나만 현행 경로로 떨어진다(액션 단위 all-or-nothing이라 나머지 모션은 계속 AX다).

## 검토한 대안

- **disable만 존중, `strokes` 재정의는 AX가 무시**: "AX는 오프셋 대입이라 스트로크 재정의가 원리적으로 의미 없다"는 논리는 성립하지만, 사용자가 재정의를 적는 실제 동기(그 앱에서 그 키를 피한다)가 무시된다. 실패 방향이 "적었는데 조용히 안 먹는다"라 나쁘다.
- **AX가 항상 우선**: 가장 단순하고 AX 표본도 늘지만, 위와 같은 이유로 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `KeyboardAdapter.usesAXCaretWrite` — 위임 표의 단일 판정 지점이며, D1b에서 편집·Visual로 넓어질 때 같은 규칙을 승계한다.

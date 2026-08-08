# linewise는 시각 줄 단위 — 소프트 랩 문단 수용 엣지

> Superseded (부분) by [20260808_ax-offset-layer-window-logical-lines.md](20260808_ax-offset-layer-window-logical-lines.md) — AX 전략 경로에서는 논리 줄로 해소(D1b 구현 시 발효) / keyboard 경로의 시각 줄 수용은 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-28

## 결정

linewise 시퀀스가 쓰는 `Cmd-←`·`↓`·`Shift-↓`는 macOS 표준 텍스트 시스템에서 논리 줄(문단)이 아니라 **시각(wrap) 줄** 단위다. 따라서 워드랩된 긴 문단(한 논리 줄이 화면 여러 행으로 접힌 상태)에서 `dd`/`cc`/`yy`/`dj`/`dk`는 문단 전체가 아니라 **화면 행 단위**로 동작한다 — 이를 수용 엣지로 확정한다(코드 무변경). 랩이 없는 텍스트에서는 시각 줄 = 논리 줄이라 정확하다.

발견 경로: 2026-07-28 코드 리뷰 트리아지. 단계 1 도그푸딩이 짧은 줄 위주라 드러나지 않았고, 기존 linewise 수용 엣지 목록([linewise 반올림](20260727_linewise-newline-rounding.md))에 랩 케이스가 빠져 있었다.

## 배경·근거 (왜)

Vim의 `dd`는 논리 줄 삭제이므로 랩 문단에서는 문단 통째 삭제가 기대 동작이다. 그러나 캐럿 이동 바인딩 중 화살표 계열은 전부 시각 줄 기준이고, Keyboard 전략은 무상태라 "지금 랩 안인가"를 감지할 수 없다. Notion·워드랩 에디터의 긴 문단에서 실사용 위화감이 있을 수 있으나, 대안(아래) 없이는 고정 시퀀스로 해결이 불가능하다.

## 검토한 대안

- **문단 바인딩으로 재구성**(`Ctrl-A`/`Opt-↓` 계열 — Cocoa 표준의 moveToBeginningOfParagraph/moveToEndOfParagraph): 성립하면 근본 해결이지만, ① Electron·Notion 등 비-Cocoa 앱의 지원 여부가 미검증이고 ② 합성 Ctrl 계열은 시스템 단축키 인접 리스크가 있다(w 3타 결정에서 `Ctrl-←`를 Spaces 충돌로 기각한 선례). **백로그로 이연** — 도그푸딩에서 랩 문단 편집이 실제로 아프면 앱별 실측 후 별도 결정으로 재개(이 문서를 supersede).
- **수용하되 기록 없음**: 랩 문단은 Notion 등 주력 앱의 일상 상태라 재발견이 확실. 기각.

## 영향 범위

- 코드 무변경. 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 도그푸딩 시 버그로 오인 금지 — 랩 문단에서 `dd`가 "문단 중간을 뜯는" 현상은 이 엣지다
- M5 AX에서 논리 줄 오프셋 계산으로 자연 해소
- 경계 포화 5종은 뿌리가 달라 별도 결정: [20260728_edit-boundary-saturation-accepted-edges.md](20260728_edit-boundary-saturation-accepted-edges.md)

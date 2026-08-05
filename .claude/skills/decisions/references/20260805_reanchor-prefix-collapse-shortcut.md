# 재앵커 접두는 collapse 1타로 단축

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-05

## 결정

재앵커 접두를 collapse **1타**로 단축한다: charwise 진입형의 `←,→` 2타 → `→` 1타(선택 위 `→`는 오른쪽 끝으로 collapse — 원래 시퀀스와 동치), linewise `Vk`류의 `←,↓` 2타 → `→` 1타(d = 0에서 선택 오른쪽 끝 = 앵커 줄 끝 다음 = 재앵커 목표점이라 동치).

동치 조건은 **"선택이 존재하는" 상태**이며, 코드 경로가 이를 보장한다: 재앵커 분기는 자가 검증(선택 비어 있지 않음 포함)을 통과한 세션 상태에서만 도달한다. linewise 쪽은 추가로 오른쪽 끝이 줄 시작(열 0)임을 창에서 증명할 때만 재앵커한다(`selectionEndIsAtLineStart`) — 개행 없는 마지막 줄에서 `Shift-↑`가 열을 끌고 올라가는 부분 선택을 막고, 그 증명이 서면 `→` 착지가 `←,↓`와 동치임도 함께 선다. 단축이 성립하지 않는 자리(`Vgg` 전진형 — 오른쪽 끝이 포커스 쪽이라 앵커 줄 끝이 아님)는 `←,↓`를 유지한다.

**동치가 깨지는 앱이 발견되면 2타로 되돌린다** — 도그푸딩(특히 Notion)에서 확인한다.

## 배경·근거 (왜)

세션 1 도그푸딩의 방향 논의에서 "시퀀스 경량화를 원칙으로 승격하지 않되, **동치 시퀀스면 짧은 쪽을 선호**"로 정리됐다. 재앵커 접두는 그 직접 적용이다: `←`(왼쪽 끝 collapse) 후 `→`(한 칸 전진)의 착지는, 선택이 살아 있는 한 `→`(오른쪽 끝 collapse) 1타의 착지와 같다. 버스트 드롭(페이싱 결정 참조)의 원인은 간격이지 길이가 아니지만, 타수가 줄면 페이싱 총 지연도 함께 준다(4타→3타 = 간격 1회 절약).

## 검토한 대안

- **`←,→` 2타 유지**: macOS collapse 시맨틱에 대한 가정이 한 겹 적지만(왼쪽 collapse + 캐럿 전진), 선택 위 `→`의 오른쪽 끝 collapse는 같은 결정 계열(`clearSelection`의 `←`)이 이미 딛는 표준 동작이다. 동치가 깨지는 앱이 나오면 이 대안으로 복귀한다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/VisualKeyMapper.swift` 재앵커 분기(`charLeftRefinement`·`wordBackwardRefinement`·`lineUpRefinement`)
- 관련: [재앵커](20260804_visual-backward-keyboard-reanchor.md)(대표 시퀀스 표의 `←,→`·`←,↓` 접두를 이 결정이 단축), [페이싱](20260805_visual-refined-group-stroke-pacing.md)

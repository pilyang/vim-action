# Visual y 완결 시 clearSelection 동반 출력

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-23

## 결정

Visual의 `y`는 `.replace([.edit(.yank, .selection), .clearSelection])`로 완결한다 — 복사 후 화면 선택의 collapse를 엔진 출력에 명시한다 (순서는 배열이 보장: 복사가 먼저). **collapse 목적지(Vim은 선택 시작점)는 어댑터 실행 규칙**으로 위임한다 — linewise 줄 반올림과 같은, 텍스트를 아는 계층의 몫.

`d`/`x`/`c`는 `clearSelection`을 동반하지 않는다 (의도적 비대칭): 범위 삭제로 화면 하이라이트가 자연 소멸하고, 어댑터의 세션 장부는 begin-리셋 계약([20260723_visual-begin-reset-switch-wise-split.md](20260723_visual-begin-reset-switch-wise-split.md))이 자가 치유하므로 별도 신호가 필요 없다. y만 텍스트가 남아 화면 잔류물이 생긴다.

## 배경·근거 (왜)

코드리뷰 F1: `v w y` 후 엔진은 Normal인데 화면 선택이 살아남아, 다음 입력(Insert 진입 후 타이핑 등)의 첫 글자가 방금 복사한 영역을 대체한다. Vim은 y 후 선택을 collapse한다. 이 collapse를 어댑터 문서 규칙으로 둘 수도 있었지만, 원 출력 계약이 진입·이탈 암묵 규약안을 기각한 근거("타입에 없는 규약이 어댑터 구현자 머리에만 쌓이고, 어댑터 2종이라 불일치 리스크 ×2")가 그대로 적용된다 — 엔진 출력에 실어야 픽스처로 고정되고 어댑터 간 불일치가 원천 차단된다.

## 검토한 대안

- **어댑터 실행 규칙으로 문서화** (`strategy-dispatch.md`에 "yank(.selection) 후 collapse" 명시): 코드 무변경이지만 픽스처 검증 불가, 어댑터 2종의 암묵 규약 증식 — 원 계약이 같은 이유로 기각한 패턴. 기각.
- **d/x/c에도 일괄 동반** (세션 종료 신호 단일화): 화면에 지울 선택이 없는 no-op 신호가 늘고, begin-리셋 계약으로 장부 정리는 이미 보장되므로 실익 없음. 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `VimEngine.swift`(`visualStep` yank 분기), `VisualFixtures.swift`(y 픽스처 2개).
- 어댑터 계약(향후 구현 시): `clearSelection`의 collapse 목적지는 어댑터가 정한다 (Vim 참고: y는 선택 시작점).

## Supersedes

- [20260722_visual-mode-output-contract.md](20260722_visual-mode-output-contract.md)의 **일부** — "Visual의 `y d x c`는 `.edit(Operator, .selection)`으로 낸다" 중 y의 출력 형태만 이 문서가 대체한다. 옛 문서는 다른 유효 계약이 남아 인덱스에 유지.

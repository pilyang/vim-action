> Superseded by [20260801_release-block-gate-lifted.md](20260801_release-block-gate-lifted.md)

# 릴리스 배포 금지 게이트는 M3(편집 실행)로 이동

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

**릴리스 배포 금지는 유지하고, 해제 게이트를 "디스패처 마일스톤 완료"에서 "M3(편집 실행) 완료"로 옮긴다.**

M2로 `.replace`의 무실행 삼킴은 없어졌지만 **이동 계열만** 실행된다. 어댑터는 `.move`만 CGEvent로 바꾸고 편집·Visual·붙여넣기·스크롤·undo는 스킵+DEBUG 로그이므로(미지원≠실패), 릴리스 빌드에서는 그 키들이 **여전히 아무 관측 흔적 없이 삼켜진다** — 원래 이 규칙이 막으려던 "죽은 키"가 그대로 남아 있다.

`.replace` 분기의 DEBUG 요약 로그(개수 + 첫 action 1개)는 그대로 유지한다. 카운트 반복으로 actions가 최대 9,999개까지 나오므로 콜백 안에서 순회 로그를 남기면 탭 콜백 타임아웃을 유발하고, passthrough까지 로그하면 키로거가 된다 — 요약 1건·DEBUG 전용은 그 두 제약의 결과이며 배선 이후에도 유효하다. 실제 용도가 하나 늘었다: 어댑터의 "미지원 액션 스킵" 요약과 대조하면 배선 문제와 매핑 문제를 가를 수 있어, M2 도그푸딩 판정을 이 두 로그로 했다.

`switch`에 `default`를 두지 않고 `String(describing:)`으로 찍는 형태도 유지한다 — `VimAction` 케이스 추가가 앱 계층 빌드를 깨지 않게 하는 소비자 non-exhaustive 계약이다.

## 배경·근거 (왜)

원 규칙의 게이트("디스패처 마일스톤 완료")는 실행 계층이 하나의 마일스톤으로 들어온다는 전제에서 쓰였다. 실제 진행은 keyboard-first 순서로 쪼개졌고([20260725_keyboard-first-mvp-build-order.md](20260725_keyboard-first-mvp-build-order.md)) M2는 모션만, M3가 편집을 맡는다. 그래서 "디스패처가 붙었는가"는 더 이상 사용자 경험을 가르는 선이 아니다 — 가르는 선은 **삼킨 키가 전부 실행되는가**이고, 그것이 M3다.

M2 시점에서 배포하면 사용자는 이동만 되는 상태에서 `dd`·`x`·`p`가 조용히 사라지는 것을 본다. 모션이 동작하는 만큼 오히려 "동작하는 앱"으로 오해되기 쉬워, 무실행 삼킴 시절보다 나을 것이 없다.

## 검토한 대안

- **M2로 규칙 해제**: 위 이유로 기각 — 편집 키의 무로그 삼킴이 남는다.
- **미지원 액션을 릴리스에서도 로그**: 릴리스 로그에 사용자 입력 유래 정보를 남기는 방향이라 키로거 우려를 다시 불러온다. 사용자 피드백이 필요하면 로그가 아니라 UI(메뉴바·Settings)가 옳은 채널이다. 기각.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (과도기 문단 — 배포 금지 게이트가 M3)
- 배포 게이트: **M3 완료 전 릴리스 배포 금지** (M6 서명·공증 배포 플랜의 선행 조건).
- 코드 변경 없음 — `.replace` 분기의 로그 형태는 그대로다.
- 관련 결정: [20260726_unsupported-action-not-failure.md](20260726_unsupported-action-not-failure.md)(편집 키가 스킵되는 근거), [20260726_m2-execution-wiring-shape.md](20260726_m2-execution-wiring-shape.md)(모션 실행 배선).

## Supersedes

- [20260717_replace-swallow-transitional-rule.md](20260717_replace-swallow-transitional-rule.md) — `.replace`를 실행 없이 삼킨다는 과도기 동작이 사실이 아니게 됐고, 배포 게이트도 이 문서가 다시 정한다. 아직 유효했던 근거(요약 1건 로그, DEBUG 전용, non-exhaustive switch)는 위 "결정"에 승계해 적었다.

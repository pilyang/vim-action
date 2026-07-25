# MVP 빌드 순서 — Keyboard 전략 베이스 우선, AX는 이후 확장

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-25

## 결정

실행 계층(어댑터)의 구축 순서를 **Keyboard 전략(key-mapping) 먼저**로 확정한다. MVP 1단계는 Keyboard 어댑터만으로 완성하고, Accessibility 어댑터 + `auto` 전략은 MVP 이후 1차 확장으로 미룬다. 그동안(MVP 구간) 번들 기본 전략은 `keyboard` 고정이다.

**전략 디스패치의 최종 구조는 불변**이다 — 이중 전략, `auto` 프로브 → keyboard 폴백, force-text 명시 선택 전용은 [20260712 결정](20260712_ax-keyboard-strategy-dispatch.md) 그대로이며, 이 결정은 빌드 순서와 과도기 기본값만 정한다 (supersede 아님).

## 배경·근거 (왜)

- 1차 사용자(작성자)의 주력 앱이 Electron 기반 — AX-first로 가면 정작 주력 앱에서 도그푸딩이 시작되지 않는다. Keyboard 방식은 Notes 등 일반 앱에서도 상당 수준 동작할 것으로 예상되어, **"먼저 어디서든 돌아가는 베이스"로 적합**하다.
- AX는 잘 만들어진 앱에서 더 정밀한(클립보드 오염 없는) 대응을 주는 **품질 향상 계층**으로 이후에 얹는 것이 첫 사용 가능 시점을 앞당긴다.
- 파생 효과 — 리졸버 해체: 단일 선행 마일스톤이던 포커스/컨텍스트 리졸버가 필요 시점별로 쪼개진다. 앱 수준(bundleID, NSWorkspace)은 모션 마일스톤에, 요소 수준(AXObserver + focusedRole 캐시)은 편집 마일스톤에, AX 프로브는 AX 확장 마일스톤에 붙는다.
- 파생 효과 — [콜백 경량 불변식](20260725_callback-light-invariant.md)이 위임한 검증의 시점 재배치: ① `AXUIElementSetMessagingTimeout` 실기기 계측은 AX 프로브가 실제로 들어오는 AX 확장 마일스톤으로, ② 삼킴/통과 판정의 캐시 충분성은 요소 캐시가 생기는 편집 마일스톤(1차)과 per_element 스키마가 들어오는 프로파일 마일스톤(최종)으로.

## 검토한 대안

- **AX-first (원래 PRD Stage 1~2 순서)**: AX 신뢰 앱(Notes/Mail)에서 정밀 실행을 먼저 확보하는 경로. 주력 앱이 Electron이라 도그푸딩 개시가 Keyboard 어댑터 완성까지 밀리고, 그 사이 실사용 피드백이 없다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (과도기 상태 — 번들 기본 전략 keyboard 명시)
- MVP 마일스톤 플랜 (plans `20260725_mvp-milestones.md`) 의 M1~M5 순서가 이 결정 위에 서 있다.
- Keyboard 어댑터의 알려진 트레이드오프(수용): delete 계열이 Cmd-X 경유라 클립보드를 덮음 — v1 "레지스터 없음, 시스템 클립보드 위임" 결정과 정합. 합성 시퀀스의 undo 단위 쪼개짐 가능성은 편집 마일스톤에서 실측·수용 여부 확인.

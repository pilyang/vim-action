# 킬스위치 탭은 전용 스레드 + 자체 CFRunLoop — 메인 런루프 유지 결정의 범위는 메인 탭 한정

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

안전장치 킬스위치 탭(`KillSwitchTap`)의 run-loop 소스는 **전용 `Thread` + 자체 `CFRunLoop`** 에 부착한다. 동시에, [20260725_tap-main-runloop-retention](20260725_tap-main-runloop-retention.md)의 "메인 런루프 유지" 결정의 **적용 범위가 엔진이 붙은 메인 탭 한정**임을 명시한다 — 두 탭은 같은 규칙을 따르지 않는다.

## 배경·근거 (왜)

킬스위치의 존재 이유는 "메인 탭이나 메인 스레드가 망가져도 가로채기를 끌 수 있다"이다. 소스를 메인 런루프에 붙이면 메인 스톨 중에 콜백이 배달되지 않아 그 존재 이유가 그대로 무너진다 — 메인 탭과 함께 죽는 킬스위치는 [20260712_synthetic-event-marker-and-failsafe](20260712_synthetic-event-marker-and-failsafe.md)가 "별도 탭이어야 한다"고 기각한 구조와 실질적으로 같아진다.

메인 탭의 유지 결정을 지탱한 근거 넷은 이 탭에 하나도 성립하지 않는다:

1. **"OS 탭 타임아웃은 스레드와 무관"** — 맞지만, 킬 탭이 고치려는 문제는 타임아웃이 아니라 **콜백 배달 자체의 정지**다. 처방이 겨누는 문제가 다르다.
2. **"무관한 메인 스톨은 희귀하고 실측 0건"** — 희귀한 사건에 대비하는 것이 안전장치의 정의다. 빈도는 안전장치의 가치를 낮추지 않는다.
3. **"실패 모드가 양성 degrade"** — 메인 탭은 꺼져도 키가 통과되므로 양성이지만, 킬스위치는 꺼지면 **탈출 경로 자체가 사라진다**. degrade 수용 논거가 성립하지 않는다.
4. **"전환 비용이 크다"(assumeIsolated 제거의 nonisolated 연쇄, TIS 프리웜, 토글 didSet 메인 고정, 관찰 프로퍼티 원자 미러)** — 전부 엔진·SwiftUI·KeyTranslator 결합에서 나온 비용이다. 킬 탭 콜백은 `(keycode, flags)` 비교와 잠금 상자 읽기뿐이라 그 결합이 0이고, 애초에 `MainActor.assumeIsolated`를 쓰지 않으므로 제거할 연쇄가 없다.

실기기 확인(2026-07-26)에서 발동 로그의 스레드 ID가 실제로 갈렸다: 콤보 감지·발동은 킬 전용 스레드, 이후 off 처리는 메인. 구조가 의도대로 두 스레드에 나뉘어 있음이 실측으로 확인됐다.

## 검토한 대안

- **메인 런루프 부착(메인 탭과 동일)**: 코드가 단순하고 기존 `assumeIsolated` 패턴을 재사용할 수 있으나, 메인 스톨 중 발동이 구조적으로 불가능해진다. 안전장치의 유일한 요구를 못 지키므로 기각.
- **전용 워치독으로 킬 탭 헬스 폴링**: 메인 탭이 워치독을 필요로 한 이유는 "스톨로 `tapDisabledBy*` 통지 자체가 유실되는" 실패 모드인데, 자체 런루프에서 도는 경량 콜백은 그 상황에 놓이지 않는다. 없는 실패 모드에 폴링을 다는 과잉 방어라 기각 — 콜백 안의 자체 재활성화만 둔다.

## 영향 범위

- 신설 코드: `VimAction/KillSwitchTap.swift`(전용 스레드 기동, 자체 콜백), `VimAction/TapPortBox.swift`(포트 참조를 스레드 간에 넘기는 잠금 상자)
- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md), [system-overview.md](../../architecture/references/system-overview.md)
- [20260725_tap-main-runloop-retention.md](20260725_tap-main-runloop-retention.md)는 **supersede하지 않는다** — 그 결정과 재검토 트리거는 메인 탭에 대해 그대로 유효하고, 이 문서는 그 범위 경계를 명시할 뿐이다.

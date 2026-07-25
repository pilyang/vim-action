# 예외 폭주 자동 off의 형태 — 순수 카운터 + 기존 소프트 off 재사용

- **결정일**: 2026-07-25

## 결정

실행 실패 폭주 감지를 다음 형태로 고정한다.

1. **판정은 시간을 주입받는 순수 타입** `FailureBurstCounter` — 슬라이딩 창(기본 1초) 안 보고 수가 임계(기본 5)에 닿으면 트립. 창·임계는 조정 가능한 상수로 두되 기본값을 채택한다.
2. **트립하면 창을 비운다** — 비우지 않으면 트립 후 들어오는 보고마다 같은 이력으로 재트립한다.
3. **트립의 효과는 `isInterceptionEnabled = false` 대입뿐** — 새 off 경로를 만들지 않는다. 사용자 알림도 그 didSet이 만드는 메뉴바 글리프 변화 + `Logger.eventTap.fault` 1건이 전부다.
4. 카운터는 컨트롤러의 MainActor 격리 안에서만 쓴다 — 별도 잠금·큐를 두지 않는다.

## 배경·근거 (왜)

`isInterceptionEnabled`의 didSet은 이미 엔진 Insert 리셋 · 워치독 정지 · 탭 비활성 · in-flight 틱 경합 봉인 · 영속 · 메뉴바 반영을 한 자리에서 책임진다. 자동 off가 별도 경로를 만들면 이 여섯 가지를 두 곳에서 유지해야 하고, 어긋나는 순간 "꺼졌다고 표시되는데 탭은 살아 있는" 부류의 버그가 된다. 자동이든 수동이든 off의 의미론은 하나여야 한다.

판정을 순수 타입으로 분리한 이유는 `watchdogTick`과 같다 — 실제 시계를 기다리는 테스트는 느리고 불안정하다. 시간 주입으로 창 경계(1초 정확히 지난 보고의 만료)를 결정적으로 검증한다.

알림을 메뉴바 + 로그로 제한한 것은 새 알림 프레임워크·TCC 권한을 들이지 않기 위해서다. 자동 off는 가로채기가 멈추는 사용자 가시 전이라 글리프 변화만으로도 관측 가능하다.

## 검토한 대안

- **트립 후 창 유지**: 임계를 넘긴 뒤 들어오는 보고마다 다시 트립해 로그가 도배되고, off→on 복귀 직후 낡은 이력으로 즉시 재차 off된다.
- **자동 off 전용 경로(탭 직접 disable 등)**: 위의 didSet 책임 여섯 가지를 복제하게 된다.
- **`Date`/실시계 직접 사용**: 시스템 시계 조정에 흔들리고 테스트가 시계를 기다려야 한다. 프로덕션은 단조 증가하는 `systemUptime`을 기본 인자로 쓴다.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 코드: `VimAction/FailureBurstCounter.swift`(신설), `EventTapController.reportExecutionFailure`
- **후속 마일스톤 계약**: 실행 계층(Keyboard 어댑터)의 실패 지점들은 이 `reportExecutionFailure`로 모인다. 현재는 엔진이 throw하지 않고 어댑터도 없어 호출자가 없다 — 존재하지 않는 오류원을 억지로 감싸지 않는다.
- 관련 결정: [20260718_interception-toggle-semantics.md](20260718_interception-toggle-semantics.md)(재사용하는 소프트 off 경로), [20260712_synthetic-event-marker-and-failsafe.md](20260712_synthetic-event-marker-and-failsafe.md)

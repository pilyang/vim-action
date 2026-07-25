# 실행 실패 보고 단위 — 키 입력 1건당 최대 1회

- **결정일**: 2026-07-26

## 결정

`EventTapController.reportExecutionFailure` 호출은 **원인 키 입력 1건당 최대 1회**다. 하나의 `.replace` 결정이 낳은 action 시퀀스가 여러 개 실패하더라도 실행 계층(Keyboard 어댑터)이 그 실패들을 접어서 한 건으로 보고한다 — action마다 보고하지 않는다.

## 배경·근거 (왜)

폭주 카운터의 임계는 "1초에 5회"([20260725_failure-burst-autodisable-shape.md](20260725_failure-burst-autodisable-shape.md))인데, 이 값은 **키 입력 단위**를 전제로 고른 것이다. 그런데 `VimAction`의 action 시퀀스는 카운트를 반복 출력으로 표현하므로 `output.actions`가 수천 개일 수 있다(`EventTapController.handleKeyDown`의 `.replace` 분기 주석, 카운트는 9999로 클램프됨 — [20260717_vimaction-edit-output-shape.md](20260717_vimaction-edit-output-shape.md)). action별로 보고하면 `100j` 한 번이 지원되지 않는 앱에서 즉시 100건을 보고해 임계를 압도한다.

그 결과는 안전장치의 목적과 정반대다. 카운터가 감지하려는 것은 "실행 계층이 무너지고 있다"이지 "이 앱에서 이 명령 하나가 안 먹는다"가 아니다. action 단위 보고는 이 둘을 구분할 수 없게 만들고, **명령 하나가 지원되지 않는다는 이유로 가로채기 전체가 꺼지는** 오탐이 실사용 첫날부터 난다. 임계값을 키우는 방식으로는 못 고친다 — 한 키 입력이 만드는 실패 수 자체가 카운트에 비례해 무제한이기 때문이다.

보고를 접는 책임을 어댑터에 두는 이유는, 어떤 action들이 한 사용자 동작에 속하는지를 아는 유일한 계층이 어댑터이기 때문이다. 카운터는 시간만 주입받는 순수 타입으로 남는다.

## 검토한 대안

- **임계값 상향**: 한 키 입력의 실패 수가 카운트에 비례해 무제한이라 어떤 상수로도 오탐을 막지 못한다.
- **카운터에 보고 단위 API 추가(`report(count:)` 등)**: 호출자가 0개인 시점에 실행 계층의 형태를 추측해 설계하는 것이고, 접는 판단은 어차피 어댑터에만 있는 정보다.
- **action별 보고 유지 + 별도 디바운스**: 완화책이 하나 더 늘고, 그 디바운스의 창·임계가 다시 같은 종류의 미검증 상수가 된다.

## M2 착수 시 확정할 항목

이 결정이 닫지 **않은** 것들 — 실행 계층을 배선할 때 함께 정한다.

1. **백그라운드 실행 큐에서의 보고 배선.** 실행은 콜백 밖 직렬 큐로 나가는데([20260725_callback-light-invariant.md](20260725_callback-light-invariant.md)) `reportExecutionFailure`는 `EventTapController`의 MainActor 격리 안에 있다. 판정(`FailureBurstCounter`)은 순수 값 타입이라 오프메인에서 굴리고 `isInterceptionEnabled` 대입만 메인으로 홉하는 형태가 가능하다 — 워치독이 같은 이유로 쓰는 구조다. 메인 홉을 그대로 둘지 이 분리를 할지는 실행 큐 형태가 정해진 뒤 판단한다.
2. **자동 트립의 재시작 영속.** 트립은 기존 소프트 off의 didSet을 재사용하므로 `isInterceptionEnabled=false`가 UserDefaults에 기록되어 **재시작 후에도 꺼진 채**로 남고, 메뉴바 표시도 사용자가 직접 끈 off와 동일하다. off 의미론을 하나로 유지한 결과라 의도적이지만, 재시작은 일시적 실패 원인이 사라졌을 가능성이 가장 높은 시점이라 영속이 옳은지는 미검증이다. 실사용 데이터가 생긴 뒤 재평가한다.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 #2)
- 코드 변경 없음 — `FailureBurstCounter`·`reportExecutionFailure`는 그대로다. 이 문서가 구속하는 것은 아직 존재하지 않는 **호출자**(Keyboard 어댑터)다.
- 관련 결정: [20260725_failure-burst-autodisable-shape.md](20260725_failure-burst-autodisable-shape.md)(임계·창과 off 경로 재사용), [20260725_keyboard-first-mvp-build-order.md](20260725_keyboard-first-mvp-build-order.md)(이 계약을 지킬 첫 호출자)

# 이벤트 탭 메인 런루프 부착 (스파이크 한정, 엔진 연결 전 재검토)

- **결정일**: 2026-07-12

## 결정

스파이크 단계의 CGEventTap 런루프 소스는 **메인 런루프**에 부착한다. 엔진 연결 전에 전용 CFRunLoop 스레드 필요 여부를 재검토한다 — 판단 데이터는 스파이크가 남기는 `tapDisabledByTimeout` 재활성화 로그의 빈도.

## 배경·근거 (왜)

- 스파이크 콜백은 로그 + 무수정 통과뿐이라 지연이 사실상 0이고, 앱 타깃의 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`와 정합해 격리 우회(`nonisolated(unsafe)` 상태 공유 등) 없이 `MainActor.assumeIsolated`만으로 안전하게 작성된다.
- 대가: 메인 스레드가 막히면 시스템 전역 키보드 전달이 함께 지연되고, ~1초 후 OS가 탭을 타임아웃 비활성화한다. 콜백의 재활성화 처리 + 로그가 이 발생 빈도를 그대로 측정해 주므로, 전용 스레드 전환 판단에 필요한 실측 데이터가 공짜로 쌓인다.
- 주의 계약: 콜백의 `MainActor.assumeIsolated`는 "소스가 메인 런루프에 있다"는 가정에 의존한다. 런루프 선택을 바꾸면 이 지점부터 깨진다 (코드 주석으로 명시).

## 검토한 대안

- **전용 CFRunLoop 스레드**: 메인 스레드 스톨과 격리되지만, 스파이크 시점에는 실측 근거 없이 스레딩 복잡도(격리 우회, 스레드 수명 관리)만 추가한다. 필요가 데이터로 입증되면 그때 전환. 기각(현 단계).

## 영향 범위

- 코드: `VimAction/EventTapController.swift` (`CFRunLoopGetMain()` 부착, `eventTapCallback`의 `assumeIsolated`)
- 후속 재검토 지점: 엔진↔탭 연결 플랜 시작 시.

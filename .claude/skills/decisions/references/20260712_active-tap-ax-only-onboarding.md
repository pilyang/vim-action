# Active tap + Accessibility 단독 온보딩

- **결정일**: 2026-07-12

## 결정

메인 이벤트 탭은 스파이크 단계부터 **active tap**(`.defaultTap`)으로 설치하고, 권한 온보딩은 **Accessibility 하나만** 요청한다. Input Monitoring은 요청하지도 상태 표시하지도 않으며, 실제로 요구되는 상황이 검증에서 발견될 때만 추가한다.

## 배경·근거 (왜)

- 제품의 최종 요구는 이벤트를 삼키고 대체하는 active tap이다. 스파이크에서 listen-only로 검증하면 "탭이 안 되는 조건, 권한 이슈" 같은 스파이크의 핵심 질문에 대해 제품과 다른 답을 얻게 된다. 스파이크 단계의 active tap은 콜백이 모든 이벤트를 무수정 통과시키므로 입력 차단 위험이 낮다.
- macOS 10.15+에서 키보드 이벤트 탭의 TCC 요구는 탭 종류에 따라 갈린다: active tap은 Accessibility, listen-only tap은 Input Monitoring(`kTCCServiceListenEvent`). active를 택했으므로 Accessibility만으로 충분하다.
- PRD §7.6도 Input Monitoring을 "추가로 필요한지(탭 위치와 macOS 버전에 따라 다름) **감지해 조건부 요청**"으로 정의하고, Stage 0/1 스코프는 접근성 온보딩만 명시한다. 권한 요청 수를 줄이면 온보딩 마찰이 줄어든다.
- 온보딩 세부: 실행 시 `AXIsProcessTrusted()` 확인 → 있으면 탭 자동 시작, 없으면 1초 폴링으로 부여 순간을 감지해 재시작 없이 설치. 프롬프트(`AXIsProcessTrustedWithOptions`)는 TCC 상태당 1회만 뜨므로 시스템 설정 딥링크 버튼이 필수 복구 경로다.

## 검토한 대안

- **Listen-only tap으로 스파이크**: 가장 안전하지만 제품 요구(swallow/replace)와 다른 권한·다른 동작을 검증하게 되어 스파이크 목적에 미달. 기각.
- **Accessibility + Input Monitoring 둘 다 온보딩**: 미래 대비는 되지만 PRD의 조건부 정의보다 넓고, 사용자 승인 단계가 2번으로 늘어남. 필요가 입증되지 않은 권한 요청은 하지 않기로 함. 기각.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 코드: `VimAction/EventTapController.swift`(탭 설치), `VimAction/AccessibilityPermissionMonitor.swift`(권한 확인·폴링), `VimAction/AppState.swift`(bootstrap 배선), `VimAction/SettingsView.swift`(온보딩 UI)

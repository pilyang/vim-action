# 전략 디스패치

- **Last updated**: 2026-08-20 (문서 분할 — 프로브·어댑터·리졸버 상세를 4개 하위 reference로 이관, 이 파일은 디스패치 코어만)

## 현재 구조

엔진에서 온 각 `VimAction`은 전략 디스패처가 앱별 프로파일과 auto 프로브 판정을 통해 **Accessibility 어댑터** 또는 **Keyboard 어댑터** 중 하나로 라우팅한다. Keyboard 어댑터는 `key-mapping`(요소 인식, 선호 폴백)과 `force-text`(요소 감지 우회, 최후 수단) 두 계열을 가진다.

상세는 하위 reference에 있다:

| 주제 | Reference |
|---|---|
| auto 전략 프로브 — 판정 계층·수명·강등·관측 | [auto-strategy-probe.md](auto-strategy-probe.md) |
| Accessibility 어댑터 — 쓰기·하이브리드·오프셋·Visual 경로 고정 | [ax-adapter.md](ax-adapter.md) |
| Keyboard 어댑터 — 걸러내기·네 매퍼·정확화 | [keyboard-adapter.md](keyboard-adapter.md) |
| 포커스 리졸버·디스패치 경로 AX 읽기 | [focus-and-dispatch-reads.md](focus-and-dispatch-reads.md) |

### 앱 수준 게이트

앱 수준 게이트는 **탭 콜백의 엔진 진입 전**에 판정한다: 최전면 앱이 `config.yaml`의 앱별 off 목록이면 번역·엔진 없이 원본 키를 통과시키고, 엔진 모드 상태는 동결한다(리셋 없음). 판정 위치는 마커 가드·마스터 토글 가드 뒤, 번역 앞이다. 최전면 bundleID는 `@MainActor` 캐시가 `NSWorkspace` 앱 활성화 알림으로 갱신하고 콜백은 캐시만 읽는다 — 디스패치 시점 게이트는 삼킨 뒤 실행만 막아 "죽은 키"가 되므로 기각됐다 ([20260726_m2-app-gate-pre-engine-passthrough.md](../../decisions/references/20260726_m2-app-gate-pre-engine-passthrough.md), [20260801_app-enable-config-yaml-only.md](../../decisions/references/20260801_app-enable-config-yaml-only.md)).

### 선택 플로우 (VimAction마다 실행)

```mermaid
flowchart TD
    VA[VimAction 수신] --> P{"설정 조회<br/>(앱별 on/off는 config.yaml,<br/>전략은 프로파일)"}
    P -->|"앱 off"| Pass[통과 후 중단]
    P -->|"strategy: accessibility"| AX[Accessibility 어댑터]
    P -->|"strategy: keyboard"| KB[Keyboard 어댑터]
    P -->|"strategy: auto"| Probe{"판정 캐시 조회<br/>(비동기 프로브 —<br/>auto-strategy-probe.md)"}
    Probe -->|trusted| AX
    Probe -->|"pending / untrusted"| KM["Keyboard 어댑터<br/>family = key-mapping"]
    AX --> Override{요소별 재정의?}
    KB --> Override
    KM --> Override
    Override -->|"per_element 매칭"| Re[재정의된 전략으로 교체]
    Override -->|없음| Exec[ActionExecutor로 실행]
    Re --> Exec
```

(`per_element` 요소별 재정의는 PR-E 몫 — 스키마 미결, [profiles-and-config.md](profiles-and-config.md).)

### AX 실행 계획의 판정 — 단일 지점

판정은 **`usesAXWrite(_:family:strategy:profile:)` 한 곳**이며(`strategy:`는 auto 판정을 접은 실효 전략), 넷 중 하나라도 걸리면 keyboard 경로다:

1. 실효 전략이 accessibility가 아님 (auto는 접힌 판정 기준 — [auto-strategy-probe.md](auto-strategy-probe.md))
2. 계열이 `.nonText`·`.unresolved` (원본 family 기준 — force-text 치환은 keyboard 쪽에만 닿는다)
3. `j`·`k` (오프셋 대입은 희망 열을 잃는다 — [ax-adapter.md](ax-adapter.md) 위임 표)
4. **프로파일 `motions:`에 그 액션이 이름한 모션 항목이 있음** — strokes 재정의든 disable이든, 재정의는 사용자 지시라 AX가 덮어쓰지 않는다(스크롤 사다리와 같은 우선순위) ([20260808_profile-motion-override-outranks-ax.md](../../decisions/references/20260808_profile-motion-override-outranks-ax.md))

넷째 가드의 대상은 "범위가 이름한 모션"까지다 — `dw`의 `w`, `cw`의 리타깃 `e`, `dk`의 `k`. `dd`·`diw`가 내부적으로 쓰는 조합(`lineStart` 등)은 사용자가 그 액션에 대해 지시한 모션이 아니고, 거기까지 보려면 `EditKeyMapper`의 조립표가 어댑터로 복사돼 두 곳이 갈라진다. `.openLine`·`.paste`에는 넷째 가드의 대상이 아예 없다 — 접두의 내부 분해는 이름한 모션이 아니며, 사용자가 지시할 수 있는 `open_line`·`paste` 스트로크는 위임분에 남아 매퍼를 그대로 지난다. `actions:` disable은 `mapping` 최상단이라 이 판정보다 앞이다.

## 불변식·계약

- **AX 호출은 콜백·메인 스레드에 들어오지 않는다** — 리졸버는 전용 큐, 디스패치 경로 읽기는 게시 큐, 프로브는 프로브 전용 큐. 타임아웃은 경로 불문 50ms 단일 상수 ([focus-and-dispatch-reads.md](focus-and-dispatch-reads.md)).
- **읽기는 분기의 근거이지 스트로크 수의 근거가 아니다 — keyboard 경로 전용 불변식.** AX 경로에는 적용되지 않는다(읽기·쓰기가 같은 큐에서 동기, 오프셋이 실행 수단 그 자체) ([keyboard-adapter.md](keyboard-adapter.md), [ax-adapter.md](ax-adapter.md)).
- `force-text`는 프로파일에서 명시적으로만 선택하며, 자동 감지가 선택하는 일은 없다. 치환은 keyboard 실행 쪽에만 닿는다.
- **auto 판정 캐시는 프로브로는 trusted 방향으로만 움직인다** — 반증은 런타임 증거뿐, 강등은 pid 수명 sticky, 왕복 없음 ([auto-strategy-probe.md](auto-strategy-probe.md)).

## 근거 요약

올바른 AX 앱에서는 AX가 정밀하지만 너무 많은 앱이 AX 지원을 거짓말하므로, 자동 감지 + Keyboard 폴백의 이중 전략이 필요하다.

- 관련 결정: [20260712_ax-keyboard-strategy-dispatch.md](../../decisions/references/20260712_ax-keyboard-strategy-dispatch.md)

## 미결 질문 (결정 시 decisions에 기록 후 이 파일 갱신)

- 일회성 Accessibility → Keyboard 다운그레이드 수정 키 (kindaVim의 `fn` 방식) — 채택 여부와 키 선택.
- 기상 상태의 Slack에서 keyboard 혼용 정확화(디스패치 경로 읽기)도 살아나는가 — "Slack은 읽기 실패 상시 폴백" 전제가 수면 상태 측정이었음이 실측됐다. auto 도그푸딩에서 함께 관측 후 판단.
- **AX로 pin된 Visual 세션 × 런타임 강등의 교차**: 강등돼도 pin이 세션 수명이라 그 세션의 확장·전환은 재진입(`Esc` → `v`) 전까지 `.skipped`(DEBUG 전용)로 남는다 — "다음 액션부터 keyboard"가 이 모서리에서는 성립하지 않는다. 무상태 폴백 금지·pin 수명 결정과 충돌 없이 낙하시킬 경로가 없어 코드 수정은 보류. **방향은 "현행 수용 + auto 도그푸딩 실빈도 관측 후 판단"으로 확정**(2026-08-14 사용자 확정 — 스킵 `.info` 승격은 결정 문언 밖 관측 확장이라 실증 없이 하지 않는다). 유일한 파괴 축(`.edit(op, .selection)`)은 위임 직전 가드가 강등 무관하게 닫아, 잔여는 무해한 no-op 스킵뿐이다 ([ax-adapter.md](ax-adapter.md)).

## 관련

- 선택 알고리즘 요구사항: 워크스페이스 `docs/prd.md` §9
- 프로파일 스키마: [profiles-and-config.md](profiles-and-config.md)
- 실행/재진입: [reentrancy-and-safety.md](reentrancy-and-safety.md)
- 테스트: 기록된 `AXUIElement` 픽스처로 회귀 테스트, 어댑터는 골든 출력 테스트 (워크스페이스 `docs/architecture.md` §7)

# Secure Input 전용 상태 (Status.secureInput)

- **결정일**: 2026-07-19

## 결정

OS Secure Event Input(비밀번호 입력 등)이 키보드 탭을 억제 중일 때를 `.failed`가 아닌 **전용 상태 `Status.secureInput`** 으로 표현한다. 워치독 틱과 `enableTapAndVerify` 실패 분기는 `IsSecureEventInputEnabled()`가 true면 재활성화를 **시도하지 않고** `.secureInput`으로 전이한다(OS 보호와 싸우지 않음). UI 표시는 메뉴바 `lock.square` 글리프 + Settings "Secure Input"이며, 우선순위는 **탭 고장 > 토글 off > Secure Input**. 해제 후 복귀는 워치독 다음 폴링(≤2초)이 담당한다.

## 배경·근거 (왜)

PR #13 코드리뷰 finding: 비밀번호 필드 포커스 동안 OS가 키보드 탭을 억제하는데, 워치독이 이를 고장으로 오인해 매 2초 재활성화 시도→거부→`.failed`+에러 로그를 반복했고, 메뉴바가 정상적인 보호 동작 내내 "inactive"(square.dashed)로 표시됐다 — 사용자에게 false failure. 단순히 `.failed` 전이만 막으면(스킵) "왜 지금 Vim 바인딩이 안 먹는지"를 알릴 수단이 없으므로 전용 상태로 표현한다. 이는 reentrancy-and-safety 완화책 ⑤ "보안 입력 인식 — 가로채기 중단 + 인디케이터"의 최소 구현이기도 하다(예정돼 있던 방향).

우선순위에서 토글 off가 Secure Input보다 앞서는 이유: off 중에는 워치독이 서지 않아 `.secureInput`이 과거 값으로 래치될 수 있는데, 사용자가 끈 상태의 표시(square.slash/"Disabled")가 OS 일시 억제 표시보다 사용자 의도를 정확히 반영한다.

## 검토한 대안

- **`.failed` 전이만 억제(상태 추가 없이 스킵)**: 재활성화 싸움은 멈추지만 사용자에게 억제 중임을 알릴 수 없음. 기각.
- **`IsSecureEventInputEnabled()` 시 가로채기 자체를 끄기(완화책 ⑤ 전체 구현)**: 탭이 이미 OS에 의해 억제되므로 추가로 끌 것이 없고, 폴링 기반 감지로 충분. 과잉 구현으로 기각(향후 필요 시 확장).

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 ⑤)
- 코드: `VimAction/EventTapController.swift` (Status·WatchdogObservation·watchdogTick·enableTapAndVerify), `VimAction/AppState.swift` (글리프·레이블), `VimAction/SettingsView.swift` (status 문구), 테스트 2파일
- `Status` 계약 소비자(글리프·Settings 파생)는 전부 갱신됨 — 이후 Status 스위치 추가 시 `.secureInput` 분기 누락 주의 (exhaustive switch가 컴파일로 잡는다).

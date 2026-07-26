# Secure Input은 배달만 억제한다 — 재활성화 보류 조항 철회

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

Secure Event Input(SEI)은 **이벤트 배달만 억제하며 탭 활성화에는 관여하지 않는다**. 이 사실에 맞춰 두 가지를 바꾼다.

1. **워치독은 SEI 중에도 재활성화를 시도한다.** `watchdogTick`의 순서를 "되살리기 먼저, SEI는 그다음"으로 뒤집는다 — `isSecureInput()` 확인은 `enableAndVerify()`가 **실패한 뒤에만** 하고, 고장(`.dead`)과 보호 상태(`.secureInput`)의 **표시를 가르는 용도**로만 쓴다.
2. **`Status.secureInput`의 의미를 재정의한다.** "SEI가 원인이라 재활성화를 보류한 상태"가 아니라 "**재활성화가 실패했고 그 시점에 SEI가 함께 관측된 상태**" — `.failed`의 하위 표시 구분이지 별개의 원인이 아니다.

`enableTapAndVerify`는 이미 `enableAndCheck`를 먼저 부르는 순서라 로직 변경 없이 거짓 주석·로그 문구만 정정한다. UI 표현(`lock.square`, Settings "Secure Input")과 표시 우선순위(고장 > 토글 off > Secure Input)는 그대로 유지한다.

## 배경·근거 (왜)

[20260719_secure-input-status](20260719_secure-input-status.md)는 "SEI가 키보드 탭을 억제한다"를 **활성화 실패**로 해석했다. 실측 결과 이 전제가 틀렸다.

macOS 26.5에서 SEI를 자기 프로세스·별도 프로세스 양쪽에서 유지한 채 측정:

```
SEI=true 상태에서
  tapCreate (HID/Session)  → 성공
  tapEnable(true)          → 성공
  tapIsEnabled             → true
  이미 켜진 탭             → 꺼지지 않음
  tapDisabledBy* 통지      → 오지 않음
```

SEI가 하는 일은 이벤트를 가로채기 프로세스에 **배달하지 않는 것**뿐이다 ([TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html), [Karabiner-Elements DEVELOPMENT.md](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md)의 "Events cannot be **captured** while Secure Event Input is enabled"). HID/세션 위치 차이도 없다.

**이 오해가 만든 실제 잘못된 동작**: `watchdogTick`은 `isEnabled()`를 먼저 보므로 SEI 분기에 도달했다는 것은 **탭이 실제로 죽어 있다**는 뜻이다. SEI가 죽인 게 아니니 원인은 타임아웃 등 진짜 고장인데, 사용자가 마침 비밀번호를 입력 중이라는 이유로 그 복구를 거부하고 있었다. 원래 결정이 막으려던 "매 2초 거부→`.failed` 반복"은 애초에 일어나지 않는 현상이다 — 재활성화가 SEI 때문에 거부되지 않으므로.

**관측 가능한 피해 자체는 작다.** SEI 중에는 살아 있는 탭도 이벤트를 못 받으므로 죽은 탭과 구별되지 않고, 차이는 SEI 해제 후 최대 한 폴링 주기(≤2초)뿐이다. 그럼에도 고치는 이유는 **틀린 모델이 이미 잘못된 판단을 낳았기 때문이다**: PR #18 코드리뷰가 "SEI 때문에 `tapEnable`이 거부될 수 있다"를 킬 탭 결함의 핵심 트리거로 삼았는데, 그 근거가 바로 이 코드가 스스로 그렇게 주장하고 있어서였다. 잘못된 모델은 전파된다.

**`.secureInput`을 남겨 두는 이유**: `.failed`와 합치면 사용자가 비밀번호를 칠 때마다 "고장"을 보게 된다. 그 조합에서는 어차피 키가 우리에게 오지 않으므로, 덜 놀라운 표시가 정직하다. 다만 그것은 **표시상의 배려**이지 원인 판정이 아니며, 코드와 주석이 그렇게 말해야 다음 사람이 또 속지 않는다.

## 검토한 대안

- **`.secureInput`을 완전 제거하고 `.failed`로 흡수**: 모델은 가장 정직해지지만 사용자 가시 상태 하나가 사라지고, 비밀번호 입력 중 "고장" 표시라는 원래 문제(PR #13 finding)가 되살아난다. 기각.
- **`.secureInput`을 탭 건강과 무관한 별도 축으로 분리** (`IsSecureEventInputEnabled()`를 status와 독립적으로 표시): 실제 동작과 가장 일치하는 근본 해결. 그러나 `Status` 소비자(글리프·Settings·접근성 레이블)를 전부 재설계해야 하고 M1 범위를 벗어난다. **이연** — 이 결정은 "순서 교정 + 의미 정정"이라는 최소 변경이며, 축 분리가 필요해지면 이 문서를 supersede한다.
- **현상 유지**: 실피해가 ≤2초라 방치도 가능하나, 코드가 거짓을 주장하는 상태가 유지되어 다음 판단을 또 오염시킨다. 기각.

## 영향 범위

- 코드: `VimAction/EventTapController.swift` — `watchdogTick`(순서 교정), `Status.secureInput` 문서, `enableTapAndVerify` 주석·로그, `applyWatchdogResult` 로그
- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 ⑤)
- 테스트: `VimActionTests/TapWatchdogTests.swift` — `tickSecureInputSkipsEnable`(제거한 동작을 단언하던 테스트)을 `tickRevivesEvenUnderSecureInput`·`tickFailedRevivalUnderSecureInputIsLabelled`로 교체. `.secureInput` 경로의 래치 읽기 횟수가 2→3회로 바뀌어 `latchRaisedAfterObservationDiscardsIt`의 인덱스도 조정.

## Supersedes

- [20260719_secure-input-status.md](20260719_secure-input-status.md) — **부분 supersede**. 뒤집는 것은 "워치독 틱과 `enableTapAndVerify` 실패 분기는 `IsSecureEventInputEnabled()`가 true면 재활성화를 시도하지 않는다" **한 조항뿐**이다. 전용 상태로 표현한다는 결정, `lock.square`+Settings 표시, 우선순위(고장 > 토글 off > Secure Input), 완화책 ⑤ 최소 구현이라는 배경은 모두 유효하므로 옛 문서는 인덱스에 남긴다.

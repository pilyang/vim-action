> Superseded (부분) by [20260801_kill-combo-autorepeat-fires.md](20260801_kill-combo-autorepeat-fires.md) — 오토리핏 가드(오토리핏 콤보 미발동) 의미론만. 단방향 off·2겹 효과·킬 요청 래치·콤보 정확 일치·마커 가드는 유효.

# 킬스위치 발동 의미론 — 단방향 off, 2겹 효과 + 킬 요청 래치, 콤보 판정 규칙

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

1. **단방향 off.** 콤보는 가로채기를 끄기만 한다. 복귀는 기존 메뉴바 토글이 유일한 경로다.
2. **효과는 2겹.** ① 킬 탭 전용 스레드에서 메인 탭 포트에 직접 `tapEnable(false)` ② `main.async` 홉으로 `isInterceptionEnabled = false` 대입. ②의 didSet이 엔진 Insert 리셋·워치독 정지·경합 봉인·영속·메뉴바 반영을 전담하며, **자동/외부 off 전용 경로는 만들지 않는다** ([20260725_failure-burst-autodisable-shape](20260725_failure-burst-autodisable-shape.md)의 `reportExecutionFailure`와 같은 규칙).
3. **킬 요청 래치.** `triggerKillSwitch`가 ① 직전에 nonisolated 래치를 세우고, 콜백 재활성화(`reenableAfterDisable`)와 워치독 bg 틱은 래치가 서 있으면 탭을 되살리지 않는다. 해제 지점은 토글 on 복귀 하나뿐이다.
4. **콤보는 고정 `Ctrl-Opt-Cmd-Esc`.** 판정은 keycode 53 + **의도한 modifier 5종**(control/option/command/shift/fn)의 정확 일치이며, Caps Lock·numericPad·nonCoalesced 같은 상태/부수 비트는 마스킹해 무시한다.
5. **콜백 방어 가드 2종**: 합성 이벤트 마커가 찍힌 이벤트와 오토리핏 이벤트로는 발동하지 않는다. 발동한 콤보 이벤트는 삼킨다.

## 배경·근거 (왜)

**단방향인 이유**: 콤보로 다시 켜지게 하면 킬스위치가 토글이 되어, 사용자가 "일단 끈다"는 확신을 잃는다. 부수 효과로 [플랜에 조건부로 적혀 있던 `FailureBurstCounter` 창 초기화가 불필요해진다](20260725_failure-burst-autodisable-shape.md) — 1초 안에 off→on 왕복이 여전히 불가능하기 때문이다.

**2겹인 이유**: ②만 두면 메인이 스톨한 동안 아무 일도 일어나지 않아 존재 이유가 사라지고, ①만 두면 영속·엔진 리셋·글리프가 갈라져 소프트 off와 상태가 어긋난다. ①은 새 off "의미론"이 아니라 ②가 멱등하게 반복할 disable의 선행 실행이다.

**래치가 필요한 이유(실기기에서 드러난 결함)**: 설계 초안은 ①과 ② 사이의 경합 상대로 워치독만 검토했고, "메인이 정상이면 홉이 ms 안에 착지하고 스톨 중이면 스톨 게이트가 틱을 건너뛴다"로 닫힌다고 봤다. 실기기 로그가 이를 반증했다 —

```
[킬 스레드] 킬스위치 발동 — 메인 탭 즉시 비활성
[메인]      시스템이 탭 비활성화(userInput) — 탭 재활성화     ← 0.7ms 뒤 되살아남
[메인]      가로채기 off — 탭 비활성화, 엔진 Insert 리셋      ← 0.85ms 뒤 진짜 off
```

**우리가 킬 스레드에서 끈 것에 대해 OS가 메인 탭 콜백에 `tapDisabledByUserInput`을 통지**하고, `reenableAfterDisable`의 `guard isInterceptionEnabled`는 ②의 메인 홉이 아직 착지하지 않아 `true`를 보므로 방금 끈 탭을 되살린다. 워치독 bg 틱도 같은 창을 연다 — 그 틱은 토글 가드 없이 `enableAndCheck`를 부르고, 토글 반영(`stopWatchdog`)은 홉 뒤에 온다.

근본 원인은 두 가드가 모두 **메인 격리 상태**를 읽는데 발동은 메인 밖에서 일어난다는 것이다. 래치는 그 판정을 메인 격리 밖으로 빼서 창을 닫는다. 불변식은 "**래치가 서 있으면 아무도 탭을 되살리지 않는다**"이며, 그래서 두 경로 모두에 같은 래치를 건다. 해제 누락은 "킬스위치 이후 재활성화가 영구 보류"라는 조용한 고장이므로, 래치 상태 읽기를 테스트용으로 열어 계약으로 고정한다.

**modifier 정확 일치의 범위**: 오발동의 복구는 메뉴바 토글 1클릭이지만, 미발동의 대가는 키보드 인질 상태다. 비대칭이 크므로 Caps Lock이 켜져 있다는 이유로 안전장치가 안 먹는 쪽을 피한다 — 사용자가 의도해 누른 modifier만 비교하고 상태 비트는 무시한다.

**방어 가드 2종**: 마커 가드는 지금 도달 불가하지만(세션에 게시한 합성 이벤트는 HID 탭에 오지 않는다) **세션 폴백 경로에서는 들어오고**, 어댑터가 modifier 조합 Esc를 합성하게 되면 앱이 자기 출력으로 자기를 끄는 버그 클래스가 열린다 — [마커는 상태 무관 불변식](20260725_marker-guard-highest-precedence.md)이라는 메인 탭의 규칙을 킬 탭에도 적용한다. 오토리핏 가드는 콤보 꾹 누름이 fault 로그와 메인 홉을 초당 수십 건 만드는 것을 막는다(효과 자체는 didSet 등가 가드가 이미 멱등하게 만든다).

**단축키 커스터마이즈 부재**: 고정 기본값만 두고 설정 UI는 M4 이후로 이연한다. 설정 가능성은 안전장치의 본질이 아니고, 잘못 설정된 킬스위치는 없는 것보다 나쁘다.

## 검토한 대안

- **콤보로 on/off 양방향 토글**: 복귀 경로가 하나 늘지만 "끈다는 확신"이 사라지고, 연타로 1초 내 off→on이 가능해져 폭주 카운터의 창 전제가 깨진다. 기각.
- **래치 없이 현상 유지**: 최종 상태는 이미 올바르고(②가 0.85ms 뒤 닫는다) 스톨 중에는 메인이 통지를 처리하지 못해 ①이 유지되므로, ①이 진짜 필요한 상황에서는 이미 동작한다. 그러나 정상 상태에서 ①이 광고한 "즉시 차단"이 성립하지 않고, 로그가 "끔 → 살아남 → 다시 끔"으로 읽혀 다음 사람이 버그로 오해한다. 8줄로 닫히는 문제라 유지 기각.
- **`isInterceptionEnabled`의 nonisolated 원자 미러 도입**: 두 가드를 근본적으로 고치지만, 관찰 프로퍼티 미러는 [메인 런루프 유지 결정](20260725_tap-main-runloop-retention.md)이 전환 비용으로 지목한 항목이다. 발동 순간에만 필요한 창을 위해 상시 미러를 들이는 것은 과하다 — 목적 전용 래치로 좁게 닫는다.

## 영향 범위

- 코드: `VimAction/EventTapController.swift`(`triggerKillSwitch`·`killSwitchRequested` 래치·`reenableAfterDisable`/워치독 틱 게이트·`disableReasonName` 로그 판독성), `VimAction/KillSwitchTap.swift`(`isKillCombo`·`shouldFire`), `VimAction/AppState.swift`(발동 효과 배선)
- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 테스트: `VimActionTests/KillSwitchTests.swift` — 콤보 판정 전 케이스, 방어 가드, 발동의 didSet 위임, 래치 설정·해제

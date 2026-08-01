# 킬 콤보는 오토리핏도 발동한다 — 발동 1회성은 킬 요청 래치 test-and-set

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

1. **`shouldFire` 술어를 제거한다.** 킬 탭 콜백은 삼킨 콤보(`shouldSwallow` = 마커 아님 + 콤보 정확 일치)마다 `fire()`를 부른다 — **오토리핏 콤보도 발동한다.**
2. **발동 효과·fault 로그의 1회성은 `triggerKillSwitch`가 보장한다.** 킬 요청 래치를 **test-and-set**으로 세우고, 이미 서 있으면(같은 에피소드) 나머지를 건너뛰고 반환한다. `triggerKillSwitch`는 `@discardableResult`로 "이번 호출이 킬을 수행했는가"를 돌려준다. 에피소드 경계는 기존과 동일 — 래치 해제는 토글 on 복귀뿐이다.
3. **실행 중단 래치 무효화(`executionAbort.invalidate()`)만은 dedupe 앞·무조건이다** — 오토리핏 재발동에서도 게시 중 버스트를 계속 끊는다.
4. `fire()`의 "콤보 감지" fault 로그는 제거한다 — 발동 기록은 `triggerKillSwitch`의 "킬스위치 발동" fault 1건(에피소드당 1회)으로 단일화한다. 감지 자체의 진단은 기존 DEBUG 진단 로그(Esc keyDown flags)가 담당한다.

## 배경·근거 (왜)

M3 단계 4 킬스위치 회귀의 실기기 검증(2026-08-01)이 **오토리핏 가드의 함정을 실증**했다. 사용자가 Esc를 modifier보다 먼저 누른 채 콤보를 꾹 누르면:

1. 최초 keyDown은 modifier 미완성으로 콤보 미달 — 발동하지 않는다 (정당).
2. 이후 modifier가 마저 눌려 **플래그가 완성돼도**, HID가 올려보내는 keyDown은 전부 오토리핏이라 가드에 걸려 **영영 발동하지 않는다.**

실기기 로그: 83ms 간격(오토리핏 주기)의 풀 콤보 keyDown(flags=1835345) 4연속 무발동 — 사용자는 뗐다 다시 정확히 눌러야만 발동시킬 수 있었다. **비상 상황에서 사용자의 자연스러운 행동("꾹 누르고 기다림")이 설계상 무효**라는 것은 안전장치로서 나쁜 성질이다. [트리거 의미론](20260726_kill-switch-trigger-semantics.md)의 modifier 정확 일치 근거와 같은 비대칭이 여기에도 적용된다: 미발동의 대가(키보드 인질·폭주 지속)가 중복 발동의 대가(무해한 no-op)보다 훨씬 크다.

오토리핏 가드의 원 근거는 "콤보 꾹 누름이 fault 로그와 메인 홉을 초당 십여 건 만든다"였다. 이 목적은 dedupe(래치 test-and-set)가 대신하며 **더 강하게** 막는다 — 가드 방식은 뗐다 누르기 반복의 도배를 못 막았지만, 에피소드당 1회는 어떤 반복도 막는다.

부수 정리: 이 변경으로 `shouldFire`가 `shouldSwallow`와 동일해지므로 술어를 하나로 합친다. [술어 분리 결정](20260726_kill-combo-swallow-independent-of-fire.md)이 분리로 풀었던 문제(오토리핏이 포커스 앱으로 새는 것)는 "삼킨 것은 전부 발동 경로"에서는 애초에 성립하지 않는다.

같은 검증에서 나온 **부분 콤보 누출**(Ctrl 늦음 → Cmd-Opt-Esc가 통과해 시스템 Force Quit 창 / 맨 Esc → Normal 전환)은 이 결정으로 해소되지 않는다 — 다만 Esc 선행 후 꾹 누르는 케이스가 이제 발동으로 수렴하므로 실질 빈도는 줄어든다. 잔여 위험은 단계 4 게이트 심사 항목으로 남긴다.

## 검토한 대안

- **오토리핏 가드 유지 + `flagsChanged` 감지**로 "Esc 눌린 채 modifier 완성" 순간 발동: 리핏 지연(~375ms) 없이 가장 빠르지만, 킬 탭 마스크에 `flagsChanged` 추가와 "Esc가 눌려 있는가" 상태 추적이 필요하다 — 상태 없는 콜백 계약을 깬다. 오토리핏 발동이 같은 결과를 상태 없이 달성한다(리핏 지연만큼 늦을 뿐). 기각.
- **콤보 변경**(시스템 Force Quit의 비상위집합으로): 부분 콤보 누출 자체가 사라지지만, 이 결정의 대상(오토리핏 함정)과는 별개 축이고 고정 콤보 변경은 영향이 크다. Cmd-Opt-Esc 누출의 결과인 Force Quit 창은 그 자체로 또 다른 구조 수단이라 치명적이지 않다. 기각 — 게이트 심사에서 재검토 여지만 남긴다.
- **`fire()` 로그는 유지하고 `triggerKillSwitch`만 dedupe**: 꾹 누르는 동안 fault 도배가 `fire()`에 그대로 남는다 — 가드 제거의 대가를 되갚지 못한다. 기각.

## 영향 범위

- 코드: `VimAction/KillSwitchTap.swift`(`shouldFire` 제거, 콜백 단순화, `fire()` 로그 제거), `VimAction/EventTapController.swift`(`triggerKillSwitch` test-and-set + `Bool` 반환)
- 테스트: `VimActionTests/KillSwitchTests.swift` — 가드 테스트를 삼킴 중심으로 재편(오토리핏 발동 경로 포함), 에피소드당 1회 테스트 신설
- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (#1 킬스위치 문단)
- 같은 검증이 남긴 별개 발견(버스트 백로그로 인한 정지 체감 지연)은 이 결정의 범위 밖 — 단계 4 게이트 심사 항목

## Supersedes

- [20260726_kill-combo-swallow-independent-of-fire.md](20260726_kill-combo-swallow-independent-of-fire.md) — **부분 supersede**. 뒤집는 것은 술어 분리와 "오토리핏 콤보는 발동하지 않는다"다. "오토리핏 콤보도 삼킨다"(이 문서에서는 발동 경로 포함으로 승계)와 keyUp 대칭 삼킴 기각은 유효하므로 인덱스에 남긴다.
- [20260726_kill-switch-trigger-semantics.md](20260726_kill-switch-trigger-semantics.md) — **부분 supersede**(추가분). 뒤집는 것은 5항의 오토리핏 가드뿐이다. 단방향 off, 2겹 효과, 킬 요청 래치, 콤보 고정·modifier 정확 일치, 마커 가드는 모두 유효하므로 인덱스에 남긴다.

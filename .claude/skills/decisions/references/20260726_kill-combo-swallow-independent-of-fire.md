> Superseded (부분) by [20260801_kill-combo-autorepeat-fires.md](20260801_kill-combo-autorepeat-fires.md) — `shouldSwallow`/`shouldFire` 술어 분리와 오토리핏 미발동만 (이제 삼킨 콤보는 전부 발동 경로). "오토리핏도 삼킨다"와 keyUp 대칭 삼킴 기각은 유효.

# 킬 콤보 삼킴은 발동과 독립 — 오토리핏도 삼킨다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

킬 탭 콜백에서 **삼킴 판정과 발동 판정을 분리**한다. 술어 두 개로 갈라 각각 테스트 가능한 seam으로 둔다.

- `shouldSwallow(_:)` = 합성 마커 아님 **AND** 콤보 일치 → 이 이벤트를 삼킨다
- `shouldFire(_:)` = `shouldSwallow` **AND** 오토리핏 아님 → 실제로 발동한다

콜백은 삼킴을 먼저 판정하고, 발동은 그 안에서 조건부로 한다:

```swift
guard KillSwitchTap.shouldSwallow(event) else { return Unmanaged.passUnretained(event) }
if KillSwitchTap.shouldFire(event) { tap.fire() }
return nil
```

즉 **오토리핏 콤보는 발동하지 않지만 삼킨다.** 합성 마커가 찍힌 이벤트와 콤보가 아닌 이벤트는 종전대로 통과시킨다.

## 배경·근거 (왜)

[20260726_kill-switch-trigger-semantics](20260726_kill-switch-trigger-semantics.md) 5항은 방어 가드 2종(마커·오토리핏)을 하나의 술어 `shouldFire`로 묶고, 콜백은 그 술어 하나로 통과/삼킴을 결정했다. 그래서 세 가드가 **서로 다른 처분을 원하는데 같은 출구로 나가는** 구조가 됐다:

| 가드 | 발동해야 하나 | 삼켜야 하나 | 기존 동작 |
|---|---|---|---|
| 합성 마커 | 아니오 | **아니오** (우리 출력) | 통과 ✅ |
| 콤보 아님 | 아니오 | **아니오** | 통과 ✅ |
| 오토리핏 콤보 | 아니오 | **예** | 통과 ❌ |

결과: 콤보를 꾹 누르면 첫 keyDown만 삼켜지고, 이후 오토리핏이 전부 포커스 앱에 도달했다 — 같은 함수 바로 아래 줄의 주석("콤보는 삼킨다 — 안전장치 조합이 포커스 앱까지 새지 않게 한다")이 스스로 깨진 상태였다.

**전제 확인**: macOS의 오토리핏은 `IOHIDKeyboardFilter`(IOHIDEventSystem 서비스 필터)가 raw `IOHIDEvent` 스트림에서 생성하므로 `kCGHIDEventTap`보다 상류다 — 즉 킬 탭에 실제로 도달한다. `processKeyRepeats`는 modifier 상태를 보지 않고, `isNotRepeated()` 제외 목록에 Escape가 없다. 따라서 "modifier가 붙은 Esc는 리핏되지 않는다"는 반증 가설은 성립하지 않는다. (사용자가 키보드 설정에서 "Delay Until Repeat"을 Off로 두면 리핏 자체가 생성되지 않지만, 그건 예외지 기본이 아니다.)

**심각도는 낮다**: 이 머신 기준 375ms 선행 지연 후 초당 ~13건이고, 새어 나가는 것은 VimAction이 아예 없을 때와 같은 이벤트다 — 상태를 오염시키지 않는다. 실질 피해는 modifier를 무시하고 `key === 'Escape'`만 보는 웹/Electron 앱에서 모달이 반복 닫히는 정도다. 그럼에도 고치는 이유는 **코드가 지키지 못하는 불변식을 주석으로 선언하고 있었기 때문**이다.

**오토리핏 가드를 유지하는 이유**: 발동 자체는 여전히 막아야 한다. 원래 근거(fault 로그와 메인 홉이 초당 수십 건 도배)는 그대로 유효하다 — 바뀐 것은 "발동하지 않는다"가 "통과시킨다"를 함의하지 않는다는 점뿐이다.

## 검토한 대안

- **콜백에 술어를 인라인**(`shouldFire` 제거): 가장 짧지만 `shouldFire`가 고아가 되어 기존 테스트 4개가 죽은 함수를 검증하게 되고, 새 콜백 로직은 커버리지 0이 된다. Swift가 unused 경고를 내지 않아(테스트 타깃이 `@testable`로 참조) 조용히 썩는다. 기각.
- **열거형 3값 반환**(`.fire`/`.swallowOnly`/`.passthrough`): 의도가 가장 명시적이나 호출부·테스트를 모두 갈아야 하고, 술어 2개로 충분히 표현된다. 기각.
- **keyUp도 마스크에 추가해 대칭 삼킴**: 현재 마스크는 keyDown 전용이라 삼킨 keyDown의 keyUp은 앱에 도달한다. 그러나 `flagsChanged`가 마스크에 없어 modifier가 갇힐 위험이 없고, 짝 없는 keyUp은 AppKit에서 무해하며, **메인 탭도 Normal 모드 삼킴에서 동일한 비대칭을 이미 설계로 채택**하고 있다. 상태 없는 콜백에 상태를 들이게 되므로 기각.

## 영향 범위

- 코드: `VimAction/KillSwitchTap.swift` — `shouldSwallow` 신설, `shouldFire` 재정의(`shouldSwallow` 위에 오토리핏 조건), `killSwitchTapCallback` 분기
- 테스트: `VimActionTests/KillSwitchTests.swift` — `autorepeatComboIsStillSwallowed`, `nonComboAndMarkedAreNotSwallowed` 추가. 기존 `shouldFire` 테스트 4개는 계약이 바이트 단위로 보존되어 무수정 통과.
- 잔여 갭(수용): `killSwitchTapCallback`은 file-private C 함수 포인터라 단위 테스트가 불가능하다. 술어 2개는 고정되지만 **콜백의 배선 자체**(삼킴 먼저)는 테스트되지 않는다.

## Supersedes

- [20260726_kill-switch-trigger-semantics.md](20260726_kill-switch-trigger-semantics.md) — **부분 supersede**. 뒤집는 것은 5항의 "발동한 콤보 이벤트는 삼킨다"라는 범위 한정뿐이다(→ 발동 여부와 무관하게 콤보는 삼킨다). 단방향 off, 2겹 효과, 킬 요청 래치, 콤보 고정·modifier 정확 일치, 마커·오토리핏 가드의 **존재 자체**는 모두 유효하므로 옛 문서는 인덱스에 남긴다.

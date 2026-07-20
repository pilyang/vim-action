# 가로채기 마스터 토글 의미론 + 설정 소유 모델

- **결정일**: 2026-07-18

## 결정

메뉴바 "가로채기" 마스터 토글(`isInterceptionEnabled`)의 off/on 의미론을 다음으로 확정한다:

- **off** = `CGEvent.tapEnable(false)`로 스트림 해방(포트는 유지) + 엔진 `.insert` 리셋 + 워치독 정지 + `handleKeyDown` 최상단 통과 가드(탭이 어떤 이유로든 살아 있어도 전부 통과하는 이중 방어). **off 중에는 아무도 탭을 되살리지 않는다** — 콜백의 `tapDisabledBy*` 재활성화도 `isInterceptionEnabled` 게이트를 탄다.
- **on 복귀** = `tapEnable(true)`를 1회 선제 호출(워치독 첫 폴링을 기다리지 않는 유일한 복귀 경로) + 워치독 재가동.

또한 이 토글과 Normal 탈출 옵션(`isNormalModeEscapeEnabled`) **둘 다 같은 소유 모델**을 쓴다: 런타임 SSOT는 `EventTapController`의 관찰 프로퍼티이고, `didSet`이 UserDefaults 저장과 부수효과(탭 enable/disable, 엔진 재생성 주입)를 함께 책임진다. UserDefaults는 팔로워라 실행 중 외부 `defaults write`는 재시작까지 무시된다.

## 배경·근거 (왜)

버그 있는 전역 키 탭은 사용자를 키보드에서 차단할 수 있어, 사용자가 즉시 끌 수 있는 마스터 토글이 필요하다. 핵심은 **off가 "통과만"이 아니라 "스트림 해방"이어야 한다**는 점이다 (2026-07-18 코드리뷰로 초안 개정):

- 초안은 "off 중에도 탭은 살려두고 콜백 최상단에서 전부 통과"(무해한 이중 안전망)였다. 하지만 그러면 모든 키가 여전히 메인 스레드 콜백을 왕복한다 — 앱이 오동작(스톨)해서 끄려는 바로 그 상황에서, off가 스톨의 원인 경로를 못 없앤다. 그래서 off는 `tapEnable(false)`로 실제 스트림을 놓아야 안전장치 목적을 지킨다. 따라서 "off 중 재활성화 유지" 전제도 틀렸음이 드러나, 콜백 재활성화까지 게이트한다.
- **소유 모델 통일** (2026-07-18 개정): 초안의 탈출 옵션은 `@AppStorage`+`onChange` 이원화였는데, "writer가 `updateConfiguration` 주입을 빼먹으면 UI 표시와 엔진 동작이 어긋난다"는 함정이 있었다. `@Observable` 클래스엔 `@AppStorage`를 못 쓰기도 해서, 프로퍼티 `didSet`이 저장+주입을 원자적으로 묶는 모델로 통일했다. `updateConfiguration`은 private(didSet 전용)이라 우회 주입을 차단한다.
- **`Status.running`의 의미**를 "탭 설치·헬스 정상"으로 정리했다 — 가로채기 on/off는 `status`가 아니라 `isInterceptionEnabled`가 표현한다. off로 설치돼 탭이 비활성이어도 설치 자체가 정상이면 `.running`이며, Settings 표시는 `eventTapStatusText`가 토글을 반영해 "Disabled"로 파생한다.
- 설정 주입이 엔진을 재생성해 모드가 Insert로 리셋되지만, 설정 조작 중이므로 수용한다.

## 검토한 대안

- **off = 탭 유지 + 통과 가드만** (초안): 스톨 원인 경로를 못 없애 안전장치 목적 미달. 기각.
- **탈출 옵션 `@AppStorage` + `onChange` 주입** (초안): 저장과 엔진 주입이 분리돼 어긋남 함정. `didSet` 단일화로 기각.
- **on/off를 `Status` enum에 케이스로**: 탭 헬스와 사용자 토글이라는 직교 축을 한 enum에 섞어 표시 우선순위가 꼬인다. 별도 프로퍼티로 분리.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md), [system-overview.md](../../architecture/references/system-overview.md)
- 앱: `EventTapController.isInterceptionEnabled`/`isNormalModeEscapeEnabled`의 `didSet`, `enableTapAndVerify`, `reenableAfterDisable` 게이트, `eventTapStatusText`.
- 워치독 게이팅("탭 설치됨 && 토글 on")·스톨 게이트 상호작용은 [20260719_watchdog-stall-gate-post-stall-recovery.md](20260719_watchdog-stall-gate-post-stall-recovery.md), 탈출 옵션 엔진 측은 [20260714_normal-mode-escape-modifiers.md](20260714_normal-mode-escape-modifiers.md).

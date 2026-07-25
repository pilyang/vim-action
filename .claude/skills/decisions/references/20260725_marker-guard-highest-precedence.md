# 마커 가드는 탭 콜백의 최우선 판정

- **결정일**: 2026-07-25

## 결정

합성 이벤트 마커 확인을 `handleKeyDown` **최상단**, 가로채기 마스터 토글 가드보다 **앞**에 둔다. 마킹된 이벤트는 번역·엔진 재해석 없이 즉시 통과한다.

마커의 게시측 짝인 `ActionExecutor.post`는 게시 함수를 주입받는다 — 프로덕션은 `.cgSessionEventTap` 게시, 테스트는 이 자리를 대체해 실제 키를 머신에 주입하지 않고 "게시되는 모든 이벤트에 마커가 찍혀 있다"만 검증한다.

## 배경·근거 (왜)

"자기 출력을 재해석하지 않는다"는 앱 상태와 **무관한** 불변식이다. 토글 뒤에 두면 "토글 on/off × 마킹 여부"의 상태 조합 중 하나가 무한 루프의 입구가 될 수 있고, 그런 루프는 사용자를 키보드에서 차단하는 최악의 실패 모드다. 상태 무관 불변식은 어떤 상태 조합보다 먼저 판정하는 것이 유일하게 안전한 순서다.

게시 seam은 워치독의 `watchdogTick`과 같은 이유다 — CGEvent 실경로는 CI·단위 테스트에서 도달하면 안 되므로(실제 키 입력이 된다), 의존을 주입해 판정만 테스트한다. 이 seam이 없으면 마커 불변식은 코드 리뷰로만 감사할 수 있다.

## 검토한 대안

- **토글 가드 뒤에 마커 확인**: off일 때 어차피 전부 통과하므로 동작은 같아 보이지만, 가드 순서가 상태 의존이 되면 이후 가드가 추가될 때마다 "이 상태에서도 마커가 먼저인가"를 재검증해야 한다. 순서 자체를 불변식으로 고정해 그 부담을 없앤다.
- **게시 seam 없이 `post`를 3줄로 두고 마커 헬퍼만 테스트**: 실제로 검증하고 싶은 명제("게시 시점에 마킹돼 있다")가 테스트에서 빠진다.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 코드: `VimAction/ActionExecutor.swift`(신설 — `SyntheticEventMarker`·`ActionExecutor`), `EventTapController.handleKeyDown` 최상단 가드
- 근거가 된 상위 결정: [20260712_synthetic-event-marker-and-failsafe.md](20260712_synthetic-event-marker-and-failsafe.md)

# Visual `.selection` 위임 가드의 불일치 스킵 로그는 상시 `.info`

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-14

## 결정

AX pin된 Visual 세션의 `.edit(op, .selection)` 위임 직전 재검증 가드([20260813_visual-selection-edit-pre-delegation-guard.md](20260813_visual-selection-edit-pre-delegation-guard.md))에서 **검증 불일치 스킵만 상시 `.info`**(번들 ID 포함)로 로그하고, **읽기 실패 스킵은 `#if DEBUG` + `.debug`** 로 남긴다.

## 배경·근거 (왜)

- 원 결정은 "스킵 사유 로그"라고만 적고 레벨을 지정하지 않았다 — 기존 Visual 스킵 관례(`skippedAXVisual` 전부 DEBUG)를 따르면 `.debug`가 기본값이다.
- 그런데 원 결정의 기각 대안("모든 Visual AX 쓰기에 수렴 폴링")에 붙은 **재검토 조건이 "도그푸딩에서 가드 불일치가 잦으면 재검토"** 다. 도그푸딩은 릴리스 빌드(Developer ID)라 `#if DEBUG` 로그는 컴파일조차 되지 않는다 — DEBUG로 두면 재검토 조건의 판정 데이터를 원리적으로 수집할 수 없다.
- 이는 [20260808_ax-illegal-argument-observation-log-level.md](20260808_ax-illegal-argument-observation-log-level.md)와 같은 규칙이다: **사후 재심사가 `log show --info`로 회수해야 하는 판정 데이터는 상시 `.info`** 이고, 그 외 스킵은 `.debug`를 유지한다. 되읽어 검증 불일치 버킷(상시 `.info` + 번들 ID)과도 같은 신호 계열이다 — "앱이 우리가 쓴 범위와 다르게 말한다".
- 읽기 실패 스킵이 DEBUG로 남는 것도 같은 선례의 반대편이다: 일시적 타임아웃은 재검토의 판정 데이터가 아니고, `.axUnavailable` 계열 관측은 auto 유래에서 이미 별도 `.info`가 있다.
- 로그에 실리는 것은 번들 ID·액션·읽은 선택의 오프셋 숫자뿐이다 — 창 본문이 릴리스 로그로 새지 않는다.

## 검토한 대안

- **전부 DEBUG (Visual 스킵 관례 일관)**: 재검토 조건의 빈도 관측이 릴리스에서 불가. 기각 (착수 전 사용자 확정).

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- `KeyboardAdapter.mapping`의 `.edit` 분기 가드 — 불일치 로그가 `mapping`에 번들 ID를 요구해 시그니처에 `bundleID` 파라미터가 추가됐다.

# `V`→`v` 전환은 상태가 아는 경우만 지원

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-04

## 결정

`V`→`v` 전환(`switchSelectionWise(linewise: false)`)은 **조건부 지원**한다: 상태가 원래 캐럿 P([협력자](20260804_visual-anchor-state-collaborator.md)가 `V` 진입 게시 직전에 읽어 보관)와 포커스 줄 거리 d(정확 linewise 모션 `j`/`k`로만 추적)를 **둘 다 알 때만** 재선택 시퀀스를 게시하고, 하나라도 모르면(`gg`/`G` 경유, 검증 실패, 읽기 실패) **현행 `nil`(정직한 스킵)을 유지**한다.

재선택 스트로크는 열 거리·줄 거리에 비례하는 **위치 상대** 시퀀스다 — 절대 오프셋 비례가 아니므로 [재조립 원칙](20260803_refinement-branches-not-stroke-counts.md) 안에 있다.

## 배경·근거 (왜)

[switchWise 결정](20260728_visual-switch-wise-focus-end-rounding.md)이 `V`→`v`를 `nil`로 둔 근거는 "원래 엔드포인트가 이미 파괴되어 복원이 원리적으로 불가능"이었다. 앵커 상태가 `V` 진입 **게시 직전**에 원래 캐럿을 읽어 두면 그 전제가 사라진다 — 파괴되기 전에 보관하는 것이므로 복원이 가능해진다.

조건부로 한정하는 이유:

1. **모르면 지어내야 한다.** `gg`/`G` 뒤의 포커스 줄 거리는 추적 불가(착지를 앱만 안다)이고, 근사로 재선택하면 "잘못된 범위를 정확하게" 만든다 — 스킵보다 나쁘다. "지원 ⟹ 정확, 아니면 정직한 스킵"이 기존 계약이다.
2. **`nil` 유지가 이미 옳은 폴백이다.** 스킵은 로그에 잡혀 게이트 심사에 드러나고(원 결정의 근거 그대로), 화면 선택은 반올림된 채 남아 사용자가 눈으로 본다.

C2로 통째로 미루지 않는 이유: 필요한 재료(원래 캐럿 보관·재앵커 메커니즘·줄 거리 추적)가 전부 C1에서 만들어지므로 한계 비용이 지금 최소이고, 플랜의 C1 해소 목록에 `V`→`v`가 명시돼 있다.

## 검토한 대안

- **무조건 지원 (모르면 근사)**: 위 1번 — 파괴적 오퍼레이터가 뒤따르는 자리라 근사 범위가 곧 데이터 손실이다. 기각.
- **C2 이연**: 세션 부담은 줄지만 재료가 다 있는 지금을 놓치고 플랜 해소 목록이 어긋난다. 기각.
- **열 거리 상한 없이 무제한 게시**: 극단 열(수백)에서 스트로크 폭주 — 청크·페이싱이 흡수하지만 상한 클램프 여부는 구현에서 실측으로 정한다(결정 유보 항목).

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [mode-engine.md](../../architecture/references/mode-engine.md)
- `VimAction/VisualKeyMapper.swift`·앵커 상태 협력자 — 구현은 후속 세션
- 관련: [재앵커](20260804_visual-backward-keyboard-reanchor.md), [자가 검증](20260804_visual-anchor-read-self-validation.md)

## Supersedes

- [20260728_visual-switch-wise-focus-end-rounding.md](20260728_visual-switch-wise-focus-end-rounding.md) — **부분**: "`V`→`v`는 복원이 원리적으로 불가능해 `nil`" 판정을 뒤집는다 (게시 전 보관으로 전제 소멸). 조건 불충족·폴백 경로에서는 `nil`과 그 로그 근거가 그대로 유효하고, `v`→`V` 방향은 [재앵커 결정](20260804_visual-backward-keyboard-reanchor.md)이 다룬다.

# AX Visual 세션 경로는 상태 폐기보다 오래 산다 — 검증 실패 뒤도 정직한 스킵

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10 (M5 PR-D1b 세션 4)

## 결정

Visual 세션의 경로 고정(pin)은 **`VisualAnchorTracker`의 프로퍼티**(`sessionPath`)이며 `VisualAnchorState`의 필드가 아니다. 쓰이는 자리는 **`beginSelection` 확정 시점 한 곳**뿐이고(AX는 쓰기 `.success` 뒤, keyboard는 `.groups` 확정 시), **자가 검증 실패나 `apply(.discard)`는 pin을 지우지 않는다.**

따라서 AX로 고정된 세션은 자가 검증이 깨져 상태를 잃어도 **남은 확장·전환을 전부 정직하게 스킵**한다 — keyboard 무상태 시퀀스로 강등하지 않는다. `clearSelection`(게시 `←`)과 `.edit(_, .selection)`(위임 `Cmd-X`/`Cmd-C`)은 그대로 동작하므로 사용자는 `Esc`·`d`·`y`로 언제든 빠져나온다.

## 배경·근거 (왜)

[경로 고정 결정](20260808_ax-visual-session-path-pinning.md)은 "세션 중간의 증명·읽기 실패는 그 액션만 정직한 스킵, 무상태 폴백 금지"를 말하면서 **자가 검증 실패 뒤**를 다루지 않았다. 검증 실패는 "그 액션의 실패"가 아니라 "세션이 죽었다는 판정"이라 두 결정([자가 검증](20260804_visual-anchor-read-self-validation.md)의 폐기 → 무상태 폴백)이 이 자리에서 갈린다. 구현 형태를 정하는 순간 답이 강제되므로(상태 필드에 두면 폐기와 함께 pin이 사라진다) 여기서 닫는다.

- **위험 시나리오가 가설이 아니다.** 자가 검증 실패의 원인 중 하나가 "앱이 우리가 쓴 범위를 정규화·클램프"인데, 세션 0 실측에서 TextEdit가 정확히 그렇게 행동했다(서로게이트 쌍 한가운데 범위 `[3,1]` → `[2,2]` 조용한 클램프). 그때 화면에 남은 선택은 **AX가 쓴 범위**이고, Visual `.ax`는 뒤에 게시할 것이 없어 되읽어 검증도 걸리지 않으므로 어긋남을 그 자리에서 잡지 못한다. 거기에 무상태 `Shift-→`를 얹는 것이 경로 고정 결정이 말한 "파괴 방향 동전 던지기"다 — 앱이 어느 끝을 포커스로 보는지 미정의이므로 앵커 반대쪽으로 자랄 수 있고, 뒤따르는 `d`가 엉뚱한 텍스트를 지운다.
- **틀리는 방향이 갈린다.** pin이 살아남으면 실패는 무동작(강등)이고, 사라지면 실패는 파괴다. 이 PR 전체가 반복해 온 선택이다.
- **낡은 pin이 남을 창이 없다.** 읽는 자리는 세션 액션(`extendSelection`·`switchSelectionWise`)뿐이고, 세션 액션에는 언제나 `beginSelection`이 앞선다 — 탈출 콤보로 `clearSelection` 없이 Visual을 빠져나가도 다음 진입이 pin을 덮어쓴다.
- 부수 효과로 `VisualKeyMapper`의 상태 생성자 5곳(재앵커 기계)이 무변경으로 남는다 — "keyboard 재앵커 기계는 폴백 전담으로 손대지 않는다"는 세션 제약과 같은 방향이다.

## 검토한 대안

- **`VisualAnchorState`의 필드**: 수명이 하나라 더 단순하고 `.set`마다 자동으로 따라다닌다. 그러나 폐기와 함께 경로를 잊으므로 위 클램프 시나리오에서 곧바로 무상태 시퀀스가 나간다 — 경로 고정 결정의 뿌리를 부분 번복하는 셈이라 기각.
- **검증 실패 시 상태를 폐기하지 않고 재도출**: 선택 하나만으로는 어느 끝이 앵커인지 알 수 없어 원리적으로 불가.

## 수용 편차

AX 세션에서 자가 검증이 한 번 깨지면 **재진입 전까지 확장·전환이 무반응**이다. 헛폐기가 잦은 앱이 발견되면(도그푸딩 스킵 로그 빈도가 판정 데이터다) 양단 검증 승격과 함께 재심사한다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (Visual 세션 경로 고정 문단)
- `VimAction/VisualAnchor.swift`(`VisualAnchorTracker.sessionPath`·`pin(_:)`), `VimAction/KeyboardAdapter.swift`(`confirmVisual`·`axVisualMapping`·`axVisualSession`)
- 도그푸딩 판독 주의: AX 앱에서 마우스 클릭 등으로 검증이 깨진 뒤 Visual 확장이 무반응인 것은 의도된 동작이다(스킵 로그가 증거).

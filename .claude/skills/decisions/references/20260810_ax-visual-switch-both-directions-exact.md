# AX 세션의 `v`↔`V` 전환은 양방향 정확 지원 (조건부 아님)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10 (M5 PR-D1b 세션 4)

## 결정

AX로 고정된 Visual 세션에서 `switchSelectionWise`는 **양방향 모두 AX 범위 쓰기**로 지원한다. 산출은 `FocusedTextOffsets.visualSwitchSelection(toLinewise:anchor:in:)`이며, 반환 타입이 범위뿐 아니라 **새 논리 앵커와 희망 열을 함께** 낸다(`Selection`) — 전환은 논리 앵커 자체가 이동하는 유일한 어휘라 범위만으로는 다음 상태를 세울 수 없다(`v`→`V` 후진형의 새 앵커는 범위의 끝점이 아니라 한가운데다).

- `v`→`V`: 선택이 걸친 논리 줄 전체, 새 앵커는 앵커 줄 시작. **charwise 앵커를 `originalCaret`에 보관**한다.
- `V`→`v`: `[원래 캐럿 P, 포커스 줄의 희망 열]`. 열이 줄을 넘으면 Vim처럼 종결자까지 클램프한다.
- 증명 실패(P 미상 — ⑥으로 만들어진 keyboard 세션에서 넘어온 경우, 열 미상, 창이 줄 경계에 못 닿음)는 정직한 스킵이다.

keyboard 경로의 조건부 지원(`originalCaret` + 포커스 줄 거리 + 상한 32)은 **무변경**이며 폴백 세션 전담으로 남는다.

## 배경·근거 (왜)

세션 1은 `v`↔`V`의 범위 산출을 **일부러 만들지 않았다** — "`V`→`v`가 포커스 열을 요구하는데 창으로 증명되지 않아 추측 코드가 된다"가 사유였다. 세션 4에서 확인해 보니 **그 사유는 keyboard 경로 전용**이었다:

- keyboard는 열을 스트로크 수로 재현해야 해서 `originalCaret` + 포커스 줄 거리 추적이 둘 다 필요했고, 그래서 [조건부 지원](20260804_visual-switch-charwise-conditional.md)이 나왔다. `v`→`V`가 만든 세션에서 `originalCaret`을 회수한 것(PR-C1 세션 2 리뷰 반영)도 열 근사가 그 세션에서만 성립하기 때문이었다.
- AX는 `V` 진입에서 원래 캐럿을 **정확히 읽어** 두고 포커스 줄 시작도 창이 답하므로 열이 뺄셈이다. 스트로크가 아니라 범위 1회 쓰기라 상한 32도 페이싱도 필요 없다.

Vim 실측이 모델을 확인했다(`/usr/bin/vim -Nes -u NONE`): `llVjv`는 `'<`=1:3 `'>`=2:3 — `V`→`v`가 **원래 캐럿 열**을 포커스 열로 쓴다. `llvjVv`는 `llvj`와 **같은 선택**을 낸다 — `v`→`V`→`v`가 원래 charwise 선택을 복원한다. 그래서 `v`→`V`가 charwise 앵커를 보관하면 왕복이 정확해진다.

- **열 전제는 새 가정이 아니다.** "`V` 세션의 Vim 커서 열 = 진입 캐럿 열"은 [charwise 모션 스킵 결정](20260804_visual-linewise-motion-range-noop.md)이 이미 수용한 편차 위에 선다 — AX 경로도 `V` 세션의 charwise 모션을 `.invalid`로 접으므로 같은 전제가 그대로 성립한다.
- **스킵은 회귀다.** `v`→`V`는 keyboard 세션에서 이미 정확히 동작한다(⑥). AX 앱에서만 `vjV`가 무동작이 되면 정확화를 켠 앱이 더 나빠진다.
- **`V`→`v`까지 여는 비용이 작다.** 두 방향이 같은 타입·같은 함수의 두 분기이고, AX에서는 keyboard ⑦이 필요로 하던 초집합 봉쇄 가드(포커스 줄에 그 열의 문자가 실재하는가)가 클램프로 대체된다 — Vim이 실제로 클램프하기 때문이다(실측).

## 검토한 대안

- **양방향 정직한 스킵**: 가장 작지만 위 회귀. 게다가 `v`→`V` 스킵 뒤에는 상태 wise(charwise)와 엔진 wise(linewise)가 갈려 이어지는 `j`/`k`가 charwise 경로로 흘러 또 스킵된다 — 세션이 통째로 죽는다.
- **`v`→`V`만 지원**: 비용 차이가 브랜치 하나라 거의 없는데, 우리가 이미 정확히 들고 있는 값(`originalCaret`·희망 열)을 버리는 선택이다. keyboard 세션은 되는데 AX 세션만 안 되는 비대칭도 남는다.
- **`Span` 반환 유지 + 앵커를 어댑터가 도출**: `v`→`V` 후진형의 새 앵커(앵커 줄 시작)가 범위의 끝점이 아니라 어댑터가 창 없이 계산할 수 없다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (산출 함수 표 + Visual 문단)
- `VimAction/FocusedTextOffsets.swift`(`Selection`·`visualSwitchSelection`·`roundedToLines`·`restoredToCharacters`), `VimAction/KeyboardAdapter.swift`(`axVisualMapping`의 전환 분기)
- 도그푸딩 판독: AX 앱에서 `vjV` 뒤 `v`가 **원래 charwise 선택으로 정확히 되돌아오는 것**이 정답이다(keyboard 세션은 종전대로 스킵).

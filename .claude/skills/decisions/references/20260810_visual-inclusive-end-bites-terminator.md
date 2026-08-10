# Visual charwise 확장의 inclusive 끝은 종결자도 문다 (Vim 실측 정정)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-10 (M5 PR-D1b 세션 4 — 착수 실측 후 정정)

## 결정

`FocusedTextOffsets`의 Visual charwise 확장에서 inclusive 끝은 **포커스 + 1**이며, 포커스가 줄 종결자 위여도 예외가 아니다(`inclusiveEnd(i) = min(i + 1, count)`). 세션 1의 "줄 끝(종결자 앞)이면 그 자리 그대로 — `v$`가 개행을 물지 않는다"를 뒤집는다.

같은 정정의 짝으로 `$`(`.lineEnd`/`.lineEndForAppend`)는 "글자 **뒤**에 착지하는 모션"이 아니다 — 목표가 종결자 **위**라 위 규칙을 그대로 지난다. 그 분류에 남는 것은 `e`(`.wordEndForward`) 하나뿐이다.

## 배경·근거 (왜)

세션 1은 이 규칙을 Vim 실측으로 세웠다고 기록했으나, 실제로는 **마지막 줄에서만 잰 값**이었다(마지막 줄에는 물 종결자가 없어 두 규칙이 같은 답을 낸다). 세션 4 착수 실측이 비-마지막 줄에서 갈림을 드러냈다 (`/usr/bin/vim -Nes -u NONE`, 레지스터 길이·내용 판정):

| 입력 | 문서 | 레지스터 |
|---|---|---|
| `v$` | `["ab","cd"]` | `"ab\n"` (len 3) — **개행 포함** |
| `v$` | `["ab"]` (마지막 줄) | `"ab"` (len 2) |
| `lvl` | `["ab","cd"]` | `"b\n"` (len 2) — 줄 마지막 글자의 `l`도 개행을 문다 |
| `ve` | `["ab","cd"]` | `"ab"` — `e`는 글자 뒤라 안 문다 |
| `vw` | `["ab","cd"]` | `"ab\nc"` |

Vim에서 Visual 커서는 줄 끝(종결자 자리)에 설 수 있고, `selection=inclusive`가 그 자리를 선택에 포함시킨다. 그래서 `v$d`·`vld`가 줄을 **병합**한다.

- **정확성이 이 계층의 존재 이유다.** AX 경로는 "표가 침묵하는 자리는 Vim 정확값"이 계약이고([20260809](20260809_ax-span-vim-exact-where-table-is-silent.md)), Visual 확장의 답은 정확화 표가 아니라 Vim이 정한다. 틀린 값을 유지할 근거가 없다.
- **이 정정이 없으면 희망 열 추적이 성립하지 않는다.** 열이 줄 길이보다 클 때 Vim은 포커스를 종결자 위에 두는데(아래 결정), 종결자를 거부하면 `vj`가 한 글자 짧은 범위를 내고 `d`가 줄을 병합하지 않는다 — 같은 규칙의 두 얼굴이다.
- 소비자가 아직 없던 시점의 값이라 정정 비용이 픽스처 두 줄이다(세션 4가 Visual의 첫 소비자다).

## 검토한 대안

- **세션 1 값 유지(종결자 거부)**: 내부 일관성은 있으나 `vj`·`v$`·`vl`이 전부 Vim보다 한 글자 짧아지고, 줄 병합이 필요한 자리에서 조용히 안 일어난다. 실측과 어긋난 값을 유지할 근거가 없어 기각.
- **`$`만 예외 처리**: `l`·`j`도 같은 자리를 겪으므로 표가 된다 — 규칙 하나로 닫는 편이 맞다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (Visual 확장 문단)
- `VimAction/FocusedTextOffsets.swift`(`Window.inclusiveEnd`·`landsPastCharacter`), 픽스처 `vl — 줄 마지막 글자에서는 개행까지`
- 도그푸딩 판독: AX 앱에서 줄 끝 `vl`·`v$` 뒤의 `d`가 **줄을 병합**하는 것이 정답이다(Vim과 같다).

## Supersedes

- [20260809_ax-span-vim-exact-where-table-is-silent.md](20260809_ax-span-vim-exact-where-table-is-silent.md) — **부분**: "`e`·`$`는 캐럿 모델에서 이미 글자 뒤라 inclusive를 더하지 않는다" 중 **`$` 부분**과 그 근거로 적힌 "`v$`가 개행을 물지 않는다(Vim 실측)". `e`의 규칙과 나머지 실측 14건, `.unproven` 강등 규칙은 그대로 유효하다.

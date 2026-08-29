# Keyboard 어댑터

- **Last updated**: 2026-08-20 (문서 분할 — [strategy-dispatch.md](strategy-dispatch.md)에서 이관 + 심볼 표기 정정: `pasteStrokeGroups` 실명, 설정 어휘 `open_line`)

## 현재 구조

### 요소 계열(element family)과 걸러내기

`ElementFamily`는 `.textArea` / `.textField` / `.nonText` / `.unresolved` 넷이며 리졸버가 보고한다([focus-and-dispatch-reads.md](focus-and-dispatch-reads.md)). `.unresolved`는 앱 전환 직후 첫 읽기가 아직 착지하지 않은 상태로, 폴백(`.textArea`)과 구분되는 별개 값이다. **계열은 시퀀스를 다변화하지 않는다 — 걸러낼지만 정한다.** `.textField`는 편집·Visual·붙여넣기·undo에서 `.textArea`와 같은 시퀀스를 쓴다 — 단일행 필드에서 자연 수렴하고, 전용 분기는 role 오보고 시 실패 방향이 비대칭으로 나쁘다 ([20260801_textfield-edit-sequences-scrapped.md](../../decisions/references/20260801_textfield-edit-sequences-scrapped.md)).

두 계열:

- **key-mapping**: 리졸버를 참조해 요소 인식 시퀀스 선택. 기본값.
- **force-text**: 항상 TextArea 시퀀스. 프로파일 명시 선택 전용(`keyboard_family: force_text`), 자동 감지·자동 폴백 없음. 구현은 실효 계열 치환 — `KeyboardAdapter.mapping` 진입부 한 곳의 로컬 `effectiveFamily`가 **keyboard 실행 쪽에만** 흐른다(걸러내기 게이트·매퍼 호출·매퍼 내부 `.nonText` 봉쇄·하이브리드 위임분 진입점). `usesAXWrite`·AX 분기의 계열 판정은 **원본 family**를 유지한다 — 치환이 AX까지 새면 비텍스트 요소에 AX 쓰기가 나가고 `.unresolved` 창이 뚫린다. AX 강등·`unproven` 위임이 낳는 keyboard 실행은 같은 `mapping` 호출 안의 순차 낙하라 치환을 자연히 승계한다. execute 요약 로그의 계열 표기는 원본이다(감사 목적). 회귀 테스트는 `KeyboardAdapterForceTextAXTests` ([20260813_force-text-keyboard-family-substitution.md](../../decisions/references/20260813_force-text-keyboard-family-substitution.md)).

**걸러내기 표** — 계열이 실제로 가르는 전부다:

| 액션 | `.textArea` | `.textField` | `.nonText` | `.unresolved` |
|---|---|---|---|---|
| `.move` · `.scroll` | 게시 | 게시 | **게시** | **게시** |
| `.edit` · Visual 4종 · `.paste` · `.undo` · `.redo` | 게시 | 게시 | `nil` 스킵 | `nil` 스킵 |
| `.openLine` (`o`/`O`) | 게시 | **`nil` 스킵** | `nil` 스킵 | `nil` 스킵 |

`.nonText`에서 모션·스크롤이 살아남는 것은 위험 축이 "비텍스트인가"가 아니라 **"앱이 이미 아는 명령인가"** 이기 때문이다(Finder에서 `p`는 파일 붙여넣기, 화살표는 무해·유용). 엔진이 이미 키를 삼킨 뒤라 스킵은 완전 무동작이다 ([20260801_non-text-filter-keeps-motion-and-scroll.md](../../decisions/references/20260801_non-text-filter-keeps-motion-and-scroll.md)). `.unresolved`가 `.nonText`와 같은 열인 것은 **모르는 동안은 위험 어휘를 보류한다**는 규칙이고, 모션·스크롤까지 막지 않는 것은 이 창이 앱을 옮길 때마다 열리기 때문이다 ([20260801_unresolved-window-after-app-switch.md](../../decisions/references/20260801_unresolved-window-after-app-switch.md)).

### 게이트 위치와 비-QWERTY 축

**걸러내기 게이트는 `KeyboardAdapter.mapping(for:family:)` 최상단 한 곳**이며 매퍼가 아니다 — 게이트가 매퍼면 세 부수효과를 앞설 수 없다(`.move`는 family 무관이 계약, `.edit`의 `recordEdit` 오염, `.paste`의 클립보드 선읽기 오집계). 매퍼 쪽에는 `.nonText → nil` 봉쇄만 남는다. 걸러내기 스킵은 **미지원(`.unsupported`) 경로로 집계**되고, 요약 로그에 결정된 계열이 함께 실려 심사자가 "미구현"과 "의도적 걸러내기"를 구분한다.

같은 자리에 **비-QWERTY 레이아웃 처리**가 나란히 선다: `KeyTranslator`가 레이아웃 캐시를 채울 때마다 키코드 4종(`kVK_ANSI_Z/X/C/V`)의 **행동 검사**(번역 결과가 기대 문자인가 — 레이아웃 ID 화이트리스트 아님)로 `hasQwertyCommandKeys`를 캐시하고, 같은 자리에서 키코드 0~50 역조회로 `z/x/c/v`를 내는 실제 키코드를 둘째 잠금 상자 `commandKeyCodes`에 캐시한다(두 값의 갱신 트리거·생명주기가 같아 어긋날 창이 없다). 어댑터는 문자 명령 키를 합성하는 액션(`.edit`·`.paste`·`.undo`·`.redo`)에 대해 액션마다 레이아웃 상태를 한 번만 읽고: QWERTY면 그대로 통과, 비-QWERTY면 필요 문자를 테이블에서 찾아 **게시 직전 논리 ANSI 키코드 6/7/8/9를 역조회 키코드로 치환**한다(플래그 보존). 못 찾으면 보류한다(`Mapping.layoutBlocked` — AZERTY에서 `Cmd-Z`가 `Cmd-W`로 나가는 데이터 손실 축의 최후 방어선). 매퍼는 ANSI 상수를 **논리 키코드**로 내고(매퍼 순수성·골든 무변경), 화살표·Return만 쓰는 액션은 이 축을 아예 지나지 않는다 ([20260806_non-qwerty-command-key-reverse-lookup.md](../../decisions/references/20260806_non-qwerty-command-key-reverse-lookup.md), [20260801_non-qwerty-command-key-layout-guard.md](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)).

### 매퍼 공통 계약

키 시퀀스 생성은 **네 순수 매퍼**(`MotionKeyMapper` / `EditKeyMapper` / `VisualKeyMapper` / `CommandKeyMapper`)가 담당하고, 어댑터는 나온 `[KeyStroke]`를 CGEvent 쌍으로 바꿔 게시한다. 매퍼 `nil` = 미지원(스킵+요약 DEBUG 로그). **네 매퍼 어디도 빈 배열을 반환하지 않는다** — "지원 ⟹ 빈 시퀀스 아님"이 공통 불변식이고, 게시할 것이 없으면 `nil`(정직한 스킵)이다(무로그 삼킴 금지). CGEvent 변환은 **액션 단위 all-or-nothing** — 스트로크 하나라도 실패하면 액션 전체를 버리고 error 로그를 남긴다(부분 시퀀스는 파괴적).

어댑터의 스킵은 **네 종류로 갈린다**: 매퍼 `nil` = 미지원 / `skipped` = 지원하지만 이번 입력에는 게시할 것 없음(사유를 아는 자리에서 자체 로그) / `layoutBlocked` = 비-QWERTY 보류(별도 요약) / `disabledByProfile` = 프로파일 disable(별도 요약). 섞이면 심사자가 구현된 어휘를 미구현으로, 사용자 설정을 버그로 읽는다.

**편집과 Visual은 분류 프로브가 셋**이다 — 매퍼가 읽기를 받으면서 `nil`이 "미지원"과 "정확화가 증명한 무게시" 두 뜻을 갖기 때문이다. 전용 함수 `classifyEdit`/`classifyVisual`이 ① 정확화 입력을 넘긴 호출 → ② 정확화 프로브(입력 없이 재조회, 값이 나오면 `.skipped`) → ③ builtIn 프로브(`profile: .empty`, 정확화 입력 비수신) 순서로 묻고, 그 순서를 **구조가 강제한다**(정확화 입력을 받는 자리를 각 함수 안 한 곳으로 닫음 — 어긋나면 정확화 결과가 `.unsupported`로 오집계. 매퍼 쪽도 같다 — `VisualKeyMapper.keyStrokes(...anchor:)`의 `anchor`에 기본값이 없어 호출부가 상태를 조용히 빠뜨리면 컴파일이 실패한다). 모션·명령 매퍼는 프로브 둘이다 ([20260803_edit-keystrokes-takes-focused-text.md](../../decisions/references/20260803_edit-keystrokes-takes-focused-text.md)).

### 편집 매퍼 — `EditKeyMapper`

`(Operator, TextRange, ElementFamily, ResolvedProfile, FocusedText?) → [KeyStroke]?`. 모든 편집이 한 형태다: **범위를 Shift+모션으로 선택한 뒤 오퍼레이터 1타**(delete·change = `Cmd-X`, yank = `Cmd-C` + `←` collapse). 선택 스트로크는 모션 매핑 결과에 `.maskShift`를 얹어 만들므로 다타 조합도 그대로 성립하고, 모션별 특례는 `cw`→`ce` 하나뿐이다. linewise 반올림은 오퍼레이터별(delete/yank는 개행 포함, change는 줄 유지), 문서 끝에서는 빈 줄 1개가 남는다. `iw`의 무상태 시퀀스는 3타(`Opt-→,Opt-←` 후 `Shift-Opt-→`)이며, 읽기가 성공하면 아래 정확화 표가 갈라내고 남는 무상태 엣지는 2자 이상의 공백·구두점 런뿐이다. 수용 엣지: Notion의 `Shift-Cmd-↑/↓` 블록 이동 충돌(M4 프로파일 몫 — [20260727_notion-cmd-shift-vertical-conflict.md](../../decisions/references/20260727_notion-cmd-shift-vertical-conflict.md)), 소프트 랩 문단의 시각 줄 linewise(창 읽기로 해소 불가 — [20260803_soft-wrap-linewise-not-resolved-by-window-read.md](../../decisions/references/20260803_soft-wrap-linewise-not-resolved-by-window-read.md)). 문서 경계 포화 엣지 5종은 정확화 표로 전부 해소됐다. ([20260727_edit-keystroke-mapping-contract.md](../../decisions/references/20260727_edit-keystroke-mapping-contract.md), [20260727_linewise-newline-rounding.md](../../decisions/references/20260727_linewise-newline-rounding.md), [20260727_yank-collapse-to-range-start.md](../../decisions/references/20260727_yank-collapse-to-range-start.md), [20260727_inner-word-anchor-via-word-end.md](../../decisions/references/20260727_inner-word-anchor-via-word-end.md))

**정확화 표** — 읽기가 증명하면 시퀀스가 갈리고, 증명하지 못하면 무상태 시퀀스가 그대로 나간다. 전부 캐럿(`selection.length == 0`)일 때만 발동한다(살아 있는 선택은 출발점 증명 불가).

| 모션 / 범위 | 증명된 조건 | 결과 |
|---|---|---|
| `charRight` | 줄 끝 & 줄에 글자 있음 | `Shift-←` 1타 — **엣지 1** |
| `charRight` | 줄 끝 & 빈 줄 | 무효 (스킵) |
| `charRight` | 줄에 남은 글자 `r < count` | `Shift-→ × r` |
| `charLeft` | 줄 시작 (문서 시작 포함) | 무효 |
| `charLeft` | 앞에 남은 글자 `r < count` | `Shift-← × r` |
| `wordForward` | 캐럿 뒤 단어 시작 없음 | `Shift-Opt-→` 1타(= `ce`), 카운트 무관 — **엣지 3** |
| `wordEndForward` | 문서 끝 | 무효 |
| `wordBackward` | 문서 시작 | 무효 |
| `lineEnd` / `lineStart` | 줄 끝 / 줄 시작 | 무효 |
| `lineFirstNonBlank` | 캐럿이 그 줄 첫 비공백 | 무효 |
| `.linewiseMotion(.lineUp, n)` | 위 줄 수 `< n` | 무효 — **엣지 2** |
| `.linewiseMotion(.documentStart)`, `op != .change` | 마지막 줄 | 접두를 `Cmd-→`로 (= `cgg` 시퀀스) — **엣지 4** |
| `.textObject(.word(.inner))` | 캐럿 런이 1자 | `Shift-→` 1타 |
| `.textObject(.word(.inner))` | 줄 끝 && 직전이 `keyword` | `Shift-Opt-←` 1타 |
| `wordEndForward`, `cw` 리타깃, `count == 1` | 캐럿이 런의 마지막 글자 | `Shift-→` 1타 |
| `wordEndForward`, `cw` 리타깃, `count == 1` | 줄 끝 (문서 끝 포함) | `Shift-←` 1타 |
| `wordEndForward`, `cw` 리타깃, `count == 1` | 빈 문서 | 무효 |

무효는 매퍼 `nil` → 어댑터 `.skipped`이며 선택 스트로크도 나가지 않는다. 판정은 시퀀스와 **같은 `cw` 리타깃 함수**를 거치고 그 함수가 리타깃 여부까지 돌려준다 — 진짜 `ce`·`de`는 `cw` 행에 들어오지 않는다. 기본값은 "증명 못 함 = 현행 시퀀스"라 조용한 억제·조용한 재조립이 생기지 않는다.

**줄 끝에서만 Vim의 블록 커서 모델을 따른다** — 적용 범위는 `charRight`(엣지 1)와 단어 어휘 `iw`·`cw` 셋. 단어 어휘는 "커서가 놓인 대상"을 고르는 어휘라 모델 선택이 액션 안에서 닫힌다. 모션 쪽은 계속 캐럿 모델이다. `iw`의 줄 끝만 `keyword` 한정인 것은 `Opt-←`가 구두점을 건너뛰기 때문이다 ([20260803_line-end-cursor-model-for-word-objects.md](../../decisions/references/20260803_line-end-cursor-model-for-word-objects.md), [20260803_line-end-charwise-vim-cursor-model.md](../../decisions/references/20260803_line-end-charwise-vim-cursor-model.md)).

설계 축은 **읽기를 분기의 근거로만 쓰는 것**이다: 오프셋 비례 스트로크는 채택하지 않으므로 재조립 결과는 위치 상대적이거나, 현행의 부분집합이거나, 상수 1타다 — `execute` 사이의 낡은 읽기에서도 최악이 현행 동작을 넘지 않는다. 유일한 예외가 엣지 1의 방향 반전(왼쪽 1글자, 명시 수용)이고, 부수 효과로 원자 그룹·청크 규칙에 새로 걸리는 것이 없다(재조립이 현행보다 길어지지 않는다). 남는 한계는 소프트 랩 미탐지(증명이 서지 않아 현행 동작 — 놓치는 방향) ([20260803_refinement-branches-not-stroke-counts.md](../../decisions/references/20260803_refinement-branches-not-stroke-counts.md), [20260803_boundary-saturation-refinement-table.md](../../decisions/references/20260803_boundary-saturation-refinement-table.md), [20260803_constant-stroke-word-refinement.md](../../decisions/references/20260803_constant-stroke-word-refinement.md), [20260802_empty-selection-edit-suppression.md](../../decisions/references/20260802_empty-selection-edit-suppression.md)).

### Visual 매퍼 — `VisualKeyMapper`

선택 **세션**(진입·확장·wise 전환·이탈)만 담당한다 — 선택에 오퍼레이터를 적용하는 `.edit(op, .selection)`은 `EditKeyMapper` 몫(`Cmd-X`/`Cmd-C` 1타, 계열 분기 밖)이다.

**앵커 상태 — `VisualAnchorTracker`** (`PasteWiseResolver` 동형의 주입 협력자, 게시 직렬 큐 단독 소유): 논리 앵커 A(UTF-16 절대 오프셋)·wise·**side**(앱에 박힌 앵커가 논리 앵커의 왼쪽=전진형 / 오른쪽=후진형 어느 끝인가)·**`pinnedEnd`**(앱 앵커의 절대 오프셋 — 검증 비교값, linewise 재앵커에서는 파생 불가라 수립·재앵커 시점 기록)·pid·원래 캐럿(`V` 전용)·포커스 줄 거리(정확 모션 `j`/`k`로만 추적, `gg`/`G` 뒤 미상 — 폴백 확장은 미상으로 좁힌다, 낡은 known이 남지 않게)를 든다. 수립은 `beginSelection` **게시 직전**의 캐럿 읽기다 — 진입 시퀀스가 원래 캐럿을 파괴하므로 이 시점뿐이며, 캐럿(길이 0)·줄 시작(`V`)을 증명하지 못한 진입은 수립하지 않고 옛 상태만 폐기한다(새 진입이 옛 세션을 절대 남기지 않는다) ([20260804_visual-anchor-state-collaborator.md](../../decisions/references/20260804_visual-anchor-state-collaborator.md)).

**자가 검증**: 매 Visual 액션의 읽기에서 앵커 쪽 끝 + pid 일치 + 선택이 비어 있지 않음을 확인한다(포커스 쪽은 착지를 앱만 안다). 불일치·상태 부재면 상태 폐기 + **현행 무상태 시퀀스 폴백**(Slack·VS Code에서는 상시 경로, 전용 무효화 신호 없음 — 헛실패 방향이 "현행 강등"이라 안전). **읽기 실패는 폐기 트리거가 아니다** — 그 액션만 폴백하고 상태는 남긴다(타임아웃 1회로 세션을 잃지 않게). 단 linewise의 포커스 줄 거리만은 그때도 미상으로 좁힌다(낡은 거리가 남으면 `V`→`v`가 잘못 재선택) ([20260804_visual-anchor-read-self-validation.md](../../decisions/references/20260804_visual-anchor-read-self-validation.md)).

매퍼는 시퀀스와 **상태 변화(`VisualAnchorUpdate`)를 함께** 반환하고 어댑터는 게시 확정된(`.groups`) 액션의 것만 적용한다(`recordEdit`과 같은 규칙 — 검증 실패의 폐기만 예외). 적용은 게시 전(매핑 확정 시점)이므로 중단·CGEvent 생성 실패의 **드롭 경로는 상태를 폐기한다** — 재앵커 `.set`이 화면과 어긋난 채 남으면 자가 검증을 거짓 통과하는 유일한 자리다.

**정확화**는 전부 `VisualKeyMapper.refined` 한 함수의 분기이며 반환은 3상태(`.invalid` = 증명된 무게시 → `.skipped` / `.refined` / `.unproven` = 무상태 위임)다. **정확화 다타 시퀀스는 페이싱 대상**(`VisualStrokes.paced` — 스트로크 사이 5ms 단독 게시. 스크롤·카운트 버스트·폴백 경로는 타이밍까지 현행 그대로다 — [20260805_visual-refined-group-stroke-pacing.md](../../decisions/references/20260805_visual-refined-group-stroke-pacing.md)). 경로 넷:

1. **후진·방향 전환은 재앵커 시퀀스** — 선택을 앵커 반대쪽 끝으로 접고(collapse 1타 접두 — [20260805_reanchor-prefix-collapse-shortcut.md](../../decisions/references/20260805_reanchor-prefix-collapse-shortcut.md)) 위치 상대 스트로크로 재확장한다. 후진형에서는 진입 `Shift-→`의 +1 원점 이동이 없어 연속 후진이 무보정 정확하다. 구현된 재앵커: charwise `h`(진입형 `→`+`Shift-←×2`)·`l`(후진형이 앵커에 닿은 뒤의 전진 — `←`+`Shift-→×2`, `vhll`의 둘째 `l`)·`b`(진입형 `→`+`Shift-Opt-←`, 캐럿이 좁은 정의의 단어 시작이면 ×2), linewise `k`(d=0에서 `→`+`Shift-↑×2`, 첫 줄은 증명된 무게시)·`j`(후진형 d=0에서 `←`+`Shift-↓×2` — `Vkjj`의 둘째 `j`)·`gg`(`←,↓` 후 `Shift-Cmd-↑` 상수 1타 — d 미상에도 성립). **개행 없는 마지막 줄**의 `k`·`gg`는 `→, Shift-Cmd-←` 변형으로 재앵커한다(`isAtDocumentEnd` 증명 조건 — 없으면 폴백이 앵커를 넘는 크로싱이 된다). 축소 방향은 폴백과 같은 1타를 내며 거리만 ±1로 유지한다(폴백은 미상으로 좁히므로 이 차이가 `V`→`v` 조건부 지원의 생명선). 확장·재앵커의 거리 갱신은 창 증명(선택 끝 다음 문자 실재, 선택 끝의 줄 시작 여부)이 설 때만이다 — 문서 경계 포화로 화면은 안 움직이는데 거리만 어긋나는 것을 막는다. 앵커가 줄 시작이면 `h`를, 줄 끝이면 `l`을 재앵커하지 않는다 — Vim은 줄을 넘지 않으므로 재앵커가 개행을 선택하는 파괴적 회귀가 된다 ([20260804_visual-backward-keyboard-reanchor.md](../../decisions/references/20260804_visual-backward-keyboard-reanchor.md)).
2. **`V` 세션의 charwise 모션(`h l w b e 0 ^ $`)은 무게시 `.skipped`** — Vim에서 범위 무변화가 정확 동작이고 desync 실패 모드는 무해한 no-op다. 열 이동이 없는 것은 수용 편차이며 그 덕에 ④의 열 근사가 실제로 일치한다 ([20260804_visual-linewise-motion-range-noop.md](../../decisions/references/20260804_visual-linewise-motion-range-noop.md)).
3. **`v`→`V`는 앵커 쪽도 줄 반올림한다** — 재앵커로 앵커를 줄 시작(전진형 `←,Cmd-←`) 또는 줄 끝 다음(후진형 `→,↓,Cmd-←`)에 재수립하고 줄 거리(선택 내부의 개행 수 — 창 안에 들어올 때만 증명)만큼 재확장하며, 상태를 완전히 재수립한다. 단 `originalCaret`은 보관하지 않는다 — ④의 열 근사는 `V` 진입 세션에서만 성립한다. 증명 실패의 폴백 `v`→`V`는 검증을 거짓 통과하므로 게시 시점에 상태를 폐기한다.
4. **`V`→`v`는 원래 캐럿 P와 줄 거리 d를 다 알 때만** 위치 상대 시퀀스(`collapse, →×열, Shift-↓×d, Shift-→` 꼴)로 재선택하고, 모르면 현행 `nil`(정직한 스킵)이다. 추가로 포커스 줄에 목표 열의 문자가 실재함을 창에서 증명해야 한다(Vim 커서와 macOS 캐럿의 클램프가 갈려 개행을 집는 초집합이 된다 — 전진형은 `selectionLastLineLength`, 후진형은 줄 시작 증명 + 앵커 줄 이탈 가드). 열·줄 거리는 공통 상한 32로 클램프(`reselectSpanClamp` — 페이싱 그룹은 원자라 내부 중단이 없어 폭주를 여기서 자른다) ([20260804_visual-switch-charwise-conditional.md](../../decisions/references/20260804_visual-switch-charwise-conditional.md)).

폴백 시퀀스는 종전 그대로다: `v`=`Shift-→`(inclusive), `V`=`Cmd-←, Shift-↓`, `v`→`V`=`Shift-↓, Shift-Cmd-←`(포커스 줄만), `V`→`v`=`nil`, `clearSelection`=`←`(collapse 전담 — 그래서 `.selection` yank는 `Cmd-C`만 낸다). `extendSelection`의 폴백·전진 경로는 `MotionKeyMapper.selectionStrokes(for:)`의 순수 재사용이라 모션 매핑 개선이 편집·Visual에 동시 전파된다. 수용 엣지: **앵커 크로싱**(한 모션이 앵커를 한 번에 넘는 경우 — 착지를 앱만 알아 게시 전 판정 불가, 현행도 틀리는 케이스라 악화 없음). ([20260728_visual-charwise-entry-inclusive-selection.md](../../decisions/references/20260728_visual-charwise-entry-inclusive-selection.md), [20260728_visual-clear-selection-collapse-left.md](../../decisions/references/20260728_visual-clear-selection-collapse-left.md))

### 명령 매퍼 — `CommandKeyMapper`

**네이티브 명령 위임 계열**(`o`/`O`·`p`/`P`·`u`/`Ctrl-r`·스크롤) 담당 — 앱이 아는 명령 키 하나에 위임하고, 우리가 조립하는 것은 위치 접두뿐이다(접두는 전부 `MotionKeyMapper` 재사용). 진입점은 2개(`keyStrokes(for:family:)` + `pasteStrokeGroups(before:count:wise:family:profile:text:)` — 붙여넣기만 wise 입력 필요)이고, 여기에 **위임분 진입점 2종**(`openLineDelegatedStrokes(above:family:profile:)`·`pasteDelegatedGroups(count:appendsLine:family:profile:)`)이 나란히 선다 — 위치 접두를 뺀 나머지(`Return`(+`O`의 `↑`)·`Cmd-V`×count)를 내며, keyboard 진입점 둘이 그 위에 접두를 얹는 형태다(`appendsLine`이 하이브리드의 `[Return, Cmd-V]` 합성이 켜지는 자리). "하이브리드가 갈아끼우는 것은 접두뿐"이라는 계약을 두 경로가 같은 함수를 지나는 것으로 강제한다(갈라지면 `.textField` 게이트·`open_line`/`paste` 재정의가 한쪽에만 걸린다). 개행 헬퍼(`newLine`)는 옵셔널 반환이다 — `nil`이 "재정의 없음"과 "disable"을 뭉치므로 기본 `Return`으로 fail-open 하면 안 되고, 판정은 `ResolvedProfile.newLineDisabled`가 답한다 ([20260730_command-key-mapper-scope.md](../../decisions/references/20260730_command-key-mapper-scope.md), [20260809_newline-synthesis-gates.md](../../decisions/references/20260809_newline-synthesis-gates.md)).

시퀀스: `o`=`Cmd-→, Return`, `O`=`Cmd-←, Return, ↑`, `u`=`Cmd-Z`, `Ctrl-r`=`Shift-Cmd-Z` ([20260730_openline-return-sequence.md](../../decisions/references/20260730_openline-return-sequence.md), [20260730_cmd-z-ansi-layout-escalation.md](../../decisions/references/20260730_cmd-z-ansi-layout-escalation.md)).

**스크롤**은 위임할 네이티브 명령이 없어 이 매퍼에서 유일하게 명령 키를 쓰지 않는다 — `↓`/`↑` 반복이다(macOS에 캐럿을 뷰포트만큼 옮기는 프리미티브가 없고 `PageUp`류는 다음 모션에 원위치 — [20260730_scroll-arrow-repetition.md](../../decisions/references/20260730_scroll-arrow-repetition.md)). **반복 줄 수의 출처는 사다리다: 프로파일 명시값 > AX 뷰포트 정확값 > 코드 상수 15/30** (extent별 독립 — [20260806_scroll-line-count-priority-ladder.md](../../decisions/references/20260806_scroll-line-count-priority-ladder.md)). 뷰포트는 별개 프리미티브 `ViewportReader`가 읽는다 — `AXVisibleCharacterRange` 양 끝의 `AXLineForIndex` **표시 줄** 번호 차 + 1(화살표가 걷는 시각 줄과 단위 일치). **문서 전체 가시는 오보로 기각한다**(`provenViewport`: `visible.length >= characterCount` → `nil`) ([20260806_viewport-lines-via-line-for-index.md](../../decisions/references/20260806_viewport-lines-via-line-for-index.md)). 산식은 Vim 그대로 half = 뷰포트/2·full = 뷰포트 − 2, AX 유래 값은 `min(max(1, n), 200)` 클램프, 그룹은 무페이싱(드롭의 실패 방향이 "덜 스크롤"이라 무해 — [20260806_scroll-viewport-clamp-no-pacing.md](../../decisions/references/20260806_scroll-viewport-clamp-no-pacing.md)). 읽기 술어는 `scrollConsultsViewport(extent:profile:)` — 명시값이 있으면 묻지 않는다(번들 Notion 프로파일 12/24 유지가 오보 앱의 이중 방어선). `ViewportSnapshot`은 lazy·실패도 memo이되 수명이 **execute당 1회**다 — 뷰포트 높이는 버스트 불변이라 `FocusedTextSnapshot`의 액션별 계약에서 의도적으로 이탈했다 ([20260806_viewport-snapshot-per-execute.md](../../decisions/references/20260806_viewport-snapshot-per-execute.md)). 읽기 실패·미노출(Slack·VS Code)·pid 없음은 현행 사다리(프로파일 → 상수)와 바이트 동일 폴백이고, 정확화가 `nil`을 새로 만들지 않아 프로브는 둘 그대로다.

**붙여넣기**는 위치 접두 1회 + `Cmd-V`×count다(charwise `p`=`→`·`P`=접두 없음, linewise `p`=`Cmd-→, →, Cmd-←`·`P`=`Cmd-←`; linewise `p`의 꼬리 `Cmd-←`는 멱등 보정자). charwise `p`의 `→`는 **읽기가 캐럿의 줄 끝을 증명하면 생략**된다(줄 끝 커서 모델 — `→`가 다음 줄로 포화해 `xp`가 글자를 넘긴다). 술어는 `pasteConsultsFocusedText`(charwise `p`만 참), 증명 실패는 현행 접두 폴백 ([20260806_charwise-paste-line-end-no-prefix.md](../../decisions/references/20260806_charwise-paste-line-end-no-prefix.md)). **`.paste` 그룹은 페이싱 대상**이다(접두 다타 그룹의 버스트 드롭 — [20260806_paste-groups-stroke-pacing.md](../../decisions/references/20260806_paste-groups-stroke-pacing.md)).

**붙여넣기 단위(wise)는 `PasteWiseResolver`가 정한다** — 게시 직렬 큐가 단독 소유하는 상태 보유 협력자. 우선순위는 "우리가 아는 것 먼저": 클립보드를 쓰는 편집 전부가 게시 확정(`.groups`) 시 그 시점의 `NSPasteboard.changeCount`와 함께 내용의 wise를 기억하고(`recordEdit`), 붙여넣기 시점에 카운트가 **정확히 1 늘었으면** 그 기억을 쓴다. 기록 표: `op ≠ change`의 `.line`/`.linewiseMotion` = linewise, change 전 범위 = charwise, `.motion`/`.textObject` = charwise, 미지 범위 = 기록 안 함 ([20260806_paste-wise-memory-covers-all-edits.md](../../decisions/references/20260806_paste-wise-memory-covers-all-edits.md)). **`.selection`(Visual `d`/`y`/`c`)만은 세션이 wise를 정한다** — 게시 확정된 `beginSelection(linewise:)`·`switchSelectionWise(linewise:)`의 값을 `noteSelectionWise`로 note하고 `recordSelectionEdit()`이 소비한다(엔진 상태가 아니라 **화면 진실 추적** — 스킵된 전환은 wise도 안 바뀌어야 내용과 일치하고, AX 무관이라 폴백 경로에서도 동작). "begin = 리셋"은 `forgetSelectionWise`가 **게이트보다 앞에서, 게시 확정과 무관하게** 복원한다 — 걸러진 begin은 note를 못 남기므로 잊지 않으면 이전 세션 wise로 오기록된다 ([20260806_selection-wise-from-confirmed-stream.md](../../decisions/references/20260806_selection-wise-from-confirmed-stream.md)). 그 외에는 순수 함수 `PasteWise(clipboardText:)`의 **끝 개행 휴리스틱 폴백**(외부 복사 전담 — [20260730_paste-wise-trailing-newline-heuristic.md](../../decisions/references/20260730_paste-wise-trailing-newline-heuristic.md), [20260730_paste-wise-from-our-own-edit.md](../../decisions/references/20260730_paste-wise-from-our-own-edit.md)). 패스트보드 접근은 전부 `Clipboard`(주입 seam)가 맡아 매퍼 순수성이 유지된다. 텍스트가 없으면 정직한 스킵이다.

위 접두 조립 전체는 **keyboard 경로 전담**이다 — AX 하이브리드 경로에서는 AX 캐럿 접두가 그 자리를 대신한다(줄 끝 접두 생략·꼬리 멱등 보정자는 폴백 전담으로 남는다). 수용 편차: charwise `p`의 줄 끝 다음-줄-시작 붙여넣기는 **읽기 실패 폴백 한정**으로 강등됐고(위 접두 생략), **마지막 줄의 linewise `p`는 `P`로 퇴행**(폴백·`.textField` 한정 — 하이브리드의 `[Return, Cmd-V]` 합성이 해소, [20260808_last-line-linewise-paste-degrades-to-P.md](../../decisions/references/20260808_last-line-linewise-paste-degrades-to-P.md)), charwise `P`는 살아 있는 선택을 덮어쓰며, `3p`는 undo 3단위, 소프트 랩 문단에서 `O`는 빈 줄을 만들지 못한다. `Return`이 전송인 앱은 프로파일 몫(`open_line` 재정의).

### 모션 매핑 — `MotionKeyMapper`

순수 매퍼 `Motion → [KeyStroke]` — **배열 반환이 계약**이라 모션 1개를 N타 조합으로 확장하는 것이 테이블 원소 교체로 된다. Keyboard 전략은 캐럿 모델이라 프리미티브가 없는 곳은 조합·수렴으로 처리한다: `wordForward`(w)는 `Opt-→,Opt-→,Opt-←` 3타, `lineFirstNonBlank`(^·I)는 `Cmd-←,Opt-→,Opt-←` 3타(탭 들여쓰기는 Chromium 계열에서 0으로 퇴행 — 수용), append 계열은 l·$와 자연 수렴 ([20260726_motion-keystroke-mapping-contract.md](../../decisions/references/20260726_motion-keystroke-mapping-contract.md), [20260726_word-forward-first-nonblank-multi-stroke.md](../../decisions/references/20260726_word-forward-first-nonblank-multi-stroke.md), [20260726_tab-indent-first-nonblank-chromium-edge.md](../../decisions/references/20260726_tab-indent-first-nonblank-chromium-edge.md)). 합성 이벤트는 keyDown·keyUp 모두 flags를 **명시 대입**한다(빈 flags 포함) — 대입이 없으면 사용자가 누르고 있던 물리 modifier가 새어 들어간다 ([20260726_shift-leak-event-flags-sufficient.md](../../decisions/references/20260726_shift-leak-event-flags-sufficient.md)).

## 불변식·계약

- **읽기는 분기의 근거이지 스트로크 수의 근거가 아니다** — keyboard 경로 전용 불변식. 절대 오프셋 비례 스트로크 금지, 재조립은 위치 상대·부분집합·상수 1타. 예외는 엣지 1 하나(명시 수용) ([20260803_refinement-branches-not-stroke-counts.md](../../decisions/references/20260803_refinement-branches-not-stroke-counts.md)).
- 매퍼는 순수하고 설정 어휘(`VimActionConfig`)를 모른다. ANSI 상수는 논리 키코드다.
- "지원 ⟹ 빈 시퀀스 아님" — 무게시는 `nil`(정직한 스킵)로만 표현한다.
- `force-text` 치환은 keyboard 실행 쪽에만 닿는다 — AX 경로의 계열 판정은 항상 원본 family다.

## 근거 요약

Keyboard 전략은 "앱이 이미 아는 키"만 합성하므로 어디서나 동작하는 폴백이되, 낡은 읽기·레이아웃·요소 오보고라는 세 축의 위험을 각각 "분기 근거로만 읽기"·행동 검사 치환·default-deny 걸러내기로 막는다.

## 관련

- 디스패치에서의 위치: [strategy-dispatch.md](strategy-dispatch.md)
- 읽기 프리미티브·파생 질의: [focus-and-dispatch-reads.md](focus-and-dispatch-reads.md)
- AX 하이브리드의 위임분 착지: [ax-adapter.md](ax-adapter.md)
- 프로파일 재정의 전파: [profiles-and-config.md](profiles-and-config.md)
- 청크 게시·중단 래치·원자 그룹: [reentrancy-and-safety.md](reentrancy-and-safety.md)

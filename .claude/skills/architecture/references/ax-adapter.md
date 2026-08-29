# Accessibility 어댑터

- **Last updated**: 2026-08-20 (문서 분할 — [strategy-dispatch.md](strategy-dispatch.md)에서 이관 + 낡은 문언 갱신: `.illegalArgument` 재심사 종결 반영, Notion 제외 수단을 거부 목록으로 정정)

## 현재 구조

실행 수단은 **범위/캐럿 쓰기(`AXSelectedTextRange`) 하나뿐**이다 — 텍스트 쓰기(`AXSelectedText`)는 채택하지 않았다. 클립보드를 채우는 주체가 앱(`Cmd-X`/`Cmd-C`)이어야 리치 클립보드·앱 undo 스택 등록이 보존된다 ([20260808_ax-edit-select-then-operator-delegate.md](../../decisions/references/20260808_ax-edit-select-then-operator-delegate.md)). 쓰기는 **`AXWriter`가 단독 소유**한다(프리미티브당 단일 통로 — [reentrancy-and-safety.md](reentrancy-and-safety.md)): seam은 `@Sendable (AXUIElement, String, CFTypeRef) -> AXError`, 요소는 반드시 `AXRead.focusedElement` 경유(50ms 상수 상속)로 액션당 1회 lazy·memo이며, 읽기·계산·쓰기가 **같은 요소 핸들·같은 게시 큐에서 동기**라 keyboard의 "낡은 읽기" 문제가 구조적으로 없다 ([20260808_ax-writer-per-primitive-channel.md](../../decisions/references/20260808_ax-writer-per-primitive-channel.md)).

### 위임 표

골격 규칙은 "명령 매퍼 계열 = 위임, 모션·편집·Visual 매퍼 계열 = AX" ([20260808_ax-delegation-table-single-driver.md](../../decisions/references/20260808_ax-delegation-table-single-driver.md)):

| 액션 | 실행 |
|---|---|
| `.move` (j/k 제외 + append 2) | AX 캐럿 쓰기 |
| `.move(.lineUp/.lineDown)` | 위임 — 오프셋 대입은 희망 열(desired column)을 잃는다 |
| `.edit` 전 범위 | 하이브리드 — AX 범위 선택(**되읽어 검증** 후) + `Cmd-X`/`Cmd-C` 1타 위임. yank collapse는 **게시 `←`** — AX 캐럿 쓰기는 게시를 상시 이겨 빈 복사가 된다 ([20260808_ax-collapse-posted-arrow-not-caret-write.md](../../decisions/references/20260808_ax-collapse-posted-arrow-not-caret-write.md)) |
| Visual 4종 | AX 범위 쓰기 |
| `.clearSelection` | **게시 `←` 유지** — `[yank, clearSelection]`에서 동기 AX 쓰기가 `Cmd-C` 게시를 상시 이긴다(위 결정과 같은 근거) |
| `.openLine` | 하이브리드 — AX 위치 접두(**논리** 줄 끝/줄 시작) + `Return` 위임(`O`는 `Return, ↑`). 자동 들여쓰기·리스트 연속은 Return만 태우고, `.textField` 게이트는 위임분 안에 있다 |
| `.paste` | 하이브리드 — AX 위치 접두 + `Cmd-V`×count 위임. **마지막 줄(뒤 개행 없음)의 linewise after는 문서 끝 캐럿 + `[Return, Cmd-V]` 원자 그룹**(끝 개행 1개 편차 수용 — [20260808_last-line-linewise-paste-return-synthesis.md](../../decisions/references/20260808_last-line-linewise-paste-return-synthesis.md)). 단 **그 합성만은 `o`/`O`와 같은 두 게이트를 지난다** — 계열 `.textField`(`Return`이 submit)와 프로파일 `open_line: disabled`. 어느 쪽이든 위임으로 강등하며 결과는 현행 `P` 퇴행 ([20260809_newline-synthesis-gates.md](../../decisions/references/20260809_newline-synthesis-gates.md)) |
| `.undo`/`.redo` (AX API 없음) · `.scroll` | 위임 |
| quote/pair | 양쪽 미지원 유지 (패리티만) |
| 계열 `.nonText`/`.unresolved` | **전 액션 keyboard 강등** — AX 대입은 텍스트 요소 전제 |

### 하이브리드 규칙

하이브리드·위임은 **액션 단위 all-or-nothing**이다. 순서는 항상 "동기 AX 쓰기 → 게시"이며, 그 안전 근거는 구조 보장이 아니라 **지연 마진 + 되읽어 검증**이다(쓰기 `.success`가 적용 완료를 뜻하지 않는 앱이 실측됨 — [20260808_ax-readback-verify-convergence-poll.md](../../decisions/references/20260808_ax-readback-verify-convergence-poll.md)). 역방향("게시 → 동기 AX 쓰기")은 상시 역전이 실측돼 금지다 — collapse 계열이 게시 `←`로 남는 이유(위 표).

**접두 실패는 세 축으로 갈린다** ([20260808_hybrid-prefix-failure-axes-clarified.md](../../decisions/references/20260808_hybrid-prefix-failure-axes-clarified.md)): 오프셋 증명 실패(`unproven`)만 keyboard 위임(쓰기 시도 전이라 이중 실행 불가 — 액션 통째, 맨 `Cmd-V`/`Return` 금지), 요소·읽기 실패는 `.axUnavailable` 스킵, 쓰기 시도 후 실패·검증 실패는 폴백 없음(아래 실패 처리). **접두 쓰기(및 되읽어 검증)와 첫 게시 그룹 사이에는 중단 질의가 없다** — 원자 그룹 ④ ([20260808_hybrid-prefix-atomic-with-first-group.md](../../decisions/references/20260808_hybrid-prefix-atomic-with-first-group.md)). `unproven` 편집 위임은 이미 읽은 AX 창(4096)의 `FocusedText`를 keyboard 정확화에 그대로 전달한다 — 한 액션은 창을 한 번만 읽는다 ([20260808_ax-unproven-edit-delegation-reuses-ax-window.md](../../decisions/references/20260808_ax-unproven-edit-delegation-reuses-ax-window.md)). AX 접두는 합성 이벤트가 아니라 페이싱 비대상이고, 비-QWERTY 게이트·치환은 위임 행에만 적용된다.

**되읽어 검증**(하이브리드 전체 — 위임 그룹 게시 전 접두 착지 확인)은 **신선한 선택 전용 재읽기의 수렴 폴링**이다: `AXWindowSnapshot` memo를 재사용하지 않고(쓰기 전 값) `AXSelectedTextRange`만 다시 읽으며, 쓴 범위와 일치할 때까지 간격 2ms·총 상한 40ms(도그푸딩 조절값). 상한 도달 = 검증 실패 = **무동작 스킵 + execute 잔여 중단**(보고 아님 — 파괴는 시도 전), 로그는 전용 버킷 상시 `.notice`(번들 ID 포함). 접두가 캐럿 이동뿐인 `.openLine`·`.paste`도 예외가 아니다 — 낡은 캐럿 위의 `Return`·`Cmd-V`는 파괴적이다 ([20260809_hybrid-insertion-readback-verify-kept.md](../../decisions/references/20260809_hybrid-insertion-readback-verify-kept.md)). 검증 없이 쓰기만 하는 것은 뒤에 아무것도 게시하지 않는 `.ax` 캐럿 모션뿐. 이 검증은 서로게이트 mid-pair 쓰기를 잡지 못하므로(쓴 값 == 읽은 값) grapheme 경계 불변식이 그 축의 유일한 방어선이다 ([20260808_ax-readback-verify-convergence-poll.md](../../decisions/references/20260808_ax-readback-verify-convergence-poll.md)).

### 오프셋 산출 — `FocusedTextOffsets`

순수 함수 계층이며 `FocusedTextAnalysis` extension 확장이 아니다(`RunClass`가 갈린다 — Analysis는 비ASCII `other`(포기 방향), Offsets는 `keyword`(CJK `w`/`diw` 성립)). UTF-16 배관은 `offsetInWindow` internal 승격으로 공유하되 **스캔 단위는 `Character`(grapheme cluster)** — 산출이 항상 클러스터 경계 위여야 하고 `\r\n`이 한 `Character`라 떠돌이 `\r`가 원천 소거된다. 캐럿 자체가 경계 위가 아니면 아무것도 증명하지 않는다. 입력은 `FocusedText` 창이되 **AX 쓰기 경로 전용 확대 반경**(`FocusedTextReader.axWindowRadius` = 4096 UTF-16, keyboard 경로 256 불변). 창 읽기는 `AXWindowSnapshot`이 담당하며 **pid가 아니라 `AXElementSnapshot`의 요소를 받는다** — 오프셋을 계산한 읽기와 뒤따르는 쓰기가 같은 핸들을 써야 `AXWriter`의 요소 수신 계약이 성립한다. 반환은 3상태(`.invalid` = Vim 무효 → 스킵 / 범위 → AX 쓰기 / `.unproven` → keyboard 위임) ([20260808_ax-offset-layer-window-logical-lines.md](../../decisions/references/20260808_ax-offset-layer-window-logical-lines.md)).

**커서 모델은 캐럿 그대로다** — 목표 오프셋은 지금 keyboard가 겨냥하는 자리다(`e` = 단어 마지막 글자 **뒤**, `$`·`A` = 줄 끝 캐럿, `gg` = 오프셋 0, `G` = `characterCount`). AX가 정확하게 만드는 것은 **단어 경계 정의**(`RunClass` 기반 Vim 시맨틱)와 `^`뿐이며, Vim 자체가 no-op인 자리(줄 시작 `h`·줄 끝 `l`·문서 시작 `b`·문서 끝 `w`/`e`, "목표 == 현재 캐럿")만 `.invalid`다. 블록 커서 모델 전면 채택은 기각 ([20260808_ax-motion-caret-model-vim-word-definition.md](../../decisions/references/20260808_ax-motion-caret-model-vim-word-definition.md)). 살아 있는 선택 위에서는 캐럿이 애매하므로 증명하지 않는다.

산출 함수는 **캐럿 1종 + 구간 5종**이며 반환 타입이 갈린다. `Target`(캐럿)·`Span`(구간)은 동형 3상태이고 "목표 == 현재"를 `.invalid`로 접지만, **`Insertion`(삽입 위치)에는 `.invalid`가 없다** — `o`·`O`·`p`·`P`는 Vim에서 무효인 자리가 없고, 줄 끝의 `o`는 목표 == 캐럿이면서 유효하다(같은 타입이면 접는 헬퍼 재사용 순간 `o`가 조용히 죽는다). `Insertion`의 셋째 케이스 `.appendingLine`이 마지막 줄 linewise `p`의 `Return` 합성 지시를 타입으로 실어 나른다 — 조건은 **뒤 개행이 없는** 마지막 줄. 캐럿이 끝 개행 **뒤**(빈 마지막 줄)면 구분 개행이 이미 있으므로 `.at`이다(`dd` 뒤 `p`가 그 자리 — 합성하면 빈 줄이 하나 더 생긴다).

| 함수 | 담당 | 반환 |
|---|---|---|
| `caretTarget(for:in:)` | `.move` 모션 목표 | `Target` |
| `editSpan(for:range:in:)` | `.edit` 전 범위 — `.motion`·`.line`·`.linewiseMotion`·`iw`, `cw` 리타깃 포함 | `Span` |
| `openLineInsertion(above:in:)` | `o`(줄 끝) / `O`(줄 시작) | `Insertion` |
| `pasteInsertion(before:wise:in:)` | `p`/`P` 삽입점 + 마지막 줄 분기 | `Insertion` |
| `visualEntrySelection(linewise:in:)` | `v`(캐럿 글자 1개) / `V`(논리 줄 + 종결자) | `Selection` |
| `visualExtendSelection(for:anchor:in:)` | `extendSelection` — 앵커 + 포커스 끝 | `Selection` |
| `visualSwitchSelection(toLinewise:anchor:in:)` | `v`↔`V` 전환 — 양방향 | `Selection` |

`editSpan`이 `(op, range)` 단일 진입점인 것은 `cw` 리타깃이 `EditKeyMapper.retargeted`와 같은 자리에서 한 번만 일어나야 판정과 실행이 갈라지지 않기 때문이고, Visual 3종이 `VisualAnchorState`를 통째로 받는 것은 포커스 끝 도출(`side`)·희망 열·원래 캐럿이 전부 범위 산술의 일부라서다. **Visual만 반환이 `Selection`(범위 + 새 논리 앵커 + 새 희망 열)인 것도 같은 이유** — 매 액션이 세션 상태를 갱신하는 유일한 어휘라 범위만으로는 다음 상태를 세울 수 없다. `side`·`pinnedEnd`는 범위와 앵커에서 도출되며 그 규칙은 `VisualAnchorState.moved(to:anchor:column:)` 한 곳에 있다. `.selection`·`aw`·quote/pair는 `.unproven`(위임 = 현행 keyboard와 바이트 동일)이고, 살아 있는 선택 위의 편집·삽입은 전부 `.unproven`(출발점 미증명)이며 Visual 확장만 그 선택을 입력으로 쓴다.

### 산출 값의 시맨틱 — 표가 침묵하면 Vim 정확값

([20260809_ax-span-vim-exact-where-table-is-silent.md](../../decisions/references/20260809_ax-span-vim-exact-where-table-is-silent.md) — Vim 실측 14건):

- 줄 마지막 단어의 `dw`는 **개행을 넘지 않는다**(뒤 공백은 줄 끝까지, 카운트 클램프는 마지막 스텝에만).
- linewise 카운트는 **클램프**하고 **모션 성분이 0줄일 때만 무효**(마지막 줄 `dj`·`2dd`, 첫 줄 `dk`) — count 2 이상에서 keyboard 정확화 표와 갈리는 것은 의도된 것이다.
- `iw`는 2자 이상의 공백·구두점 런까지 정확하다.
- **Visual 진입에는 무효가 없다** — 잡을 글자가 없으면 `.invalid`가 아니라 `.unproven` 강등(진입을 스킵하면 엔진 모드와 화면이 어긋난다).
- charwise 확장은 포커스 **글자**(전진형은 선택 끝 −1자) 위에서 모션을 적용해 `[min, max+1)`로 합치되, inclusive를 더하지 않는 것은 `e` 하나 — **`$`·`l`·`j`가 줄 종결자 위에 서면 그 개행까지 문다** ([20260810_visual-inclusive-end-bites-terminator.md](../../decisions/references/20260810_visual-inclusive-end-bites-terminator.md)).
- **`j`/`k`는 어느 세션에서도 위임이 아니다** — `V` 세션은 열이 없고, charwise 세션은 **희망 열(Vim curswant)을 `VisualAnchorState.desiredColumn`에 추적**한다: 포커스 = 줄 시작 + `min(희망 열, 줄 길이)`, 수평 모션마다 갱신·`j`/`k`는 물려받음, `$` 뒤는 줄 끝 고정 sentinel(`lineEndColumn`), 열 미상(`gg`/`G` 경유)은 정직한 스킵 ([20260810_ax-visual-desired-column-tracked.md](../../decisions/references/20260810_ax-visual-desired-column-tracked.md)).
- `v`↔`V` 전환도 양방향 정확이다 — `V` 진입이 원래 캐럿을 정확값으로 읽어 두므로 열이 뺄셈이고, keyboard 경로의 조건부 지원·상한 32·페이싱이 필요 없다 ([20260810_ax-visual-switch-both-directions-exact.md](../../decisions/references/20260810_ax-visual-switch-both-directions-exact.md)).

**단 마지막 줄 linewise(delete/yank)는 앞 개행을 흡수하지 않는다** — 범위는 `[줄 시작, 문서 끝)`이고 빈 줄 1개가 남는다(keyboard와 같은 답). **우리 레지스터는 OS 클립보드의 생 텍스트**라 한 번의 `Cmd-X`가 자르는 범위가 곧 레지스터의 모양이고, 흡수하면 내용이 `"\n마지막줄"`이 되어 `ddp`·`yy`·외부 붙여넣기·wise 휴리스틱이 함께 틀린다 — 표시상 편차보다 레지스터의 정확성을 택했다 ([20260809_no-leading-newline-absorb-clipboard-is-the-register.md](../../decisions/references/20260809_no-leading-newline-absorb-clipboard-is-the-register.md)).

**linewise는 논리 줄**이다 — 소프트 랩 문단의 `dd`가 논리 줄 전체를 지운다(keyboard 수용 엣지의 AX 경로 해소, `dj` ≠ `d`+`j` 편차 명시 수용). `dgg`/`dG`는 끝점 두 개만 필요해 문서 규모 무관이고, 파라미터화 속성(`AXLineForIndex`/`AXRangeForLine`)은 표시 줄 시맨틱이라 미채택. 줄 종결자는 `\r\n`·`\n`·`\r`·U+2028/2029, 경계 불변식(`location ≥ 0`, `upperBound ≤ characterCount`)은 순수 함수 테스트로 고정 ([20260808_ax-offset-layer-window-logical-lines.md](../../decisions/references/20260808_ax-offset-layer-window-logical-lines.md)).

### 실패 처리

`AXError` 분류는 default-deny 화이트리스트다: 실보고는 `.failure`만, `.illegalArgument`는 관측 전용 요약 로그(재심사 종결·관측 유지 — [20260813_illegalargument-cannotcomplete-observation-kept.md](../../decisions/references/20260813_illegalargument-cannotcomplete-observation-kept.md)), `.attributeUnsupported`류 = 미지원 스킵, `.invalidUIElement`/`.cannotComplete` = 경합 스킵, 미지 코드 = 미보고 + error 로그. **쓰기 시도 후 실패의 keyboard 폴백은 없다**(이중 실행·어긋난 상태 위 상대 시퀀스 위험). **중단 규칙은 `.success` 외 전부**다 — default-deny가 흐름 제어에도 적용돼 새 코드가 조용히 "계속 진행"으로 흘러들지 않는다. **쓰기 시도 전 단계 실패**(포커스 요소 미노출·창 읽기 실패)는 보고도 폴백도 아닌 스킵이되 역시 execute 잔여를 접으며, `.unproven`(창이 답 못 함 → 위임)과 **별개 축**이라 `Mapping.axUnavailable`로 표현된다 — 위임으로 접으면 AX 전략이 조용히 무효화되고, 접지 않으면 `100j`가 100×50ms로 게시 큐를 잡는다 ([20260808_ax-pre-write-failure-ends-execute.md](../../decisions/references/20260808_ax-pre-write-failure-ends-execute.md)). 사전 경계 검증(`AXWriteOutcome.provenWriteRange`) 탈락은 우리 계산이 어긋난 신호라 즉시 error 로그이며 보고가 아니라 스킵이다.

분류(`AXWriteOutcome.classify` — `AXError` 16코드 → 7클래스 순수 함수)와 **효과 실행**(`AXWriteEffects` — 보고·요약 로그·버킷, execute 1회 수명)은 갈려 있다 — 분류가 로깅까지 하면 표를 테스트로 고정할 수 없다. 보고 seam은 어댑터 주입(`KeyboardAdapter(reportExecutionFailure:now:)` → `axWriteEffects(bundleID:)`)이고 시각은 게시 큐에서 캡처한다 — 상세 배선·로그 레벨은 [reentrancy-and-safety.md](reentrancy-and-safety.md) ([20260808_ax-write-failure-whitelist-no-fallback.md](../../decisions/references/20260808_ax-write-failure-whitelist-no-fallback.md)).

### 드라이버 배선

**단일 실행 드라이버**: execute 루프(중단 래치·스냅샷·요약 로그)와 게이트 3종·부수효과(`recordEdit` 등)를 keyboard와 공유하고, `Mapping`에 `.ax`(쓰기 계획)와 `.hybrid`(접두 범위 + 위임 그룹) 형제 케이스를 얹는다. `.hybrid`의 연관값은 `(NSRange, [[KeyStroke]], paced: Bool)`로 `.groups`와 같은 모양이며, **원자인 것은 첫 그룹뿐** — 둘째 그룹부터는 `.groups`와 같은 청크·페이싱 루프로 낙하한다(하이브리드 전용 게시 루프를 두지 않아 청크 규칙이 한 곳에 남는다). 그룹이 여럿인 액션은 `.paste` 하나(`1000p` = `Cmd-V` 1,000타 — 통짜면 중단 래치가 파고들 틈이 없다). `paced`는 `.paste`만 `true`이며 실효 지점은 `.appendingLine`의 `[Return, Cmd-V]` 그룹뿐이다. `paced:`가 `.ax`에 없는 것도 계약이다 — AX 쓰기는 드롭 모드가 없어 페이싱 비대상 ([20260809_hybrid-mapping-multi-group-paced.md](../../decisions/references/20260809_hybrid-mapping-multi-group-paced.md)). "AX 어댑터가 keyboard 어댑터를 부른다"(감사 안 되는 둘째 진입점)와 "디스패처가 액션 단위로 어댑터를 가른다"(계약 분열)는 기각.

`recordEdit`(paste-wise 기억)은 하이브리드에서 **매핑 시점이 아니라 실제 게시 뒤**다 — 접두 쓰기·되읽어 검증이라는 설계된 실패 단계가 사이에 있어, 매핑 시점 기록은 접힌 편집의 wise를 남긴다. 호출 자리는 액션 무관 단일 지점(게시 직후)이며 함수 자체가 `.edit` 가드로 시작한다. `.paste`의 `pasteWise.resolve()`가 매퍼보다 앞에 남는 것도 계약이다 — 기억을 소비하지 않는 순수 조회이고, wise가 접두 삽입점과 위임 그룹 모양을 둘 다 정한다 ([20260809_paste-resolve-is-pure-lookup.md](../../decisions/references/20260809_paste-resolve-is-pure-lookup.md)).

드라이버의 `.ax` 처리 순서: ① `flush()`(**순서 봉인** — 같은 execute의 미게시 위임 이벤트를 먼저 비운다. 게시는 배달만 걸고 돌아오고 AX 쓰기는 동기라, 두고 쓰면 화면 순서가 뒤집힌다) → ② 중단 래치 → ③ 요소·읽기·`provenWriteRange` → ④ 쓰기·`effects.apply` → ⑤ `.success`가 아니면 반환. `.hybrid`는 둘이 더 낀다 — ③과 ④ 사이 **위임 그룹의 CGEvent 생성**(만들 수 없으면 접두 쓰기 자체를 하지 않는다), ④와 게시 사이 **되읽어 검증**. 그 게시는 래치 질의도 페이싱도 없이 `executor.post` 직행이다(원자 그룹 ④ — `flush()`가 `isCurrent()`를 부르므로 그 경로를 지나면 안 된다). ①과 ④는 두 케이스가 같은 함수를 공유한다 — 감사 경로가 한쪽에서만 바뀌면 안 된다. 중단 래치 질의는 액션 사이 + 파괴적 게시 직전. `AXWriteEffects`는 execute 진입 시 1개 만들고 `defer { logSummary() }`로 중단 경로까지 덮는다. 역방향("게시 → AX 쓰기") 소비 순서는 미확정·도달 불가여야 하며, 전제가 깨지면 보이도록 DEBUG 감사 로그가 남는다.

### Visual 세션 경로 고정

진입(`beginSelection`) 증명 성공이면 세션 전체 AX, 실패면 세션 전체 keyboard(기존 재앵커 기계). 세션 중간 실패는 그 액션만 정직한 스킵 — **무상태 폴백 금지**(AX가 쓴 범위는 앱의 포커스 끝이 미정의라 무상태 `Shift-→`가 파괴 방향 불확정). 그래서 `.unproven`도 Normal 경로와 달리 위임이 아니라 스킵이고, 요소·읽기 실패만 `.axUnavailable`(execute 잔여 접기)이다 ([20260808_ax-visual-session-path-pinning.md](../../decisions/references/20260808_ax-visual-session-path-pinning.md)).

**경로 pin(`VisualAnchorTracker.sessionPath`)은 진입 확정 시점에만 쓰이고 상태 폐기로는 지워지지 않는다** — 자가 검증 실패의 원인 중 하나가 "앱이 우리가 쓴 범위를 정규화·클램프"라, 그때 화면에 남은 선택이 AX가 쓴 범위이기 때문이다. 검증이 깨진 AX 세션은 재진입 전까지 확장·전환이 전부 스킵이며, `clearSelection`(게시 `←`)은 그대로 동작하고 `.edit(_, .selection)`(위임)은 **위임 직전 선택 재검증 1회**를 거친다 ([20260810_ax-visual-session-path-outlives-state-discard.md](../../decisions/references/20260810_ax-visual-session-path-outlives-state-discard.md)).

**`.edit(op, .selection)` 위임 직전 재검증 가드**: 구현은 `mapping`의 `.edit` 분기 최상단(부수효과 `recordEditWise`보다 앞) — 가드 기준은 실효 전략이 아니라 `visualAnchor.sessionPath == .accessibility`라 **런타임 강등 뒤에도 발동**하고(pin된 화면 선택은 여전히 AX가 쓴 범위), 읽기는 그 액션의 확대 창 lazy 읽기(AX 경로에서는 memo 공유라 추가 왕복 0건), 술어는 기존 `validated(against:processID:)` 재사용이다. 읽기 실패 = 정직한 스킵(상태 유지 — 폐기 트리거 아님, DEBUG 로그), 불일치 = 상태 폐기(+pin 생존) + 정직한 스킵(상시 `.notice` + 번들 ID — [20260814_visual-guard-mismatch-log-info.md](../../decisions/references/20260814_visual-guard-mismatch-log-info.md)). 상태가 폐기된 세션은 재검증이 설 수 없어 역시 스킵이다. keyboard 세션은 가드 밖·현행 그대로다 ([20260813_visual-selection-edit-pre-delegation-guard.md](../../decisions/references/20260813_visual-selection-edit-pre-delegation-guard.md)).

`VisualAnchorTracker`는 두 경로가 공유하고 AX는 `side`·`pinnedEnd`까지 정확값으로 채운다(전략 인수인계 공짜 — 단 포커스 줄 거리는 AX가 추적하지 않아 미상으로 좁힌다). 자가 검증은 AX에서도 유지(단측 + 비어 있지 않음 — 포커스 끝 불일치는 DEBUG 로그만), 확정 부수효과(상태 적용·경로 고정·세션 wise note)는 `confirmVisual` 한 함수가 담당하며 위임은 매핑 확정 시·AX는 쓰기 `.success` 확인 시다 — 단 `.success`가 적용 완료를 뜻하지 않는 앱이 있어 실질 방어선은 다음 액션 읽기의 자가 검증이다. **프로파일 `motions:` 항목이 있는 모션의 `extendSelection`은 AX 세션에서 정직한 스킵** — 재정의 시퀀스도 무상태 시퀀스라 무상태 폴백 금지가 그대로 적용된다 ([20260808_ax-visual-overridden-motion-honest-skip.md](../../decisions/references/20260808_ax-visual-overridden-motion-honest-skip.md)).

## 불변식·계약

- AX 쓰기는 `AXWriter` 단독 통로, 요소는 `AXRead.focusedElement` 경유 — 50ms 단일 상수가 쓰기에도 상속된다.
- "동기 AX 쓰기 → 게시" 순서 고정, 역방향 금지. 하이브리드 접두+첫 게시 그룹은 원자.
- 쓰기 시도 후 실패에 keyboard 폴백 없음. 중단 규칙은 `.success` 외 전부.
- Visual 세션은 진입 시점 경로 고정 — 세션 중간 무상태 폴백 금지, pin은 상태 폐기보다 오래 산다.
- "읽기는 분기의 근거"(keyboard 불변식)는 AX 경로에 적용되지 않는다 — 읽기·쓰기가 같은 큐에서 동기라 낡은 읽기 창이 없고, 오프셋이 실행 수단 그 자체다.

## 근거 요약

AX 경로의 가치는 keyboard가 증명 못 하는 정확성(단어 경계·경계 포화·Visual 앵커)이고, 위험은 "앱이 AX를 거짓말하거나 비동기로 적용"하는 것이다 — 그래서 모든 쓰기에 되읽어 검증이 붙고, 실패의 기본 방향은 항상 "폴백 없는 정직한 스킵"이다.

- 관련 결정: [20260808_ax-delegation-table-single-driver.md](../../decisions/references/20260808_ax-delegation-table-single-driver.md) 외 본문 인라인 링크.
- Notion은 AX Visual에 부적합하다 ([20260810_notion-unfit-for-ax-visual-session-5-withdrawn.md](../../decisions/references/20260810_notion-unfit-for-ax-visual-session-5-withdrawn.md)) — 현재는 auto 거부 목록의 초기 항목으로 AX에서 제외된다 ([auto-strategy-probe.md](auto-strategy-probe.md)).

## 관련

- 디스패치에서의 위치·`usesAXWrite` 판정: [strategy-dispatch.md](strategy-dispatch.md)
- auto 판정이 이 어댑터로 라우팅: [auto-strategy-probe.md](auto-strategy-probe.md)
- `unproven` 위임의 착지·keyboard 정확화: [keyboard-adapter.md](keyboard-adapter.md)
- 창 읽기 프리미티브: [focus-and-dispatch-reads.md](focus-and-dispatch-reads.md)
- 실행 통로·실패 보고 배선: [reentrancy-and-safety.md](reentrancy-and-safety.md)

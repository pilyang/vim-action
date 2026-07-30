# M3 — Keyboard 어댑터 ② 편집 + Visual + 요소 리졸버

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-26
- **갱신일**: 2026-07-31 (**단계 2.5 도그푸딩 자동화분 완료 — 수정 1건 반영**(flush 재확인을 게시 직전으로). 남은 확인: 물리 킬 콤보 1건 + 체감 2건. 그다음 **단계 3 리졸버**)

## 목표

v1 어휘 전체(편집·Visual·o/p/u·스크롤)가 Keyboard 전략으로 실제 실행되고, 요소 리졸버(focusedRole 캐시)가 TextArea/TextField 시퀀스를 가르는 상태. 끝나면 릴리스 배포 금지 게이트(`.replace` 무로그 삼킴 규칙)가 해제된다 — [게이트 이동 결정](../../decisions/references/20260726_release-block-gate-moves-to-m3.md). 상위 마일스톤: [20260725_mvp-milestones.md](20260725_mvp-milestones.md).

**범위 확정 3건 (2026-07-26 사용자 확인)**:
- 텍스트 오브젝트는 **word만 근사 지원**(diw/ciw ≈ `Opt-←, Shift-Opt-→`) — aw·quote·pair는 미지원 스킵(로그), M5 AX에서 정식 지원.
- 순서는 **편집 먼저, 리졸버 나중** — 단계 1·2는 TextArea 시퀀스 고정, 단 매퍼 테이블은 처음부터 `(action, family)` 키로 설계해 단계 3 재작업을 봉쇄.
- **사전 실측을 단계 0으로 선행** — 결과가 래치 승격·undo 매핑 설계를 확정한 뒤 코드 착수.

## 완료된 것

- [x] **단계 2.5 — 실행 중단 래치 코드 완료** (2026-07-30): 신규 `ExecutionAbortLatch`(세대 카운터, 컨트롤러 소유·sink 팩토리 주입) + `KeyboardAdapter.execute` 청크 루프(8 스트로크, 첫 청크 즉시·이후 2ms) + `CommandKeyMapper.pasteStrokeGroups`(paste 내부 분할). 무효화 3주체 배선(새 사용자 키 **전부**·토글 off·킬스위치), 원자 그룹 2종 반영. **엔진·모션·편집·Visual 매퍼·`ActionExecutor` 무변경**, 카운트 클램프도 9,999 유지. 검증 3종 그린(엔진 40 / 앱 514 / 빌드). 결정 3건은 아래 "진행 중 컨텍스트" 참조. **도그푸딩 미완**.
- [x] **단계 2c 종료 — 나머지 어휘 실행 + 도그푸딩 완료** (2026-07-30): 신규 순수 매퍼 `CommandKeyMapper`(네이티브 명령 위임 계열) + `Clipboard`/`PasteWiseResolver` + 어댑터 배선. 이제 **v1 어휘 전체가 실행된다** — `default: nil`에 남은 것은 미구현 텍스트 오브젝트(aw·따옴표·괄호쌍)와 `V`→`v`뿐이다. 도그푸딩에서 **수정 2건**이 나와 반영됐다(스크롤 화살표 반복, paste wise 우리 편집 기억) — 재확인까지 정상 동작. 설계 결정 8건은 아래 "진행 중 컨텍스트" 참조. 검증 3종 + CI 2잡 그린, **PR #26 ready**.
- [x] **단계 2a+2b 종료 — Visual 실행 + 도그푸딩 완료** (2026-07-28): `VisualKeyMapper` 신규 + `MotionKeyMapper.selectionStrokes` 공유 추출 + `EditKeyMapper` `.selection` + 어댑터 배선, 골든 신규 21행. 도그푸딩에서 `v`/`Esc` 캐럿 무표류·`vwd`·`vwy` 정상 확인, `V` 세션 편차는 전부 예측대로. 편차 1건(`vb` 빈 선택)만 신규 — 코드 무변경 수용. 설계 결정 5건은 아래 "진행 중 컨텍스트" 참조.
- [x] (선행 상태, **M3 착수 시점**) M1·M2 종료 — 모션 실행·앱 게이트·킬스위치·출력 인프라 완비. 당시 편집·Visual·paste·undo·스크롤은 전부 스킵 상태였다(편집·Visual은 단계 1·2로 해소, 나머지는 2c).
- [x] **단계 1 도그푸딩 완료** (2026-07-27 실기기): `x`·charwise 모션·`cw`(뒤 공백 유지 + Insert 전이)·`dd/cc/yy`·`j k`·`diw/ciw/yiw`(수정 후 단어 시작·중간 정확) 확인. 편차 2건은 아래 "진행 중 컨텍스트" 참조 — 1건 수정, 1건 수용. **단계 1 종료**.
- [x] **단계 1 — Normal 편집 실행 (본체) 코드 완료** (2026-07-27): 신규 순수 매퍼 `EditKeyMapper`(선택 후 오퍼레이터 1타, 선택은 모션 매핑 재사용) + `KeyboardAdapter` `.edit` 배선 + 골든 57행. 범위: `x`, d/c/y + charwise 8모션, cw→ce 특례, `dd/cc/yy`, `j k G gg`, `diw/ciw/yiw`. 미지원(aw·따옴표·괄호쌍·Visual selection)은 `nil` → 스킵+로그. 설계 결정 4건은 아래 "진행 중 컨텍스트" 참조. **도그푸딩 미완**.
- [x] **단계 0 — 사전 실측 2건 완료** (2026-07-26 실기기): ① 카운트 폭탄 — 100j 1초 이내·9999j 수 초 폭주(비치볼), 킬스위치 발동 즉시지만 in-flight 못 멈춤, 버스트 중 타이핑 순서 역전 실증, Notion 이벤트 드랍 → **실행 중단 래치 단계 4 승격 확정** ([결정](../../decisions/references/20260726_count-burst-abort-latch-promotion.md)). ② undo — 선택+잘라내기/붙여넣기/새줄 시퀀스 전부 1 undo 단위, change만 삭제+타이핑 분리 → **u=Cmd-Z 유지·시퀀스 설계 자유 확정** ([결정](../../decisions/references/20260726_undo-unit-cmdz-policy.md)).

## 남은 것
- [ ] **단계 2.5 도그푸딩 마무리** (사용자 물리 조작 필요, 나머지는 2026-07-31 자동화로 완료 — 결과는 "진행 중 컨텍스트"): ① **물리 킬 콤보** `Ctrl-Opt-Cmd-Esc`를 폭주 중 실제 키보드로 — 합성 주입은 HID 킬 탭에 원리적으로 안 닿아 이것만 자동화 불가(`킬스위치 콤보 감지` fault 로그 + 즉시 정지 + 글리프 off 확인, 발동 후 메뉴바 재토글) ② ⑤ 일상 입력(`h j k l`·`dw`·`p`) 체감 반응성 ③ (선택) 폭주 중 메뉴바 토글 off — didSet 경로는 유닛 테스트로 고정돼 있어 물리 확인은 선택. ⑤가 걸리면 `KeyboardAdapter`의 `chunkStrokes`(8)·`chunkInterval`(2ms)이 조절 손잡이다.
- [ ] **단계 3 — 요소 리졸버 + TextField 분기**: `AXObserver`(kAXFocusedUIElementChanged) + NSWorkspace 활성화로 focusedRole 캐시(콜백은 캐시만 읽음 — 콜백 경량 불변식 위임 ②), TextField 시퀀스 분기(예: `delete(.line)` → `Cmd-A, Delete`), **캐시 충분성 1차 확정**(결정 문서). 앱 최초의 실질 AX 의존(읽기 전용) — 실기기 검증 비중 큼.
- [ ] **단계 4 — 안전망 회귀 + 게이트 해제**: 킬스위치 회귀 확인(래치와의 상호작용 포함), 미지원 스킵 로그 전수 확인 → `.replace` 무로그 삼킴 해소 → 릴리스 금지 게이트 해제 결정 문서.

## 진행 중 컨텍스트

- **단계 2.5 코드 완료** (2026-07-30). 신규 `ExecutionAbortLatch`(세대 카운터 — 해제 API 없음) + `EventTapController` 소유·`keyboardActionSink(abort:)` 주입 + `KeyboardAdapter.execute(_:isCurrent:)` 청크 루프 + `CommandKeyMapper.pasteStrokeGroups`. `dispatchActions` 시그니처는 불변(세대는 sink 안에서 오간다). **결정 3건**: [세대 카운터 래치](../../decisions/references/20260730_execution-abort-generation-latch.md), [청크 게시와 페이싱](../../decisions/references/20260730_chunked-posting-with-pacing.md), [클램프 9,999 유지](../../decisions/references/20260730_count-clamp-retained-at-9999.md). 설계 중 방향을 가른 것: **지연 없는 청크 분할은 아무것도 못 끊는다** — 게시는 순식간이고 느린 쪽은 대상 앱이라, 간격이 없으면 2만 이벤트를 수십 ms에 다 넘겨 잔여가 안 남는다. 구현 중 잡은 버그 1건: "다음 액션과 붙는다" 잠금을 액션 처리 **후에** 세우면 이미 그 안에서 끊긴 뒤다 → 진입 시점 판정으로 수정.
- **단계 2.5가 남긴 계약 (다음 세션이 깨지 말 것)**: ① 래치 무효화는 **마커 가드 뒤** — 앞이면 우리 합성 이벤트가 자기 버스트를 끊는다(첫 청크 만에 죽는 조용한 고장). ② 무효화는 **결정 종류 불문**(passthrough 포함) — 실증된 순서 역전의 `abc`가 passthrough다. ③ 청크 경계는 원자 그룹 사이에만 — 액션 전체 / `.edit(_,.selection)`+`clearSelection` / `.paste`의 `접두+첫 Cmd-V`. ④ `beginRun()`은 게시 큐 **밖**에서. 넷 다 테스트로 고정돼 있다(`ExecutionAbortWiringTests`, `KeyboardAdapterAbortTests` — 후자엔 "잠금 없으면 실제로 끊긴다"는 대조군 테스트가 함께 있다).
- **단계 2c 코드 완료** (2026-07-30, Draft PR). 신규 `CommandKeyMapper`(진입점 2개 — openLine·undo·redo·scroll / paste) + `Clipboard`(`nonisolated`, 패스트보드 읽기만) + `PasteWiseResolver` 주입·`Mapping` 3갈래. **엔진·모션·편집·Visual 매퍼·게시 인프라 무변경.** 시퀀스: `o`=`Cmd-→,Return`, `O`=`Cmd-←,Return,↑`, `u`=`Cmd-Z`, `Ctrl-r`=`Shift-Cmd-Z`, **스크롤=`↓`/`↑` 반복(half 15·full 30)**, paste=wise별 접두 1회+`Cmd-V`×count(wise는 **우리 편집 기억 우선, 끝 개행 휴리스틱은 폴백**).
- **2.5 도그푸딩 결과 (2026-07-31, osascript 주입 + AX 관측 자동화)** — **수정 1건**이 나와 반영됐다:
  - **② 순서 역전**: 1차에서 폭주 중 타이핑이 마지막 청크 8스트로크와 인터리브(4줄에 흩어짐) → 원인은 flush의 재확인이 페이싱 sleep **앞**이라 잠든 사이 무효화를 놓치는 3ms 창 → **재확인을 게시 직전으로 이동**(판별 테스트 `chunkInvalidatedRightBeforePostIsDiscarded` 추가, 앱 516 그린). 재검증에서 인터리브 1스트로크로 축소 — 무효화 순간 in-flight 꼬리는 환원 불가라 **≤1 스트로크 수용**.
  - **⑥ 총 소요**: `9999j` 정확 도달(드랍 0)·~27.5초, 병목은 TextEdit 소비(~2.7ms/이벤트)라 **페이싱 기여 ≈ 0초**.
  - **④ Notion**: `999j` 전량 게시 확인(로그 ×999·중단 없음)에도 도달 984·977줄 — **앱 측 드랍 1.5~2.2% 잔존**(완화됐지만 완전 해소 아님, `chunkInterval` 증가가 다음 튜닝 카드).
  - **① 킬스위치(부분)**: 합성 콤보는 세션 레벨 진입이라 HID 킬 탭이 못 본다 — 대신 메인 탭의 "새 사용자 입력" 경로가 래치를 끊어 **심층 방어를 실측**(1,680 화살표에서 정확 동결, 이후 유출 0). 킬 탭 자체 발동은 물리 키만 가능.
  - 자동화 교훈: 한글 IM에서 System Events `keystroke`는 문자 합성 조합이 전역 핫키(⌥⌘N Little Arc)를 오발 — **`key code`만 사용**. Insert passthrough 타이핑은 IM을 타 한글 자모로 삽입된다(엔진 커맨드는 ASCII 번역이라 무관).
- **단계 2c 설계 결정 8건**: [매퍼 신설](../../decisions/references/20260730_command-key-mapper-scope.md), [o/O 시퀀스](../../decisions/references/20260730_openline-return-sequence.md), [paste wise 휴리스틱](../../decisions/references/20260730_paste-wise-trailing-newline-heuristic.md), [Cmd-Z ANSI 위험 확대](../../decisions/references/20260730_cmd-z-ansi-layout-escalation.md), [비텍스트 UI 발사](../../decisions/references/20260730_native-command-non-text-ui-hazard.md), 그리고 도그푸딩이 낳은 2건 — [스크롤 화살표 반복](../../decisions/references/20260730_scroll-arrow-repetition.md)(스크롤 수렴 결정을 **supersede**), [wise는 우리 편집 기억](../../decisions/references/20260730_paste-wise-from-our-own-edit.md). 설계 리뷰에서 잡혀 반영된 것 3건: linewise `p`에 꼬리 `Cmd-←`가 없으면 **마지막 줄에서 텍스트를 훼손**한다(추가함), 텍스트 없는 클립보드의 `p`를 미지원으로 집계하면 **단계 4 게이트 심사자가 paste를 미구현으로 읽는다**(스킵 2종 분리), `Cmd-Z`의 AZERTY 위험은 기존 ANSI 결정이 수용한 등급과 **다르다**(별 결정으로 승격).
- **2c 1차 도그푸딩 결과 (2026-07-30 실기기)** — 8항목 중 6건 통과, **2건이 수정으로 이어졌다**:
  - 통과: `o`/`O` 직후 즉시 타이핑(순서 역전 없음), `O`의 `↑` 착지 열, 한글 IME(조합 중 Esc 후 `o`/`p`), Electron redo(`Shift-Cmd-Z` 수용). 소프트 랩 문단의 `O`는 **예측대로** 빈 줄을 못 만들고 문단을 하드 분리 — 수용 편차 확인.
  - **수정 ① 스크롤** — 페이지 키가 만든 스크롤이 **다음 모션 한 번에 원위치**함을 정량 확인(AX). Vim 레이어는 모든 키가 모션이라 죽은 기능이었다 → 화살표 반복(15/30)으로 교체. `Opt-Page*`·`Shift-PageDown`·스크롤 휠 모두 실측 후 기각. [결정](../../decisions/references/20260730_scroll-arrow-repetition.md)
  - **수정 ② Notion `ddp`** — 지목했던 stale 경합이 **아니었다**(느리게 눌러도 재현). 비파괴 `yy`로 클립보드를 실측해 원인 확정: **Notion은 블록을 잘라내도 끝 개행을 안 붙인다**(TextEdit 44B·개행 1 vs Notion 12B·개행 0) → 우리 편집을 `changeCount`와 함께 기억하는 방식으로 교체. [결정](../../decisions/references/20260730_paste-wise-from-our-own-edit.md)
  - **오진 정정**: 1차 관찰에서 "Notion `dd`가 6줄을 지운다"고 봤으나 통제된 재현에서 **선택은 정확히 한 블록**이었다. 그때 읽은 6줄 클립보드는 그 `dd`의 산물이 아니라 이전 내용이 남아 있던 것이다 — **과잉 삭제 버그는 없다.**
  - **미측정 1건**: `Ctrl-O`(`insertNewlineIgnoringFieldEditor:`)는 우리 엔진이 매핑 없는 키를 **삼켜서**(`VimEngine.swift`의 Normal 최종 fallthrough) 측정이 무효였다. 재려면 **가로채기를 끄고** 재야 한다. 네이티브 필드의 Return-submit 회피 수단이 되는지, 캐럿이 개행 앞/뒤 어디에 남는지가 `o`/`O` 프리미티브 교체 여부를 가른다.
- **2c 재도그푸딩 결과 (2026-07-30)**: 수정 2건 **전부 정상 동작 확인** — 화살표 스크롤(캐럿 동반), Notion `ddp`가 줄 단위로 붙음, 외부 복사 폴백. 단계 2c는 여기서 닫힌다.
- **측정 도구 (다음 세션이 재사용할 것)**: 화면 기록 권한이 없어 스크린샷은 못 쓰지만, **AX로 정량 관측이 된다** — 터미널이 이미 Accessibility 권한을 갖고 있어 `AXFocusedUIElement`의 `AXSelectedTextRange`(캐럿)와 `AXVisibleCharacterRange`(보이는 줄 범위)를 읽을 수 있다(Notion도 `AXTextArea`를 연다). 여기에 `osascript`의 `key code` 주입을 붙이면 **주입 → 관측 → 판정** 루프가 사용자 눈 없이 돈다. 파괴적 검증은 `dd` 대신 **같은 선택 시퀀스의 `yy`**로 대체하면 비파괴로 같은 것을 잰다.
- **도그푸딩 버그 오인 금지 (2c 추가분)** — 전부 설계상 수용된 편차다:
  - **charwise `p`는 줄 끝·빈 줄에서 다음 줄 시작에 붙여넣는다** (`→`가 개행을 넘는다 — 줄 끝 `x`의 줄 병합과 같은 계열)
  - **linewise `p`는 마지막 줄에서 `P`처럼 위에 붙여넣는다** — `Cmd-←` 보정자의 **의도된** 퇴행이다(그것이 없으면 텍스트 훼손이었다)
  - **charwise `P`는 살아 있는 선택을 덮어쓴다** — 네 시퀀스 중 유일하게 앞서 선택을 접는 접두가 없다(마우스 선택, Visual 탈출 콤보 잔류 선택 포함)
  - **`3p`는 undo 3단위**다(`Cmd-V` 3연타)
  - **`cc`/`cG` 뒤의 `p`는 charwise로 분류된다** — 그 시퀀스가 끝 개행을 남기지 않는다(`dd`/`yy` 뒤는 정확히 linewise)
  - **소프트 랩 문단에서 `O`는 빈 줄을 아예 안 만든다**, `o`는 문단 중간에 하드 개행을 넣는다
  - **`o`/`O`가 단일행 필드에서 submit, Slack류 컴포저에서 전송**된다(후자는 단계 3 리졸버로도 해소되지 않는다 — M4 프로파일)
  - **Finder·Mail에서 `u`/`p`/`o`가 앱 수준 명령으로 나간다** → 도그푸딩은 스크래치 문서 **+ 스크래치 폴더**에서만(기존 "실문서 금지" 규율의 확대)
  - **스크롤이 화면을 안 움직이고 캐럿만 내려갈 수 있다** — 15/30줄은 뷰포트 높이를 모르는 근사값이라, 한 화면이 그보다 크면(실측한 창은 118줄이었다) 캐럿이 아래 경계에 닿기 전까지 뷰가 그대로다. 버그가 아니라 근사의 대가이며 M4 프로파일에서 조절값이 된다
  - 기존 목록 유지: change 후 `u` 2회가 정상, Notion 버스트 드랍, Notion `Shift-Cmd-↑/↓` 충돌 6조합(+Visual 4조합), 편집 경계 포화 5종, Visual 후진 편차
- **(해소됨 — 2.5가 반영) 래치 입력 2건 (2c가 만든 것)**: ① `.paste`는 **액션 카운트에 묶이지 않는 첫 액션**이다 — `9999p`는 액션 **1개**로 `Cmd-V` 9,999타 = CGEvent 19,998개이며, all-or-nothing 게이트가 게시 전에 통째로 만든다. 래치의 "청크 게시 + 청크 사이 중단 체크"가 **액션 내부**를 쪼개야 하거나 매퍼에 paste 클램프가 필요하다. ② 스크롤은 비파괴적이면서 가장 값싼 버스트라(`9999 Ctrl-f`) 래치 검증의 안전한 카나리아다.
- **단계 2a+2b 종료** (2026-07-28, PR #25 `fba92bd` 병합). 신규 순수 매퍼 `VisualKeyMapper`(세션 진입·확장·wise 전환·이탈) + `MotionKeyMapper.selectionStrokes(for:)` 공유 추출 + `EditKeyMapper`의 `.selection` 분기(계열 분기 **밖**) + 어댑터 4케이스 배선. 검증 3종 통과(엔진 무변경, 앱 391 테스트, 빌드) + 실기기 도그푸딩 통과. **엔진·게시 인프라 무변경.** 다음은 **2c**, 그다음 단계 2.5 래치.
- **단계 2 설계 결정 5건**: [charwise 진입 1문자 선택](../../decisions/references/20260728_visual-charwise-entry-inclusive-selection.md), [무상태 확장](../../decisions/references/20260728_visual-extend-stateless-no-linewise-rounding.md), [switchWise 근사](../../decisions/references/20260728_visual-switch-wise-focus-end-rounding.md), [collapse 단일화](../../decisions/references/20260728_visual-clear-selection-collapse-left.md), [charwise 후진 원점 이동](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md). 설계 리뷰에서 잡힌 것 2건이 여기 반영돼 있다: `v` 진입을 무게시로 두면 `vd`/`vy`가 무동작이고 Esc가 캐럿을 표류시킨다(→ `Shift-→`), `V`→`v`는 무게시가 아니라 `nil`이어야 게이트 로그에 잡힌다.
- **도그푸딩 결과 (2026-07-28 실기기)**: 정상 확인 — `v`+`Esc` 반복의 캐럿 무표류(진입 `Shift-→` 설계의 핵심 검증), `vwd`, `vwy` 후 Normal 복귀. 예측대로 재현된 편차 — `Vk` 빈 선택, `Vkk` 위 줄만, `V$`/`Vl` 다음 줄 유출(`Vl`은 다음 줄 **첫 글자**까지 = `V` 진입이 포커스를 다음 줄 시작에 두는 모델과 정확히 일치), `vb` 후 `V`가 줄+아랫줄 일부. **신규 편차 1건**: `vb`가 빈 선택([결정](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md)) — 코드 무변경 수용.
- **도그푸딩 버그 오인 금지 (Visual 추가분)** — 전부 수용된 편차다:
  - **`V` 세션에서 충실한 건 `j`·`0`·`G`뿐이다.** `Vk`는 빈 선택으로 접히고, `Vkk`·`Vgg`는 **현재 줄이 빠지며**, `Vl`·`Vw`·`V$`·`V^`는 다음 줄로 샌다. 앵커가 줄 시작의 *점*이라 후진은 원리적으로 불가.
  - **charwise 후진도 어긋난다** — `vb`·`vh`는 **빈 선택**이 된다. 진입 `Shift-→`가 모션 출발점을 P+1로 밀어 `Opt-←`가 이전 단어에 못 닿는다. 상태로도 못 넘는 원점 문제라 M5 AX 몫.
  - `v`→`V` 반복(`vVvV`)은 줄이 누적된다(비멱등). `v` 직후 `V`는 캐럿부터라 현재 줄 전체가 아니다. `V`→`v`는 **아무 일도 안 일어나고 스킵 로그만 남는다**(의도).
  - **전진** 선택 후 Esc는 캐럿이 범위 시작으로 간다(Vim은 active end). 후진 선택과 yank 후는 Vim과 일치.
  - Notion `Shift-Cmd-↑/↓` 충돌이 `vgg vG Vgg VG`를 더해 **6조합 → 10조합**이 됐다. M4 프로파일이 해소.
  - 문서 마지막 단어에서 `vw` 선택 반전 = 기존 [경계 포화 3번](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md)의 재현. 줄 끝 `vd`가 줄을 병합하는 것도 기존 엣지 1번.
- **(해소됨 — 2.5의 원자 그룹 ②가 반영) 래치 입력 2건 (Visual이 만든 것)**: ① Visual에서 **탈출 콤보**로 빠지면 엔진이 `clearSelection`을 안 내므로 **살아 있는 선택이 Normal로 넘어온다** — 그 상태의 `x`(`Shift-→, Cmd-X`)는 stale 선택을 통째로 잘라낸다(사용자 마우스 선택도 동일). ② 래치는 `.edit(.yank, .selection)`과 `clearSelection` **사이를 끊으면 안 된다**(선택이 잔류한다). 또한 `.selection` 편집은 2이벤트로 무제한 범위를 파괴하는 가장 값싼 파괴 액션이 됐다.
- **재검토 후보 (2.5에서도 보류 — 다음 기회는 M5 AX)**: 어댑터에 `linewise: Bool` 상자 1개를 두면 linewise 세션에서 `h l w b e ^ $`를 무게시로 만들어(Vim에서 그 모션들은 V 범위를 안 바꾼다) 위 파괴적 편차 상당수가 사라진다. desync 시 실패 모드는 "모션이 no-op"으로 무해. v1에서는 값 타입 계약 유지를 위해 보류.
- **단계 1 종료** (PR #24 `9f30a54` 병합, 커밋 4개: 매퍼+골든 / 어댑터 배선 / 문서 / `iw` 수정). 검증 3종 + 도그푸딩 통과, 엔진·모션 매퍼·게시 인프라 무변경.
- **단계 1 코드 리뷰 트리아지 (2026-07-28)**: 워크플로 리뷰 9건 검증 — 전부 현상 실재, 오탐 0. 처리: ① 경계 포화 5종 + 소프트 랩 시각 줄 = 수용 엣지 결정 2건 기록([경계 포화](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md), [시각 줄](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md)) — **도그푸딩 시 버그 오인 금지 목록이 늘었다**(특히 첫 줄 `dk`의 아래 줄 삭제, 랩 문단 `dd`). ② 버스트 2건(순서 역전·카운트 폭탄)은 래치 단계 2.5 이동으로 대응. ③ 어댑터 CGEvent 생성 실패 시 액션 단위 all-or-nothing 가드 적용(부분 시퀀스 게시 봉쇄). **래치 전까지 도그푸딩 규율**: 실문서 대신 스크래치 문서, 큰 카운트 자제.
- **단계 1이 남긴 실행 구조**: `EditKeyMapper.keyStrokes(for:range:family:) -> [KeyStroke]?`가 편집 시퀀스를 내고, `nil`이 곧 미지원(스킵+로그)이다. 선택은 `MotionKeyMapper` 결과에 Shift를 얹어 만들므로 **모션 매핑이 개선되면 편집이 자동으로 따라온다** — 단계 2의 Visual 선택 확장도 같은 재사용을 쓴다. `ElementFamily`는 어댑터가 `.textArea` 고정 주입 중이며 단계 3에서 이 자리에 리졸버가 들어온다. 결정 4건: [매핑 계약](../../decisions/references/20260727_edit-keystroke-mapping-contract.md), [linewise 반올림](../../decisions/references/20260727_linewise-newline-rounding.md), [yank collapse](../../decisions/references/20260727_yank-collapse-to-range-start.md), [ANSI 레이아웃 가정](../../decisions/references/20260727_operator-key-ansi-layout-assumption.md).
- **도그푸딩 1차 결과 (2026-07-27)**: 편차 2건. ① `iw` 앵커가 `Opt-←` 1타라 캐럿이 단어 시작이면 앞 단어를 지웠다 → `Opt-→,Opt-←` 경유 3타로 수정([결정](../../decisions/references/20260727_inner-word-anchor-via-word-end.md)). ② Notion은 `Shift-Cmd-↑/↓`가 블록 이동이라 `d/c/y`+`G`·`gg` 6조합이 파괴적 오동작 → **수용**, M4 프로파일이 해소([결정](../../decisions/references/20260727_notion-cmd-shift-vertical-conflict.md)).
- **M5 AX 인계 메모**: 지금 수용해 둔 엣지 상당수가 쓰기가 아니라 **읽기** 문제다 — `iw` 단어 경계(캐럿 좌우가 공백인지), 마지막 줄 `dd`·`dG`(캐럿이 마지막 줄인지), 탭 들여쓰기 `^`(앱별 단어 경계), `cw`→`ce` 특례, 경계 포화 5종(줄 끝 `x`·첫 줄 `dk`·마지막 단어 `dw`·마지막 줄 `dgg`·빈 선택)과 소프트 랩 시각 줄(2026-07-28 수용 엣지 결정 2건). **2c 편차도 대부분 읽기 문제다** — charwise `p`의 줄 끝(캐럿이 줄 끝인지), linewise `p`의 마지막 줄(마지막 줄인지), 소프트 랩의 `o`/`O`(논리 줄 경계), charwise `P`의 살아 있는 선택(`AXSelectedTextRange` 길이), 그리고 paste wise 자체(레지스터가 있으면 휴리스틱이 필요 없다 — v2 레지스터 또는 AX 어댑터의 yank 경로가 wise를 기억하면 해소). **Visual 편차는 통째로 여기 속한다** — `V` 세션 후진(`Vk`·`Vkk`)과 charwise 후진(`vb`·`vh`)은 앵커가 앱 안에 점으로 박혀 읽을 수 없어서 생기며, `AXSelectedTextRange`를 읽고 쓰면 원점 이동·정적 앵커 문제가 함께 사라진다. `AXValue`+`AXSelectedTextRange`로 정확 오프셋을 계산하고 실행은 키보드로 하는 혼용이면 전부 해소된다(적용 범위는 [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)의 미결 질문).
- **단계 4로 넘긴 항목 2건 추가**: ① 비-QWERTY 레이아웃에서 오퍼레이터 키가 엉뚱한 `Cmd-` 단축키로 나간다 — 게이트 해제 시 안전판 필요 여부 판단. ② Notion `G`·`gg` 파괴적 오동작 — "무로그 삼킴 없음"과 별개 축이라 게이트 판정 시 재검토.
- 규모 추정: 남은 것(2c 도그푸딩 + 단계 2.5·3·4) 3~4세션, PR 3개.
- **단계 0 실측이 남긴 주의사항 (단계 1·2 설계 참고)**: ① Notion은 버스트에서 합성 이벤트를 드랍한다 — 편집 시퀀스 도그푸딩 시 Notion에서 어긋나면 드랍 가능성부터 의심. ② TextEdit 등 일부 네이티브 앱은 Opt-화살표 계열이 표준대로 안 먹힌다 — 시퀀스 검증은 표준 바인딩 앱(Notion·Chrome·VS Code) 기준, 네이티브 편차는 M5 AX 영역으로 수용. ③ change 실행 후 u는 2회(타이핑→삭제 복원)가 정상 동작이다 — 버그로 오인 금지.
- **인계 계약 (M2에서 그대로)**: 합성 게시는 반드시 `ActionExecutor.post` 경유, CGEvent는 게시 직렬 큐 위에서 생성(비-Sendable), 실패 보고는 `reportExecutionFailure`로 원인 키 1건당 최대 1회 — 단 Keyboard 게시 경로는 오류를 돌려주지 않아 M3에서도 호출자 없음 유지(신호는 M5 AX가 만든다).
- **실행 구조 (M2가 남긴 것)**: `.replace` → sink 클로저 → 게시 직렬 큐 → `KeyboardAdapter` → `ActionExecutor`. 앱 게이트는 마커·토글 뒤·번역 앞. 세부: [실행 배선 결정](../../decisions/references/20260726_m2-execution-wiring-shape.md).
- **테스트 seam**: `ActionExecutor(postEvent:)` 수집기 주입(headless 가능). 실행 sink·앱 게이트 기본값은 XCTest 하위에서 무해한 것으로 바꿔치기됨 — 동작 검증 테스트는 init으로 자기 것을 주입.
- **도그푸딩 관측**: `/usr/bin/log stream --level debug --predicate 'subsystem == "dev.pilyang.VimAction"'` (zsh가 `log`를 가려 절대 경로 필요, `log show`로는 `.debug` 판정 불가).
- 소비자는 `VimAction`에 exhaustive switch 금지(`default:` 흡수) — 엔진 케이스 추가에 견디는 계약.

## 관련 링크

- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (네 매퍼·요소 계열·스킵 2종), [mode-engine.md](../../architecture/references/mode-engine.md) (어댑터 위임 계약: cw→ce, paste 판정, linewise 반올림, append, Visual y collapse), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [게이트 M3 이동](../../decisions/references/20260726_release-block-gate-moves-to-m3.md), [모션 매핑 계약](../../decisions/references/20260726_motion-keystroke-mapping-contract.md), [실행 배선 형태](../../decisions/references/20260726_m2-execution-wiring-shape.md), [콜백 경량 불변식](../../decisions/references/20260725_callback-light-invariant.md), [실패 보고 단위](../../decisions/references/20260726_execution-failure-report-granularity.md)

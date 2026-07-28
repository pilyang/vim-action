# M3 — Keyboard 어댑터 ② 편집 + Visual + 요소 리졸버

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-26
- **갱신일**: 2026-07-28 (**단계 2a+2b 코드 완료** — Visual 실행 배선, 결정 4건 기록. 도그푸딩·2c 미완)

## 목표

v1 어휘 전체(편집·Visual·o/p/u·스크롤)가 Keyboard 전략으로 실제 실행되고, 요소 리졸버(focusedRole 캐시)가 TextArea/TextField 시퀀스를 가르는 상태. 끝나면 릴리스 배포 금지 게이트(`.replace` 무로그 삼킴 규칙)가 해제된다 — [게이트 이동 결정](../../decisions/references/20260726_release-block-gate-moves-to-m3.md). 상위 마일스톤: [20260725_mvp-milestones.md](20260725_mvp-milestones.md).

**범위 확정 3건 (2026-07-26 사용자 확인)**:
- 텍스트 오브젝트는 **word만 근사 지원**(diw/ciw ≈ `Opt-←, Shift-Opt-→`) — aw·quote·pair는 미지원 스킵(로그), M5 AX에서 정식 지원.
- 순서는 **편집 먼저, 리졸버 나중** — 단계 1·2는 TextArea 시퀀스 고정, 단 매퍼 테이블은 처음부터 `(action, family)` 키로 설계해 단계 3 재작업을 봉쇄.
- **사전 실측을 단계 0으로 선행** — 결과가 래치 승격·undo 매핑 설계를 확정한 뒤 코드 착수.

## 완료된 것

- [x] **단계 2a+2b — Visual 실행 코드 완료** (2026-07-28): `VisualKeyMapper` 신규 + `MotionKeyMapper.selectionStrokes` 공유 추출 + `EditKeyMapper` `.selection` + 어댑터 배선, 골든 신규 21행. 설계 결정 4건은 아래 "진행 중 컨텍스트" 참조. **도그푸딩 미완.**
- [x] (선행 상태) M1·M2 종료 — 모션 실행·앱 게이트·킬스위치·출력 인프라 완비. 편집·Visual·paste·undo·스크롤은 아직 무로그 스킵.
- [x] **단계 1 도그푸딩 완료** (2026-07-27 실기기): `x`·charwise 모션·`cw`(뒤 공백 유지 + Insert 전이)·`dd/cc/yy`·`j k`·`diw/ciw/yiw`(수정 후 단어 시작·중간 정확) 확인. 편차 2건은 아래 "진행 중 컨텍스트" 참조 — 1건 수정, 1건 수용. **단계 1 종료**.
- [x] **단계 1 — Normal 편집 실행 (본체) 코드 완료** (2026-07-27): 신규 순수 매퍼 `EditKeyMapper`(선택 후 오퍼레이터 1타, 선택은 모션 매핑 재사용) + `KeyboardAdapter` `.edit` 배선 + 골든 57행. 범위: `x`, d/c/y + charwise 8모션, cw→ce 특례, `dd/cc/yy`, `j k G gg`, `diw/ciw/yiw`. 미지원(aw·따옴표·괄호쌍·Visual selection)은 `nil` → 스킵+로그. 설계 결정 4건은 아래 "진행 중 컨텍스트" 참조. **도그푸딩 미완**.
- [x] **단계 0 — 사전 실측 2건 완료** (2026-07-26 실기기): ① 카운트 폭탄 — 100j 1초 이내·9999j 수 초 폭주(비치볼), 킬스위치 발동 즉시지만 in-flight 못 멈춤, 버스트 중 타이핑 순서 역전 실증, Notion 이벤트 드랍 → **실행 중단 래치 단계 4 승격 확정** ([결정](../../decisions/references/20260726_count-burst-abort-latch-promotion.md)). ② undo — 선택+잘라내기/붙여넣기/새줄 시퀀스 전부 1 undo 단위, change만 삭제+타이핑 분리 → **u=Cmd-Z 유지·시퀀스 설계 자유 확정** ([결정](../../decisions/references/20260726_undo-unit-cmdz-policy.md)).

## 남은 것
- [ ] **단계 2c — 나머지 어휘**: `o/O`, `p/P`, `u`/`Ctrl-r`=Cmd-Z/Shift-Cmd-Z, 스크롤. **방향은 사용자 확정 완료** — 2c 세션이 결정 문서화만 하면 된다:
  - **스크롤**: half/full 모두 `PageUp`/`PageDown` ×1로 수렴 (half-page 프리미티브가 없다).
  - **paste 판정**: 클립보드 끝 개행 휴리스틱으로 charwise/linewise를 가른다. charwise `p`=`→`+`Cmd-V`·`P`=`Cmd-V`, linewise `p`=다음 줄 시작 이동 후 `Cmd-V`·`P`=`Cmd-←` 후 `Cmd-V`, `3p`=`Cmd-V` 3연타.
- [ ] **단계 2 도그푸딩 (Visual)**: 아래 "진행 중 컨텍스트"의 수용 엣지 목록을 먼저 읽을 것 — 버그 오인 금지 항목이 단계 1보다 많다. 편차 트리아지 후 PR 마무리(이 브랜치는 PR 미생성 상태).
- [ ] **단계 2.5 — 실행 중단 래치** (2026-07-28 리뷰 트리아지로 단계 4에서 앞당김): 방향은 청크 게시 + 청크 사이 중단 체크(단계 0 실측 확정), 순서 역전 방지("새 입력 시 잔여 큐 폐기")·Notion 드랍 완화 겸용 검토, 클램프 값 재검토 포함. **단계 2 직후에 두는 이유**: `.edit` 배선으로 버스트가 파괴적(`Cmd-X`로 종결)으로 격상됐는데, Visual까지 본 뒤 설계해야 "선택 확장 도중 중단" 의미론의 재작업이 없다 — 단계 3(읽기 전용 AX, 래치 무관)보다는 앞선다.
- [ ] **단계 3 — 요소 리졸버 + TextField 분기**: `AXObserver`(kAXFocusedUIElementChanged) + NSWorkspace 활성화로 focusedRole 캐시(콜백은 캐시만 읽음 — 콜백 경량 불변식 위임 ②), TextField 시퀀스 분기(예: `delete(.line)` → `Cmd-A, Delete`), **캐시 충분성 1차 확정**(결정 문서). 앱 최초의 실질 AX 의존(읽기 전용) — 실기기 검증 비중 큼.
- [ ] **단계 4 — 안전망 회귀 + 게이트 해제**: 킬스위치 회귀 확인(래치와의 상호작용 포함), 미지원 스킵 로그 전수 확인 → `.replace` 무로그 삼킴 해소 → 릴리스 금지 게이트 해제 결정 문서.

## 진행 중 컨텍스트

- **단계 2a+2b 코드 완료** (2026-07-28, 브랜치 `feat/m3-visual-vocab`). 신규 순수 매퍼 `VisualKeyMapper`(세션 진입·확장·wise 전환·이탈) + `MotionKeyMapper.selectionStrokes(for:)` 공유 추출 + `EditKeyMapper`의 `.selection` 분기(계열 분기 **밖**) + 어댑터 4케이스 배선. 검증 3종 통과(엔진 무변경, 앱 391 테스트, 빌드). **엔진·게시 인프라 무변경.** 다음은 **도그푸딩**, 그다음 2c, 그다음 단계 2.5 래치.
- **단계 2 설계 결정 4건**: [charwise 진입 1문자 선택](../../decisions/references/20260728_visual-charwise-entry-inclusive-selection.md), [무상태 확장](../../decisions/references/20260728_visual-extend-stateless-no-linewise-rounding.md), [switchWise 근사](../../decisions/references/20260728_visual-switch-wise-focus-end-rounding.md), [collapse 단일화](../../decisions/references/20260728_visual-clear-selection-collapse-left.md). 설계 리뷰에서 잡힌 것 2건이 여기 반영돼 있다: `v` 진입을 무게시로 두면 `vd`/`vy`가 무동작이고 Esc가 캐럿을 표류시킨다(→ `Shift-→`), `V`→`v`는 무게시가 아니라 `nil`이어야 게이트 로그에 잡힌다.
- **도그푸딩 버그 오인 금지 (Visual 추가분)** — 전부 수용된 편차다:
  - **`V` 세션에서 충실한 건 `j`·`0`·`G`뿐이다.** `Vk`는 빈 선택으로 접히고, `Vkk`·`Vgg`는 **현재 줄이 빠지며**, `Vl`·`Vw`·`V$`·`V^`는 다음 줄로 샌다. 앵커가 줄 시작의 *점*이라 후진은 원리적으로 불가.
  - `v`→`V` 반복(`vVvV`)은 줄이 누적된다(비멱등). `v` 직후 `V`는 캐럿부터라 현재 줄 전체가 아니다. `V`→`v`는 **아무 일도 안 일어나고 스킵 로그만 남는다**(의도).
  - **전진** 선택 후 Esc는 캐럿이 범위 시작으로 간다(Vim은 active end). 후진 선택과 yank 후는 Vim과 일치.
  - Notion `Shift-Cmd-↑/↓` 충돌이 `vgg vG Vgg VG`를 더해 **6조합 → 10조합**이 됐다. M4 프로파일이 해소.
  - 문서 마지막 단어에서 `vw` 선택 반전 = 기존 [경계 포화 3번](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md)의 재현. 줄 끝 `vd`가 줄을 병합하는 것도 기존 엣지 1번.
- **단계 2.5 래치 입력 2건 (Visual이 만든 것)**: ① Visual에서 **탈출 콤보**로 빠지면 엔진이 `clearSelection`을 안 내므로 **살아 있는 선택이 Normal로 넘어온다** — 그 상태의 `x`(`Shift-→, Cmd-X`)는 stale 선택을 통째로 잘라낸다(사용자 마우스 선택도 동일). ② 래치는 `.edit(.yank, .selection)`과 `clearSelection` **사이를 끊으면 안 된다**(선택이 잔류한다). 또한 `.selection` 편집은 2이벤트로 무제한 범위를 파괴하는 가장 값싼 파괴 액션이 됐다.
- **단계 2.5 재검토 후보**: 어댑터에 `linewise: Bool` 상자 1개를 두면 linewise 세션에서 `h l w b e ^ $`를 무게시로 만들어(Vim에서 그 모션들은 V 범위를 안 바꾼다) 위 파괴적 편차 상당수가 사라진다. desync 시 실패 모드는 "모션이 no-op"으로 무해. v1에서는 값 타입 계약 유지를 위해 보류.
- **단계 1 종료** (브랜치 `feat/m3-edit-execution`, 커밋 4개: 매퍼+골든 / 어댑터 배선 / 문서 / `iw` 수정). 검증 3종 + 도그푸딩 통과, 엔진·모션 매퍼·게시 인프라 무변경. 다음은 **단계 2 Visual**, 그 다음이 **단계 2.5 래치**.
- **단계 1 코드 리뷰 트리아지 (2026-07-28)**: 워크플로 리뷰 9건 검증 — 전부 현상 실재, 오탐 0. 처리: ① 경계 포화 5종 + 소프트 랩 시각 줄 = 수용 엣지 결정 2건 기록([경계 포화](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md), [시각 줄](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md)) — **도그푸딩 시 버그 오인 금지 목록이 늘었다**(특히 첫 줄 `dk`의 아래 줄 삭제, 랩 문단 `dd`). ② 버스트 2건(순서 역전·카운트 폭탄)은 래치 단계 2.5 이동으로 대응. ③ 어댑터 CGEvent 생성 실패 시 액션 단위 all-or-nothing 가드 적용(부분 시퀀스 게시 봉쇄). **래치 전까지 도그푸딩 규율**: 실문서 대신 스크래치 문서, 큰 카운트 자제.
- **단계 1이 남긴 실행 구조**: `EditKeyMapper.keyStrokes(for:range:family:) -> [KeyStroke]?`가 편집 시퀀스를 내고, `nil`이 곧 미지원(스킵+로그)이다. 선택은 `MotionKeyMapper` 결과에 Shift를 얹어 만들므로 **모션 매핑이 개선되면 편집이 자동으로 따라온다** — 단계 2의 Visual 선택 확장도 같은 재사용을 쓴다. `ElementFamily`는 어댑터가 `.textArea` 고정 주입 중이며 단계 3에서 이 자리에 리졸버가 들어온다. 결정 4건: [매핑 계약](../../decisions/references/20260727_edit-keystroke-mapping-contract.md), [linewise 반올림](../../decisions/references/20260727_linewise-newline-rounding.md), [yank collapse](../../decisions/references/20260727_yank-collapse-to-range-start.md), [ANSI 레이아웃 가정](../../decisions/references/20260727_operator-key-ansi-layout-assumption.md).
- **도그푸딩 1차 결과 (2026-07-27)**: 편차 2건. ① `iw` 앵커가 `Opt-←` 1타라 캐럿이 단어 시작이면 앞 단어를 지웠다 → `Opt-→,Opt-←` 경유 3타로 수정([결정](../../decisions/references/20260727_inner-word-anchor-via-word-end.md)). ② Notion은 `Shift-Cmd-↑/↓`가 블록 이동이라 `d/c/y`+`G`·`gg` 6조합이 파괴적 오동작 → **수용**, M4 프로파일이 해소([결정](../../decisions/references/20260727_notion-cmd-shift-vertical-conflict.md)).
- **M5 AX 인계 메모**: 지금 수용해 둔 엣지 상당수가 쓰기가 아니라 **읽기** 문제다 — `iw` 단어 경계(캐럿 좌우가 공백인지), 마지막 줄 `dd`·`dG`(캐럿이 마지막 줄인지), 탭 들여쓰기 `^`(앱별 단어 경계), `cw`→`ce` 특례, 경계 포화 5종(줄 끝 `x`·첫 줄 `dk`·마지막 단어 `dw`·마지막 줄 `dgg`·빈 선택)과 소프트 랩 시각 줄(2026-07-28 수용 엣지 결정 2건). `AXValue`+`AXSelectedTextRange`로 정확 오프셋을 계산하고 실행은 키보드로 하는 혼용이면 전부 해소된다(적용 범위는 [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)의 미결 질문).
- **단계 4로 넘긴 항목 2건 추가**: ① 비-QWERTY 레이아웃에서 오퍼레이터 키가 엉뚱한 `Cmd-` 단축키로 나간다 — 게이트 해제 시 안전판 필요 여부 판단. ② Notion `G`·`gg` 파괴적 오동작 — "무로그 삼킴 없음"과 별개 축이라 게이트 판정 시 재검토.
- 규모 추정: 남은 3단계 3~5세션, PR 3~4개.
- **단계 0 실측이 남긴 주의사항 (단계 1·2 설계 참고)**: ① Notion은 버스트에서 합성 이벤트를 드랍한다 — 편집 시퀀스 도그푸딩 시 Notion에서 어긋나면 드랍 가능성부터 의심. ② TextEdit 등 일부 네이티브 앱은 Opt-화살표 계열이 표준대로 안 먹힌다 — 시퀀스 검증은 표준 바인딩 앱(Notion·Chrome·VS Code) 기준, 네이티브 편차는 M5 AX 영역으로 수용. ③ change 실행 후 u는 2회(타이핑→삭제 복원)가 정상 동작이다 — 버그로 오인 금지.
- **인계 계약 (M2에서 그대로)**: 합성 게시는 반드시 `ActionExecutor.post` 경유, CGEvent는 게시 직렬 큐 위에서 생성(비-Sendable), 실패 보고는 `reportExecutionFailure`로 원인 키 1건당 최대 1회 — 단 Keyboard 게시 경로는 오류를 돌려주지 않아 M3에서도 호출자 없음 유지(신호는 M5 AX가 만든다).
- **실행 구조 (M2가 남긴 것)**: `.replace` → sink 클로저 → 게시 직렬 큐 → `KeyboardAdapter` → `ActionExecutor`. 앱 게이트는 마커·토글 뒤·번역 앞. 세부: [실행 배선 결정](../../decisions/references/20260726_m2-execution-wiring-shape.md).
- **테스트 seam**: `ActionExecutor(postEvent:)` 수집기 주입(headless 가능). 실행 sink·앱 게이트 기본값은 XCTest 하위에서 무해한 것으로 바꿔치기됨 — 동작 검증 테스트는 init으로 자기 것을 주입.
- **도그푸딩 관측**: `/usr/bin/log stream --level debug --predicate 'subsystem == "dev.pilyang.VimAction"'` (zsh가 `log`를 가려 절대 경로 필요, `log show`로는 `.debug` 판정 불가).
- 소비자는 `VimAction`에 exhaustive switch 금지(`default:` 흡수) — 엔진 케이스 추가에 견디는 계약.

## 관련 링크

- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [mode-engine.md](../../architecture/references/mode-engine.md) (어댑터 위임 계약: cw→ce, paste 판정, linewise 반올림, append, Visual y collapse), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [게이트 M3 이동](../../decisions/references/20260726_release-block-gate-moves-to-m3.md), [모션 매핑 계약](../../decisions/references/20260726_motion-keystroke-mapping-contract.md), [실행 배선 형태](../../decisions/references/20260726_m2-execution-wiring-shape.md), [콜백 경량 불변식](../../decisions/references/20260725_callback-light-invariant.md), [실패 보고 단위](../../decisions/references/20260726_execution-failure-report-granularity.md)

# M3 — Keyboard 어댑터 ② 편집 + Visual + 요소 리졸버

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-26
- **갱신일**: 2026-07-27 (단계 1 도그푸딩 1차 — 편차 2건 처리: `iw` 앵커 수정, Notion `Shift-Cmd-↑/↓` 수용)

## 목표

v1 어휘 전체(편집·Visual·o/p/u·스크롤)가 Keyboard 전략으로 실제 실행되고, 요소 리졸버(focusedRole 캐시)가 TextArea/TextField 시퀀스를 가르는 상태. 끝나면 릴리스 배포 금지 게이트(`.replace` 무로그 삼킴 규칙)가 해제된다 — [게이트 이동 결정](../../decisions/references/20260726_release-block-gate-moves-to-m3.md). 상위 마일스톤: [20260725_mvp-milestones.md](20260725_mvp-milestones.md).

**범위 확정 3건 (2026-07-26 사용자 확인)**:
- 텍스트 오브젝트는 **word만 근사 지원**(diw/ciw ≈ `Opt-←, Shift-Opt-→`) — aw·quote·pair는 미지원 스킵(로그), M5 AX에서 정식 지원.
- 순서는 **편집 먼저, 리졸버 나중** — 단계 1·2는 TextArea 시퀀스 고정, 단 매퍼 테이블은 처음부터 `(action, family)` 키로 설계해 단계 3 재작업을 봉쇄.
- **사전 실측을 단계 0으로 선행** — 결과가 래치 승격·undo 매핑 설계를 확정한 뒤 코드 착수.

## 완료된 것

- [x] (선행 상태) M1·M2 종료 — 모션 실행·앱 게이트·킬스위치·출력 인프라 완비. 편집·Visual·paste·undo·스크롤은 아직 무로그 스킵.
- [x] **단계 1 — Normal 편집 실행 (본체) 코드 완료** (2026-07-27): 신규 순수 매퍼 `EditKeyMapper`(선택 후 오퍼레이터 1타, 선택은 모션 매핑 재사용) + `KeyboardAdapter` `.edit` 배선 + 골든 57행. 범위: `x`, d/c/y + charwise 8모션, cw→ce 특례, `dd/cc/yy`, `j k G gg`, `diw/ciw/yiw`. 미지원(aw·따옴표·괄호쌍·Visual selection)은 `nil` → 스킵+로그. 설계 결정 4건은 아래 "진행 중 컨텍스트" 참조. **도그푸딩 미완**.
- [x] **단계 0 — 사전 실측 2건 완료** (2026-07-26 실기기): ① 카운트 폭탄 — 100j 1초 이내·9999j 수 초 폭주(비치볼), 킬스위치 발동 즉시지만 in-flight 못 멈춤, 버스트 중 타이핑 순서 역전 실증, Notion 이벤트 드랍 → **실행 중단 래치 단계 4 승격 확정** ([결정](../../decisions/references/20260726_count-burst-abort-latch-promotion.md)). ② undo — 선택+잘라내기/붙여넣기/새줄 시퀀스 전부 1 undo 단위, change만 삭제+타이핑 분리 → **u=Cmd-Z 유지·시퀀스 설계 자유 확정** ([결정](../../decisions/references/20260726_undo-unit-cmdz-policy.md)).

## 남은 것
- [ ] **단계 1 도그푸딩 2차 (실기기)**: 1차에서 나온 `iw` 앵커 수정을 재확인(단어 시작·중간·끝에서 `diw/ciw/yiw`)하고, 아직 안 돈 항목을 마저 돈다 — `x`·`d/c/y`+charwise 모션·`dd/cc/yy`·`d/c/y`+`j k`·미지원 스킵 로그(`caw`·`ci"`)·M2 회귀(이동·토글·킬스위치). **버그 아닌 것**: 마지막 줄 `dd`·`dG`의 빈 줄 1개 잔존, `change` 후 `u` 2회, TextEdit 등 네이티브 앱의 Opt-화살표 편차, **Notion의 `d/c/y`+`G`·`gg`**(수용 확정), 미지원 오브젝트의 "안 지워진 채 Insert". 어긋나면 Notion은 이벤트 드랍부터 의심.
- [ ] **단계 2 — Visual + 나머지 어휘**: Visual(begin/extend/switchWise/clear → Shift+모션, 선택 동작은 단계 1 실행 재사용, y 후 collapse 목적지), `o/O`, `p/P`(NSPasteboard 검사로 charwise/linewise 판정 + linewise 줄 반올림), `u`/`Ctrl-r`=Cmd-Z/Shift-Cmd-Z, 스크롤(half-page 프리미티브 부재 — 키 선택 결정 필요, PageUp/Down 수렴 유력).
- [ ] **단계 3 — 요소 리졸버 + TextField 분기**: `AXObserver`(kAXFocusedUIElementChanged) + NSWorkspace 활성화로 focusedRole 캐시(콜백은 캐시만 읽음 — 콜백 경량 불변식 위임 ②), TextField 시퀀스 분기(예: `delete(.line)` → `Cmd-A, Delete`), **캐시 충분성 1차 확정**(결정 문서). 앱 최초의 실질 AX 의존(읽기 전용) — 실기기 검증 비중 큼.
- [ ] **단계 4 — 실행 중단 래치 + 안전망 회귀 + 게이트 해제**: **실행 중단 래치 구현** (단계 0 실측으로 승격 확정 — 방향은 청크 게시 + 청크 사이 중단 체크, 순서 역전 방지·Notion 드랍 완화 겸용 검토, 클램프 값 재검토 포함), 킬스위치 회귀 확인, 미지원 스킵 로그 전수 확인 → `.replace` 무로그 삼킴 해소 → 릴리스 금지 게이트 해제 결정 문서.

## 진행 중 컨텍스트

- **단계 1 코드 완료** (브랜치 `feat/m3-edit-execution`, 커밋 2개: 매퍼+골든 / 어댑터 배선). 검증 3종 통과, 엔진·모션 매퍼·게시 인프라 무변경. 남은 것은 **실기기 도그푸딩**뿐 — 그다음 단계 2.
- **단계 1이 남긴 실행 구조**: `EditKeyMapper.keyStrokes(for:range:family:) -> [KeyStroke]?`가 편집 시퀀스를 내고, `nil`이 곧 미지원(스킵+로그)이다. 선택은 `MotionKeyMapper` 결과에 Shift를 얹어 만들므로 **모션 매핑이 개선되면 편집이 자동으로 따라온다** — 단계 2의 Visual 선택 확장도 같은 재사용을 쓴다. `ElementFamily`는 어댑터가 `.textArea` 고정 주입 중이며 단계 3에서 이 자리에 리졸버가 들어온다. 결정 4건: [매핑 계약](../../decisions/references/20260727_edit-keystroke-mapping-contract.md), [linewise 반올림](../../decisions/references/20260727_linewise-newline-rounding.md), [yank collapse](../../decisions/references/20260727_yank-collapse-to-range-start.md), [ANSI 레이아웃 가정](../../decisions/references/20260727_operator-key-ansi-layout-assumption.md).
- **도그푸딩 1차 결과 (2026-07-27)**: 편차 2건. ① `iw` 앵커가 `Opt-←` 1타라 캐럿이 단어 시작이면 앞 단어를 지웠다 → `Opt-→,Opt-←` 경유 3타로 수정([결정](../../decisions/references/20260727_inner-word-anchor-via-word-end.md)). ② Notion은 `Shift-Cmd-↑/↓`가 블록 이동이라 `d/c/y`+`G`·`gg` 6조합이 파괴적 오동작 → **수용**, M4 프로파일이 해소([결정](../../decisions/references/20260727_notion-cmd-shift-vertical-conflict.md)).
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

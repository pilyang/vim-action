# M3 — Keyboard 어댑터 ② 편집 + Visual + 요소 리졸버

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-26
- **갱신일**: 2026-07-26 (단계 0 실측 완료 — 래치 승격 확정, undo 정책 확정, 결정 2건 기록)

## 목표

v1 어휘 전체(편집·Visual·o/p/u·스크롤)가 Keyboard 전략으로 실제 실행되고, 요소 리졸버(focusedRole 캐시)가 TextArea/TextField 시퀀스를 가르는 상태. 끝나면 릴리스 배포 금지 게이트(`.replace` 무로그 삼킴 규칙)가 해제된다 — [게이트 이동 결정](../../decisions/references/20260726_release-block-gate-moves-to-m3.md). 상위 마일스톤: [20260725_mvp-milestones.md](20260725_mvp-milestones.md).

**범위 확정 3건 (2026-07-26 사용자 확인)**:
- 텍스트 오브젝트는 **word만 근사 지원**(diw/ciw ≈ `Opt-←, Shift-Opt-→`) — aw·quote·pair는 미지원 스킵(로그), M5 AX에서 정식 지원.
- 순서는 **편집 먼저, 리졸버 나중** — 단계 1·2는 TextArea 시퀀스 고정, 단 매퍼 테이블은 처음부터 `(action, family)` 키로 설계해 단계 3 재작업을 봉쇄.
- **사전 실측을 단계 0으로 선행** — 결과가 래치 승격·undo 매핑 설계를 확정한 뒤 코드 착수.

## 완료된 것

- [x] (선행 상태) M1·M2 종료 — 모션 실행·앱 게이트·킬스위치·출력 인프라 완비. 편집·Visual·paste·undo·스크롤은 아직 무로그 스킵.
- [x] **단계 0 — 사전 실측 2건 완료** (2026-07-26 실기기): ① 카운트 폭탄 — 100j 1초 이내·9999j 수 초 폭주(비치볼), 킬스위치 발동 즉시지만 in-flight 못 멈춤, 버스트 중 타이핑 순서 역전 실증, Notion 이벤트 드랍 → **실행 중단 래치 단계 4 승격 확정** ([결정](../../decisions/references/20260726_count-burst-abort-latch-promotion.md)). ② undo — 선택+잘라내기/붙여넣기/새줄 시퀀스 전부 1 undo 단위, change만 삭제+타이핑 분리 → **u=Cmd-Z 유지·시퀀스 설계 자유 확정** ([결정](../../decisions/references/20260726_undo-unit-cmdz-policy.md)).

## 남은 것
- [ ] **단계 1 — Normal 편집 실행 (본체)**: 순수 매퍼 확장(`.edit(op, range)` → 범위 선택(Shift+모션) 후 delete/x=Cmd-X·yank=Cmd-C·change=Cmd-X 후 Insert 유지), `x`·`dd/cc/yy`·오퍼레이터+모션·linewise 줄 반올림, cw→ce 특례, append 시맨틱(`charRightForAppend`/`lineEndForAppend`), word 텍스트 오브젝트 근사. TextArea 고정, 테이블은 `(action, family)` 키. 골든 출력 테스트.
- [ ] **단계 2 — Visual + 나머지 어휘**: Visual(begin/extend/switchWise/clear → Shift+모션, 선택 동작은 단계 1 실행 재사용, y 후 collapse 목적지), `o/O`, `p/P`(NSPasteboard 검사로 charwise/linewise 판정 + linewise 줄 반올림), `u`/`Ctrl-r`=Cmd-Z/Shift-Cmd-Z, 스크롤(half-page 프리미티브 부재 — 키 선택 결정 필요, PageUp/Down 수렴 유력).
- [ ] **단계 3 — 요소 리졸버 + TextField 분기**: `AXObserver`(kAXFocusedUIElementChanged) + NSWorkspace 활성화로 focusedRole 캐시(콜백은 캐시만 읽음 — 콜백 경량 불변식 위임 ②), TextField 시퀀스 분기(예: `delete(.line)` → `Cmd-A, Delete`), **캐시 충분성 1차 확정**(결정 문서). 앱 최초의 실질 AX 의존(읽기 전용) — 실기기 검증 비중 큼.
- [ ] **단계 4 — 실행 중단 래치 + 안전망 회귀 + 게이트 해제**: **실행 중단 래치 구현** (단계 0 실측으로 승격 확정 — 방향은 청크 게시 + 청크 사이 중단 체크, 순서 역전 방지·Notion 드랍 완화 겸용 검토, 클램프 값 재검토 포함), 킬스위치 회귀 확인, 미지원 스킵 로그 전수 확인 → `.replace` 무로그 삼킴 해소 → 릴리스 금지 게이트 해제 결정 문서.

## 진행 중 컨텍스트

- 단계 0 완료, 다음은 **단계 1 (편집 본체)**. 코드 변경 아직 없음. 규모 추정: 4~6세션, PR 4~5개.
- **단계 0 실측이 남긴 주의사항 (단계 1·2 설계 참고)**: ① Notion은 버스트에서 합성 이벤트를 드랍한다 — 편집 시퀀스 도그푸딩 시 Notion에서 어긋나면 드랍 가능성부터 의심. ② TextEdit 등 일부 네이티브 앱은 Opt-화살표 계열이 표준대로 안 먹힌다 — 시퀀스 검증은 표준 바인딩 앱(Notion·Chrome·VS Code) 기준, 네이티브 편차는 M5 AX 영역으로 수용. ③ change 실행 후 u는 2회(타이핑→삭제 복원)가 정상 동작이다 — 버그로 오인 금지.
- **인계 계약 (M2에서 그대로)**: 합성 게시는 반드시 `ActionExecutor.post` 경유, CGEvent는 게시 직렬 큐 위에서 생성(비-Sendable), 실패 보고는 `reportExecutionFailure`로 원인 키 1건당 최대 1회 — 단 Keyboard 게시 경로는 오류를 돌려주지 않아 M3에서도 호출자 없음 유지(신호는 M5 AX가 만든다).
- **실행 구조 (M2가 남긴 것)**: `.replace` → sink 클로저 → 게시 직렬 큐 → `KeyboardAdapter` → `ActionExecutor`. 앱 게이트는 마커·토글 뒤·번역 앞. 세부: [실행 배선 결정](../../decisions/references/20260726_m2-execution-wiring-shape.md).
- **테스트 seam**: `ActionExecutor(postEvent:)` 수집기 주입(headless 가능). 실행 sink·앱 게이트 기본값은 XCTest 하위에서 무해한 것으로 바꿔치기됨 — 동작 검증 테스트는 init으로 자기 것을 주입.
- **도그푸딩 관측**: `/usr/bin/log stream --level debug --predicate 'subsystem == "dev.pilyang.VimAction"'` (zsh가 `log`를 가려 절대 경로 필요, `log show`로는 `.debug` 판정 불가).
- 소비자는 `VimAction`에 exhaustive switch 금지(`default:` 흡수) — 엔진 케이스 추가에 견디는 계약.

## 관련 링크

- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [mode-engine.md](../../architecture/references/mode-engine.md) (어댑터 위임 계약: cw→ce, paste 판정, linewise 반올림, append, Visual y collapse), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [게이트 M3 이동](../../decisions/references/20260726_release-block-gate-moves-to-m3.md), [모션 매핑 계약](../../decisions/references/20260726_motion-keystroke-mapping-contract.md), [실행 배선 형태](../../decisions/references/20260726_m2-execution-wiring-shape.md), [콜백 경량 불변식](../../decisions/references/20260725_callback-light-invariant.md), [실패 보고 단위](../../decisions/references/20260726_execution-failure-report-granularity.md)

# M5 — AX 어댑터 + auto 전략 (MVP 이후 1차 확장)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-02
- **갱신일**: 2026-08-02 (**PR-B 세션 1/3 완료** — 읽기의 첫 소비자가 붙고 엣지 5가 해소됐다. 다음은 세션 2)

## 목표

키보드 합성만으로는 정확해질 수 없는 어휘를 AX 읽기로 해소한다: `AXSelectedTextRange`+캐럿 주변 창 읽기(`AXStringForRange` — `AXValue` 전체 읽기는 실측으로 금지됨)로 정확 오프셋을 계산하고 실행은 키보드로 하는 **혼용**이 축이다. 여기에 순수 AX 쓰기 어댑터, `auto` 전략 프로브, `per_element` 재정의가 얹힌다.

M1~M4는 종료됐다(MVP 1단계 완료, 2026-08-02). 구조·계약의 최종 상태는 architecture가, 결정 히스토리는 decisions가 SSOT다 — 이 문서는 **M5가 무엇을 해야 하는지**만 담는다.

**빌드 순서 원칙**: 읽기 먼저, 쓰기 나중 (keyboard-first와 같은 논리 — 읽기는 실패가 즉시 드러나 폴백이 안전하고, 쓰기는 비대칭적으로 위험하다). 사용자 가치도 혼용(PR-B·C)이 순수 AX 어댑터(PR-D)보다 먼저 나온다. AX 어댑터를 "쓰기 대체"로 설계하면 이 이득을 놓친다 — M3 인계 메모의 핵심 판단.

## 완료된 것

- **PR-A 사전 실측** (2026-08-02, 앱 6종 순회 프로브): 웜 읽기 분포(Notion `selectedRange` p50 7.1ms/max 16ms — 콜백 배치 기각 근거), `AXValue` 전체 읽기의 크기 비례 비용(100만자 3.5~5.3ms), 타임아웃 실효성(실패 반환 캡+2ms 바운드, 예외는 프로세스 최초 호출 1회 ~23ms), 콜드 웜업(재시도 2~3회/+10~23ms). Slack·VS Code는 포커스 요소 미노출(자연 폴백 경로).
- **PR-A 착수 결정 2건 기록**: [읽기 형태 — 게시 큐 위 lazy·창 프리미티브·무상태 폴백](../../decisions/references/20260802_dispatch-read-on-posting-queue.md), [AX 타임아웃 50ms 단일 상수 — 3ms 캡 supersede](../../decisions/references/20260802_ax-read-timeout-50ms-supersedes-3ms.md). architecture(strategy-dispatch·reentrancy-and-safety) 갱신 완료.
- **PR-A 구현 완료** (브랜치 `feat/m5-pr-a-ax-read-foundation`): `AXRead`(타임아웃·포커스 요소 조회 단독 소유), `FocusedText`·`FocusedTextReader`·`FocusedTextSnapshot`(액션별 lazy·1회 memo·실패도 memo), `DispatchContext.processID`(출처 = 리졸버 `observedProcessID`), `KeyboardAdapter(reader:)`·`execute(processID:)`, sink 배선. API 모양은 [결정 문서](../../decisions/references/20260802_focused-text-read-api-shape.md)로 확정. **동작 diff 0** — 앱 785 + 엔진 81 테스트 통과, 빌드 경고 0.
- **PR-B 세션 1/3 완료** (worktree `feat/m5-pr-b-hybrid-motion-edit`, 커밋 2개 + 문서): 읽기의 **첫 소비자**가 붙었고 [수용 엣지 5](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md)(빈 선택+오퍼레이터)가 해소됐다. 결정 2건 기록: [소비 형태](../../decisions/references/20260802_read-consumption-via-mapper-predicates.md), [0폭 포화 억제](../../decisions/references/20260802_empty-selection-edit-suppression.md). architecture `strategy-dispatch.md` 갱신 완료(과도기 표기 해제·스킵 4종·엣지 서술). 앱/엔진 테스트 전체 통과, 빌드 경고 0.

## 남은 것 (PR 단위 — 순서 = 의존 순서)

각 PR은 자기 worktree에서 작업한다. A → B → C는 선형 의존이고, D1 → D2도 선형이다. C와 D는 원칙적으로 병렬 가능하지만 어댑터 파일 충돌이 클 수 있어 순차를 기본으로 한다.

- [x] **PR-A — 읽기 기반 (리졸버 확장)** — [PR #35](https://github.com/pilyang/vim-action/pull/35) **머지 완료** (main `b206a87`). 상세는 위 "완료된 것".
- [ ] **PR-B — 혼용 1: 편집·모션 정확화** *(worktree `feat/m5-pr-b-hybrid-motion-edit`, base `b206a87`)*: PR-A의 읽기를 소비해 무상태 매퍼를 정확화. 어댑터 무상태는 유지(정확화 diff). **3세션 분할이며 PR 생성은 세션 3 이후다** — 세션마다 커밋만 하고 push·PR은 하지 않는다.
  - [x] **세션 1** — 소비 배선 + 공통 파생 질의 유틸 + 엣지 5(빈 선택+오퍼레이터). 상세는 위 "완료된 것".
  - [ ] **세션 2** — [경계 포화 나머지 4종](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md) + [소프트 랩 시각 줄](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md). 착수 지점은 아래 "진행 중 컨텍스트".
  - [ ] **세션 3** — `iw` 단어 경계, `cw`→`ce` 특례 정확화. 오프셋만큼 스트로크를 보내면 버스트가 되므로 실행 중단 래치·청크 원자 그룹 규칙과 묶인다.
- [ ] **PR-C1 — 혼용 2a: Visual 앵커 상태**: 어댑터가 처음으로 앵커·범위 상태를 든다(구조 변화 — PR-B와 분리하는 이유). [Visual 후진 전체](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md)(`Vk`·`vb`·`vh`)가 통째로 해소되고, `V`→`v` 전환·앵커 쪽 반올림도 가능해진다. 어댑터의 `linewise: Bool` 상자 재검토가 여기 속한다.
- [ ] **PR-C2 — 혼용 2b: paste wise·스크롤 정확화**: charwise/linewise `p` 경계와 paste wise 자체 — 레지스터·yank 경로의 wise 기억으로 해소. 스크롤 근사 줄 수 → `AXVisibleCharacterRange` 뷰포트 정확화. 비-QWERTY 정식 해소(문자→키코드 역조회 주입 — [레이아웃 가드 결정](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)의 이연 항목)도 여기.
- [ ] **PR-D1 — 순수 AX 쓰기 어댑터**: `AXSelectedTextRange` 직접 조작으로 `VimAction` 실행. `AXError` 반환이 **실패 폭주 자동 비활성화(`reportExecutionFailure`)의 첫 실호출자**가 된다 — 실패 보고 배선 포함.
- [ ] **PR-D2 — auto 프로브 + AX 거짓말 감지 + force-text**: 프로브 → key-mapping 폴백, 왕복 테스트 휴리스틱·번들 거부 목록, `key-mapping`→`force-text` 자동 폴백 존재 여부 결정. force-text 자체는 작다(걸러내기 우회 + 항상 TextArea 시퀀스). 라우팅할 AX 어댑터(D1)와 혼용 단계의 실기기 관측이 입력이라 뒤에 온다.
- [ ] **PR-E — 스키마 확장 + 마감**: `strategy`·`per_element` 필드 additive 확장(M4 로더가 미지 키 warn+무시라 전방 호환은 열려 있다). **캐시 충분성 최종 확정** — `per_element` 스키마 시점에 재심사하기로 예약됨 ([1차 확정](../../decisions/references/20260801_cache-only-callback-confirmed-sufficient.md)). 도그푸딩 마감.

## 진행 중 컨텍스트

- **PR-B 세션 2 착수 지점 (세션 1 인계)** — 코드 재탐색 없이 이어받을 수 있게:
  - **공통 유틸**: `VimAction/FocusedTextAnalysis.swift` = `extension FocusedText`. `caretOffsetInWindow: Int?`, `isAtDocumentStart/End: Bool`, `isAtLineStart/End: Bool` 다섯. 설계 의도 셋 — ① **증명 못 하면 `false`**(다섯 다 `false`가 "정확화 안 함 = 현행 시퀀스"라 보수적 방향이 균일하다), ② 오프셋은 **UTF-16**(`Character` 인덱싱은 이모지 창에서 개행을 오탐해 "잘못 정확화"라는 안전하지 않은 방향으로 틀린다), ③ `isAtDocumentEnd`는 `==` + "창이 문서 끝에 닿았다" 방증(`>=`는 `AXNumberOfCharacters`를 어긋나게 보고하는 앱에서 편집 키를 영구히 삼킨다). 테스트는 `VimActionTests/FocusedTextAnalysisTests.swift`이고, 문서+캐럿으로 `FocusedText`를 만드는 헬퍼 `focusedText(_:caret:length:)`가 거기 있다(다른 테스트 파일에서 쓰라고 internal이다).
  - **소비 형태**: `EditKeyMapper.consultsFocusedText(_:)`(이 범위가 읽기를 묻는가)와 `collapsesToNothing(op:range:text:)`(무엇을 증명했는가) 두 순수 함수. 어댑터는 `mapping`의 `.edit` 분기에서 전자를 보고 읽을지 정한다 — 범위 표가 어댑터로 복사되지 않는다. `keyStrokes`의 시그니처는 **아직 안 바뀌었다**. `cw` 리타깃은 `retargeted(_:for:)` 하나로 뽑혀 시퀀스와 판정이 같은 함수를 공유한다. 근거는 [결정 문서](../../decisions/references/20260802_read-consumption-via-mapper-predicates.md).
  - **세션 2가 할 일과 그때 바뀌는 것**: 엣지 1~4는 억제가 아니라 **시퀀스 재조립**이다(엣지 1 = `charRight`/`charLeft`가 **줄** 경계에서 개행을 집는 문제 — 0폭과 다른 규칙, 엣지 2 = 첫 줄 `dk`, 엣지 3 = 마지막 단어 `dw`의 선택 반전, 엣지 4 = 마지막 줄 `dgg`, 여기에 소프트 랩과 `^`). 그러려면 그때는 `keyStrokes`가 `text:`를 받아야 하고, `nil`이 "미지원"과 "정확화 결과" 두 뜻을 갖게 되므로 **`classify`에 세 번째 프로브**가 필요해진다. **프로브 순서가 계약이다**: 텍스트 프로브(`text: nil`로 재조회)가 `builtIn`보다 **앞**이어야 하고 `builtIn`은 **절대 `text`를 받으면 안 된다** — 둘 중 하나만 어겨도 포화가 미지원(`.unsupported`)으로 집계돼 스킵 분류가 무너진다. 그 자리에서 `.skipped` 로그의 사유를 어떻게 남길지도 함께 정해야 한다(`classify`는 `op`·`range`를 모른다).
  - **엣지 2·4는 `.linewiseMotion` 범위**라 `consultsFocusedText`를 먼저 넓혀야 하고, 넓히는 순간 `dd`·`dj`류에도 읽기 왕복이 붙는다(Notion 7ms).
- **실측 메모 (계속 유효)**: 정확화가 Notion에서는 키당 ~7ms를 산다(selectedRange 비용) — 액션별 스냅샷이 액션당 1회로 접어 주지만 **액션 수만큼은 곱해진다**. Slack·VS Code는 포커스 요소 미노출이라 혼용 정확화가 원리적으로 도달 불가(무상태 폴백 상시) — 도그푸딩 때 텍스트 포커스 상태로 재확인 필요(이번 실측은 자동 순회 한계로 두 앱의 텍스트 영역을 못 봤다).
- **읽기의 구조적 한계 (세션 2·3도 상속)**: `CGEvent.post`는 배달만 걸어 두고 돌아오므로 **`execute` 사이**에는 낡은 값을 읽을 수 있다(`p` 직후 빠른 `x`). 한 `execute` **안**에는 레이스가 없다 — 엔진이 한 `.replace`에서 모션→편집을 섞어 내지 않음을 확인했다. 수용 근거는 실패의 비대칭(잘못된 억제 = 키 한 타 유실 vs 미억제 = 파괴적 편집)이라, **재조립 쪽 정확화에는 이 논리가 그대로 적용되지 않는다** — 세션 2에서 다시 따져야 한다.

- **M3가 남긴 인계 메모 (핵심 판단)**: M3에서 수용한 엣지 **대부분이 쓰기가 아니라 읽기 문제다** — 정확 오프셋을 AX로 읽고 실행은 키보드로 하면 해소된다. 해소 대상은 위 PR-B·C1·C2에 배분돼 있다. 탭 들여쓰기 `^`·Notion 계열 충돌은 M4 프로파일이 우선 수단이다(M5 해소 대상 아님).

- **M6 (MVP 밖)**: 서명·공증 배포. [릴리스 금지 게이트는 해제됐다](../../decisions/references/20260801_release-block-gate-lifted.md) — 착수 가능하며, 시작할 때 별도 플랜으로 만든다.

## 관련 링크

- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [profiles-and-config.md](../../architecture/references/profiles-and-config.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [AX/Keyboard 전략 디스패치](../../decisions/references/20260712_ax-keyboard-strategy-dispatch.md), [Keyboard-first 빌드 순서](../../decisions/references/20260725_keyboard-first-mvp-build-order.md), [콜백 경량 불변식](../../decisions/references/20260725_callback-light-invariant.md)

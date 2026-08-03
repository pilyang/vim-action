# M5 — AX 어댑터 + auto 전략 (MVP 이후 1차 확장)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-02
- **갱신일**: 2026-08-03 (**PR-B 구현 완료 — PR 생성 대기**. 세션 3/3까지 끝났고 다음 단계는 push + PR 생성이다)

## 목표

키보드 합성만으로는 정확해질 수 없는 어휘를 AX 읽기로 해소한다: `AXSelectedTextRange`+캐럿 주변 창 읽기(`AXStringForRange` — `AXValue` 전체 읽기는 실측으로 금지됨)로 정확 오프셋을 계산하고 실행은 키보드로 하는 **혼용**이 축이다. 여기에 순수 AX 쓰기 어댑터, `auto` 전략 프로브, `per_element` 재정의가 얹힌다.

M1~M4는 종료됐다(MVP 1단계 완료, 2026-08-02). 구조·계약의 최종 상태는 architecture가, 결정 히스토리는 decisions가 SSOT다 — 이 문서는 **M5가 무엇을 해야 하는지**만 담는다.

**빌드 순서 원칙**: 읽기 먼저, 쓰기 나중 (keyboard-first와 같은 논리 — 읽기는 실패가 즉시 드러나 폴백이 안전하고, 쓰기는 비대칭적으로 위험하다). 사용자 가치도 혼용(PR-B·C)이 순수 AX 어댑터(PR-D)보다 먼저 나온다. AX 어댑터를 "쓰기 대체"로 설계하면 이 이득을 놓친다 — M3 인계 메모의 핵심 판단.

## 완료된 것

- **PR-A 사전 실측** (2026-08-02, 앱 6종 순회 프로브): 웜 읽기 분포(Notion `selectedRange` p50 7.1ms/max 16ms — 콜백 배치 기각 근거), `AXValue` 전체 읽기의 크기 비례 비용(100만자 3.5~5.3ms), 타임아웃 실효성(실패 반환 캡+2ms 바운드, 예외는 프로세스 최초 호출 1회 ~23ms), 콜드 웜업(재시도 2~3회/+10~23ms). Slack·VS Code는 포커스 요소 미노출(자연 폴백 경로).
- **PR-A 착수 결정 2건 기록**: [읽기 형태 — 게시 큐 위 lazy·창 프리미티브·무상태 폴백](../../decisions/references/20260802_dispatch-read-on-posting-queue.md), [AX 타임아웃 50ms 단일 상수 — 3ms 캡 supersede](../../decisions/references/20260802_ax-read-timeout-50ms-supersedes-3ms.md). architecture(strategy-dispatch·reentrancy-and-safety) 갱신 완료.
- **PR-A 구현 완료** (브랜치 `feat/m5-pr-a-ax-read-foundation`): `AXRead`(타임아웃·포커스 요소 조회 단독 소유), `FocusedText`·`FocusedTextReader`·`FocusedTextSnapshot`(액션별 lazy·1회 memo·실패도 memo), `DispatchContext.processID`(출처 = 리졸버 `observedProcessID`), `KeyboardAdapter(reader:)`·`execute(processID:)`, sink 배선. API 모양은 [결정 문서](../../decisions/references/20260802_focused-text-read-api-shape.md)로 확정. **동작 diff 0** — 앱 785 + 엔진 81 테스트 통과, 빌드 경고 0.
- **PR-B 세션 1/3 완료** (worktree `feat/m5-pr-b-hybrid-motion-edit`, 커밋 2개 + 문서): 읽기의 **첫 소비자**가 붙었고 수용 엣지 5(빈 선택+오퍼레이터)가 해소됐다. 결정 2건 기록: [소비 형태](../../decisions/references/20260802_read-consumption-via-mapper-predicates.md), [0폭 포화 억제](../../decisions/references/20260802_empty-selection-edit-suppression.md).
- **PR-B 세션 2/3 완료** (커밋 2개 + 문서): **경계 포화 수용 엣지 5종 전부 해소** — 억제에서 시퀀스 재조립으로 넘어갔다. `EditKeyMapper.keyStrokes`가 `text:`를 받고 어댑터의 편집 분류가 3-프로브가 됐다. 결정 5건 기록: [재조립 원칙(레이스)](../../decisions/references/20260803_refinement-branches-not-stroke-counts.md), [시그니처·3-프로브](../../decisions/references/20260803_edit-keystrokes-takes-focused-text.md), [정확화 표(엣지 2·3·4·`^`)](../../decisions/references/20260803_boundary-saturation-refinement-table.md), [줄 끝 Vim 커서 모델(엣지 1)](../../decisions/references/20260803_line-end-charwise-vim-cursor-model.md), [소프트 랩 미해소 사유](../../decisions/references/20260803_soft-wrap-linewise-not-resolved-by-window-read.md). architecture `strategy-dispatch.md` 갱신 완료. 앱 테스트 1,043건 + 엔진 81건 통과, **빌드 경고 0**(세션 1이 남긴 격리 경고 4건도 함께 해소).
- **PR-B 세션 3/3 완료** (커밋 2개 + 문서): **`iw`·`cw`→`ce` 정확화** — 단어 런 질의 3종(`caretRunIsSingleCharacter`·`caretIsAtRunEnd`·`runClassBeforeLineEnd`)을 세우고 1자 런·런 끝·줄 끝을 상수 1타로 재조립했다. 결정 3건 기록: [단어 질의는 로컬 술어(오프셋 없음)](../../decisions/references/20260803_word-run-local-predicates-no-offsets.md), [상수 1타 재조립 — 원칙 예외 없이 유지](../../decisions/references/20260803_constant-stroke-word-refinement.md), [줄 끝 커서 모델을 단어 어휘로 완화](../../decisions/references/20260803_line-end-cursor-model-for-word-objects.md). architecture 갱신 완료. 앱 테스트 **1,081건** + 엔진 81건 통과, 빌드 경고 0.

## 남은 것 (PR 단위 — 순서 = 의존 순서)

각 PR은 자기 worktree에서 작업한다. A → B → C는 선형 의존이고, D1 → D2도 선형이다. C와 D는 원칙적으로 병렬 가능하지만 어댑터 파일 충돌이 클 수 있어 순차를 기본으로 한다.

- [x] **PR-A — 읽기 기반 (리졸버 확장)** — [PR #35](https://github.com/pilyang/vim-action/pull/35) **머지 완료** (main `b206a87`). 상세는 위 "완료된 것".
- [ ] **PR-B — 혼용 1: 편집·모션 정확화** *(worktree `feat/m5-pr-b-hybrid-motion-edit`, base `b206a87`)*: **구현 완료 — PR 생성 대기.** 3세션 전부 끝났고 남은 것은 push + PR 생성뿐이다(아래 "진행 중 컨텍스트"의 PR 준비 메모).
  - [x] **세션 1** — 소비 배선 + 공통 파생 질의 유틸 + 엣지 5(빈 선택+오퍼레이터). 상세는 위 "완료된 것".
  - [x] **세션 2** — 경계 포화 나머지 4종 + `^`. [소프트 랩 시각 줄](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md)은 **해소하지 않고 사유를 결정으로 남겼다**(창 읽기로 불가 — 단락 바인딩 실측이 재개 조건). 상세는 위 "완료된 것".
  - [x] **세션 3** — `iw` 단어 경계, `cw`→`ce` 특례 정확화. 상세는 위 "완료된 것".
- [ ] **PR-C1 — 혼용 2a: Visual 앵커 상태**: 어댑터가 처음으로 앵커·범위 상태를 든다(구조 변화 — PR-B와 분리하는 이유). [Visual 후진 전체](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md)(`Vk`·`vb`·`vh`)가 통째로 해소되고, `V`→`v` 전환·앵커 쪽 반올림도 가능해진다. 어댑터의 `linewise: Bool` 상자 재검토가 여기 속한다.
- [ ] **PR-C2 — 혼용 2b: paste wise·스크롤 정확화**: charwise/linewise `p` 경계와 paste wise 자체 — 레지스터·yank 경로의 wise 기억으로 해소. 스크롤 근사 줄 수 → `AXVisibleCharacterRange` 뷰포트 정확화. 비-QWERTY 정식 해소(문자→키코드 역조회 주입 — [레이아웃 가드 결정](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)의 이연 항목)도 여기.
- [ ] **PR-D1 — 순수 AX 쓰기 어댑터**: `AXSelectedTextRange` 직접 조작으로 `VimAction` 실행. `AXError` 반환이 **실패 폭주 자동 비활성화(`reportExecutionFailure`)의 첫 실호출자**가 된다 — 실패 보고 배선 포함.
- [ ] **PR-D2 — auto 프로브 + AX 거짓말 감지 + force-text**: 프로브 → key-mapping 폴백, 왕복 테스트 휴리스틱·번들 거부 목록, `key-mapping`→`force-text` 자동 폴백 존재 여부 결정. force-text 자체는 작다(걸러내기 우회 + 항상 TextArea 시퀀스). 라우팅할 AX 어댑터(D1)와 혼용 단계의 실기기 관측이 입력이라 뒤에 온다.
- [ ] **PR-E — 스키마 확장 + 마감**: `strategy`·`per_element` 필드 additive 확장(M4 로더가 미지 키 warn+무시라 전방 호환은 열려 있다). **캐시 충분성 최종 확정** — `per_element` 스키마 시점에 재심사하기로 예약됨 ([1차 확정](../../decisions/references/20260801_cache-only-callback-confirmed-sufficient.md)). 도그푸딩 마감.

## 진행 중 컨텍스트

- **PR-B PR 생성 준비 메모 (세션 3 인계)** — 다음 단계는 push + PR 생성이다. 코드 작업은 없다.
  - **브랜치 커밋 구성** (base `b206a87`, 8커밋 — 세션마다 FEAT 2 + docs 1):
    - 세션 1: `38190f1` 파생 질의 유틸 / `ac710f3` AX 읽기 첫 소비(엣지 5) / `e2208f8` docs
    - 세션 2: `1876811` 줄·단어 경계 질의 6종 / `3983333` 경계 포화 엣지 전 항목 해소 / `e901464` docs
    - 세션 3: `a2ce4b7` 단어 런 질의 3종 / `afc462b` `iw`·`cw` 정확화 / (docs 커밋)
  - **PR 본문 핵심 요약**: PR-A의 읽기에 **첫 소비자**가 붙어, 어댑터 무상태를 유지한 채(앵커·범위 상태는 PR-C1) 무상태 시퀀스를 정확화한다. 해소된 수용 엣지 — 경계 포화 5종(줄 끝 `x`, 첫 줄 `dk`, 마지막 단어 `dw`, 마지막 줄 `dgg`, 빈 선택+오퍼레이터), `^`의 0폭, `iw`의 공백 1칸·1자 구두점·줄 끝, `cw`의 런 끝·줄 끝. **남긴 것** — 소프트 랩 시각 줄 linewise(창 읽기로 원리적 불가, [사유 문서](../../decisions/references/20260803_soft-wrap-linewise-not-resolved-by-window-read.md), 단락 바인딩 실측이 재개 조건), 2자 이상의 공백·구두점 런(오프셋 비례 스트로크가 되어 기각), Notion `Shift-Cmd-↑/↓` 충돌(M4 프로파일 몫).
  - **리뷰어가 볼 결정 문서** (설계 축 순): [재조립 원칙 — 읽기는 분기의 근거](../../decisions/references/20260803_refinement-branches-not-stroke-counts.md) → [`keyStrokes(text:)`·3-프로브](../../decisions/references/20260803_edit-keystrokes-takes-focused-text.md) → [경계 포화 정확화 표](../../decisions/references/20260803_boundary-saturation-refinement-table.md) → [줄 끝 Vim 커서 모델](../../decisions/references/20260803_line-end-charwise-vim-cursor-model.md) + [단어 어휘로의 완화](../../decisions/references/20260803_line-end-cursor-model-for-word-objects.md) → [단어 런 로컬 술어](../../decisions/references/20260803_word-run-local-predicates-no-offsets.md) → [상수 1타 재조립](../../decisions/references/20260803_constant-stroke-word-refinement.md). 세션 1의 [소비 형태](../../decisions/references/20260802_read-consumption-via-mapper-predicates.md)·[0폭 억제](../../decisions/references/20260802_empty-selection-edit-suppression.md)는 부분 supersede된 상태로 읽어야 한다.
  - **리뷰에서 깨지기 쉬운 계약 3가지**: ① `classifyEdit`의 프로브 **순서**(text 포함 → 텍스트 프로브 → builtIn, builtIn은 text 미수신) — 하나만 어긋나면 정확화가 `.unsupported`로 집계돼 게이트 심사가 무너진다. ② `Refinement`의 **`.unproven`이 기본값**이라는 것 — 조용한 억제·조용한 재조립 방지. ③ `retargeted(_:for:)`가 시퀀스와 판정에 **같은 답**을 주고 리타깃 여부까지 함께 돌려준다는 것 — `cw`와 진짜 `ce`·`de`가 줄 끝에서 갈린다.
  - **검증 상태**: 앱 1,081건 + 엔진 81건 통과, 앱 빌드 경고 0. 테스트는 실기기 AX·`~/.config`·개발자 클립보드 비의존(읽기는 `focusedText(_:caret:length:)` 헬퍼 주입).
- **실측 메모 (계속 유효)**: 정확화가 Notion에서는 키당 ~7ms를 산다(selectedRange 비용) — 액션별 스냅샷이 액션당 1회로 접어 주지만 **액션 수만큼은 곱해진다**. Slack·VS Code는 포커스 요소 미노출이라 혼용 정확화가 원리적으로 도달 불가(무상태 폴백 상시) — 도그푸딩 때 텍스트 포커스 상태로 재확인 필요(이번 실측은 자동 순회 한계로 두 앱의 텍스트 영역을 못 봤다).
- **읽기의 구조적 한계 (PR-C 이후도 상속)**: `CGEvent.post`는 배달만 걸어 두고 돌아오므로 **`execute` 사이**에는 낡은 값을 읽을 수 있다(`p` 직후 빠른 `x`). 한 `execute` **안**에는 레이스가 없다 — 엔진이 한 `.replace`에서 모션→편집을 섞어 내지 않음을 확인했다. 세션 2가 이 한계에 대한 재조립 쪽 답(원칙 + 엣지 1의 명시 예외)을 세웠고, 세션 3의 상수 1타는 그 원칙 안에서 오히려 최악을 **줄인다**(현행 3타는 이웃 단어 통째, 재조립은 1자).
- **도그푸딩 시 바뀐 동작** (버그로 오인 금지):
  - 세션 1·2: 문서 끝 `x`가 이제 **마지막 글자를 지운다**(세션 1의 "안 먹는 것이 의도" 메모는 무효), 첫 줄 `dk`와 첫 비공백 위 `d^`는 **아무 일도 하지 않는다**(Vim과 같다).
  - 세션 3: 공백 1칸 위의 `diw`가 **그 공백만** 지운다(다음 단어가 아니다), 1자 구두점(`.`·`,`) 위의 `diw`가 **그 구두점만** 지운다, 줄 끝·문서 끝의 `diw`가 **직전 단어**를 지운다(다음 줄의 첫 단어가 아니다), 단어의 마지막 글자 위·줄 끝의 `cw`가 **그 한 글자만** 바꾼다(문서 끝 `cw`도 이제 무동작이 아니다 — 남는 무효는 빈 문서뿐).
  - 다만 위 전부 **읽기 성공 경로 한정**이다. Slack·VS Code는 포커스 요소 미노출이라 현행 3타 그대로여야 한다 — 그것이 폴백 계약의 실사용 확인이다.

- **M3가 남긴 인계 메모 (핵심 판단)**: M3에서 수용한 엣지 **대부분이 쓰기가 아니라 읽기 문제다** — 정확 오프셋을 AX로 읽고 실행은 키보드로 하면 해소된다. 해소 대상은 위 PR-B·C1·C2에 배분돼 있다. 탭 들여쓰기 `^`·Notion 계열 충돌은 M4 프로파일이 우선 수단이다(M5 해소 대상 아님).

- **M6 (MVP 밖)**: 서명·공증 배포. [릴리스 금지 게이트는 해제됐다](../../decisions/references/20260801_release-block-gate-lifted.md) — 착수 가능하며, 시작할 때 별도 플랜으로 만든다.

## 관련 링크

- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [profiles-and-config.md](../../architecture/references/profiles-and-config.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [AX/Keyboard 전략 디스패치](../../decisions/references/20260712_ax-keyboard-strategy-dispatch.md), [Keyboard-first 빌드 순서](../../decisions/references/20260725_keyboard-first-mvp-build-order.md), [콜백 경량 불변식](../../decisions/references/20260725_callback-light-invariant.md)

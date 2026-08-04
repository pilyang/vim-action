# M5 — AX 어댑터 + auto 전략 (MVP 이후 1차 확장)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-02
- **갱신일**: 2026-08-04 (**PR-C1 설계 세션 완료** — worktree `feat/m5-pr-c1-visual-anchor-state`, 결정 5건 기록. 다음은 구현 세션)

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
- **PR-C1 설계 세션 완료** (2026-08-04, worktree `feat/m5-pr-c1-visual-anchor-state`, 코드 무변경 — 문서만): 설계 결정 5건 기록 — [키보드 재앵커](../../decisions/references/20260804_visual-backward-keyboard-reanchor.md)(side 모델, 후진형은 원점 이동 없음, 크로싱은 수용 엣지, AX 쓰기 기각), [앵커 상태는 게시 큐 협력자](../../decisions/references/20260804_visual-anchor-state-collaborator.md)(PasteWiseResolver 동형, 수립은 진입 게시 직전 읽기), [무효화는 읽기 자가 검증](../../decisions/references/20260804_visual-anchor-read-self-validation.md)(앵커 쪽 끝+pid, 전용 신호 없음), [V→v 조건부 지원](../../decisions/references/20260804_visual-switch-charwise-conditional.md), [V 세션 charwise 모션 스킵](../../decisions/references/20260804_visual-linewise-motion-range-noop.md)(`linewise: Bool` 상자 재검토 종결). architecture(strategy-dispatch·mode-engine) 갱신 완료. 옛 Visual 결정 3건 부분 supersede 마킹.
- **PR-B 세션 3/3 완료** (커밋 2개 + 문서): **`iw`·`cw`→`ce` 정확화** — 단어 런 질의 3종(`caretRunIsSingleCharacter`·`caretIsAtRunEnd`·`runClassBeforeLineEnd`)을 세우고 1자 런·런 끝·줄 끝을 상수 1타로 재조립했다. 결정 3건 기록: [단어 질의는 로컬 술어(오프셋 없음)](../../decisions/references/20260803_word-run-local-predicates-no-offsets.md), [상수 1타 재조립 — 원칙 예외 없이 유지](../../decisions/references/20260803_constant-stroke-word-refinement.md), [줄 끝 커서 모델을 단어 어휘로 완화](../../decisions/references/20260803_line-end-cursor-model-for-word-objects.md). architecture 갱신 완료. 앱 테스트 **1,081건** + 엔진 81건 통과, 빌드 경고 0.

## 남은 것 (PR 단위 — 순서 = 의존 순서)

각 PR은 자기 worktree에서 작업한다. A → B → C는 선형 의존이고, D1 → D2도 선형이다. C와 D는 원칙적으로 병렬 가능하지만 어댑터 파일 충돌이 클 수 있어 순차를 기본으로 한다.

- [x] **PR-A — 읽기 기반 (리졸버 확장)** — [PR #35](https://github.com/pilyang/vim-action/pull/35) **머지 완료** (main `b206a87`). 상세는 위 "완료된 것".
- [x] **PR-B — 혼용 1: 편집·모션 정확화** — [PR #36](https://github.com/pilyang/vim-action/pull/36) **머지 완료** (main `69a81a6`, 3세션 + 도그푸딩). 상세는 위 "완료된 것".
- [ ] **PR-C1 — 혼용 2a: Visual 앵커 상태**: 어댑터가 처음으로 앵커·범위 상태를 든다(구조 변화 — PR-B와 분리하는 이유). [Visual 후진 전체](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md)(`Vk`·`vb`·`vh`)가 통째로 해소되고, `V`→`v` 전환·앵커 쪽 반올림도 가능해진다. 어댑터의 `linewise: Bool` 상자 재검토가 여기 속한다.
- [ ] **PR-C2 — 혼용 2b: paste wise·스크롤 정확화**: charwise/linewise `p` 경계와 paste wise 자체 — 레지스터·yank 경로의 wise 기억으로 해소. 스크롤 근사 줄 수 → `AXVisibleCharacterRange` 뷰포트 정확화. 비-QWERTY 정식 해소(문자→키코드 역조회 주입 — [레이아웃 가드 결정](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)의 이연 항목)도 여기.
- [ ] **PR-D1 — 순수 AX 쓰기 어댑터**: `AXSelectedTextRange` 직접 조작으로 `VimAction` 실행. `AXError` 반환이 **실패 폭주 자동 비활성화(`reportExecutionFailure`)의 첫 실호출자**가 된다 — 실패 보고 배선 포함.
- [ ] **PR-D2 — auto 프로브 + AX 거짓말 감지 + force-text**: 프로브 → key-mapping 폴백, 왕복 테스트 휴리스틱·번들 거부 목록, `key-mapping`→`force-text` 자동 폴백 존재 여부 결정. force-text 자체는 작다(걸러내기 우회 + 항상 TextArea 시퀀스). 라우팅할 AX 어댑터(D1)와 혼용 단계의 실기기 관측이 입력이라 뒤에 온다.
- [ ] **PR-E — 스키마 확장 + 마감**: `strategy`·`per_element` 필드 additive 확장(M4 로더가 미지 키 warn+무시라 전방 호환은 열려 있다). **캐시 충분성 최종 확정** — `per_element` 스키마 시점에 재심사하기로 예약됨 ([1차 확정](../../decisions/references/20260801_cache-only-callback-confirmed-sufficient.md)). 도그푸딩 마감.

## 진행 중 컨텍스트

- **PR-C1 구현 세션 착수 지점 (설계 세션 인계)** — worktree `feat/m5-pr-c1-visual-anchor-state`에서 이어간다. 설계는 위 결정 5건으로 확정됐고 **코드는 아직 무변경**이다.
  - **첫 구현 단위**: 앵커 상태 협력자 타입 + `beginSelection` 게시 직전 수립 + 자가 검증 골격 + **최소 소비자 하나(`vh` 재앵커)**를 끝까지 뚫어 설계를 검증한다. seam은 전부 선례 그대로(주입 협력자·`FocusedTextReader` 골든 주입).
  - **구현 순서 제안**: ① 협력자 타입·수립·폐기 ② Visual 분기 읽기 배선(세션 술어) + 자가 검증 ③ `vh` 재앵커 ④ `vb`·`Vk`·`Vgg` 후진 전체 ⑤ `V` 세션 charwise 모션 스킵 ⑥ `v`→`V` 앵커 반올림 ⑦ `V`→`v` 조건부. ①~③이 세션 하나 분량, ④~⑦이 다음 세션.
  - **매퍼 시그니처 주의**: Visual 매퍼의 `nil`이 "미지원"과 "스킵" 두 뜻을 갖게 되므로 편집의 `classifyEdit` 선례(프로브 순서를 구조로 강제)를 참고해 분류가 어긋나지 않게 한다 — `.skipped` 분류(V 세션 charwise 모션·검증 실패)와 `.unsupported`가 섞이면 게이트 심사가 틀린다.
  - **상속되는 계약**: "지원 ⟹ 빈 시퀀스 아님"(스킵은 분류로) / 읽기는 액션당 1회 lazy·실패도 memo / 읽기·검증 실패 = 현행 무상태 시퀀스 폴백(Slack·VS Code 상시) / 재조립은 위치 상대적이거나 현행의 부분집합이거나 상수.
  - **원자 그룹 재확인**: 재앵커 접두(`←,→` 등)와 재확장은 한 액션의 시퀀스라 기존 규칙("액션 1개의 전체 시퀀스는 원자")이 그대로 덮는다 — 새 원자 그룹 규칙은 필요 없어 보이나 구현에서 재확인.
  - **V→v 열 거리 상한**: 극단 열에서 스트로크 폭주 여부를 구현에서 실측해 클램프를 정한다(결정 문서에 유보 항목으로 명시됨).

- **실측 메모 (계속 유효)**: 정확화가 Notion에서는 키당 ~7ms를 산다(selectedRange 비용) — 액션별 스냅샷이 액션당 1회로 접어 주지만 **액션 수만큼은 곱해진다**. Slack·VS Code는 포커스 요소 미노출이라 혼용 정확화가 원리적으로 도달 불가(무상태 폴백 상시) — **세션 3 도그푸딩에서 Slack 컴포저로 확인 완료**(줄 끝 `x`가 여전히 줄을 병합 = 정확화 미적용). M5 안에서는 안 풀리며 PR-D2의 `auto` 프로브도 같은 이유로 Keyboard로 라우팅한다. Slack 쪽 개선 수단은 M4 프로파일뿐이다.
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

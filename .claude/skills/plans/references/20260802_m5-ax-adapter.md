# M5 — AX 어댑터 + auto 전략 (MVP 이후 1차 확장)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-02
- **갱신일**: 2026-08-04 (**PR-C1 구현 세션 1 완료** — 구현 순서 ①~③: 앵커 협력자·세션 술어 읽기·자가 검증·`vh` 재앵커. 다음은 구현 세션 2 — ④~⑦)

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
- **PR-C1 구현 세션 1 완료** (2026-08-04, 구현 순서 ①~③): 어댑터가 처음으로 상태를 든다 — `VisualAnchor.swift` 신규(`VisualAnchorState`·`Update`·`Context` + `VisualAnchorTracker`, `PasteWiseResolver` 동형 주입·게시 큐 단독 소유), `VisualKeyMapper.keyStrokes(...anchor:)` 정확화 진입점(`.none` = 무상태와 바이트 동일을 위임으로 보장, 시퀀스와 `VisualAnchorUpdate`를 함께 반환), 어댑터 Visual 분기의 세션 술어 읽기 + `classifyVisual` 3-프로브(`classifyEdit` 동형) + `.groups` 확정 후 상태 적용, **`vh` 재앵커 끝까지 관통**(진입형만 `←,→`+`Shift-←×2`·side 반전, 길이≥2 축소·후진형은 1타). `v`·`V` 수립 규칙 모두 포함(증명 실패 = 수립 안 함 + 옛 상태 폐기). 앱 테스트 전체 + 엔진 81건 통과, 앱 빌드 경고 0. architecture `strategy-dispatch.md` 갱신 완료. **구현 수준 보강 5건**(결정 문언 밖, 방향은 전부 보수 — 뒤 3건은 3-에이전트 리뷰가 잡은 실이슈): ⓐ 자가 검증에 "선택이 비어 있지 않음" 추가(빈 선택 = 세션 사망 증거) ⓑ 읽기 실패는 폐기 트리거가 아님(그 액션만 폴백) ⓒ **드롭 경로(중단·CGEvent 실패)는 상태 폐기** — 갱신이 게시 전이라, 게시 안 된 재앵커 `.set`은 진입형 선택과 우연히 일치해 검증을 거짓 통과하는 유일한 자리였다 ⓓ **줄 시작(열 0) 앵커의 `h`는 재앵커 봉쇄** — Vim은 no-op인데 재앵커는 개행을 선택하는 파괴적 회귀였다(편집 `charLeftRefinement`와 같은 규칙) ⓔ **읽기 실패 중의 linewise 확장도 줄 거리를 미상으로 좁힘**(무상태 확장이 게시되므로).
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

- **PR-C1 구현 세션 2 착수 지점 (세션 1 인계)** — worktree `feat/m5-pr-c1-visual-anchor-state`에서 이어간다. ①~③은 완료됐고(위 "완료된 것") 남은 것은 **④ `vb`·`Vk`·`Vgg` 후진 전체 ⑤ `V` 세션 charwise 모션 스킵 ⑥ `v`→`V` 앵커 반올림 ⑦ `V`→`v` 조건부** + 도그푸딩 + PR 생성이다.
  - **얹는 자리가 이미 있다**: 정확화 분기는 전부 `VisualKeyMapper.refined(for:state:text:profile:)` 한 함수에 들어간다 — `vh`가 그 최소 소비자다. 단 **⑤를 얹으려면 `refined`의 반환을 3상태로 바꿔야 한다**(리뷰 확인): 지금은 `VisualStrokes?` 2상태라 `nil`이 무조건 무상태 위임이고, "정확화가 무게시를 증명" 신호를 낼 통로가 없어 `classifyVisual` 프로브 ①이 구조적으로 도달 불가다 — `EditKeyMapper.Refinement`(`.invalid`/`.selection`/`.unproven`)와 같은 3상태 전환이 그 시점의 최소 변경이다. 프로브 ①·`.skipped` 자체 로그 배선은 이미 있다. ⑥은 폴백 `v`→`V`의 `.discard`를 재앵커+`.set`으로 교체, ⑦은 `nil` 유지 조건(원래 캐럿·줄 거리 미상)을 그대로 두고 아는 경우만 재선택을 추가한다.
  - **linewise 확장의 줄 거리 추적**: 폴백 확장이 `focusLineDistance`를 미상(nil)으로 좁혀 두므로, 세션 2는 정확 `j`/`k` 경로에서 ±1을 넣도록 **좁히기만** 하면 된다(낡은 known이 남는 실패 모드는 원천 봉쇄됨).
  - **`vb`는 PR-B 단어 런 술어 재사용**: 캐럿이 단어 시작이면 `Shift-Opt-←` ×2 (결정 문서 표). `Vk` 재앵커(`←,↓`)의 `pinnedEnd`는 앵커 줄 끝 다음 — 상태 필드가 이를 위해 이미 있다.
  - **V→v 열 거리 상한**: 극단 열에서 스트로크 폭주 여부를 구현에서 실측해 클램프를 정한다(결정 문서에 유보 항목으로 명시됨).
  - **상속되는 계약**(변화 없음): "지원 ⟹ 빈 시퀀스 아님" / 읽기는 액션당 1회 lazy·실패도 memo / 읽기·검증 실패 = 현행 무상태 폴백(Slack·VS Code 상시) / 재조립은 위치 상대·부분집합·상수 / 상태 갱신은 `.groups` 확정 뒤(`recordLinewiseEdit` 선례). 원자 그룹은 재확인 완료 — 액션 1건 = 그룹 1개라 재앵커 접두가 갈라질 수 없다.
  - **도그푸딩 오인 금지 (세션 1 반영)**: 읽기 성공 앱에서 `vh`(진입 직후 포함)가 이제 **커서 왼쪽을 잡아야 정상**이다 — 단 **열 0에서는 종전처럼 선택이 접힌다**(Vim no-op 방향의 봉쇄, 재앵커하면 개행을 잡는 회귀라 의도). `vb`·`Vk` 빈 선택·크로싱은 아직 종전대로. 빠른 `v l h` 연타에서 낡은 읽기가 진입형으로 보이면 한 글자 넓게 잡을 수 있다(비-강등 유일 실패 모드 — 세션 1이 수용, 관찰 대상).

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

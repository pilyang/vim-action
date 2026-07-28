---
name: decisions
description: VimAction 프로젝트의 기술 결정 히스토리 SSOT — 아키텍처, 툴링, 라이브러리, 빌드/배포, 테스트 전략 등 모든 기술 결정의 기록과 조회. Use this skill whenever a technical decision is made, changed, or reversed ("~하기로 했어", "~로 결정했어", "이 결정 기록해줘", "X 대신 Y로 바꾸자"), and whenever someone asks about a past decision's history or rationale ("왜 X로 결정했었지?", "예전에 어떻게 하기로 했더라?", "이거 언제 바뀐 거야?"). Also use BEFORE overturning or revisiting any existing decision, even if the user doesn't say "decision" explicitly.
---

# VimAction 기술 결정 기록 (Decision Log)

이 스킬은 VimAction의 **기술 결정 히스토리의 단일 소스(SSOT)** 입니다. 결정 문서는 전부 `references/`에 있고, 이 파일은 규칙과 인덱스만 관리합니다.

역할 분담: 이 스킬은 "**언제, 왜** 그렇게 결정했는가"(히스토리)를 담당하고, 결정이 반영된 "**지금** 구조가 어떤가"(최종 상태)는 `architecture` 스킬이 담당합니다. 결정 기록의 진입점은 항상 이 스킬입니다.

## 워크플로우 1 — 결정 기록

새 기술 결정이 생기거나 기존 결정이 바뀌면:

1. **항상 신규 문서를 추가**합니다: `references/` 아래 `yyyymmdd_<kebab-case-title>.md` (`_template.md` 복사). 날짜는 **결정일**이며 반드시 파일명에 포함 — 기록 시점의 날짜는 `date +%Y%m%d`로 확인합니다. 기존 결정 문서는 수정하거나 재작성하지 않습니다. 문서 하나가 결정 하나의 불변 스냅샷이어야, 나중에 "그때 왜 그랬는지"를 있는 그대로 신뢰할 수 있습니다.
   - **문서 하나 = 결정 하나.** 큰 설계 안에 독립적으로 뒤집힐 수 있는 결정이 여러 개 섞여 있으면 문서를 나눕니다 (예: "전략 디스패치 구조"와 "AX 감지 타임아웃 값"은 별도 문서). 이렇게 해야 나중에 그 결정 하나만 supersede할 수 있고, 나머지 유효한 결정이 함께 폐기되지 않습니다.
2. **기존 결정을 뒤집는 경우** (supersede):
   - 새 문서의 `Supersedes` 섹션에 옛 문서를 명시합니다.
   - 옛 문서에는 **맨 위에 한 줄만** 추가합니다: `> Superseded by [yyyymmdd_새문서.md](yyyymmdd_새문서.md)` — 본문은 그대로 둡니다. 파일을 직접 연 사람도 낡은 결정임을 즉시 알 수 있게 하기 위한 유일한 허용 수정입니다.
   - 옛 문서가 **뒤집힌 결정만 담고 있다면** (다른 유효한 컨텍스트가 없다면) 아래 인덱스 테이블에서 **제거**합니다.
   - 옛 문서에 아직 유효한 다른 결정·컨텍스트가 섞여 있어 제거 여부가 **애매하다면, 임의로 판단하지 말고 사용자에게 확인**합니다 (마킹·인덱스 제거를 보류하고 상황을 설명한 뒤 질문). 잘못 제거하면 유효한 결정이 컨텍스트에서 사라지고, 잘못 남기면 낡은 값이 계속 주입됩니다 — 문서 하나 = 결정 하나 원칙을 지켰다면 이 애매함 자체가 드뭅니다.
3. **인덱스 테이블을 반드시 갱신**합니다. 인덱스에 없는 문서는 다음 작업자의 컨텍스트에 주입되지 않습니다 — 이것이 폐기된 결정이 새 작업을 오염시키지 않게 하는 메커니즘입니다. 반대로, 인덱스를 빼먹으면 유효한 결정도 없는 것이 됩니다.
4. **구조·아키텍처에 영향이 있는 결정이면, 같은 플로우에서 `architecture` 스킬의 해당 reference(최종 상태)도 갱신**합니다. 결정 문서는 "왜 바뀌었는가"를, architecture reference는 "바뀐 결과가 무엇인가"를 담습니다. 여기서 갱신을 빼먹으면 두 스킬이 서로 다른 구조를 말하게 됩니다.

기록하지 않는 것: 사소하거나 코드만 봐도 자명한 선택. 결정 문서의 가치는 코드에서 역추적할 수 없는 맥락(근거, 기각된 대안)에 있습니다.

## 워크플로우 2 — 결정 조회

과거 결정의 경위·근거를 물으면 아래 인덱스에서 관련 항목을 찾아 **해당 문서만** 읽습니다. 전부 읽지 마세요. 인덱스에 없는(폐기된) 문서는 "그때 왜 그렇게 했다가 바뀌었는지" 같은 히스토리 조사가 목적일 때만 `references/` 디렉토리에서 직접 찾아 읽습니다.

## Decision Index

| Date | Title | Short Description | Reference |
|---|---|---|---|
| 2026-07-12 | 단일 이벤트 탭 파이프라인 | 키 입력 진입점을 단일 CGEventTap으로 고정, 해석(엔진)과 실행(어댑터) 분리 | [20260712_single-event-tap-pipeline.md](references/20260712_single-event-tap-pipeline.md) |
| 2026-07-12 | 순수 Swift 모드 엔진 | 모드 엔진을 macOS 의존성 없는 별도 SPM 타깃으로 | [20260712_pure-swift-mode-engine.md](references/20260712_pure-swift-mode-engine.md) |
| 2026-07-12 | AX/Keyboard 전략 디스패치 | 앱별 프로파일 + AX 자동 감지로 전략 선택, force-text는 명시 선택 전용 | [20260712_ax-keyboard-strategy-dispatch.md](references/20260712_ax-keyboard-strategy-dispatch.md) |
| 2026-07-12 | AX 감지 하드 타임아웃 3ms | 자동 감지 AX 탐지에 3ms 하드 캡, 타임아웃 시 key-mapping 폴백 | [20260712_ax-probe-hard-timeout-3ms.md](references/20260712_ax-probe-hard-timeout-3ms.md) |
| 2026-07-12 | 합성 이벤트 마커와 안전장치 | userData 마커 + 단일 ActionExecutor로 무한 루프 방지, 안전장치는 별도 탭 | [20260712_synthetic-event-marker-and-failsafe.md](references/20260712_synthetic-event-marker-and-failsafe.md) |
| 2026-07-12 | YAML 3계층 설정 | Yams 기반 YAML, 번들 기본값→사용자→앱별 3계층, 파일 감시 자동 리로드 | [20260712_yaml-three-layer-config.md](references/20260712_yaml-three-layer-config.md) |
| 2026-07-12 | 엔진 테스트는 Swift Testing | 픽스처 파라미터라이즈드 테스트에 적합, UI 테스트 타깃은 XCTest 유지 | [20260712_swift-testing-for-engine-tests.md](references/20260712_swift-testing-for-engine-tests.md) |
| 2026-07-12 | 단일 코어 SPM 패키지 | 순수 Swift 모듈은 VimActionCore 패키지의 다중 타깃으로, 개별 패키지 분리 안 함 | [20260712_single-core-spm-package.md](references/20260712_single-core-spm-package.md) |
| 2026-07-12 | Key 표현·픽스처 포맷 | Key는 base+modifiers 구조체(shift는 문자에 흡수), 픽스처는 Swift 코드 테이블 | [20260712_key-representation-and-fixture-format.md](references/20260712_key-representation-and-fixture-format.md) |
| 2026-07-12 | GitHub Actions CI 도입 | macos-26 러너 병렬 2잡(엔진 swift test + 앱 xcodebuild), Xcode 26.6 고정, 사이닝 off | [20260712_github-actions-ci.md](references/20260712_github-actions-ci.md) |
| 2026-07-12 | pending 무효 시퀀스 no-op | 멀티키 pending(g 등) 후 무효 키는 둘 다 버림, 타임아웃 없음 (Vim 동일) | [20260712_pending-invalid-sequence-noop.md](references/20260712_pending-invalid-sequence-noop.md) |
| 2026-07-12 | 미매핑 modifier 조합 passthrough | Normal 모드에서 매핑 없는 Cmd/Ctrl/Option 조합은 통과 — 시스템 단축키 보존 | [20260712_unmapped-modifier-passthrough.md](references/20260712_unmapped-modifier-passthrough.md) |
| 2026-07-12 | append 전용 Motion 케이스 | a/A는 charRightForAppend/lineEndForAppend — 어댑터가 l·$와 줄 끝 시맨틱 구분 | [20260712_append-dedicated-motion-cases.md](references/20260712_append-dedicated-motion-cases.md) |
| 2026-07-12 | App Sandbox 해제 + Developer ID 배포 | CGEventTap/AX가 샌드박스 불가 → 샌드박스 off, MAS 포기하고 Developer ID 직접 배포 | [20260712_disable-sandbox-developer-id.md](references/20260712_disable-sandbox-developer-id.md) |
| 2026-07-12 | Active tap + AX 단독 온보딩 | 메인 탭은 처음부터 .defaultTap, 권한은 Accessibility만 요청 (Input Monitoring은 필요 입증 시) | [20260712_active-tap-ax-only-onboarding.md](references/20260712_active-tap-ax-only-onboarding.md) |
| 2026-07-13 | 탭 자동복구 워치독 | 콜백 재활성화만으로 못 잡는 완전정지/장기스톨 대비 CGEventTapIsEnabled 주기 폴링 워치독 추가 | [20260713_tap-reenable-watchdog-polling.md](references/20260713_tap-reenable-watchdog-polling.md) |
| 2026-07-14 | 멀티키 커맨드 문법 빌더 | diw·dd·카운트 지원 위해 pending을 부분 파스 상태로, resolve를 extend/complete/cancel 스텝 함수로 일반화. Esc/탈출 콤보 취소는 명시적 최우선 분기로 | [20260714_multikey-command-grammar-builder.md](references/20260714_multikey-command-grammar-builder.md) |
| 2026-07-14 | Normal 모드 modifier 탈출 옵션 | Cmd/Opt 등 미매핑 콤보는 pending 폐기+Insert 탈출+통과(Spotlight/Raycast 직후 타이핑). Configuration 주입, 기본 on, Ctrl 제외(Ctrl-d 충돌), pending 중에도 탈출 | [20260714_normal-mode-escape-modifiers.md](references/20260714_normal-mode-escape-modifiers.md) |
| 2026-07-16 | CGEvent→Key 번역 방식 | UCKeyTranslate + ASCII-capable 레이아웃(한글 입력 소스에서도 동작), base 추출은 shift만 반영, 번역 불가 nil=무조건 통과, TIS 메인 스레드 요구로 @MainActor 고정 | [20260716_cgevent-key-translation-ascii-layout.md](references/20260716_cgevent-key-translation-ascii-layout.md) |
| 2026-07-16 | KeyTranslator total function 가드 | keyDown 외 타입은 번역기 내부 가드로 nil — 호출자 보장 계약·시그니처 축소 대신 어댑터의 도메인 정의로 | [20260716_keytranslator-total-function-keydown-guard.md](references/20260716_keytranslator-total-function-keydown-guard.md) |
| 2026-07-17 | VimAction 편집 출력 형태 | .edit(Operator, TextRange) 확정 — 모션 카운트는 .move 반복, 에디트 카운트는 TextRange 값, opMotion charwise 화이트리스트, 9999 클램프 | [20260717_vimaction-edit-output-shape.md](references/20260717_vimaction-edit-output-shape.md) |
| 2026-07-17 | 취소 최우선 순서의 전제 | Esc 정확 매치 + 탈출 콤보 선행 판정 — 선행 순서는 modifier 매핑 부재 위에서만 동치, Ctrl-d 류 추가 시 재검토 필수 | [20260717_cancellation-first-ordering-premise.md](references/20260717_cancellation-first-ordering-premise.md) |
| 2026-07-17 | KeyTranslator 레이아웃 캐싱 | ASCII-capable 레이아웃 Data 캐시 + 분산 노티 무효화. selector+deliverImmediately(LSUIElement 항상 비활성), 선택·enabled 두 축 관찰, UCKeyTranslate 실패 시 캐시 폐기 | [20260717_keytranslator-layout-caching.md](references/20260717_keytranslator-layout-caching.md) |
| 2026-07-18 | 가로채기 마스터 토글 의미론 + 설정 소유 모델 | off=tapEnable(false) 스트림 해방+엔진 리셋+워치독 정지+재활성화 게이트, on=선제 tapEnable. 토글·탈출 옵션 둘 다 컨트롤러 프로퍼티 SSOT+didSet 주입, .running=설치 헬스(on/off와 직교) | [20260718_interception-toggle-semantics.md](references/20260718_interception-toggle-semantics.md) |
| 2026-07-19 | change의 Insert 전이 + cw 특례 이연 | change 완결 시 엔진 즉시 Insert 전이(complete 헬퍼 단일화), cw→ce 특례는 어댑터 몫, "삭제 실행 후 후속 이벤트" 어댑터 계약 | [20260719_change-insert-transition-and-cw-deferral.md](references/20260719_change-insert-transition-and-cw-deferral.md) |
| 2026-07-19 | TextObject quote·pair 확장 형태 | kind 케이스+Scope 연관값, 여닫이 양쪽+b/B 별칭 인정, 경계 의미는 어댑터 몫, 카운트+오브젝트는 invalid(파괴적 오해석 방지) | [20260719_textobject-quote-pair-expansion.md](references/20260719_textobject-quote-pair-expansion.md) |
| 2026-07-19 | linewise TextRange + 절대 카운트 invalid | additive .linewiseMotion(기존 .motion 불변), 상대(j/k)만 카운트, 절대(G/gg)+카운트는 invalid(모션 3G 반복-수용과 다른 기준), dgg는 op-pending g extend | [20260719_linewise-textrange-absolute-count-invalid.md](references/20260719_linewise-textrange-absolute-count-invalid.md) |
| 2026-07-19 | 오퍼레이터 모션 단일 테이블 통합 | opMotion 화이트리스트를 kind(charwise/linewiseRelative/linewiseAbsolute) 딸린 단일 테이블로 — 카운트 의미는 불변, gg만 prefix 유지 | [20260719_opmotion-unified-dispatch-table.md](references/20260719_opmotion-unified-dispatch-table.md) |
| 2026-07-19 | 워치독 스톨 게이트 | 워치독 목적을 "스톨 종료 후 복구"로 확정 — 스톨 중(홉 pending) 재활성화 보류, 홉 FIFO(main.async), off 최종 disable 시리얼 큐 봉인 | [20260719_watchdog-stall-gate-post-stall-recovery.md](references/20260719_watchdog-stall-gate-post-stall-recovery.md) |
| 2026-07-19 | Secure Input 전용 상태 | 비밀번호 입력 등 OS 억제를 .failed 아닌 Status.secureInput으로 — 재활성화 미시도, lock.square 표시, 우선순위 고장>토글off>secureInput | [20260719_secure-input-status.md](references/20260719_secure-input-status.md) |
| 2026-07-22 | Visual 모드 출력 계약 | extendSelection(반복 카운트)·beginSelection(linewise:)·clearSelection·TextRange.selection 신설 — wise는 세션 속성으로 진입 신호가 나름, 앵커·범위는 어댑터 상태, 모드 동봉·mode 참조안 기각 | [20260722_visual-mode-output-contract.md](references/20260722_visual-mode-output-contract.md) |
| 2026-07-22 | Visual 진입 pending 상호작용 | 특례 없이 기존 규칙 적용 — 3v는 카운트 무시 진입(3i 선례), dv는 invalid no-op(dq 선례). Vim의 {count}v·forced-motion은 v1 범위 밖 의도적 이연, v2 지원 시 supersede | [20260722_visual-entry-pending-interaction.md](references/20260722_visual-entry-pending-interaction.md) |
| 2026-07-23 | Visual 진입/전환 신호 분리 | beginSelection은 항상 앵커 리셋, v↔V 전환은 switchSelectionWise 신설(앵커 유지·무세션이면 begin 취급) — stale 세션 모호성 해소, 탈출 콤보 선택 잔류는 수용 확정 | [20260723_visual-begin-reset-switch-wise-split.md](references/20260723_visual-begin-reset-switch-wise-split.md) |
| 2026-07-23 | Visual y의 clearSelection 동반 | y는 [edit(yank,.selection), clearSelection]으로 완결 — 화면 잔류 선택의 collapse를 픽스처로 고정, collapse 목적지는 어댑터 몫, d/x/c는 자연 소멸이라 미동반 | [20260723_visual-yank-clear-selection.md](references/20260723_visual-yank-clear-selection.md) |
| 2026-07-23 | Visual 카운트+오퍼레이터 실행 | 3d 등 선행 카운트는 버리고 즉시 실행(Vim 동일) — 선택 범위가 피연산자라 오해석 위험 0, 기존 invalid-swallow(무피드백)를 번복 | [20260723_visual-count-operator-executes.md](references/20260723_visual-count-operator-executes.md) |
| 2026-07-23 | openLine(o/O) 출력 계약 | 새 top-level 케이스 openLine(above:) + 완결 시 Insert 전이(a/A 패턴), 카운트 무시(3i 선례 — Insert 세션 기억 없어 표현 불가, 반복 출력은 오해석) | [20260723_openline-output-contract.md](references/20260723_openline-output-contract.md) |
| 2026-07-23 | paste(p/P) 출력 계약 | 새 케이스 paste(before:count:) — 카운트는 한 편집 단위의 count 값(3x 선례), charwise/linewise 판정은 어댑터 몫, v1 레지스터 없음(시스템 클립보드 위임) | [20260723_paste-output-contract.md](references/20260723_paste-output-contract.md) |
| 2026-07-23 | undo(u) 출력 계약 | 새 케이스 undo — 네이티브 undo 위임, 카운트는 반복 출력(.move 선례, 이산 반복 동작), Ctrl-r은 Ctrl 콤보 묶음으로 이연(비대칭 수용) | [20260723_undo-output-contract.md](references/20260723_undo-output-contract.md) |
| 2026-07-24 | Ctrl 매핑 취소 충돌 해소 — 매핑 예외 셋 | 취소 순서 유지 + 매핑된 Ctrl 콤보만 탈출 판정 제외(테이블 파생 단일 소스), Normal 전용·키 단위 예외 — 20260717 전제 재검토의 해소 | [20260724_ctrl-combo-mapped-exception-cancellation.md](references/20260724_ctrl-combo-mapped-exception-cancellation.md) |
| 2026-07-24 | 스크롤·redo 출력 계약 | 전용 케이스 scroll(ScrollExtent, forward:)·redo(undo 미러) — 카운트는 반복 출력(3u 규칙), Normal 전용, 실행 수단·커서 동반은 어댑터 몫 | [20260724_scroll-redo-output-contract.md](references/20260724_scroll-redo-output-contract.md) |
| 2026-07-24 | Ctrl-[ Esc 별칭 — 진입부 정규화 | handle() 초입에서 Esc로 치환(정확 매치만) — 세 모드 완전 별칭, 탈출 콤보 판정보다 선행, 앱 계층 아닌 엔진 정규화(픽스처 커버) | [20260724_ctrl-bracket-escape-normalization.md](references/20260724_ctrl-bracket-escape-normalization.md) |
| 2026-07-25 | 탭 메인 런루프 유지 확정 | 전용 스레드 전환 기각(3-에이전트 리뷰) — 타임아웃은 스레드 무관, 실측 0건·양성 degrade, 재검토 트리거 3종 명시 | [20260725_tap-main-runloop-retention.md](references/20260725_tap-main-runloop-retention.md) |
| 2026-07-25 | 콜백 경량 불변식 | 탭 콜백 동기 구간을 번역+엔진 step+캐시 읽기로 제한 — AX 프로브·실행은 콜백 밖 비동기, 디스패처 설계 제약, 3ms 캡 실기기 검증 위임 | [20260725_callback-light-invariant.md](references/20260725_callback-light-invariant.md) |
| 2026-07-25 | Keyboard-first MVP 빌드 순서 | 실행 계층은 Keyboard 어댑터 먼저, AX+auto는 MVP 이후 확장 — 주력 앱 Electron, 과도기 기본 전략 keyboard, 리졸버는 시점별 분해 (최종 디스패치 구조 불변) | [20260725_keyboard-first-mvp-build-order.md](references/20260725_keyboard-first-mvp-build-order.md) |
| 2026-07-25 | 마커 가드는 콜백 최우선 판정 | 마커 확인을 handleKeyDown 최상단(토글 가드보다 앞)에 — 상태 무관 불변식이라 상태 조합보다 선행. ActionExecutor는 게시 함수 주입 seam으로 마커 불변식을 테스트 | [20260725_marker-guard-highest-precedence.md](references/20260725_marker-guard-highest-precedence.md) |
| 2026-07-25 | 예외 폭주 자동 off의 형태 | 시간 주입 순수 카운터(1초/5회, 트립 시 창 비움) + 효과는 isInterceptionEnabled=false 대입뿐(기존 소프트 off didSet 재사용), 알림은 메뉴바 글리프+로그 | [20260725_failure-burst-autodisable-shape.md](references/20260725_failure-burst-autodisable-shape.md) |
| 2026-07-26 | 킬스위치 탭은 전용 스레드 | 킬 탭은 전용 Thread+자체 CFRunLoop — 메인 스톨 중 배달 보장. 메인 런루프 유지 결정의 범위는 메인 탭 한정임을 명시(supersede 아님), 킬 탭 전용 워치독은 과잉 방어로 기각 | [20260726_kill-switch-dedicated-runloop-thread.md](references/20260726_kill-switch-dedicated-runloop-thread.md) |
| 2026-07-26 | 킬스위치 탭 위치·폴백 | HID 능동 탭 우선 + 세션 head-insert 2단 폴백, 설치 순서가 계약(메인 탭 다음). **비루트 HID 생성 성공 실측** — 3단 사다리·재설치 연동 기각, 상태는 Settings 읽기 전용 행으로 노출 | [20260726_kill-switch-hid-tap-session-fallback.md](references/20260726_kill-switch-hid-tap-session-fallback.md) |
| 2026-07-26 | 킬스위치 발동 의미론 | 단방향 off + 2겹 효과(직접 tapEnable / 홉 후 didSet 위임) + **킬 요청 래치**(우리 disable에 대한 OS 통지가 탭을 되살리는 실기기 결함 해소), 콤보는 고정·의도 modifier 정확 일치, 마커·오토리핏 가드 | [20260726_kill-switch-trigger-semantics.md](references/20260726_kill-switch-trigger-semantics.md) |
| 2026-07-26 | 실행 실패 보고 단위 | 보고는 원인 키 입력 1건당 최대 1회 — 어댑터가 action 시퀀스 실패를 접는다(카운트 반복 출력이 임계를 압도하는 것 차단). 특이도는 미해결. M2 확정 항목 3종: 백그라운드 큐 배선(4항 supersede 필요), 재시작 영속, 1초/5회 임계 재검증 | [20260726_execution-failure-report-granularity.md](references/20260726_execution-failure-report-granularity.md) |
| 2026-07-26 | 킬 콤보 삼킴은 발동과 독립 | 삼킴(`shouldSwallow`)과 발동(`shouldFire`) 술어 분리 — **오토리핏 콤보도 삼킨다**(기존엔 통과해 포커스 앱으로 샘). keyUp 대칭 삼킴은 메인 탭과 같은 비대칭으로 기각 | [20260726_kill-combo-swallow-independent-of-fire.md](references/20260726_kill-combo-swallow-independent-of-fire.md) |
| 2026-07-26 | 킬스위치 off 영속은 홉과 독립 | 메인 스톨 중 강제 종료해도 off가 남도록 킬 경로가 직접 영속(공유 함수, 함수 말미 — XPC가 안전장치 경로를 막지 않게). **SIGKILL 생존 실측**, defaults 단일 writer 모델 완화 | [20260726_kill-switch-off-persistence-off-main.md](references/20260726_kill-switch-off-persistence-off-main.md) |
| 2026-07-26 | 킬 탭 활성화 검증·강등 | `tapEnable` 뒤 `tapIsEnabled` 검증(통지는 평생 1회라 놓치면 복구 불가), 실패 시 킬 스레드에서 직접 fault + `Installation.failed` 강등. 재시도 타이머는 런루프 수명 계약을 깨 기각 | [20260726_kill-tap-enable-verification.md](references/20260726_kill-tap-enable-verification.md) |
| 2026-07-26 | ActionExecutor 격리·게시 클로저 계약 | `SyntheticEventMarker`·`ActionExecutor`는 타입 단위 nonisolated + 명시적 Sendable, 게시 클로저는 `@Sendable (CGEvent) -> Void`. CGEvent 비-Sendable의 답은 우회가 아니라 **이벤트를 post 호출자와 같은 직렬 큐에서 만든다**는 계약. 경고 기준선 4건→0건, Swift 6 잔여는 AccessibilityPermissionMonitor:35 하나 | [20260726_action-executor-nonisolated-sendable.md](references/20260726_action-executor-nonisolated-sendable.md) |
| 2026-07-26 | Secure Input은 배달만 억제 | **실측**: SEI 중에도 tapCreate·tapEnable·tapIsEnabled 정상 — 활성화를 막지 않는다. 워치독은 SEI 중에도 재활성화 시도(되살리기 먼저, SEI는 표시 구분용). `.secureInput`은 `.failed`의 하위 표시 구분으로 재정의 | [20260726_secure-input-suppresses-delivery-not-enablement.md](references/20260726_secure-input-suppresses-delivery-not-enablement.md) |
| 2026-07-26 | 미지원 액션은 실패 아님 | `reportExecutionFailure` 의미론을 "실행 시도 후 깨짐"으로 한정 — 미구현 액션은 스킵+DEBUG 로그 (dd 5회가 자동 off를 트립하는 오탐 차단), M3 편집 구현 시에도 동일 규칙 | [20260726_unsupported-action-not-failure.md](references/20260726_unsupported-action-not-failure.md) |
| 2026-07-26 | M2 앱 게이트는 엔진 전 통과 | disable 앱은 번역·엔진 전 원본 통과(디스패치 시점 게이트는 죽은 키 — 기각) + 엔진 모드 동결, bundleID는 활성화 알림 갱신 캐시로(콜백 경량), 초기 목록 ghostty 하나 하드코딩(M4 프로파일이 교체) | [20260726_m2-app-gate-pre-engine-passthrough.md](references/20260726_m2-app-gate-pre-engine-passthrough.md) |
| 2026-07-26 | 릴리스 배포 금지 게이트는 M3 | 배포 금지 **유지**, 해제 게이트를 "디스패처 마일스톤"에서 **M3(편집 실행)** 으로 이동 — M2는 모션만 실행하고 편집 키는 여전히 무로그 스킵이라 "죽은 키"가 남는다. `.replace` 요약 1건·DEBUG 전용·non-exhaustive switch 근거를 승계 | [20260726_release-block-gate-moves-to-m3.md](references/20260726_release-block-gate-moves-to-m3.md) |
| 2026-07-26 | M2 실행 배선 형태 | 컨트롤러는 주입된 sink 클로저 하나만 안다 — 기본 팩토리가 게시 직렬 큐+`KeyboardAdapter`를 캡처(별도 디스패처 객체 기각). 기본 sink·게이트는 XCTest 하위에서 무해로 바꿔치기(실제 키 주입·Ghostty에서 테스트 시 GREEN 뒤집힘 차단). 실패 보고는 여전히 배선 없음 → 폭주 카운터 MainActor 4항 supersede 불필요 | [20260726_m2-execution-wiring-shape.md](references/20260726_m2-execution-wiring-shape.md) |
| 2026-07-26 | 모션 키스트로크 매핑 계약 | 순수 매퍼 `Motion → [KeyStroke]` — 배열 반환이 계약(모션 1개=키 N개 조합 확장 허용), CGEvent 변환은 게시 큐 위에서, 정확 의미는 M5 AX 몫. 초기 근사 표의 w·^ 2건은 3타 조합 결정이 갱신 | [20260726_motion-keystroke-mapping-contract.md](references/20260726_motion-keystroke-mapping-contract.md) |
| 2026-07-26 | w·^(I) 매핑 3타 조합 | 도그푸딩 후속 — w는 `Opt-→,Opt-→,Opt-←`, ^·I는 `Cmd-←,Opt-→,Opt-←`(단어 끝 지나친 뒤 시작 복귀). 계약·매퍼 위치 불변, 테이블 원소 2개 교체. 수용 엣지 3종(e직후 w, 문서 끝 w 후퇴, 공백줄 ^) 기록 | [20260726_word-forward-first-nonblank-multi-stroke.md](references/20260726_word-forward-first-nonblank-multi-stroke.md) |
| 2026-07-26 | Shift 새어 들어감 종결 | 이벤트 flags 명시 대입(기존 구현)이 채택된 완결 형태 — 전역 modifier 상태 채널은 재현 도그푸딩 미재현 + 정리 수단이 침습적 핵뿐이라 기각. 실증상 발견 시 supersede로 재개 | [20260726_shift-leak-event-flags-sufficient.md](references/20260726_shift-leak-event-flags-sufficient.md) |
| 2026-07-26 | 탭 들여쓰기 ^·I 엣지 수용 | Chromium 계열은 탭 런을 경계 토큰으로 취급해 ^·I가 0으로 퇴행(TextKit은 실측 정확) — 두 세그먼테이션을 만족하는 고정 시퀀스 부재로 수용, 4타·앱별 분기 기각. M5 AX에서 자연 해소 | [20260726_tab-indent-first-nonblank-chromium-edge.md](references/20260726_tab-indent-first-nonblank-chromium-edge.md) |
| 2026-07-26 | 카운트 폭탄 실측 — 실행 중단 래치 M3 승격 | 9999j 수 초 폭주·킬스위치 in-flight 한계·버스트 중 타이핑 순서 역전·Notion 드랍 실증 → 래치를 M3 단계 4로 승격, 방향은 청크 게시+중단 체크 | [20260726_count-burst-abort-latch-promotion.md](references/20260726_count-burst-abort-latch-promotion.md) |
| 2026-07-26 | undo 단위 실측 — u=Cmd-Z 유지 | 선택+잘라내기/붙여넣기/새줄 시퀀스는 1 undo 단위 실증 → 시퀀스 설계 자유, change만 삭제+타이핑 분리 수용 엣지. 네이티브 앱 키바인딩 편차는 M5 AX 영역 | [20260726_undo-unit-cmdz-policy.md](references/20260726_undo-unit-cmdz-policy.md) |
| 2026-07-27 | 편집 키스트로크 매핑 계약 | 신규 순수 매퍼 `EditKeyMapper` — `(op, range, family) → [KeyStroke]?`(nil=미지원 스킵). 모든 편집은 "Shift+모션 선택 후 오퍼레이터 1타", 선택은 모션 매핑 재사용(Shift 부여)이라 3타 조합도 특례 없이 성립. family는 편집 매퍼에만(모션은 계열 무관) | [20260727_edit-keystroke-mapping-contract.md](references/20260727_edit-keystroke-mapping-contract.md) |
| 2026-07-27 | linewise 개행 반올림 | delete/yank는 개행 포함, change는 줄 유지(마지막 확장만 줄 끝) — 통일하면 셋 중 하나가 반드시 틀린다. 문서 끝은 빈 줄 1개 수용(감지가 원리적 불가, 무조건 보정은 더 위험), `dgg`만 정확 | [20260727_linewise-newline-rounding.md](references/20260727_linewise-newline-rounding.md) |
| 2026-07-27 | yank collapse는 왼쪽 | `Cmd-C` 뒤 `←` 1타로 범위 시작에 붙임 — 왼쪽 끝이 항상 Vim의 범위 시작이라 모션 방향 분기 불필요. 미collapse는 잔류 선택 + 앱별 착지점 편차 | [20260727_yank-collapse-to-range-start.md](references/20260727_yank-collapse-to-range-start.md) |
| 2026-07-27 | 오퍼레이터 키 ANSI 고정 | `Cmd-X`/`Cmd-C`는 ANSI 키코드 고정 = QWERTY 가정(화살표와 달리 레이아웃 의존). 역조회는 매퍼 순수성·주입 계층 비용으로 이연, 비-QWERTY 안전판은 릴리스 게이트 판단 항목 | [20260727_operator-key-ansi-layout-assumption.md](references/20260727_operator-key-ansi-layout-assumption.md) |
| 2026-07-27 | `iw` 앵커는 단어 끝 경유 3타 | 도그푸딩 후속 — `Opt-←` 1타는 캐럿이 단어 시작일 때 **앞 단어를 지운다**. `Opt-→, Opt-←`로 복귀해 앵커를 잡는 `^`와 같은 패턴으로 교체(수용 엣지: 뒤 공백 위면 다음 단어) | [20260727_inner-word-anchor-via-word-end.md](references/20260727_inner-word-anchor-via-word-end.md) |
| 2026-07-27 | Notion `Shift-Cmd-↑/↓` 충돌 수용 | 도그푸딩 후속 — Notion은 이 조합이 블록 이동이라 `d/c/y`+`G`·`gg` 6조합이 파괴적 오동작. 회피 수단이 앱 축뿐이라 매퍼 무변경 수용, M4 프로파일이 해소·단계 4 게이트에서 재검토 | [20260727_notion-cmd-shift-vertical-conflict.md](references/20260727_notion-cmd-shift-vertical-conflict.md) |
| 2026-07-28 | 편집 경계 포화 수용 엣지 5종 | 리뷰 트리아지 후속 — 줄 끝 x 줄 병합, 첫 줄 dk 아래 줄 삭제, 마지막 단어 dw 반전, 마지막 줄 dgg 누락, 빈 선택+오퍼레이터. 무상태 전제상 감지 불가·조건부 보정 금지로 코드 무변경 수용, 정확화는 M5 AX 읽기 혼용 | [20260728_edit-boundary-saturation-accepted-edges.md](references/20260728_edit-boundary-saturation-accepted-edges.md) |
| 2026-07-28 | linewise 시각 줄 수용 엣지 | 소프트 랩 문단에서 dd/cc/dj가 논리 줄 아닌 화면 행 단위 — 화살표 계열이 전부 시각 줄 기준. 문단 바인딩(Ctrl-A/Opt-↓) 재구성은 앱 커버리지 미검증으로 백로그 이연, M5 AX가 자연 해소 | [20260728_linewise-visual-line-wrap-accepted-edge.md](references/20260728_linewise-visual-line-wrap-accepted-edge.md) |

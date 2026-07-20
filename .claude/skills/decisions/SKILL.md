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
| 2026-07-12 | 탭 메인 런루프 부착 | 스파이크는 메인 런루프 부착, 타임아웃 재활성화 로그를 근거로 엔진 연결 전 전용 스레드 재검토 | [20260712_main-runloop-tap-attachment.md](references/20260712_main-runloop-tap-attachment.md) |
| 2026-07-13 | 탭 자동복구 워치독 | 콜백 재활성화만으로 못 잡는 완전정지/장기스톨 대비 CGEventTapIsEnabled 주기 폴링 워치독 추가 | [20260713_tap-reenable-watchdog-polling.md](references/20260713_tap-reenable-watchdog-polling.md) |
| 2026-07-14 | 멀티키 커맨드 문법 빌더 | diw·dd·카운트 지원 위해 pending을 부분 파스 상태로, resolve를 extend/complete/cancel 스텝 함수로 일반화. Esc/탈출 콤보 취소는 명시적 최우선 분기로 | [20260714_multikey-command-grammar-builder.md](references/20260714_multikey-command-grammar-builder.md) |
| 2026-07-14 | Normal 모드 modifier 탈출 옵션 | Cmd/Opt 등 미매핑 콤보는 pending 폐기+Insert 탈출+통과(Spotlight/Raycast 직후 타이핑). Configuration 주입, 기본 on, Ctrl 제외(Ctrl-d 충돌), pending 중에도 탈출 | [20260714_normal-mode-escape-modifiers.md](references/20260714_normal-mode-escape-modifiers.md) |
| 2026-07-16 | CGEvent→Key 번역 방식 | UCKeyTranslate + ASCII-capable 레이아웃(한글 입력 소스에서도 동작), base 추출은 shift만 반영, 번역 불가 nil=무조건 통과, TIS 메인 스레드 요구로 @MainActor 고정 | [20260716_cgevent-key-translation-ascii-layout.md](references/20260716_cgevent-key-translation-ascii-layout.md) |
| 2026-07-16 | KeyTranslator total function 가드 | keyDown 외 타입은 번역기 내부 가드로 nil — 호출자 보장 계약·시그니처 축소 대신 어댑터의 도메인 정의로 | [20260716_keytranslator-total-function-keydown-guard.md](references/20260716_keytranslator-total-function-keydown-guard.md) |
| 2026-07-17 | VimAction 편집 출력 형태 | .edit(Operator, TextRange) 확정 — 모션 카운트는 .move 반복, 에디트 카운트는 TextRange 값, opMotion charwise 화이트리스트, 9999 클램프 | [20260717_vimaction-edit-output-shape.md](references/20260717_vimaction-edit-output-shape.md) |
| 2026-07-17 | 취소 최우선 순서의 전제 | Esc 정확 매치 + 탈출 콤보 선행 판정 — 선행 순서는 modifier 매핑 부재 위에서만 동치, Ctrl-d 류 추가 시 재검토 필수 | [20260717_cancellation-first-ordering-premise.md](references/20260717_cancellation-first-ordering-premise.md) |
| 2026-07-17 | replace 미실행 과도기 규칙 | 배선 마일스톤은 .replace를 실행 없이 삼키고 DEBUG 요약 1건만 로그 — 실행은 디스패처 마일스톤. 무로그 삼킴이라 그 전 릴리스 배포 금지 | [20260717_replace-swallow-transitional-rule.md](references/20260717_replace-swallow-transitional-rule.md) |
| 2026-07-17 | KeyTranslator 레이아웃 캐싱 | ASCII-capable 레이아웃 Data 캐시 + 분산 노티 무효화. selector+deliverImmediately(LSUIElement 항상 비활성), 선택·enabled 두 축 관찰, UCKeyTranslate 실패 시 캐시 폐기 | [20260717_keytranslator-layout-caching.md](references/20260717_keytranslator-layout-caching.md) |
| 2026-07-18 | 가로채기 마스터 토글 의미론 + 설정 소유 모델 | off=tapEnable(false) 스트림 해방+엔진 리셋+워치독 정지+재활성화 게이트, on=선제 tapEnable. 토글·탈출 옵션 둘 다 컨트롤러 프로퍼티 SSOT+didSet 주입, .running=설치 헬스(on/off와 직교) | [20260718_interception-toggle-semantics.md](references/20260718_interception-toggle-semantics.md) |
| 2026-07-19 | change의 Insert 전이 + cw 특례 이연 | change 완결 시 엔진 즉시 Insert 전이(complete 헬퍼 단일화), cw→ce 특례는 어댑터 몫, "삭제 실행 후 후속 이벤트" 어댑터 계약 | [20260719_change-insert-transition-and-cw-deferral.md](references/20260719_change-insert-transition-and-cw-deferral.md) |
| 2026-07-19 | TextObject quote·pair 확장 형태 | kind 케이스+Scope 연관값, 여닫이 양쪽+b/B 별칭 인정, 경계 의미는 어댑터 몫, 카운트+오브젝트는 invalid(파괴적 오해석 방지) | [20260719_textobject-quote-pair-expansion.md](references/20260719_textobject-quote-pair-expansion.md) |
| 2026-07-19 | linewise TextRange + 절대 카운트 invalid | additive .linewiseMotion(기존 .motion 불변), 상대(j/k)만 카운트, 절대(G/gg)+카운트는 invalid(모션 3G 반복-수용과 다른 기준), dgg는 op-pending g extend | [20260719_linewise-textrange-absolute-count-invalid.md](references/20260719_linewise-textrange-absolute-count-invalid.md) |
| 2026-07-19 | 오퍼레이터 모션 단일 테이블 통합 | opMotion 화이트리스트를 kind(charwise/linewiseRelative/linewiseAbsolute) 딸린 단일 테이블로 — 카운트 의미는 불변, gg만 prefix 유지 | [20260719_opmotion-unified-dispatch-table.md](references/20260719_opmotion-unified-dispatch-table.md) |
| 2026-07-19 | 워치독 스톨 게이트 | 워치독 목적을 "스톨 종료 후 복구"로 확정 — 스톨 중(홉 pending) 재활성화 보류, 홉 FIFO(main.async), off 최종 disable 시리얼 큐 봉인 | [20260719_watchdog-stall-gate-post-stall-recovery.md](references/20260719_watchdog-stall-gate-post-stall-recovery.md) |
| 2026-07-19 | Secure Input 전용 상태 | 비밀번호 입력 등 OS 억제를 .failed 아닌 Status.secureInput으로 — 재활성화 미시도, lock.square 표시, 우선순위 고장>토글off>secureInput | [20260719_secure-input-status.md](references/20260719_secure-input-status.md) |

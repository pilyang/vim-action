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
   - 옛 문서에는 **맨 위에 한 줄만** 추가합니다: `> Superseded by [yyyymmdd_새문서.md](yyyymmdd_새문서.md)` — 본문은 그대로 둡니다. 파일을 직접 연 사람도 낡은 결정임을 즉시 알 수 있게 하기 위한 유일한 허용 수정입니다. 부분 supersede는 `> Superseded (부분) by ... — <뒤집힌 부분> / <유효한 부분>` 형태로 범위를 명시합니다.
   - 옛 문서가 **뒤집힌 결정만 담고 있다면** (다른 유효한 컨텍스트가 없다면) 아래 인덱스 테이블에서 **제거**합니다. 제거한 문서 중 히스토리 가치까지 소진된 것(단명한 과도기 규칙, 이행이 끝난 스케줄링 결정 등)은 **파일도 삭제**할 수 있습니다 — git 히스토리가 아카이브입니다. 실측 기록·위험 분석 등 재참조 가치가 남아 있거나 애매하면 파일은 남깁니다.
   - 옛 문서에 아직 유효한 다른 결정·컨텍스트가 섞여 있어 제거 여부가 **애매하다면, 임의로 판단하지 말고 사용자에게 확인**합니다 (마킹·인덱스 제거를 보류하고 상황을 설명한 뒤 질문). 잘못 제거하면 유효한 결정이 컨텍스트에서 사라지고, 잘못 남기면 낡은 값이 계속 주입됩니다 — 문서 하나 = 결정 하나 원칙을 지켰다면 이 애매함 자체가 드뭅니다.
3. **인덱스 테이블을 반드시 갱신**합니다. 인덱스에 없는 문서는 다음 작업자의 컨텍스트에 주입되지 않습니다 — 이것이 폐기된 결정이 새 작업을 오염시키지 않게 하는 메커니즘입니다. 반대로, 인덱스를 빼먹으면 유효한 결정도 없는 것이 됩니다. 인덱스 요약은 **한 줄**로 짧게 — 상세 근거는 문서 몫이고, 인덱스는 "어떤 결정이 있는지 찾는" 용도입니다.
4. **구조·아키텍처에 영향이 있는 결정이면, 같은 플로우에서 `architecture` 스킬의 해당 reference(최종 상태)도 갱신**합니다. 결정 문서는 "왜 바뀌었는가"를, architecture reference는 "바뀐 결과가 무엇인가"를 담습니다. 여기서 갱신을 빼먹으면 두 스킬이 서로 다른 구조를 말하게 됩니다.

기록하지 않는 것: 사소하거나 코드만 봐도 자명한 선택. 결정 문서의 가치는 코드에서 역추적할 수 없는 맥락(근거, 기각된 대안)에 있습니다.

## 워크플로우 2 — 결정 조회

과거 결정의 경위·근거를 물으면 아래 인덱스에서 관련 항목을 찾아 **해당 문서만** 읽습니다. 전부 읽지 마세요. 인덱스에 없는(폐기된) 문서는 "그때 왜 그렇게 했다가 바뀌었는지" 같은 히스토리 조사가 목적일 때만 `references/` 디렉토리에서 직접 찾아 읽습니다 (삭제된 문서는 git 히스토리에서).

## Decision Index

도메인별 섹션, 각 섹션 안은 결정일 순. 요약은 결정의 핵심 한 줄 — 근거·대안·실측은 문서에 있습니다.

### 빌드·설정·배포

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-12 | YAML 설정 (Yams) | 설정은 전부 YAML + Yams 파싱 (루트는 20260801, 3계층 병합·자동 리로드는 20260802 부분 supersede) | [20260712_yaml-three-layer-config.md](references/20260712_yaml-three-layer-config.md) |
| 07-12 | 엔진 테스트는 Swift Testing | 픽스처 파라미터라이즈드에 적합, UI 테스트는 XCTest 유지 | [20260712_swift-testing-for-engine-tests.md](references/20260712_swift-testing-for-engine-tests.md) |
| 07-12 | 단일 코어 SPM 패키지 | 순수 Swift 모듈은 VimActionCore 단일 패키지의 다중 타깃으로 | [20260712_single-core-spm-package.md](references/20260712_single-core-spm-package.md) |
| 07-12 | GitHub Actions CI | macos-26 병렬 2잡(엔진 테스트+앱 빌드), Xcode 고정, 사이닝 off | [20260712_github-actions-ci.md](references/20260712_github-actions-ci.md) |
| 07-12 | 샌드박스 해제 + Developer ID | CGEventTap/AX가 샌드박스 불가 → MAS 포기, 직접 배포 | [20260712_disable-sandbox-developer-id.md](references/20260712_disable-sandbox-developer-id.md) |
| 07-12 | Active tap + AX 단독 온보딩 | 메인 탭은 처음부터 .defaultTap, 권한은 Accessibility만 요청 | [20260712_active-tap-ax-only-onboarding.md](references/20260712_active-tap-ax-only-onboarding.md) |
| 08-01 | 릴리스 배포 금지 게이트 해제 | M3 완료 — 무로그 삼킴 0건+위험 심사 4건 종결, 로그·switch 계약 승계 | [20260801_release-block-gate-lifted.md](references/20260801_release-block-gate-lifted.md) |
| 08-01 | 설정 루트 `~/.config/vim-action/` | 개발자 친화(dotfiles) — Application Support 부분 supersede | [20260801_config-root-dot-config.md](references/20260801_config-root-dot-config.md) |
| 08-01 | 앱별 on/off는 config.yaml 단일 소유 | 프로파일 스키마에서 enabled 제거, profiles/는 특수 동작 전용 | [20260801_app-enable-config-yaml-only.md](references/20260801_app-enable-config-yaml-only.md) |
| 08-01 | config.yaml 스키마 v1 | apps는 bundle-id→bool 맵, 미지 키 warn+무시, 리로드 실패 시 직전 유지 (병합 규칙은 20260802 부분 supersede) | [20260801_config-yaml-schema-v1.md](references/20260801_config-yaml-schema-v1.md) |
| 08-01 | 프로파일 재정의는 모션 단위 | motions가 매핑 테이블 원소 교체 — 편집·Visual 자동 전파, 액션 단위 기각 | [20260801_profile-motion-override-unit.md](references/20260801_profile-motion-override-unit.md) |
| 08-01 | 프로파일 스키마 v1 필드 | name·scroll·motions 구성, 문자 키 v1 제외, M4 전부 구현 (disabled_actions·표기는 08-02 부분 supersede) | [20260801_profile-schema-v1-fields.md](references/20260801_profile-schema-v1-fields.md) |
| 08-01 | 설정 UI는 YAML 읽기 전용 | Yams 주석 미보존 — UI는 표시+파일 열기만, 쓰기는 사용자 몫 (표시 대상은 20260802 부분 supersede) | [20260801_settings-ui-read-only-yaml.md](references/20260801_settings-ui-read-only-yaml.md) |
| 08-01 | UserDefaults↔YAML 소유권 경계 | defaults=런타임·안전 상태(마스터 토글·탈출 옵션), YAML=사용자 편집 설정 | [20260801_userdefaults-yaml-ownership.md](references/20260801_userdefaults-yaml-ownership.md) |
| 08-02 | 설정 계층은 VimActionConfig 타깃 | VimActionCore 새 타깃(VimEngine+Yams, Yams는 그 타깃에만) — headless 테스트·의존 격리 | [20260802_config-layer-vimactionconfig-target.md](references/20260802_config-layer-vimactionconfig-target.md) |
| 08-02 | disable은 매핑 값 `disabled` | disabled_actions 폐기 — motions/actions 매핑 값으로 통일, 빈 배열은 warn+무시 (actions 값 어휘는 20260802 자기 키 재정의로 부분 supersede) | [20260802_profile-disable-via-mapping-keyword.md](references/20260802_profile-disable-via-mapping-keyword.md) |
| 08-02 | 액션 자신의 키 재정의 | `actions:` 값에 시퀀스 허용 — 자기 키만 교체(모션 접두는 motions 유지), scroll은 disabled 전용 | [20260802_action-own-key-override.md](references/20260802_action-own-key-override.md) |
| 08-02 | 설정 키워드 소문자 통일 | modifier·키 이름 전부 소문자 snake_case, v1 키 11종, 대소문자 관용 없음 | [20260802_config-keyword-notation-lowercase.md](references/20260802_config-keyword-notation-lowercase.md) |
| 08-02 | 번들 기본 프로파일 동봉 | Slack·Notion 기본 프로파일 포함 — 설치 즉시 위험 해소 + 실물 예시(전달 방식은 20260802 시딩으로 부분 supersede) | [20260802_bundled-default-profiles-slack-notion.md](references/20260802_bundled-default-profiles-slack-notion.md) |
| 08-02 | scroll 재정의 값 1...200 | 스크롤은 카운트 33과 곱해지는 증폭 축 — 범위 밖은 warn+무시 | [20260802_scroll-override-bounds.md](references/20260802_scroll-override-bounds.md) |
| 08-02 | append 모션은 base를 따라감 | charRightForAppend/lineEndForAppend는 어휘 비노출 — char_right/line_end 재정의 자동 상속 | [20260802_append-motions-follow-base-override.md](references/20260802_append-motions-follow-base-override.md) |
| 08-02 | 번들 기본값은 시딩 | 병합 계층 폐기 — 없는 파일만 복사, 읽기는 사용자 파일 1계층(계층 출처 소멸), 기존 파일 미갱신 수용 | [20260802_bundled-defaults-seeded-not-merged.md](references/20260802_bundled-defaults-seeded-not-merged.md) |
| 08-02 | Package.resolved 커밋 | Yams가 첫 외부 의존 — CI·로컬 버전 고정(파싱 테스트가 Yams 해석에 의존) | [20260802_package-resolved-committed.md](references/20260802_package-resolved-committed.md) |
| 08-02 | 설정 리로드는 메뉴바 수동 트리거 | 파일 감시 폐기 — 'Reload Config' 클릭, 실패는 클릭 자리에서 가시화, 자동 감시는 재개 조건부 | [20260802_config-reload-manual-menubar-trigger.md](references/20260802_config-reload-manual-menubar-trigger.md) |
| 08-02 | 메뉴바 최전면 앱 편의 기능 2종 | bundle id 복사 + 프로파일 scaffold 생성·열기 — non-self 앱 캐시 전제, 기존 파일 무수정 | [20260802_menubar-frontmost-app-conveniences.md](references/20260802_menubar-frontmost-app-conveniences.md) |
| 08-02 | 비자신 캐시는 게이트 소유 + `@Observable` | 캐시·순수 파생을 `FrontmostAppGate`에, 판정은 계속 최전면 — 자기 활성화는 Preferences 경로에서 실측 | [20260802_frontmost-gate-non-self-cache-observable.md](references/20260802_frontmost-gate-non-self-cache-observable.md) |
| 08-02 | ConfigError 가시화·적용 의미론 | 메뉴 상태 라인 상시 + 리로드 실패만 NSAlert, 최초 로드는 부분 적용·이후 실패는 직전 유지 | [20260802_config-error-visibility-and-apply-semantics.md](references/20260802_config-error-visibility-and-apply-semantics.md) |
| 08-02 | App Icon은 Icon Composer `.icon` | legacy는 macOS 26이 회색 컨테이너에 강제 합성(실측) — appiconset 제거, 소스 벡터는 stroke가 아닌 외곽선 fill이어야 함 | [20260802_app-icon-icon-composer.md](references/20260802_app-icon-icon-composer.md) |
| 08-02 | 설정 창 열린 동안만 Dock 아이콘 | `.regular` 승격(앱 메뉴 동반 수용) — 열림=`onAppear`(창이 key가 안 됨, 실측)·닫힘=`willClose`(visible+titled+비-`NSPanel`) | [20260802_dock-icon-while-settings-open.md](references/20260802_dock-icon-while-settings-open.md) |

### 이벤트 탭 — 진입·번역·수명

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-12 | 단일 이벤트 탭 파이프라인 | 진입점은 단일 CGEventTap, 해석(엔진)과 실행(어댑터) 분리 | [20260712_single-event-tap-pipeline.md](references/20260712_single-event-tap-pipeline.md) |
| 07-12 | 합성 이벤트 마커와 안전장치 | userData 마커 + 단일 ActionExecutor로 무한 루프 방지 | [20260712_synthetic-event-marker-and-failsafe.md](references/20260712_synthetic-event-marker-and-failsafe.md) |
| 07-13 | 탭 자동복구 워치독 | 완전정지·장기스톨 대비 CGEventTapIsEnabled 주기 폴링 | [20260713_tap-reenable-watchdog-polling.md](references/20260713_tap-reenable-watchdog-polling.md) |
| 07-16 | CGEvent→Key 번역 방식 | UCKeyTranslate + ASCII 레이아웃, 번역 불가 nil=통과, @MainActor | [20260716_cgevent-key-translation-ascii-layout.md](references/20260716_cgevent-key-translation-ascii-layout.md) |
| 07-16 | KeyTranslator total function 가드 | keyDown 외 타입은 번역기 내부 가드로 nil | [20260716_keytranslator-total-function-keydown-guard.md](references/20260716_keytranslator-total-function-keydown-guard.md) |
| 07-17 | KeyTranslator 레이아웃 캐싱 | 레이아웃 Data 캐시 + 분산 노티 무효화, 실패 시 캐시 폐기 | [20260717_keytranslator-layout-caching.md](references/20260717_keytranslator-layout-caching.md) |
| 07-18 | 가로채기 마스터 토글 의미론 | off=tapEnable(false)+엔진 리셋, 설정은 컨트롤러 프로퍼티 SSOT | [20260718_interception-toggle-semantics.md](references/20260718_interception-toggle-semantics.md) |
| 07-19 | 워치독 스톨 게이트 | 워치독은 스톨 종료 후 복구 전담 — 스톨 중 재활성화 보류 | [20260719_watchdog-stall-gate-post-stall-recovery.md](references/20260719_watchdog-stall-gate-post-stall-recovery.md) |
| 07-19 | Secure Input 전용 상태 | OS 억제는 전용 상태로 표시, 우선순위 고장>토글off>SEI | [20260719_secure-input-status.md](references/20260719_secure-input-status.md) |
| 07-25 | 탭 메인 런루프 유지 확정 | 전용 스레드 전환 기각(3-에이전트 리뷰), 재검토 트리거 3종 명시 | [20260725_tap-main-runloop-retention.md](references/20260725_tap-main-runloop-retention.md) |
| 07-25 | 콜백 경량 불변식 | 탭 콜백 동기 구간은 번역+엔진 step+캐시 읽기로 제한 | [20260725_callback-light-invariant.md](references/20260725_callback-light-invariant.md) |
| 07-25 | 마커 가드는 콜백 최우선 판정 | 마커 확인은 handleKeyDown 최상단 — 상태 무관 불변식 | [20260725_marker-guard-highest-precedence.md](references/20260725_marker-guard-highest-precedence.md) |
| 07-26 | Secure Input은 배달만 억제 | 실측 — SEI는 활성화를 안 막음, .secureInput은 .failed 하위 구분으로 재정의 | [20260726_secure-input-suppresses-delivery-not-enablement.md](references/20260726_secure-input-suppresses-delivery-not-enablement.md) |

### 엔진 — 모드·문법·취소

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-12 | 순수 Swift 모드 엔진 | 모드 엔진은 macOS 의존성 없는 별도 SPM 타깃 | [20260712_pure-swift-mode-engine.md](references/20260712_pure-swift-mode-engine.md) |
| 07-12 | Key 표현·픽스처 포맷 | Key는 base+modifiers(shift는 문자에 흡수), 픽스처는 Swift 테이블 | [20260712_key-representation-and-fixture-format.md](references/20260712_key-representation-and-fixture-format.md) |
| 07-12 | pending 무효 시퀀스 no-op | pending 후 무효 키는 둘 다 버림, 타임아웃 없음 (Vim 동일) | [20260712_pending-invalid-sequence-noop.md](references/20260712_pending-invalid-sequence-noop.md) |
| 07-12 | 미매핑 modifier 조합 passthrough | 매핑 없는 Cmd/Ctrl/Opt 조합은 통과 — 시스템 단축키 보존 | [20260712_unmapped-modifier-passthrough.md](references/20260712_unmapped-modifier-passthrough.md) |
| 07-14 | 멀티키 커맨드 문법 빌더 | pending은 부분 파스 상태, resolve는 extend/complete/cancel 스텝 | [20260714_multikey-command-grammar-builder.md](references/20260714_multikey-command-grammar-builder.md) |
| 07-14 | Normal 모드 modifier 탈출 옵션 | 미매핑 콤보는 pending 폐기+Insert 탈출+통과, Ctrl 제외, 기본 on | [20260714_normal-mode-escape-modifiers.md](references/20260714_normal-mode-escape-modifiers.md) |
| 07-17 | 취소 최우선 순서의 전제 | 탈출 콤보 선행은 modifier 매핑 부재가 전제 (Esc swallow는 20260801 부분 supersede) | [20260717_cancellation-first-ordering-premise.md](references/20260717_cancellation-first-ordering-premise.md) |
| 07-24 | Ctrl 매핑 취소 충돌 해소 | 매핑된 Ctrl 콤보만 탈출 판정 제외 — 테이블 파생 단일 소스 | [20260724_ctrl-combo-mapped-exception-cancellation.md](references/20260724_ctrl-combo-mapped-exception-cancellation.md) |
| 07-24 | Ctrl-[ Esc 별칭 | handle() 초입에서 Esc로 치환 — 세 모드 완전 별칭, 엔진 정규화 | [20260724_ctrl-bracket-escape-normalization.md](references/20260724_ctrl-bracket-escape-normalization.md) |
| 08-01 | Normal 빈 상태 Esc는 passthrough | pending 있으면 폐기+swallow, 없으면 통과 — Esc 연타로 앱에 취소 전달 | [20260801_normal-esc-passthrough-when-empty.md](references/20260801_normal-esc-passthrough-when-empty.md) |

### 엔진 — 출력 계약 (VimAction 어휘)

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-12 | append 전용 Motion 케이스 | a/A는 전용 케이스 — 어댑터가 l·$와 줄 끝 시맨틱 구분 | [20260712_append-dedicated-motion-cases.md](references/20260712_append-dedicated-motion-cases.md) |
| 07-17 | 편집 출력 형태 | .edit(Operator, TextRange) 확정 — 모션 카운트는 반복, 에디트 카운트는 값 | [20260717_vimaction-edit-output-shape.md](references/20260717_vimaction-edit-output-shape.md) |
| 07-19 | change의 Insert 전이 | change 완결 시 엔진 즉시 Insert 전이, cw→ce 특례는 어댑터 몫 | [20260719_change-insert-transition-and-cw-deferral.md](references/20260719_change-insert-transition-and-cw-deferral.md) |
| 07-19 | TextObject quote·pair 확장 | kind 케이스+Scope 연관값, 카운트+오브젝트는 invalid | [20260719_textobject-quote-pair-expansion.md](references/20260719_textobject-quote-pair-expansion.md) |
| 07-19 | linewise TextRange | additive .linewiseMotion — 상대만 카운트, 절대+카운트는 invalid | [20260719_linewise-textrange-absolute-count-invalid.md](references/20260719_linewise-textrange-absolute-count-invalid.md) |
| 07-19 | 오퍼레이터 모션 단일 테이블 | opMotion은 kind 딸린 단일 테이블로 통합, gg만 prefix | [20260719_opmotion-unified-dispatch-table.md](references/20260719_opmotion-unified-dispatch-table.md) |
| 07-22 | Visual 모드 출력 계약 | extendSelection·beginSelection(linewise:)·clearSelection 신설, 앵커·범위는 어댑터 상태 | [20260722_visual-mode-output-contract.md](references/20260722_visual-mode-output-contract.md) |
| 07-22 | Visual 진입 pending 상호작용 | 특례 없음 — 3v는 카운트 무시, dv는 invalid no-op | [20260722_visual-entry-pending-interaction.md](references/20260722_visual-entry-pending-interaction.md) |
| 07-23 | Visual 진입/전환 신호 분리 | beginSelection은 앵커 리셋, v↔V 전환은 switchSelectionWise 신설 | [20260723_visual-begin-reset-switch-wise-split.md](references/20260723_visual-begin-reset-switch-wise-split.md) |
| 07-23 | Visual y의 clearSelection 동반 | y는 [edit(yank), clearSelection] — 잔류 선택 collapse 고정, d/x/c는 미동반 | [20260723_visual-yank-clear-selection.md](references/20260723_visual-yank-clear-selection.md) |
| 07-23 | Visual 카운트+오퍼레이터 실행 | 3d 등 선행 카운트는 버리고 즉시 실행 (Vim 동일) | [20260723_visual-count-operator-executes.md](references/20260723_visual-count-operator-executes.md) |
| 07-23 | openLine(o/O) 출력 계약 | openLine(above:)+Insert 전이, 카운트 무시 | [20260723_openline-output-contract.md](references/20260723_openline-output-contract.md) |
| 07-23 | paste(p/P) 출력 계약 | paste(before:count:) — wise 판정은 어댑터 몫, v1 레지스터 없음 | [20260723_paste-output-contract.md](references/20260723_paste-output-contract.md) |
| 07-23 | undo(u) 출력 계약 | 네이티브 undo 위임, 카운트는 반복 출력, Ctrl-r은 이연 | [20260723_undo-output-contract.md](references/20260723_undo-output-contract.md) |
| 07-24 | 스크롤·redo 출력 계약 | scroll(ScrollExtent, forward:)·redo 신설 — 카운트 반복, Normal 전용 | [20260724_scroll-redo-output-contract.md](references/20260724_scroll-redo-output-contract.md) |
| 07-31 | 카운트 클램프 1,000 하향 | 기준을 "일상 사용 상한"으로 전환 — 폭주 총량 1/10 안전 마진 | [20260731_count-clamp-lowered-to-1000.md](references/20260731_count-clamp-lowered-to-1000.md) |
| 08-01 | D/C 어휘 추가 | d$/c$ 축약 즉시 완결 — 동일 출력, 3D는 invalid | [20260801_line-end-shorthand-d-c.md](references/20260801_line-end-shorthand-d-c.md) |
| 08-01 | 스크롤 카운트 상한 33 | 스크롤만 수십 타 증폭이라 전용 상한 — 클램프 1,000 우회 차단 | [20260801_scroll-count-clamp-33.md](references/20260801_scroll-count-clamp-33.md) |

### 킬스위치·폭주 방어

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-25 | 예외 폭주 자동 off | 시간 주입 순수 카운터(1초/5회), 효과는 소프트 off didSet 재사용 | [20260725_failure-burst-autodisable-shape.md](references/20260725_failure-burst-autodisable-shape.md) |
| 07-26 | 킬스위치 탭은 전용 스레드 | 전용 Thread+자체 CFRunLoop — 메인 스톨 중 배달 보장 | [20260726_kill-switch-dedicated-runloop-thread.md](references/20260726_kill-switch-dedicated-runloop-thread.md) |
| 07-26 | 킬스위치 탭 위치·폴백 | HID 능동 탭 우선 + 세션 폴백, 설치 순서가 계약 (비루트 HID 실측) | [20260726_kill-switch-hid-tap-session-fallback.md](references/20260726_kill-switch-hid-tap-session-fallback.md) |
| 07-26 | 킬스위치 발동 의미론 | 단방향 off + 2겹 효과 + 킬 요청 래치 (오토리핏 가드는 20260801 부분 supersede) | [20260726_kill-switch-trigger-semantics.md](references/20260726_kill-switch-trigger-semantics.md) |
| 07-26 | 실행 실패 보고 단위 | 보고는 원인 키 입력 1건당 최대 1회 — 어댑터가 시퀀스 실패를 폴딩 | [20260726_execution-failure-report-granularity.md](references/20260726_execution-failure-report-granularity.md) |
| 07-26 | 킬 콤보 삼킴은 발동과 독립 | 오토리핏 콤보도 삼킴 (술어 분리·미발동은 20260801 부분 supersede) | [20260726_kill-combo-swallow-independent-of-fire.md](references/20260726_kill-combo-swallow-independent-of-fire.md) |
| 07-26 | 킬스위치 off 영속은 홉과 독립 | 킬 경로 직접 영속 — SIGKILL 생존 실측 | [20260726_kill-switch-off-persistence-off-main.md](references/20260726_kill-switch-off-persistence-off-main.md) |
| 07-26 | 킬 탭 활성화 검증·강등 | tapEnable 뒤 tapIsEnabled 검증, 실패 시 fault + failed 강등 | [20260726_kill-tap-enable-verification.md](references/20260726_kill-tap-enable-verification.md) |
| 07-26 | 미지원 액션은 실패 아님 | 실패 의미론은 "실행 시도 후 깨짐"으로 한정 — 미구현은 스킵+로그 | [20260726_unsupported-action-not-failure.md](references/20260726_unsupported-action-not-failure.md) |
| 07-30 | 실행 중단 래치는 세대 카운터 | beginRun() 세대 비교, 해제 API 없음, 무효화 3주체, 마커 가드 뒤 | [20260730_execution-abort-generation-latch.md](references/20260730_execution-abort-generation-latch.md) |
| 07-30 | 청크 게시 + 페이싱 | 8타 청크·첫 청크 즉시·이후 2ms, 원자 그룹 3종 | [20260730_chunked-posting-with-pacing.md](references/20260730_chunked-posting-with-pacing.md) |
| 08-01 | 킬 콤보 오토리핏도 발동 | shouldFire 제거 — 삼킨 콤보는 전부 발동, 1회성은 래치 test-and-set | [20260801_kill-combo-autorepeat-fires.md](references/20260801_kill-combo-autorepeat-fires.md) |

### 실행 계층 — 배선·매퍼·키 시퀀스

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-25 | Keyboard-first MVP 빌드 순서 | 실행은 Keyboard 어댑터 먼저, AX+auto는 이후 (디스패치 구조 불변) | [20260725_keyboard-first-mvp-build-order.md](references/20260725_keyboard-first-mvp-build-order.md) |
| 07-26 | ActionExecutor 격리·게시 계약 | nonisolated+Sendable, 이벤트는 post 호출자와 같은 직렬 큐에서 생성 | [20260726_action-executor-nonisolated-sendable.md](references/20260726_action-executor-nonisolated-sendable.md) |
| 07-26 | M2 앱 게이트는 엔진 전 통과 | disable 앱은 번역·엔진 전 원본 통과+모드 동결, bundleID는 알림 캐시 | [20260726_m2-app-gate-pre-engine-passthrough.md](references/20260726_m2-app-gate-pre-engine-passthrough.md) |
| 07-26 | M2 실행 배선 형태 | 컨트롤러는 주입된 sink 클로저만 안다, 테스트에선 무해 바꿔치기 | [20260726_m2-execution-wiring-shape.md](references/20260726_m2-execution-wiring-shape.md) |
| 07-26 | 모션 키스트로크 매핑 계약 | 순수 매퍼 Motion→[KeyStroke], 배열 반환이 계약 | [20260726_motion-keystroke-mapping-contract.md](references/20260726_motion-keystroke-mapping-contract.md) |
| 07-26 | w·^(I) 매핑 3타 조합 | 단어 끝 지나친 뒤 시작 복귀 — 수용 엣지 3종 기록 | [20260726_word-forward-first-nonblank-multi-stroke.md](references/20260726_word-forward-first-nonblank-multi-stroke.md) |
| 07-27 | 편집 키스트로크 매핑 계약 | EditKeyMapper (op,range,family)→[KeyStroke]? — Shift 선택 후 오퍼레이터 1타 | [20260727_edit-keystroke-mapping-contract.md](references/20260727_edit-keystroke-mapping-contract.md) |
| 07-27 | linewise 개행 반올림 | delete/yank는 개행 포함·change는 줄 유지, 문서 끝 빈 줄 수용 | [20260727_linewise-newline-rounding.md](references/20260727_linewise-newline-rounding.md) |
| 07-27 | yank collapse는 왼쪽 | Cmd-C 뒤 ← 1타로 범위 시작에 붙임 — 방향 분기 불필요 | [20260727_yank-collapse-to-range-start.md](references/20260727_yank-collapse-to-range-start.md) |
| 07-27 | 오퍼레이터 키 ANSI 고정 | Cmd-X/C는 ANSI 키코드 고정 = QWERTY 가정, 역조회 이연 | [20260727_operator-key-ansi-layout-assumption.md](references/20260727_operator-key-ansi-layout-assumption.md) |
| 07-27 | iw 앵커는 단어 끝 경유 3타 | Opt-← 1타는 앞 단어 삭제 위험 — ^와 같은 복귀 패턴으로 교체 (수용 엣지는 20260803 부분 supersede, 3타는 읽기 실패 시 상시 경로) | [20260727_inner-word-anchor-via-word-end.md](references/20260727_inner-word-anchor-via-word-end.md) |
| 07-30 | 명령 매퍼 신설 | CommandKeyMapper(o/O·p/P·u/Ctrl-r·스크롤) — 네이티브 위임 계열, NSPasteboard는 주입 seam | [20260730_command-key-mapper-scope.md](references/20260730_command-key-mapper-scope.md) |
| 07-30 | o/O 시퀀스 | o=Cmd-→,Return / O=Cmd-←,Return,↑ — 수용 엣지 4종 | [20260730_openline-return-sequence.md](references/20260730_openline-return-sequence.md) |
| 07-30 | paste wise 끝 개행 휴리스틱 | 클립보드 끝 개행으로 charwise/linewise, linewise p는 꼬리 보정 | [20260730_paste-wise-trailing-newline-heuristic.md](references/20260730_paste-wise-trailing-newline-heuristic.md) |
| 07-30 | 스크롤은 화살표 반복 | 페이지 키는 죽은 기능(실측) — ↓/↑ 반복(half 15·full 30) | [20260730_scroll-arrow-repetition.md](references/20260730_scroll-arrow-repetition.md) |
| 07-30 | paste wise는 우리 편집을 기억 | 줄 단위 편집을 changeCount와 기억 — 휴리스틱은 외부 복사 전담으로 강등 (기억 대상 한정은 20260806 부분 supersede) | [20260730_paste-wise-from-our-own-edit.md](references/20260730_paste-wise-from-our-own-edit.md) |
| 08-01 | 비-QWERTY 레이아웃 가드 | 행동 검사(Z/X/C/V 번역 확인)로 판별, 문자 명령 키 액션 보류(layoutBlocked) | [20260801_non-qwerty-command-key-layout-guard.md](references/20260801_non-qwerty-command-key-layout-guard.md) |
| 08-02 | 프로파일 재정의 전파는 조회 전면 | 단일 지점=MotionKeyMapper(옵셔널) — 명령 접두·yank collapse까지 전파, disabled는 복합 통째 스킵 + .disabledByProfile 분류 | [20260802_profile-override-propagation-full-lookup.md](references/20260802_profile-override-propagation-full-lookup.md) |
| 08-06 | paste wise 기억은 편집 전반 | 클립보드 쓰기 편집 전부 기록(change=charwise 포함) — 휴리스틱은 외부 복사 전담, 델타-1 불변 | [20260806_paste-wise-memory-covers-all-edits.md](references/20260806_paste-wise-memory-covers-all-edits.md) |
| 08-06 | `.selection` wise는 확정 스트림 추적 | 게시 확정된 begin/switch의 wise를 PasteWiseResolver가 note — 화면 진실 추적(엔진 확장·앵커 병합 기각) | [20260806_selection-wise-from-confirmed-stream.md](references/20260806_selection-wise-from-confirmed-stream.md) |

### 실행 계층 — Visual 시퀀스

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-28 | charwise Visual 진입은 1문자 선택 | v는 Shift-→ 1타 즉시 선택 — inclusive 시맨틱 | [20260728_visual-charwise-entry-inclusive-selection.md](references/20260728_visual-charwise-entry-inclusive-selection.md) |
| 07-28 | Visual 확장은 무상태 | extendSelection은 모션+Shift가 전부 — linewise 반올림 미적용 (앵커 상태·linewise 스킵은 20260804 부분 supersede — 무상태는 읽기 실패 폴백 전담) | [20260728_visual-extend-stateless-no-linewise-rounding.md](references/20260728_visual-extend-stateless-no-linewise-rounding.md) |
| 07-28 | switchSelectionWise 반올림 | v→V는 포커스 끝만 반올림, V→v는 역연산 없어 nil 스킵 (20260804 부분 supersede — 앵커 반올림·조건부 V→v, 현행 시퀀스는 폴백) | [20260728_visual-switch-wise-focus-end-rounding.md](references/20260728_visual-switch-wise-focus-end-rounding.md) |
| 07-28 | Visual collapse는 ← 1타 단일화 | clearSelection이 collapse 전담, .selection yank는 Cmd-C만 | [20260728_visual-clear-selection-collapse-left.md](references/20260728_visual-clear-selection-collapse-left.md) |
| 08-04 | Visual 후진은 키보드 재앵커 | 접고 재확장(side 모델) — 후진형은 원점 이동 없음, 크로싱은 수용 엣지, AX 쓰기 기각 (접두는 08-05 단축으로 부분 supersede) | [20260804_visual-backward-keyboard-reanchor.md](references/20260804_visual-backward-keyboard-reanchor.md) |
| 08-04 | 앵커 상태는 게시 큐 협력자 | PasteWiseResolver 동형 주입 — 앵커·wise·side·pid·원캐럿, 수립은 진입 게시 직전 읽기 | [20260804_visual-anchor-state-collaborator.md](references/20260804_visual-anchor-state-collaborator.md) |
| 08-04 | 앵커 무효화는 읽기 자가 검증 | 앵커 쪽 끝+pid 비교, 전용 신호 없음 — 헛실패 방향이 현행 강등이라 안전 | [20260804_visual-anchor-read-self-validation.md](references/20260804_visual-anchor-read-self-validation.md) |
| 08-04 | V→v는 조건부 지원 | 원캐럿+줄 거리 다 알 때만 재선택(위치 상대), 모르면 현행 nil 유지 | [20260804_visual-switch-charwise-conditional.md](references/20260804_visual-switch-charwise-conditional.md) |
| 08-04 | V 세션 charwise 모션은 스킵 | wise 알면 h l w b e 0 ^ $ 무게시(.skipped) — Vim 범위 무변화가 정확, desync는 무해 no-op | [20260804_visual-linewise-motion-range-noop.md](references/20260804_visual-linewise-motion-range-noop.md) |
| 08-05 | 정확화 그룹 한정 스트로크 페이싱 | refined 다타 그룹만 스트로크 사이 5ms(Notion 버스트 드롭 실측) — 스크롤·카운트·폴백은 타이밍까지 현행 | [20260805_visual-refined-group-stroke-pacing.md](references/20260805_visual-refined-group-stroke-pacing.md) |
| 08-05 | 재앵커 접두는 collapse 1타 | `←,→`·`←,↓` → `→`(선택 존재 시 동치, 코드 경로 보장) — 깨지는 앱 발견 시 2타 복귀 | [20260805_reanchor-prefix-collapse-shortcut.md](references/20260805_reanchor-prefix-collapse-shortcut.md) |

### 수용 엣지 — 도그푸딩 실측 (대부분 M4 프로파일·M5 AX가 해소 예정)

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-26 | Shift 새어 들어감 종결 | 이벤트 flags 명시 대입으로 충분 — 전역 채널 기각, 재발 시 재개 | [20260726_shift-leak-event-flags-sufficient.md](references/20260726_shift-leak-event-flags-sufficient.md) |
| 07-26 | 탭 들여쓰기 ^·I 엣지 | Chromium 계열 퇴행 수용 — 고정 시퀀스 부재, M5 AX 해소 | [20260726_tab-indent-first-nonblank-chromium-edge.md](references/20260726_tab-indent-first-nonblank-chromium-edge.md) |
| 07-26 | undo 단위 실측 — u=Cmd-Z 유지 | 합성 시퀀스는 1 undo 단위 실증, change만 분리 수용 | [20260726_undo-unit-cmdz-policy.md](references/20260726_undo-unit-cmdz-policy.md) |
| 07-27 | Notion Shift-Cmd-↑/↓ 충돌 수용 | 블록 이동 충돌로 6조합 파괴적 오동작 — M4 프로파일이 해소 | [20260727_notion-cmd-shift-vertical-conflict.md](references/20260727_notion-cmd-shift-vertical-conflict.md) |
| 07-28 | linewise 시각 줄 엣지 | 소프트 랩에서 dd/cc가 화면 행 단위 — 창 읽기로는 해소 불가(20260803), 단락 바인딩 실측이 재개 조건 | [20260728_linewise-visual-line-wrap-accepted-edge.md](references/20260728_linewise-visual-line-wrap-accepted-edge.md) |
| 07-28 | charwise Visual 후진 원점 이동 | 진입 Shift-→가 원점을 P+1로 — vb·vh 빈 선택 (수용 결정은 20260804 재앵커로 부분 supersede — 읽기 실패 폴백만 잔존) | [20260728_visual-charwise-backward-origin-shift.md](references/20260728_visual-charwise-backward-origin-shift.md) |
| 07-30 | 명령 어휘 비텍스트 UI 발사 | Finder p=파일 붙여넣기 등 — 도그푸딩 규율 추가, 리졸버가 구조적 해소 | [20260730_native-command-non-text-ui-hazard.md](references/20260730_native-command-non-text-ui-hazard.md) |

### 전략 디스패치·요소 리졸버

| Date | Title | 요약 | Reference |
|---|---|---|---|
| 07-12 | AX/Keyboard 전략 디스패치 | 앱별 프로파일 + AX 자동 감지로 전략 선택, force-text는 명시 전용 | [20260712_ax-keyboard-strategy-dispatch.md](references/20260712_ax-keyboard-strategy-dispatch.md) |
| 08-01 | TextField 전용 편집 시퀀스 폐기 | .textField도 TextArea 시퀀스 — 전용 분기는 role 오보고 시 개악 | [20260801_textfield-edit-sequences-scrapped.md](references/20260801_textfield-edit-sequences-scrapped.md) |
| 08-01 | 리졸버 폴백은 .textArea | AX 실패·타임아웃·미지 role은 전부 .textArea — 걸러내기는 확실할 때만 | [20260801_resolver-fallback-defaults-to-text-area.md](references/20260801_resolver-fallback-defaults-to-text-area.md) |
| 08-01 | 계열 판별자는 AXSelectedTextRange 노출 | role 화이트리스트 붕괴(실측) — 속성 이름 목록만 유효, role은 Area/Field 구분만 | [20260801_element-family-classification-table.md](references/20260801_element-family-classification-table.md) |
| 08-01 | focusedRole 캐시 — AX는 메인 밖 | 읽기는 전용 큐 50ms(3ms 캡은 콜드 6/6 실패), 계열은 키 입력 시점 스냅샷 | [20260801_focused-role-cache-shape.md](references/20260801_focused-role-cache-shape.md) |
| 08-01 | 앱 전환 직후는 미확정 창 | 레이스 실증 — 4번째 케이스 .unresolved, 걸러내기는 nonText와 같은 편 | [20260801_unresolved-window-after-app-switch.md](references/20260801_unresolved-window-after-app-switch.md) |
| 08-01 | 캐시 충분성 1차 확정 | 라이브 AX 읽기 필요 케이스 없음 — 갱신 2경로 실측, M5에서 재확인 | [20260801_cache-only-callback-confirmed-sufficient.md](references/20260801_cache-only-callback-confirmed-sufficient.md) |
| 08-01 | 비텍스트 걸러내기 범위 | .nonText 스킵은 편집·Visual·명령 위임만 — move·scroll 유지, 게이트는 어댑터 1곳 | [20260801_non-text-filter-keeps-motion-and-scroll.md](references/20260801_non-text-filter-keeps-motion-and-scroll.md) |
| 08-02 | 디스패치 경로 AX 읽기 형태 | 게시 큐 위 lazy 읽기(콜백·메인 무접촉 유지), 창 프리미티브(AXValue 전체 금지), 실패는 무상태 폴백 | [20260802_dispatch-read-on-posting-queue.md](references/20260802_dispatch-read-on-posting-queue.md) |
| 08-02 | AX 타임아웃 50ms 단일 상수 | 3ms 캡 supersede(웜 Notion 16ms 실측) — 탭을 지키는 건 캡 값이 아니라 배치, 실패 반환 캡+2ms 바운드 확인 | [20260802_ax-read-timeout-50ms-supersedes-3ms.md](references/20260802_ax-read-timeout-50ms-supersedes-3ms.md) |
| 08-02 | 캐럿 주변 읽기 API 모양 | `FocusedText` 4필드(`windowRange` 필수), 창 ±256 고정, pid 출처는 리졸버(게이트 아님), 실패는 액션 단위로 기억되는 단일 nil | [20260802_focused-text-read-api-shape.md](references/20260802_focused-text-read-api-shape.md) |
| 08-02 | 읽기 소비는 매퍼 술어 2함수 | `keyStrokes`에 text를 넣지 않는다(nil 의미 중첩·classify 3프로브·사유 모르는 자리의 로그) — `consultsFocusedText`/`collapsesToNothing`이 값을 받고, cw 리타깃은 시퀀스와 같은 함수를 공유 | [20260802_read-consumption-via-mapper-predicates.md](references/20260802_read-consumption-via-mapper-predicates.md) |
| 08-02 | 0폭 포화 편집 억제 (엣지 5 해소) | 증명된 6종만 액션 통째 스킵(`.skipped` 재사용), 카운트 규칙 없음 — w·^·줄 경계·`.selection`은 각각 다른 이유로 보류 (charRight/문서 끝 행은 20260803 부분 supersede) | [20260802_empty-selection-edit-suppression.md](references/20260802_empty-selection-edit-suppression.md) |
| 08-03 | 재조립은 분기의 근거만 (레이스) | 읽기로 시퀀스를 고르되 스트로크 수는 정하지 않는다 — 낡은 읽기의 최악이 현행 동작을 넘지 않게, 오프셋 비례 스트로크 금지 | [20260803_refinement-branches-not-stroke-counts.md](references/20260803_refinement-branches-not-stroke-counts.md) |
| 08-03 | `keyStrokes(text:)` + 3-프로브 | 재조립이 시그니처를 바꾼다 — `collapsesToNothing` 접힘, 편집 전용 `classifyEdit`이 프로브 순서를 구조로 강제(텍스트→builtIn, builtIn은 text 미수신) | [20260803_edit-keystrokes-takes-focused-text.md](references/20260803_edit-keystrokes-takes-focused-text.md) |
| 08-03 | 경계 포화 정확화 표 (엣지 2·3·4·`^`) | 첫 줄 `dk`·첫 비공백 `^`는 무효 스킵, 마지막 단어 `dw`는 `e` 1타, 마지막 줄 `dgg`는 `cgg` 접두 재사용 — 읽기를 묻는 범위는 최소로만 확장 | [20260803_boundary-saturation-refinement-table.md](references/20260803_boundary-saturation-refinement-table.md) |
| 08-03 | 줄 끝 charwise = Vim 커서 모델 (엣지 1) | 줄 끝 `x`는 `Shift-←`로 마지막 글자 삭제(그 한 자리로 범위 한정), 빈 줄은 무효, 아니면 clamp — 문서 끝 억제를 덮어씀. 유일하게 "현행 이하"가 아닌 재조립 (모션 밖 확대 금지 한정은 20260803 단어 어휘로 부분 완화) | [20260803_line-end-charwise-vim-cursor-model.md](references/20260803_line-end-charwise-vim-cursor-model.md) |
| 08-03 | 소프트 랩은 창 읽기로 해소 불가 | 증명 실패(랩 문단 > 창 반경)·중단 불가 원자 그룹·낡은 오프셋 셋 — 수용 엣지 유지, `dd`·`dj`는 읽기 0건. 단락 바인딩 실측이 재개 조건 | [20260803_soft-wrap-linewise-not-resolved-by-window-read.md](references/20260803_soft-wrap-linewise-not-resolved-by-window-read.md) |
| 08-03 | 단어 질의는 로컬 술어 (오프셋 없음) | Vim 런 4클래스(blank/keyword/punctuation/other, 개행은 종결자) + 캐럿 ±1자 술어 3종 — 오프셋을 안 쓰니 `Opt-→` 정합·잘린 단어 난점이 소멸 | [20260803_word-run-local-predicates-no-offsets.md](references/20260803_word-run-local-predicates-no-offsets.md) |
| 08-03 | `iw`·`cw` 재조립은 상수 1타 | 스트로크 수 원칙 예외 없이 유지 — 1자 런/런 끝만 1타로 정확화, 낡은 읽기 최악이 현행보다 작아지고 원자 그룹도 4타→2타. `cw`와 진짜 `ce`·`de`는 리타깃 플래그로 갈림 | [20260803_constant-stroke-word-refinement.md](references/20260803_constant-stroke-word-refinement.md) |
| 08-03 | 줄 끝 커서 모델을 `iw`·`cw`로 완화 | 줄 끝 = 커서가 마지막 글자 위 — `iw`는 `Shift-Opt-←`(키워드 한정), `cw`는 `Shift-←`. 완화가 단어 어휘 안에서 닫히는 것이 근거(모션은 캐럿 모델 유지) | [20260803_line-end-cursor-model-for-word-objects.md](references/20260803_line-end-cursor-model-for-word-objects.md) |

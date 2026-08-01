# MVP 1단계 마일스톤 (Keyboard 베이스)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-25
- **갱신일**: 2026-08-01 (**M3 종료 — 릴리스 금지 게이트 해제**([결정](../../decisions/references/20260801_release-block-gate-lifted.md)). 다음은 M4 프로파일 = MVP 완료선)

## 목표

"실제 사용 가능한" MVP 1단계 = **M4 완료**: 주력 앱(Electron 포함)에서 Keyboard 전략으로 전체 v1 어휘가 실행되고, 프로파일로 앱별 on/off가 제어되는 상태. M5(AX)는 MVP 이후 1차 확장. 순서 근거: [keyboard-first 결정](../../decisions/references/20260725_keyboard-first-mvp-build-order.md).

이 문서가 마일스톤 SSOT다 — 워크스페이스 `docs/roadmap.md`·PRD §11의 Stage 구분은 더 이상 참조하지 않는다 (엔진이 이미 초과 달성해 낡음). PRD의 나머지(§7 어휘, §7.4 스키마, §9 선택 알고리즘)는 범위 SSOT로 유지.

## 완료된 것

- [x] (선행 상태) 엔진 v1 어휘 전체 + 탭 인프라(KeyTranslator·워치독·토글·Secure Input·모드 글리프·TCC 온보딩) + 콜백 경량 불변식 확정 — 남은 것은 전부 실행 계층
- [x] **M1 세션 A — 출력 인프라 3종** (PR #17 병합, `f2040fd`): `ActionExecutor`(마커를 찍는 유일한 지점, 게시 프리미티브까지만) + 탭측 마커 가드(`handleKeyDown` 최우선 판정) + 폭주 카운터(`FailureBurstCounter` 1초/5회) 및 `reportExecutionFailure` 훅. 유닛 테스트 62건 GREEN. 아직 **호출자 없음** — 게시·실패 보고 배선은 M2. 리뷰에서 보고 단위 계약([20260726](../../decisions/references/20260726_execution-failure-report-granularity.md))이 추가로 확정됐다.
- [x] **M1 세션 B — 킬스위치** (PR #18 병합, `a91bcda`) → **M1 종료**: `KillSwitchTap`(HID 능동 탭 + 전용 스레드 런루프, 세션 폴백 1단) + `triggerKillSwitch` 2겹 발동 + 킬 요청 래치 + Settings 상태·안내 행. 실기기 확인 완료(비루트 HID 생성 성공, 발동·삼킴·오토리핏·래치 전부 정상). 결정 3건: [전용 스레드](../../decisions/references/20260726_kill-switch-dedicated-runloop-thread.md), [탭 위치·폴백](../../decisions/references/20260726_kill-switch-hid-tap-session-fallback.md), [발동 의미론](../../decisions/references/20260726_kill-switch-trigger-semantics.md).
- [x] **M1 세션 B 후속 — 코드리뷰 반영** (같은 PR #18): 서브에이전트 재검증으로 리뷰 10건 중 절반의 판정이 뒤집혔고, 살아남은 것만 고쳤다. 삼킴/발동 술어 분리, off 영속을 메인 홉과 분리, 킬 탭 활성화 검증 + `Installation.failed`, 종료 경합 nil 가드, 킬 탭 설치 재시도 훅(`onTapInstalled`), 래치 회귀 테스트(가드 삭제 시 실제로 RED 확인), SEI 모델 정정. 결정 4건 추가: [삼킴/발동 분리](../../decisions/references/20260726_kill-combo-swallow-independent-of-fire.md), [홉 무관 영속](../../decisions/references/20260726_kill-switch-off-persistence-off-main.md), [활성화 검증](../../decisions/references/20260726_kill-tap-enable-verification.md), [SEI는 배달만 억제](../../decisions/references/20260726_secure-input-suppresses-delivery-not-enablement.md).
- [x] **M2 선행 — `ActionExecutor` Swift 6 동시성 정리** (PR #19 병합, `aaf637c`): `SyntheticEventMarker`·`ActionExecutor`를 타입 단위 `nonisolated` + 명시적 `Sendable`로, 게시 클로저는 `@Sendable (CGEvent) -> Void`로 바꿨다. 기능 변화 0, 테스트 변경 0(수집기의 기존 `nonisolated(unsafe)` 캡처가 그대로 컴파일됐다). **빌드 경고 4건 → 0건**, 테스트 GREEN, Swift 6 프로브에서 `ActionExecutor.swift` 진단 0건. Copilot 리뷰 코멘트 0건. 결정: [ActionExecutor 격리·게시 클로저 계약](../../decisions/references/20260726_action-executor-nonisolated-sendable.md).
- [x] **M2 종료 — Keyboard 어댑터 ① 모션** (PR #20 `0eb2187` + PR #21 `bd643e1` 병합): 세션 A가 순수 실행 계층(`MotionKeyMapper`·`KeyboardAdapter`), 세션 B가 앱 게이트(`FrontmostAppGate`)와 실행 배선을 붙였다. 이동 계열이 실제 앱에서 캐럿을 움직이고 disable 앱(Ghostty)은 완전 통과하며, 실기기 도그푸딩으로 게이트 전이·모션 디스패치(`10w` 카운트 포함)·미지원 스킵·실패 보고 0건을 확인했다. 릴리스 배포 금지 게이트는 M3로 이동([결정](../../decisions/references/20260726_release-block-gate-moves-to-m3.md)). **매핑 정확도 후속도 종료** (PR #23 `4f2dd65` 병합): w·^(I)를 3타 조합으로 교체([결정](../../decisions/references/20260726_word-forward-first-nonblank-multi-stroke.md)), Shift 누출은 미재현·기존 flags 명시 대입으로 종결([결정](../../decisions/references/20260726_shift-leak-event-flags-sufficient.md)), 탭 들여쓰기 ^·I의 Chromium 퇴행 엣지는 수용([결정](../../decisions/references/20260726_tab-indent-first-nonblank-chromium-edge.md)). 실기기 재검증 완료 — M2 상세 플랜은 완료 정리로 삭제됨.

## 남은 것
- [x] **M3 종료 — Keyboard 어댑터 ② 편집 + Visual + 요소 리졸버** (PR #24~#29 병합 + 단계 4): v1 어휘 전체가 실행되고, 실행 중단 래치가 버스트를 끊으며, 요소 리졸버가 비텍스트 UI에서 편집·명령을 걸러낸다. 단계 4에서 안전망 회귀(킬 콤보 오토리핏 발동 수정 포함)·무로그 삼킴 0건 전수 확인·위험 심사 4건(레이아웃 가드·스크롤 클램프 33 구현 포함) 종결 — **릴리스 금지 게이트 해제**([결정](../../decisions/references/20260801_release-block-gate-lifted.md)). 요소 계열(TextArea/TextField)별 편집 시퀀스, AXObserver 포커스 캐시(focusedRole), y/p/u=Cmd-C/V/Z, 스크롤 실행. 어댑터 위임 계약 이행처: cw→ce 특례, paste charwise/linewise 판정, linewise 줄 반올림, append 줄 끝 시맨틱, Visual y 후 collapse. 확인 항목: 합성 시퀀스의 undo 단위 쪼개짐 실측, 캐시 충분성 1차 확정(콜백 경량 불변식 위임 ②). 되면: 주력 앱에서 편집 실사용 — 도그푸딩 본편.
- [ ] **M4 — 프로파일 배관 + 앱별 on/off** ← **MVP 1단계 완료선**: Yams YAML 3계층 로더 + 핫 리로드, M2 하드코딩 게이트를 프로파일로 교체, 내장 프로파일(주력 앱 + VS Code류 enabled: false), 설정 UI 앱별 목록. per_element 스키마 시점에 캐시 충분성 최종 확정.
- [ ] **M5 — AX 어댑터 + auto 전략 (MVP 이후 1차 확장)**: AX 어댑터(AXSelectedTextRange 직접 조작), auto 프로브 → key-mapping 폴백, force-text 계열, per_element 재정의 본격화. `AXUIElementSetMessagingTimeout` 실기기 계측(콜백 경량 불변식 위임 ①)은 여기.
  - **M3가 남긴 인계 메모 (M3 플랜 삭제 시 이관)**: M3에서 수용한 엣지 대부분이 쓰기가 아니라 **읽기** 문제다 — `AXValue`+`AXSelectedTextRange`로 정확 오프셋을 계산하고 실행은 키보드로 하는 혼용이면 해소된다. 목록: `iw` 단어 경계·`cw`→`ce` 특례·경계 포화 5종·소프트 랩 시각 줄([결정](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md)·[결정](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md)), charwise/linewise `p`의 경계·paste wise 자체(레지스터·yank 경로 wise 기억으로 해소), **Visual 후진 전체**(`Vk`·`vb` — 앵커가 앱 안의 점이라 읽을 수 없어 생김, [결정](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md)), 비-QWERTY 정식 해소(문자→키코드 역조회 주입 — [레이아웃 가드 결정](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)의 이연 항목), 탭 들여쓰기 `^`·Notion 계열 충돌은 M4 프로파일 우선. 3ms 캡 결정의 supersede 여부 판단도 M5 착수 시([focusedRole 캐시 결정](../../decisions/references/20260801_focused-role-cache-shape.md) 참조 — `strategy: auto` 프로브 코드가 아직 없어 보류됨). 어댑터 `linewise: Bool` 상자 재검토 후보(무게시 모션으로 V 세션 편차 해소)도 여기.
- [ ] (MVP 밖) M6 — 서명·공증 배포는 외부 공유 시점에 별도 플랜으로.

## 진행 중 컨텍스트

- **M3 종료** (상세 플랜은 완료 정리로 삭제 — 수용 엣지·계약은 decisions·architecture가, M5 인계 메모는 위 M5 항목이 승계): 실행 계층은 순수 매퍼 4종(`MotionKeyMapper`/`EditKeyMapper`/`VisualKeyMapper`/`CommandKeyMapper`) + 요소 리졸버(`FocusedElementResolver`) + 게이트 2축(요소 걸러내기·비-QWERTY 레이아웃) 구조다. M1·M2·M3 완전 종료.
- **M2에서 이관된 미확인 항목 2건**은 M3 상세 플랜의 단계 0(카운트 폭탄 실측)·단계 4(킬스위치 회귀)로 편입됐다.
- **도그푸딩 관측 방법**: `.debug` 로그는 로그 저장소에 남지 않아 `log show`로는 판정 불가 — `/usr/bin/log stream --level debug --predicate 'subsystem == "dev.pilyang.VimAction"'` (zsh에서 `log`가 가려져 절대 경로 필요).
- **테스트 seam (M2가 만든 것, M3 어댑터 테스트도 같은 방식)**: `ActionExecutor(postEvent:)` 수집기 주입으로 키코드·플래그·마커 검증 (CGEvent 생성은 TCC 불요라 headless 가능). 실행 sink와 앱 게이트의 기본값은 **XCTest 하위에서 무해한 것으로 바꿔치기**된다 — 그냥 두면 테스트가 실제 화살표 키를 머신에 주입하거나, Ghostty에서 테스트를 돌릴 때 게이트가 켜져 결정 테스트가 뒤집힌다. 동작을 검증하는 테스트는 init으로 자기 것을 주입한다.
- **빌드 경고 기준선은 이제 0건이다** — M2는 0을 기준으로 비교한다. (정정: M1 종료 시점 기준선 4건은 전부 `ActionExecutor.swift`(20·24·39·47행)였다. 이 문서가 함께 적었던 `AccessibilityPermissionMonitor.swift:35`는 **Swift 5 모드에선 경고가 아니다** — 2026-07-26 실측 빌드에서 재현되지 않았다.)
- **Swift 6 언어 모드 잔여 항목은 딱 하나**: `AccessibilityPermissionMonitor.swift:35`의 `kAXTrustedCheckOptionPrompt`(전역 `var`) 참조가 Swift 6 모드에서만 에러다. `EventTapController`·`Preferences`·`ActionExecutor`는 프로브에서 깨끗함을 확인했다. 프로브는 pbxproj를 고치지 말고 **명령줄 오버라이드**로 하면 되돌림 실수가 원천 봉쇄된다: `xcodebuild build … CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=6.0`.
- **테스트 단언 함정 (M2에서 반복 주의)**: `defaults.bool(forKey:)`는 **미설정 키에도 `false`** 를 반환한다. 영속을 검증할 때 `object(forKey:) != nil`을 앞세우지 않으면 영속 코드를 통째로 지워도 테스트가 통과한다 — M1에서 실제로 4곳이 이 상태였다(전부 수정됨).
- **`.secureInput` 축 분리는 이연**: SEI가 탭 건강과 무관한 별개 축이라는 것이 실측으로 확정됐지만, `Status` 소비자(글리프·Settings·접근성 레이블) 전면 재설계라 M1 범위 밖으로 뒀다. 필요해지면 [SEI 결정 문서](../../decisions/references/20260726_secure-input-suppresses-delivery-not-enablement.md)를 supersede한다.
- **마커 왕복 보존 실기 확인 완료 (2026-07-26)**: 외부 프로세스가 `.eventSourceUserData`에 매직값을 찍어 `.cgSessionEventTap`에 게시 → 우리 탭에서 마커가 그대로 읽혔다. 같은 키를 마킹 없이 게시하면 0ms 만에 `replace(wordForward)`로 잡히고, 마킹하면 로그 없이 앱까지 전달돼 문자가 입력된다. `CGEventSource.userData` 폴백은 불필요 — M2는 이 전제 위에서 게시해도 된다.
- M2가 인계받는 계약 **네 가지**: 합성 CGEvent 게시는 반드시 `ActionExecutor.post`를 거친다(우회 시 마커 불변식 붕괴), **CGEvent 시퀀스는 `post`를 호출할 그 직렬 큐 위에서 만든다**(CGEvent가 비-Sendable이라 격리를 건너면 안 된다 — [ActionExecutor 격리 결정](../../decisions/references/20260726_action-executor-nonisolated-sendable.md)), 실행 실패는 `EventTapController.reportExecutionFailure`로 보고한다(새 off 경로 금지), 그 보고는 **원인 키 입력 1건당 최대 1회**다(어댑터가 action 시퀀스 실패를 접는다). 세부는 [20260725_failure-burst-autodisable-shape.md](../../decisions/references/20260725_failure-burst-autodisable-shape.md), [20260725_marker-guard-highest-precedence.md](../../decisions/references/20260725_marker-guard-highest-precedence.md), [20260726_execution-failure-report-granularity.md](../../decisions/references/20260726_execution-failure-report-granularity.md).
- 릴리스 배포 금지 규칙은 **해제됐다**([결정](../../decisions/references/20260801_release-block-gate-lifted.md)) — 무로그 삼킴 0건 전수 확인 + 안전망 회귀 + 위험 심사 4건 종결. M6(서명·공증 배포) 착수 가능.
- **M2가 남긴 실행 계층 구조** (M3가 그대로 쓴다): `.replace` → 컨트롤러가 든 sink 클로저 → 게시 직렬 큐 → `KeyboardAdapter` → `ActionExecutor`. 어댑터를 큐 **안에서** 부르는 것이 계약이고(CGEvent 비-Sendable), 앱 게이트는 마커·토글 뒤·번역 앞에 있다. 계약 ③④(실패 보고)는 M2에서도 호출자가 없다 — Keyboard 게시 경로가 오류를 돌려주지 않아 접을 실패가 없고, 신호는 M5 AX 어댑터가 만든다. 세부: [실행 배선 형태 결정](../../decisions/references/20260726_m2-execution-wiring-shape.md).
- M2~M4 동안 번들 기본 전략 = keyboard 고정 (과도기, [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)에 표기).

## 관련 링크

- decisions: [20260725_keyboard-first-mvp-build-order.md](../../decisions/references/20260725_keyboard-first-mvp-build-order.md), [20260725_callback-light-invariant.md](../../decisions/references/20260725_callback-light-invariant.md)
- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)

# M5 — AX 어댑터 + auto 전략 (MVP 이후 1차 확장)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-02
- **갱신일**: 2026-08-02 (범위 분석 후 PR 단위로 재구성 — PR마다 worktree를 만들어 작업한다. **아직 착수 전이다**)

## 목표

키보드 합성만으로는 정확해질 수 없는 어휘를 AX 읽기로 해소한다: `AXValue`+`AXSelectedTextRange`로 정확 오프셋을 계산하고 실행은 키보드로 하는 **혼용**이 축이다. 여기에 순수 AX 쓰기 어댑터, `auto` 전략 프로브, `per_element` 재정의가 얹힌다.

M1~M4는 종료됐다(MVP 1단계 완료, 2026-08-02). 구조·계약의 최종 상태는 architecture가, 결정 히스토리는 decisions가 SSOT다 — 이 문서는 **M5가 무엇을 해야 하는지**만 담는다.

**빌드 순서 원칙**: 읽기 먼저, 쓰기 나중 (keyboard-first와 같은 논리 — 읽기는 실패가 즉시 드러나 폴백이 안전하고, 쓰기는 비대칭적으로 위험하다). 사용자 가치도 혼용(PR-B·C)이 순수 AX 어댑터(PR-D)보다 먼저 나온다. AX 어댑터를 "쓰기 대체"로 설계하면 이 이득을 놓친다 — M3 인계 메모의 핵심 판단.

## 완료된 것

- (없음 — 착수 전)

## 남은 것 (PR 단위 — 순서 = 의존 순서)

각 PR은 자기 worktree에서 작업한다. A → B → C는 선형 의존이고, D1 → D2도 선형이다. C와 D는 원칙적으로 병렬 가능하지만 어댑터 파일 충돌이 클 수 있어 순차를 기본으로 한다.

- [ ] **PR-A — 읽기 기반 (리졸버 확장)**: 디스패치 경로의 동기 AX 읽기(`AXSelectedTextRange`·`AXValue`) 도입. 선택 범위는 키마다 변해 캐시 불가라 **읽는 위치·타임아웃 결정이 선행**한다(아래 "착수 시 판단할 것"). `AXUIElementSetMessagingTimeout` 실기기 계측 포함(콜백 경량 불변식이 M1에 위임한 항목 ①). **M5 전체의 모양을 정하는 PR — 코드 착수 전 결정을 plan mode 수준으로 다룰 것.**
- [ ] **PR-B — 혼용 1: 편집·모션 정확화**: PR-A의 읽기를 소비해 무상태 매퍼를 정확화. `iw` 단어 경계, `cw`→`ce` 특례, [경계 포화 5종](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md), [소프트 랩 시각 줄](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md). 어댑터 무상태는 유지(정확화 diff). 골든 테스트 대량 갱신 예상. 오프셋만큼 스트로크를 보내면 버스트가 되므로 실행 중단 래치·청크 원자 그룹 규칙과 묶인다. 커지면 모션/편집으로 2분할 가능.
- [ ] **PR-C1 — 혼용 2a: Visual 앵커 상태**: 어댑터가 처음으로 앵커·범위 상태를 든다(구조 변화 — PR-B와 분리하는 이유). [Visual 후진 전체](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md)(`Vk`·`vb`·`vh`)가 통째로 해소되고, `V`→`v` 전환·앵커 쪽 반올림도 가능해진다. 어댑터의 `linewise: Bool` 상자 재검토가 여기 속한다.
- [ ] **PR-C2 — 혼용 2b: paste wise·스크롤 정확화**: charwise/linewise `p` 경계와 paste wise 자체 — 레지스터·yank 경로의 wise 기억으로 해소. 스크롤 근사 줄 수 → `AXVisibleCharacterRange` 뷰포트 정확화. 비-QWERTY 정식 해소(문자→키코드 역조회 주입 — [레이아웃 가드 결정](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)의 이연 항목)도 여기.
- [ ] **PR-D1 — 순수 AX 쓰기 어댑터**: `AXSelectedTextRange` 직접 조작으로 `VimAction` 실행. `AXError` 반환이 **실패 폭주 자동 비활성화(`reportExecutionFailure`)의 첫 실호출자**가 된다 — 실패 보고 배선 포함.
- [ ] **PR-D2 — auto 프로브 + AX 거짓말 감지 + force-text**: 프로브 → key-mapping 폴백, 왕복 테스트 휴리스틱·번들 거부 목록, `key-mapping`→`force-text` 자동 폴백 존재 여부 결정. force-text 자체는 작다(걸러내기 우회 + 항상 TextArea 시퀀스). 라우팅할 AX 어댑터(D1)와 혼용 단계의 실기기 관측이 입력이라 뒤에 온다.
- [ ] **PR-E — 스키마 확장 + 마감**: `strategy`·`per_element` 필드 additive 확장(M4 로더가 미지 키 warn+무시라 전방 호환은 열려 있다). **캐시 충분성 최종 확정** — `per_element` 스키마 시점에 재심사하기로 예약됨 ([1차 확정](../../decisions/references/20260801_cache-only-callback-confirmed-sufficient.md)). 도그푸딩 마감.

## 진행 중 컨텍스트

- **PR-A 착수 시 판단할 것 2건** (여기가 막히면 B~E 전부가 흔들린다):
  - 디스패치 시점 동기 AX 읽기를 **어디서** 하는가 — 게시 큐 위면 버스트 도중 포커스 이동 후의 읽기 문제, 콜백 근처면 경량 불변식과 충돌. [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) 미결 질문 "AX 읽기 + Keyboard 쓰기 혼용의 적용 범위" 참조.
  - [AX 감지 3ms 캡 결정](../../decisions/references/20260712_ax-probe-hard-timeout-3ms.md)의 supersede 여부 — `strategy: auto` 프로브 코드가 아직 없어 보류돼 있다 ([focusedRole 캐시 결정](../../decisions/references/20260801_focused-role-cache-shape.md)이 리졸버 경로에는 이미 전용 큐 50ms를 쓴다).

- **M3가 남긴 인계 메모 (핵심 판단)**: M3에서 수용한 엣지 **대부분이 쓰기가 아니라 읽기 문제다** — 정확 오프셋을 AX로 읽고 실행은 키보드로 하면 해소된다. 해소 대상은 위 PR-B·C1·C2에 배분돼 있다. 탭 들여쓰기 `^`·Notion 계열 충돌은 M4 프로파일이 우선 수단이다(M5 해소 대상 아님).

- **M6 (MVP 밖)**: 서명·공증 배포. [릴리스 금지 게이트는 해제됐다](../../decisions/references/20260801_release-block-gate-lifted.md) — 착수 가능하며, 시작할 때 별도 플랜으로 만든다.

## 관련 링크

- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [profiles-and-config.md](../../architecture/references/profiles-and-config.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [AX/Keyboard 전략 디스패치](../../decisions/references/20260712_ax-keyboard-strategy-dispatch.md), [Keyboard-first 빌드 순서](../../decisions/references/20260725_keyboard-first-mvp-build-order.md), [콜백 경량 불변식](../../decisions/references/20260725_callback-light-invariant.md)

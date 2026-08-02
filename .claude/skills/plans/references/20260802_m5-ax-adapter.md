# M5 — AX 어댑터 + auto 전략 (MVP 이후 1차 확장)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-02
- **갱신일**: 2026-08-02 (MVP 마일스톤 플랜 완료 정리 시 신설 — M5 인계 메모를 승계. **아직 착수 전이다**)

## 목표

키보드 합성만으로는 정확해질 수 없는 어휘를 AX 읽기로 해소한다: `AXValue`+`AXSelectedTextRange`로 정확 오프셋을 계산하고 실행은 키보드로 하는 **혼용**이 축이다. 여기에 `auto` 전략 프로브와 `per_element` 재정의가 얹힌다.

M1~M4는 종료됐다(MVP 1단계 완료, 2026-08-02). 구조·계약의 최종 상태는 architecture가, 결정 히스토리는 decisions가 SSOT다 — 이 문서는 **M5가 무엇을 해야 하는지**만 담는다.

## 완료된 것

- (없음 — 착수 전)

## 남은 것

- [ ] **AX 어댑터**: `AXSelectedTextRange` 직접 조작. `AXUIElementSetMessagingTimeout` 실기기 계측이 여기 속한다(콜백 경량 불변식이 M1에 위임한 항목 ①).
- [ ] **auto 전략 프로브 → key-mapping 폴백**, force-text 계열. (M2~M4 동안 번들 기본 전략은 keyboard 고정이었다 — 과도기 표기는 [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)에 있다.)
- [ ] **`per_element` 재정의 본격화** — M4 스키마에는 `per_element`가 없다(확정). 스키마는 additive로 확장한다.
- [ ] **캐시 충분성 최종 확정** — `per_element` 스키마 시점에 다시 본다 ([1차 확정](../../decisions/references/20260801_cache-only-callback-confirmed-sufficient.md)).

## 진행 중 컨텍스트

- **M3가 남긴 인계 메모 (핵심 판단)**: M3에서 수용한 엣지 **대부분이 쓰기가 아니라 읽기 문제다** — 정확 오프셋을 AX로 읽고 실행은 키보드로 하면 해소된다. AX 어댑터를 "쓰기 대체"로 설계하면 이 이득을 놓친다.

  해소 대상 목록:
  - `iw` 단어 경계, `cw`→`ce` 특례
  - [경계 포화 5종](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md), [소프트 랩 시각 줄](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md)
  - charwise/linewise `p`의 경계와 paste wise 자체 — 레지스터·yank 경로의 wise 기억으로 해소
  - **Visual 후진 전체**(`Vk`·`vb`) — [앵커가 앱 안의 점이라 읽을 수 없어 생긴 문제](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md)라, 읽기가 생기면 통째로 사라진다
  - 비-QWERTY 정식 해소(문자→키코드 역조회 주입) — [레이아웃 가드 결정](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)의 이연 항목
  - 탭 들여쓰기 `^`·Notion 계열 충돌은 M4 프로파일이 우선 수단이다

- **착수 시 판단할 것 2건**:
  - [AX 감지 3ms 캡 결정](../../decisions/references/20260712_ax-probe-hard-timeout-3ms.md)의 supersede 여부 — `strategy: auto` 프로브 코드가 아직 없어 보류돼 있다 ([focusedRole 캐시 결정](../../decisions/references/20260801_focused-role-cache-shape.md)이 리졸버 경로에는 이미 전용 큐 50ms를 쓴다).
  - 어댑터의 `linewise: Bool` 상자 재검토 — 무게시 모션으로 V 세션 편차를 해소할 수 있는지.

- **M6 (MVP 밖)**: 서명·공증 배포. [릴리스 금지 게이트는 해제됐다](../../decisions/references/20260801_release-block-gate-lifted.md) — 착수 가능하며, 시작할 때 별도 플랜으로 만든다.

## 관련 링크

- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [profiles-and-config.md](../../architecture/references/profiles-and-config.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- decisions: [AX/Keyboard 전략 디스패치](../../decisions/references/20260712_ax-keyboard-strategy-dispatch.md), [Keyboard-first 빌드 순서](../../decisions/references/20260725_keyboard-first-mvp-build-order.md), [콜백 경량 불변식](../../decisions/references/20260725_callback-light-invariant.md)

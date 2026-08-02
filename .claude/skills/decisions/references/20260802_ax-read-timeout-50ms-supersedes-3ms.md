# AX 메시징 타임아웃 50ms 단일 상수 — 3ms 하드 캡 supersede

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

AX 메시징 타임아웃(`AXUIElementSetMessagingTimeout`)은 **경로 불문 50ms 단일 상수**로 한다 — 리졸버(이미 50ms)와 M5 디스패치 경로 읽기가 같은 상수를 공유한다. [3ms 하드 캡 결정](20260712_ax-probe-hard-timeout-3ms.md)은 supersede한다.

불변식도 재정의한다: **탭 생존을 지키는 것은 캡 값이 아니라 배치다** — AX 호출은 콜백·메인 스레드에 들어오지 않는다(리졸버는 전용 큐, 디스패치 읽기는 게시 큐). 캡은 병적 정지가 큐를 잡아두는 것을 자르는 차단기일 뿐이다.

`strategy: auto` 프로브(PR-D2): "동기 프로브 + 소캡" 형태는 콜드 실측으로 성립 불가가 확정됐다. 구체 재설계(비동기 캐시형 유력)는 그 코드가 생기는 D2 착수 시 결정한다.

## 배경·근거 (왜)

3ms 결정은 스스로 "실기기 계측 없는 초기 추정값, 오폴백 관찰 시 재검토"를 명시했고, 두 번 관찰됐다: [2026-08-01 실측](20260801_focused-role-cache-shape.md)에서 콜드 6/6 실패, 2026-08-02 실측에서 **웜 정상 읽기까지 죽인다** — Notion `selectedRange`는 웜 p50 7.1ms / max 16.0ms라 3ms 캡에서 전멸한다.

50ms의 근거:

- 실측 콜드 성공 19~35ms, 웜 정상 최대 16ms — 50ms는 관측 최대의 ~3배 여유로 전부 통과시킨다.
- **실패 대기는 캡+1.5~2ms로 바운드됨을 확인했다** (콜백 경량 불변식이 위임한 계측 항목 ①의 답): 3ms 캡에서 콜드 실패는 ~4.8ms, Notion 웜 실패는 p50 4.5ms에 반환됐다. 즉 병적 정지 시 게시 큐가 잡히는 시간은 최대 ~52ms/읽기이고, 읽기는 액션당 1회라 수용 범위다.
- **예외 1건**: 프로세스 생애 **최초** AX 호출 1회는 캡을 무시하고 ~23ms 블록한다(순서를 바꿔 재실행해 앱이 아니라 "첫 호출" 속성임을 확인 — 1차 실행 TextEdit 23.6ms, 순서 역전 2차 실행 Finder 23.3ms). 실사용에서는 리졸버가 앱 시작 직후 먼저 AX를 호출하므로 디스패치 경로가 이 1회를 맞을 일은 사실상 없다.
- 캡 경계는 퍼지다 — 3ms 캡에서 3.3~4.1ms 성공이 관측됐다. 캡은 정밀 상한이 아니다(불변식을 "값"이 아니라 "배치"로 재정의한 이유).

## 검토한 대안

- **25ms** (관측 최대 16ms × 1.5): 상수가 2개가 되고(리졸버 50ms 별도), 여유가 얇다. 캡 오탐(정상 앱의 정확화 상실)이 캡 여유의 비용(병적 앱에서 큐 지연 +25ms)보다 아프다 — 실패 방향 비대칭. 기각.
- **3ms 유지 + 콜드/슬로우 수용**: 정확화가 가장 필요한 앱(Notion)에서 정확화가 구조적으로 죽는다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (불변식 재정의), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 ③)
- `FocusedElementResolver.messagingTimeout` — 리더와 공유하는 상수로 승격 (PR-A 구현)
- 읽기 형태 결정: [20260802_dispatch-read-on-posting-queue.md](20260802_dispatch-read-on-posting-queue.md)

## Supersedes

- [20260712_ax-probe-hard-timeout-3ms.md](20260712_ax-probe-hard-timeout-3ms.md) — 3ms 하드 캡. 그 결정이 겨냥한 위험("응답 없는 AX가 탭을 멈춤")은 배치 불변식(AX는 메인·콜백 진입 금지)이 더 강하게 담당한다.

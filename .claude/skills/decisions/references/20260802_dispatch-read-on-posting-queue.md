# 디스패치 경로 AX 읽기 형태 — 게시 큐 위 lazy 읽기, 창 프리미티브, 무상태 폴백

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

M5 혼용(AX 읽기 + Keyboard 쓰기)의 읽기 기반 형태를 다음으로 확정한다:

1. **동기 AX 읽기는 게시 직렬 큐 위에서만** 한다. 콜백·메인 스레드는 계속 AX 무접촉이다(리졸버 결정의 보장 그대로). 읽기는 액션을 처리하는 시점에 어댑터가 **lazy로** 수행한다 — 키 입력 시점 선읽기가 아니다.
2. **대상 pid는 키 입력 시점 스냅샷**이다 — `DispatchContext`에 pid가 추가되고 콜백이 싣는다. 게시 큐는 그 pid로 `AXUIElement`를 큐 위에서 생성한다 — 비-`Sendable` 값이 격리를 건너지 않는 규칙은 그대로다([focusedRole 캐시](20260801_focused-role-cache-shape.md) ④와 동일).
3. **읽기 프리미티브는 `AXSelectedTextRange` + `AXNumberOfCharacters` + `AXStringForRange`(캐럿 주변 창)** 다. **`AXValue` 전체 읽기는 키당 경로에서 금지한다** — 비용이 문서 크기에 비례한다(실측: 100만자 TextEdit에서 3.5~5.3ms, 창 읽기는 크기 무관 ~0.2ms).
4. **읽기 실패·타임아웃 시 그 액션은 현행 무상태 시퀀스로 폴백**한다 — 정확화만 포기하고 실행은 한다. 스킵이 아니고, `reportExecutionFailure` 대상도 아니다: 읽기는 정확화의 입력이지 실행이 아니다([미지원≠실패](20260726_unsupported-action-not-failure.md)와 같은 의미론 구획).
5. **리더는 어댑터에 주입**한다 (`ActionExecutor.postEvent`·`PasteWiseResolver`와 같은 seam) — 골든 테스트가 실기기 AX 없이 읽기 결과를 주입한다.

## 배경·근거 (왜)

2026-08-02 실측(프로브: 장수 프로세스가 앱 활성화 직후 콜드 1회 + 웜 60~100회, 웜 1회 = pid→focusedElement 재조회→속성 읽기)이 형태를 정했다.

### ① 게시 큐인 이유 — 콜백은 지연만으로 기각

| 앱 (웜, p50) | fetch | selectedRange | numberOfChars | value 전체 | stringForRange 200자 |
|---|---|---|---|---|---|
| TextEdit 5.6k자 | 0.03ms | 0.03ms | 0.02ms | 0.05ms | 0.04ms |
| TextEdit 100만자 | 0.09ms | 0.08ms | 0.08ms | **3.5ms (max 5.3)** | 0.17ms |
| Notion 7.7k자 | 0.08ms | **7.1ms (p95 8.6, max 16.0)** | 0.06ms | 0.10ms | 0.06ms |
| Finder·Zen(비텍스트) | 0.02~0.06ms | attrUnsupported, ~0.02ms 즉시 | — | — | — |
| Slack·VS Code | **noValue — 포커스 요소 자체 없음**, 즉시 | — | — | — | — |

Notion의 `selectedRange`가 **웜에서도 키당 7~16ms**다. 콜백 경량 불변식과의 충돌을 논하기 전에 이 지연 자체가 콜백(메인)에 들어올 수 없다 — 키 배달이 그만큼 밀린다. 게시 큐 위면 이 지연은 해당 버스트의 소요일 뿐 탭·다른 키와 무관하다.

### lazy(액션 처리 시점)인 이유 — 계열 스냅샷과 시점 요구가 반대다

계열·프로파일은 키 입력 시점 스냅샷이 유일하게 일관된 값이다(캐시 형태 결정 ⑦). 선택 범위는 정반대다 — **같은 버스트의 앞 액션이 캐럿을 옮기므로, 실행 직전 값만이 정확하다.** 콜백에서 선읽기해 실어 보내면 액션 2개째부터는 낡은 오프셋으로 계산한다. 읽기는 소비 지점(어댑터)에서 필요한 순간에 하는 것이 정확성의 요구다.

### ③ 창 프리미티브인 이유

PR-B·C가 필요로 하는 것은 캐럿 주변 텍스트(단어 경계, 줄 경계, 경계 포화 감지)와 문서 길이뿐이다. `AXValue` 전체는 얻는 것 없이 문서 크기에 비례하는 비용만 낸다(위 표). M5 플랜의 "`AXValue`+`AXSelectedTextRange`" 표현은 이 실측으로 정정된다 — 전체 값이 아니라 창이다.

### ④ 무상태 폴백인 이유

실패는 빠르고(즉시 ~ 캡+2ms) 에러코드로 구분된다(attrUnsupported / noValue / cannotComplete). 읽기 실패 시 무상태 시퀀스는 **오늘의 정상 동작**이므로 폴백의 실패 방향이 안전하다 — "읽기는 실패가 즉시 드러나 폴백이 안전하고, 쓰기는 비대칭적으로 위험하다"(M5 빌드 순서 원칙)의 실측 확인. Slack·VS Code는 포커스 요소 자체를 노출하지 않아 이 폴백이 상시 경로다.

## 검토한 대안

- **콜백 동기 읽기 + 짧은 캡**: Notion 웜 7~16ms — 캡으로 자르면 정확화가 가장 필요한 앱(Notion, M3 수용 엣지의 주 무대)에서 정확화가 죽는다. 기각.
- **리졸버 비동기 캐시 확장** (`selectedRange` 캐싱): 선택 범위는 키마다 변한다 — 캐시가 원리적으로 따라갈 수 없다. 기각.
- **콜백 선읽기 → `DispatchContext`로 운반**: 읽기 시점이 콜백이 되어 위와 같은 지연 문제 + 버스트 내 2번째 액션부터 낡은 값. 기각.
- **버스트 도중 포커스 이동 대비 요소 토큰 재검증**: 합성 이벤트는 어차피 **현재** 최전면 앱에 배달되므로, mismatch 창은 계열 스냅샷이 이미 수용한 창과 동일하고 새 사용자 입력은 실행 중단 래치가 끊는다. 추가 왕복만 늘어 기각(수용).

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (미결 질문 "AX 읽기 + Keyboard 쓰기 혼용의 적용 범위" 해소), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 신규 리더 타입(게시 큐 위 AX 읽기), `DispatchContext`(+pid), `KeyboardAdapter.execute` 주입 seam, `EventTapController` sink 배선 — PR-A 구현 범위
- 타임아웃 값은 별도 결정: [20260802_ax-read-timeout-50ms-supersedes-3ms.md](20260802_ax-read-timeout-50ms-supersedes-3ms.md)
- [캐시 충분성 1차 확정](20260801_cache-only-callback-confirmed-sufficient.md)이 예고한 재심사의 이행 — 콜백이 캐시만 읽는 형태는 그대로 유지되고, 라이브 읽기는 게시 큐에 추가된다

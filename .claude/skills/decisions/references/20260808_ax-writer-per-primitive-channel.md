# AX 쓰기 통로는 별도 `AXWriter` — 불변식은 "프리미티브당 단일 통로"로 재문언

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 D1-설계 세션, 결정 ①)

## 결정

AX 쓰기(`AXUIElementSetAttributeValue`)는 `ActionExecutor`에 넣지 않고 **별도 타입 `AXWriter`가 단독 소유**한다. 재진입 불변식 1은 "모든 출력은 단일 `ActionExecutor`"에서 **"모든 출력은 프리미티브마다 단일 통로 — 합성 이벤트 게시는 `ActionExecutor`, AX 속성 쓰기는 `AXWriter`"** 로 재문언한다. seam 계약:

- `nonisolated struct AXWriter: Sendable`, 주입 클로저 `@Sendable (AXUIElement, String, CFTypeRef) -> AXError` (읽기 seam 2종과 동형). 비-Sendable 파라미터는 같은 격리 안에서 넘어가므로 crossing이 아니다.
- **요소는 pid가 아니라 `AXUIElement`로 받는다** — 읽기(오프셋 계산)와 쓰기가 **같은 요소 핸들**을 써야, 그 사이 포커스가 옮겨간 경우 엉뚱한 요소에 계산된 범위를 써 넣는 창이 구조적으로 닫힌다. 어댑터는 액션당 1회 lazy·memo로 요소를 잡는다(`FocusedTextSnapshot` 수명 계약 동형). 요소 획득은 반드시 `AXRead.focusedElement`를 거친다 — 50ms 단일 타임아웃 상수가 이 고리로 쓰기 경로에도 상속된다.
- **`AXError`는 raw로 반환**한다 — 읽기 seam이 단일 `nil`인 것은 소비자 폴백이 하나뿐이라서였고, 쓰기는 소비자 행동이 갈린다(미지원 스킵 vs 실패 보고 — [20260808_ax-write-failure-whitelist-no-fallback.md](20260808_ax-write-failure-whitelist-no-fallback.md)). 분류는 어댑터의 순수 함수로 두어 표로 테스트한다(`provenViewport` 선례).
- 테스트는 클로저에 수집기를 꽂아 headless로 쓰기 호출·인자·주입 에러를 단언한다. `AXUIElementCreateApplication`은 메시징이 아니라 TCC 없이 생성된다.

`ActionExecutor` doc에 크로스 레퍼런스 1줄("AX 속성 쓰기는 `AXWriter`가 같은 규칙으로 소유")을 넣고, `AXRead` doc은 "쓰기 경로도 요소는 반드시 여기서 받는다"를 계약으로 명시한다.

## 배경·근거 (왜)

- **감사 가능성은 "타입 1개"가 아니라 "프리미티브당 소유자 1개"에서 나온다.** CGEvent 감사는 `post(tap:)` 호출자가 `ActionExecutor` 외 0건임을 확인하는 것이고, AX 쓰기 감사는 `SetAttributeValue` 호출자가 소유 타입 외 0건임을 확인하는 것 — 이 성질은 타입이 하나든 둘이든 동일하게 성립한다.
- **`ActionExecutor`의 존재 이유는 마커 강제다.** AX 쓰기는 탭으로 되돌아오지 않아 마커·무한 루프 개념 자체가 없다. 마커 개념 없는 쓰기를 마커 타입에 넣으면 "이 타입을 거치면 마커가 찍힌다"가 거짓이 되고, AX 쓰기에도 마커가 관여한다는 오독 여지가 생긴다. 현행 불변식 문언이 바로 그 오독을 유발하므로 재문언은 약화가 아니라 **강화**다.
- **이 코드베이스는 읽기 쪽에서 이미 같은 결론을 내렸다** — `AXRead`(진입점 단독 소유) 위에 주입 seam이 둘(`FocusedTextReader`·`ViewportReader`)이며, 후자는 "별개 프리미티브"라는 명시 근거로 갈라졌다(PR-C2).
- **실패 보고의 수렴 지점은 통로가 아니라 어댑터다** — "키 입력 1건당 최대 1회" 접기는 액션 시퀀스 전체를 보는 층만 할 수 있다([20260726_execution-failure-report-granularity.md](20260726_execution-failure-report-granularity.md)). "보고 수렴을 위해 한 타입"이라는 논거는 애초에 `ActionExecutor`가 가져갈 수 없는 책임이었다.
- 클립보드 쓰기(NSPasteboard)가 이미 자기 seam(`PasteWiseResolver`)을 갖고 있다 — "프리미티브당 통로" 문언은 이 기존 사실과도 정합한다.

## 검토한 대안

- **A. `ActionExecutor` 확장** (postEvent 옆에 axWrite 주입): 불변식 문언 그대로라는 것이 유일한 이득인데, 위 근거대로 그 문언 자체가 오독 유발이다. 미래에 두 프리미티브를 아우르는 공통 정책(전역 출력 로그 등)이 생기면 그때 얇은 파사드를 얹으면 되고 seam은 안 바뀐다.
- **C. 절충** (`ActionExecutor`가 통로, 저수준 호출은 `AXRead` 계열 소유): 양쪽 비용을 다 낸다 — 타입은 두 얼굴이 되면서 감사 지점도 결국 둘.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (불변식 1 재문언), [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (AX 어댑터 최종 상태)
- 신규 코드(PR-D1a): `VimAction/AXWriter.swift`. 착수 시 확인 항목: Swift 6 모드 프로브(명령줄 오버라이드), AX **쓰기** 지연 분포 실측(50ms 상수는 읽기 실측치 — 공유는 실측 전까지 잠정).

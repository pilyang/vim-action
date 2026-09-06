# 인디케이터 앵커 사다리 — 캐럿 → 요소 → 창, 갱신은 이벤트 기반만

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-06

## 결정

1. **앵커는 정밀도 사다리**로 고른다: 캐럿 rect → 포커스 요소 rect(`AXPosition`+`AXSize`) → 포커스 창 rect(`AXFocusedWindow` 위치·크기, 실패 시 `CGWindowListCopyWindowInfo`) → 없음(메뉴바만). 위 단이 실패하면 다음 단으로 내려간다.
2. **순간 표시는 캐럿부터, 상시 배지는 요소부터** 시작한다. 상시 배지는 캐럿을 따라다니지 않는다.
3. **갱신은 이벤트 기반만**: 모드 전환, 포커스 요소 변경(리졸버의 `kAXFocusedUIElementChanged`), 앱 활성화(리졸버 기존 경로), 창 이동·리사이즈(`kAXWindowMoved`/`kAXWindowResized`를 같은 `AXObserver`에 추가). **키마다 재배치·주기 폴링은 하지 않는다.**
4. **AX 읽기는 메인·콜백 밖**(리졸버 `readQueue` 또는 게시 큐)에서, 50ms 단일 타임아웃으로, **pid만** 건너가 요소를 새로 만든다. 결과 rect만 메인으로 넘겨 패널을 옮긴다.
5. **캐럿 읽기 순서**: `AXBoundsForRange`에 `(loc, 1)` → 문서 끝이면 `(loc-1, 1)` → `AXSelectedTextMarkerRange`+`AXBoundsForTextMarkerRange`. 길이 0 범위는 쓰지 않는다. 마커 결과가 요소 rect와 같으면 "없음"으로 취급한다.
6. **좌표 변환**: AX(좌상단 원점) → AppKit은 `y' = NSScreen.screens[0].frame.maxY - (y + h)`. 화면 밖으로 나가면 화면 안으로 클램프한다.

## 배경·근거 (왜)

### 실측 (2026-09-06, 실기기·디스플레이 2대)

최전면 앱의 포커스 텍스트 요소에서 읽은 기하 가용성. 읽기 한 번(요소·선택·캐럿 3변형·마커·창)에 2~40ms, 첫 접촉 30~45ms.

| 앱 (텍스트 엔진) | 요소 rect | 캐럿 `AXBoundsForRange` | 캐럿 텍스트 마커 | 비고 |
|---|---|---|---|---|
| TextEdit·Notes 본문 (AppKit NSTextView) | Y | Y | – | **길이 0 범위는 한 줄 위 rect**를 돌려준다. 줄 첫머리에서 `(loc-1,1)`은 개행 문자라 이전 줄 끝까지 넓어진다 |
| Safari 주소창 (AppKit NSTextField) | Y | Y | – | 같은 길이 0 quirk |
| Safari 페이지 input·textarea·contenteditable (WebKit) | Y | Y | Y | 길이 0도 정확 |
| Chrome·Arc input·textarea·contenteditable (Chromium 기본 AX 모드) | Y | **N** | **N** | 인라인 텍스트 박스 미로드 → inner-text 범위 rect가 빈 값. 별도 결정 [20260906_no-forced-chromium-screen-reader-mode.md](20260906_no-forced-chromium-screen-reader-mode.md) |
| Slack 컴포저 (Electron, `AXManualAccessibility` 켠 상태) | Y | N | **Y** (0×18) | contenteditable 루트라 `AXBoundsForRange`는 구조적으로 불가 — Chromium `frameForRange`는 텍스트 노드·원자 필드만 답한다. 마커 결과가 내용 끝 선택에서는 요소 전체 rect로 퇴화 |
| Notion 블록 (Electron) | Y | N | Y | `AXStaticText` 자식의 `AXBoundsForRange`도 됨 |
| Ghostty | Y(표면 전체) | N | N | 터미널은 어차피 disabled |
| 포커스 창 rect | 전 앱 Y | | | 추가 권한 불필요 |

오버레이 프로토타입(비활성화 `NSPanel`, 200ms 주기)으로 앱 7종을 순환하며 위 사다리를 실제로 돌렸다 — 캐럿이 있는 앱(Safari·Slack·Notion·TextEdit)은 캐럿 아래에, 없는 앱(Chrome)은 요소 모서리에 배지가 붙었고, 주 디스플레이 왼쪽 보조 디스플레이(AX x 음수)에서도 픽셀 정렬이 맞았으며 최전면 앱을 한 번도 빼앗지 않았다.

### 왜 사다리인가

- 캐럿 앵커가 UX는 최선이지만(Vim 커서 모양·Apple 캐럿 아래 인디케이터와 동일 자리) 실측대로 앱 계열에 따라 없다. 요소 rect는 프로버가 이미 읽는 값이라 사실상 보편이고, 창 rect는 항상 있다. 그래서 "어디에 붙일지"는 앱마다 고르는 게 아니라 위에서부터 내려오는 사다리 하나로 정의한다.
- **상시 배지가 캐럿을 따라다니지 않는 이유**: 따라다니려면 키마다(또는 마우스 스크롤마다) AX를 다시 읽어야 한다. 이는 [20260725_tap-main-runloop-retention.md](20260725_tap-main-runloop-retention.md)가 명시한 재검토 트리거("실시간 오버레이 UI 같은 메인 상시 부하")에 정확히 해당하고, 마우스 휠 스크롤은 우리가 관측하지 못해 배지가 엉뚱한 곳에 남는다(드리프트). 요소 모서리는 포커스·창 이벤트 때만 움직이므로 관측 가능한 이벤트만으로 정확히 유지된다. 순간 표시는 1초 뒤 사라지므로 드리프트 문제가 없어 캐럿을 쓸 수 있다.
- **이벤트 기반만**: 콜백 경량 불변식([20260725_callback-light-invariant.md](20260725_callback-light-invariant.md))과 "AX는 메인 밖" 규칙([20260801_focused-role-cache-shape.md](20260801_focused-role-cache-shape.md))을 그대로 따른다. 리졸버가 앱마다 `AXObserver`를 이미 붙이고 있어 창 이동·리사이즈 알림은 종류만 추가하면 된다.
- **캐럿 읽기 순서**: AppKit의 길이 0 quirk 때문에 `(loc,1)`을 우선하고, 문서 끝에서만 `(loc-1,1)`로 물러난다. 마커 경로는 Electron contenteditable의 유일한 답이므로 마지막에 둔다. 마커의 "내용 끝 = 요소 rect" 퇴화는 요소 rect와 같은지로 걸러낸다.
- **좌표 변환**: 주 화면 높이 하나로 뒤집는 전역 변환이 보조 디스플레이에서도 맞음이 실측됐다(디스플레이별 개별 변환 불필요).

## 검토한 대안

- **상시 캐럿 추적(항상 캐럿 옆)**: 기각 — 위 재검토 트리거·드리프트. `kAXSelectedTextChanged` 알림 기반 추적도 마우스 스크롤을 못 잡고 앱마다 발화 여부가 다르다.
- **요소 앵커만(캐럿 미사용)**: 기각 — 큰 텍스트 영역에서 전환 피드백이 시선에서 멀다. AppKit·WebKit·Electron에서 캐럿이 실제로 되므로 버릴 이유가 없다.
- **창 앵커만**: 기각 — 어느 입력칸인지 말하지 못한다. 폴백으로만 남긴다.
- **디스플레이별 좌표 변환**: 불필요함이 실측됐다.

## 영향 범위

- 갱신한 architecture reference: 없음 — PR 1 머지 시 신규 reference에 사다리·갱신 트리거·읽기 위치를 기술한다.
- 코드: 리졸버 `AXObserver`에 알림 2종 추가, 게시 큐/`readQueue` 위 기하 읽기 협력자, 순수 함수(사다리 선택·배치·클램프·좌표 변환)와 그 유닛 테스트.
- 표시 정책은 [20260906_mode-indicator-hybrid-display-policy.md](20260906_mode-indicator-hybrid-display-policy.md).

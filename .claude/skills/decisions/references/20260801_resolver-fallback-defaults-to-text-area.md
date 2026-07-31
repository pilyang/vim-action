# 리졸버 폴백은 `.textArea` — 걸러내기는 확실한 보고에만 발동

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

요소 리졸버가 role을 확정하지 못하는 모든 경우 — AX 호출 실패, 3ms 하드 타임아웃, `AXObserver` 등록 실패, **모르는 role** — 에 `.textArea`를 보고한다. 걸러내기(`nil` 스킵)는 **"확실히 비텍스트/TextField로 보고된 경우"에만** 발동한다.

따라서 비텍스트 판정은 **화이트리스트**다: 명시적으로 아는 비텍스트 role만 `.nonText`이고, 애매한 role(`AXGroup`·`AXWebArea`·`AXUnknown`·`AXSplitGroup` 등)은 전부 `.textArea`로 떨어진다.

## 배경·근거 (왜)

이 프로젝트가 Keyboard 전략을 먼저 만든 이유 자체가 **"너무 많은 앱이 AX 지원을 거짓말한다"** 였다([전략 디스패치](20260712_ax-keyboard-strategy-dispatch.md)). 그 전제를 리졸버에도 일관되게 적용하면, 리졸버가 아무 말도 못 하는 앱은 정확히 **AX 부실 앱**이고 그런 앱이야말로 Keyboard 전략이 겨냥한 주 대상이다. 거기서 걸러내기가 발동하면 Vim 레이어가 통째로 죽는다 — 리졸버를 붙인 결과가 "앱 하나가 통째로 무동작"이라면 안 붙인 것만 못하다.

두 실패 방향의 대가가 **비대칭**인 것이 핵심이다:

- **폴백이 `.textArea`일 때의 오판**: 진짜 비텍스트인데 텍스트로 봐서 명령이 발사된다 — 이것은 오늘(단계 2c) 이미 감수하고 있는 위험이고, 릴리스 금지 게이트가 유효해 사용자 노출도 없다. 리졸버는 이 위험을 **줄이는** 장치지 없애는 장치가 아니다.
- **폴백이 `.nonText`일 때의 오판**: AX가 부실한 텍스트 앱에서 편집 어휘 전체가 조용히 죽는다 — 새로 만드는 고장이고, 사용자에게는 "가끔 안 먹는 앱"으로 보여 진단이 가장 어려운 종류다.

즉 폴백 선택은 "안전한 쪽"의 문제가 아니라 **"이미 있는 위험을 유지할 것인가, 새 고장을 만들 것인가"** 의 문제다.

`AXGroup`·`AXWebArea`를 애매한 쪽으로 분류하는 것도 같은 논리다 — Chromium/Electron 계열이 편집 가능한 영역에 이 role들을 붙이는 사례가 흔하고, 주력 앱이 Electron이다([Keyboard-first 빌드 순서](20260725_keyboard-first-mvp-build-order.md)).

## 검토한 대안

- **폴백 `.nonText`(모르면 막는다)**: 위 비대칭 때문에 기각. "안전"의 정의를 "아무것도 안 하기"로 잡으면 앱 커버리지가 무너진다.
- **폴백을 앱별로 다르게**: 앱 축의 지식은 M4 프로파일의 몫이고, 지금 급조하면 앱 게이트와 이중 게이트가 된다([비텍스트 UI 위험](20260730_native-command-non-text-ui-hazard.md)이 같은 이유로 임시 차단 목록을 기각했다) — 기각.
- **모르는 role을 만나면 로그만 남기고 `.textArea`**: 채택. 로그는 남긴다 — 세션 2 도그푸딩에서 미지 role이 곧 분류표 확장 후보다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) — 포커스/컨텍스트 리졸버 절
- `FocusedElementResolver.family(role:subrole:)`의 기본 반환값과 화이트리스트 구조
- 3ms 하드 타임아웃 유지: [AX 감지 하드 타임아웃](20260712_ax-probe-hard-timeout-3ms.md)
- 관련: [TextField 시퀀스 폐기](20260801_textfield-edit-sequences-scrapped.md), [걸러내기 범위](20260801_non-text-filter-keeps-motion-and-scroll.md)

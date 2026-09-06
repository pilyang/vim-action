# Chromium 브라우저에 스크린리더 모드(`AXEnhancedUserInterface`)를 강제하지 않음

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-06

## 결정

VimAction은 어떤 앱에도 `AXEnhancedUserInterface`를 설정하지 않는다. Chromium 브라우저(Chrome·Arc 등 `.browser` 클래스)에서 **캐럿 앵커는 불가로 수용**하고 앵커 사다리의 요소 rect로 내려간다. Electron 앱의 `AXManualAccessibility` 기상([20260813_electron-tree-wake-on-probe-failure.md](20260813_electron-tree-wake-on-probe-failure.md))은 그대로 유지하며, 그 부수효과로 Electron에서는 텍스트 마커 경로 캐럿이 된다.

## 배경·근거 (왜)

- **실측**: Chromium 기본 AX 모드에서는 `AXBoundsForRange`·`AXBoundsForTextMarkerRange` 모두 빈 값이다. Chromium은 범위 rect를 `kInlineTextBox` 자식으로 계산하는데(`BrowserAccessibility::GetInnerTextRangeBoundsRectInSubtree`) 인라인 텍스트 박스는 완전 모드에서만 실린다. 앱 요소에 `AXEnhancedUserInterface=true`를 넣자(반환값은 `kAXErrorNotImplemented`지만 효과는 있음) input·textarea는 `AXBoundsForRange`, contenteditable은 마커 경로로 캐럿이 나왔고, false로 되돌리자 다시 빈 값이 됐다. 즉 기술적으로는 가능하다.
- **그럼에도 강제하지 않는 이유**: `AXEnhancedUserInterface`는 VoiceOver가 켜질 때 세우는 플래그로, 브라우저가 "스크린리더가 붙었다"고 판단해 **모든 탭의 AX 트리를 완전 모드로 유지**한다. 성능 비용이 브라우저 전체에 걸리고, 웹앱이 스크린리더 감지 시 동작을 바꾸는 경우도 있다. 모드 배지 하나를 캐럿 옆에 붙이려고 브라우저의 전역 접근성 모드를 바꾸는 것은 비례하지 않는다. 브라우저에는 AX 접촉을 최소화한다는 [20260818_browser-class-auto-untrusted.md](20260818_browser-class-auto-untrusted.md)와 같은 방향이다.
- **Electron이 다른 이유**: `AXManualAccessibility`는 Electron이 제공하는 앱 단위 opt-in이고 이미 프로버가 pid당 1회 세우기로 결정돼 있다. 새 접촉이 아니라 기존 결정의 부수효과를 쓰는 것뿐이다.

## 검토한 대안

- **Chromium 브라우저에 `AXEnhancedUserInterface` 강제**: 기각 — 위 비례성.
- **앱별 opt-in 설정으로 노출**: 보류 — 수요가 실증되지 않았고, 설정 항목이 늘어나는 비용만 확실하다. 요구가 생기면 additive로 추가할 수 있다.

## 영향 범위

- 갱신한 architecture reference: 없음(구조 변경 아님 — 앵커 사다리의 한 단이 브라우저에서 비어 있는 것을 수용).
- 코드: 캐럿 읽기 실패는 조용한 폴백. 로그는 프로브 요약 버킷 관례를 따른다.

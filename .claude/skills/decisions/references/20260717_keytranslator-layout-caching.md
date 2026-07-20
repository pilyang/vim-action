# KeyTranslator 레이아웃 캐싱 + 노티 무효화

- **결정일**: 2026-07-17

## 결정

`KeyTranslator`는 현재 ASCII-capable 키보드 레이아웃 `Data`를 `@MainActor` static으로 **캐시**하고, 키 입력마다 반복하던 TIS 조회를 캐시 히트로 대체한다. 무효화는 `DistributedNotificationCenter`로 **입력 소스 변경 노티**를 받아 캐시를 클리어(다음 키에서 재조회)한다. 관찰 노티는 두 축이다: 선택 소스 변경(`kTISNotifySelectedKeyboardInputSourceChanged`) + enabled 소스 목록 변경(`kTISNotifyEnabledKeyboardInputSourcesChanged`). 옵저버는 **selector 기반 + `.deliverImmediately`**로 등록하고, `UCKeyTranslate` 실패 시 캐시를 폐기한다.

## 배경·근거 (왜)

문자 키 번역은 매 keyDown마다 `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` + 레이아웃 데이터 추출을 호출했다 — 시스템 전역 탭 콜백 경로에서 키마다 반복하기엔 무겁다. 캐시하면 키당 비용이 nil 체크뿐이 된다. 캐시의 어려움은 전부 "언제 낡는가"에 있고, 그 판정이 코드만 봐선 자명하지 않아 기록한다:

- **`.deliverImmediately`가 필수**다. block 기반 옵저버 API는 `suspensionBehavior`를 지정할 수 없고, 분산 노티의 기본(coalesce) 동작은 **앱이 비활성인 동안 배달을 유예**한다. 이 앱은 `LSUIElement` 메뉴바 백그라운드 앱이라 **사실상 항상 비활성** — 기본 동작이면 사용자가 입력 소스를 바꿔도 노티가 도착하지 않아 캐시가 조용히 낡는다. selector 기반 등록만이 `.deliverImmediately`를 받는다(그래서 `KeyTranslator` enum 대신 NSObject 셔틀 `LayoutCacheInvalidator`가 필요하다).
- **enabled 소스 목록 변경도 관찰**한다. 캐시 대상은 "ASCII-capable 레이아웃"이라, 선택 소스가 그대로여도 enabled 목록이 바뀌면 TIS가 고르는 ASCII-capable 레이아웃이 달라질 수 있다. 선택 소스 노티만으로는 이 축을 놓친다.
- **`UCKeyTranslate` 실패 시 캐시 폐기**(자가 치유). API 실패의 원인이 캐시된 데이터일 수 있는데, 유지하면 영구 무번역(모든 문자 키 통과)에 갇힌다. 폐기하면 다음 키가 새로 조회해 캐시 도입 전의 "키마다 재조회" 복원력을 되찾는다. 조회 실패 자체도 캐시하지 않는다.
- **옵저버 콜백은 MainActor로 홉**한다 — 분산 노티 배달 스레드는 문서상 보장이 없는데 캐시는 `@MainActor` static이라, 배달 스레드에서 직접 만지면 격리 위반이다. 홉 지연(그 사이 이전 캐시로 번역)은 노티 기반 무효화에 원래 내재한 창이라 무해하다.

## 검토한 대안

- **캐시 없이 키마다 TIS 조회**: 정확하지만 탭 콜백 경로의 반복 비용. 캐싱이 최적화하려는 바로 그 지점.
- **block 기반 옵저버**: 코드가 짧지만 `.deliverImmediately`를 못 줘 LSUIElement에서 노티 유실 → 캐시 무효화 실패. 기각.
- **선택 소스 노티만 관찰**: enabled 목록 변경으로 바뀌는 ASCII-capable 레이아웃을 놓친다. 두 축 모두 관찰로 기각.

## 영향 범위

- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md)
- 앱: `KeyTranslator.cachedLayoutData`/`invalidateLayoutCache`/`registerLayoutChangeObserverIfNeeded`/`currentLayoutData`, `LayoutCacheInvalidator`.
- 번역 방식 자체(UCKeyTranslate + ASCII-capable 레이아웃, total function)는 [20260716_cgevent-key-translation-ascii-layout.md](20260716_cgevent-key-translation-ascii-layout.md), [20260716_keytranslator-total-function-keydown-guard.md](20260716_keytranslator-total-function-keydown-guard.md).

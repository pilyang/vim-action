# 비자신 앱 캐시는 게이트가 소유하고, 게이트가 `@Observable`이 된다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

메뉴바 편의 기능이 겨누는 "마지막 비자신(non-self) 앱"을 **`FrontmostAppGate`의
`lastNonSelfBundleID`가 단독 소유**하고, 메뉴가 그 변화를 그릴 수 있도록
**`FrontmostAppGate`를 `@Observable`로** 만든다.

- 파생은 순수 함수 `nonSelfBundleID(_:selfBundleID:previous:)`이며 **nil과 자기 자신은 직전
  값을 유지한다** — 둘 다 "대상 앱이 없어졌다"가 아니라 "지금은 알 수 없다"다.
- 자기 자신 판정용 `selfBundleID`는 init 주입이다(기본값 `Bundle.main.bundleIdentifier`).
- **게이트 판정은 이 캐시를 보지 않는다** — `isFrontmostAppDisabled`는 계속
  `frontmostBundleID`만 본다.
- `deinit`이 만지는 `observerToken`에는 `@ObservationIgnored`가 필수다.

## 배경·근거 (왜)

메뉴 항목이 "지금 대상 앱"을 표시하려면 그 값이 관찰 가능해야 한다. 그런데 이 값은 최전면
캐시일 수 없다: VimAction 자신이 최전면이 되는 순간 대상 앱 정보가 사라진다.

**실기기 확인 결과(2026-08-02)**: MenuBarExtra 메뉴 클릭 자체는 자기 활성화를 유발하지
**않았다**. 대신 **Preferences 창을 여는 경로에서 `최전면 앱 → dev.pilyang.VimAction`이
실측됐다.** 기존 'Reload Config' 실패 알림의 `NSApp.activate`도 같은 경로다. 즉 캐시가
필요한 전제는 예상과 다른 경로로 실재했고, 캐시가 그것을 그대로 흡수했다(같은 세션에서
Notes 포커스 중 생성한 scaffold가 `com.apple.Notes.yaml`로 나왔다).

캐시를 게이트에 두는 이유는 **입력이 이미 거기 있기 때문**이다 — `NSWorkspace` 활성화 알림
구독과 시드가 게이트에 있고, 다른 곳에 두면 같은 알림을 두 번 구독하거나 값이 두 곳에
살게 된다.

`@Observable` 전환이 문제가 되지 않는 근거:

- 핫 패스(`EventTapController`가 키마다 `isFrontmostAppDisabled`·`frontmostBundleID`를 읽는다)가
  더해 받는 것은 `access(keyPath:)`뿐이고, 추적 스코프가 없는 탭 콜백에서는 즉시 반환한다.
- **같은 콜백이 이미 `@Observable`인 `EventTapController`의 프로퍼티를 읽는다** — 새로운
  성격의 비용이 아니라 이미 수용된 비용이다.
- 진짜 비싼 쪽인 **변경 통지**는 `update(bundleID:)`·`update(disabledBundleIDs:)`의 기존
  동등성 가드 덕에 실제 전이(앱 전환·리로드)에만 돈다.

캐시 갱신을 `update(bundleID:)`의 동등성 early-return **뒤**에 두는 것은 파생이 멱등이기
때문이다 — 걸러진 재통지가 만들 결과가 통과했을 때와 같다.

## 검토한 대안

- **`AppState`가 콜백으로 미러 프로퍼티 유지**: 기각. 핫 패스 클래스를 건드리지 않는 장점이
  있지만, 같은 값이 두 곳에 살고 콜백 발화 시점과 게이트의 early-return이 어긋나면 조용히
  드리프트한다. 코드도 배선·미러 동기화 테스트만큼 늘어난다.
- **캐시를 게이트 판정에도 재사용**: 기각. 다른 앱으로 갔는데 disable이 따라오는 오동작이
  된다. 판정과 표시는 다른 질문이다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- 코드: `FrontmostAppGate`(캐시·순수 파생·`@Observable`), `AppState.frontmostTargetBundleID`,
  `VimActionApp`의 메뉴 항목 3개.
- 관련 결정: [메뉴바 편의 기능 2종](20260802_menubar-frontmost-app-conveniences.md)의
  "구현 전제"가 여기서 확정됐다. 핫 패스 정책은
  [콜백 경량 불변식](20260725_callback-light-invariant.md)과 충돌하지 않는다.

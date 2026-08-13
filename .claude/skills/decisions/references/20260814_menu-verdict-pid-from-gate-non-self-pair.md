# 메뉴 판정 표시의 pid는 게이트 비자신 (bundleID, pid) 짝

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-14

## 결정

메뉴바 "Strategy:" 줄(현재 앱 판정 표시 — [20260813 강등·관측 결정](20260813_auto-trusted-runtime-demotion-and-observability.md))이 판정 캐시를 조회하는 pid는 **`FrontmostAppGate`의 비자신 캐시를 (bundleID, pid) 짝으로 확장**해 얻는다 (`lastNonSelfProcessID`). 짝은 같은 활성화 알림에서 **한 단위로** 갱신되며, 갱신 위치는 `update`의 dedupe 가드 **앞**이다 — 같은 번들 ID의 재실행(새 pid)은 최전면 캐시 기준 무변화라 가드에 걸리는데, 짝 갱신이 함께 걸러지면 메뉴 판정 조회가 죽은 pid로 남는다. 시드도 짝 계약을 따른다 — `forCurrentEnvironment()`가 `frontmostApplication`을 한 번만 읽어 두 값을 뽑고, XCTest 분기는 pid 시드도 무해화한다. 디스패치 경로의 판정 키는 계속 리졸버 `observedProcessID`다(변경 없음 — 이 결정은 메뉴 표시 전용).

## 배경·근거 (왜)

- 세션 3 인계 문언은 "최전면 pid는 리졸버 `observedProcessID`"였으나, **메뉴를 여는 행위 자체가 VimAction을 최전면으로 만들 수 있고 리졸버에는 비자신 필터가 없다** — 그대로 쓰면 메뉴가 열리는 순간 자기 pid의 `.pending`이 조회되어 대상 앱 판정이 "판정 중"으로 오표시된다. 기존 메뉴가 게이트의 `lastNonSelfBundleID`를 쓰는 정확히 그 이유([20260802 비자신 캐시 결정](20260802_frontmost-gate-non-self-cache-observable.md))가 pid에도 적용된다.
- **번들과 pid가 한 짝인 것이 계약이다**: 메뉴 줄의 라벨(번들)과 판정(pid 조회)이 서로 다른 앱을 가리키면 안 된다. 판정 캐시(`AXTrustProber`)의 키가 pid라, 짝이 갈리는 모든 창(같은 번들 재실행·시드의 이중 조회)이 오표시 창이다.
- 게이트 쪽 확장은 사용자 확정(2026-08-14, 착수 전 질문) — 리졸버 확장 대비 AppState 배선이 최소다(게이트 핸들은 이미 있다). "번들 ID = 게이트, pid = 리졸버" 분업이 흐려지는 비용은 이 짝이 **메뉴 표시 전용**(디스패치 경로 무접촉)임을 문서·주석으로 명시해 좁혔다.

## 검토한 대안

- **리졸버에 비자신 pid 캐시 추가**: 출처 문언("리졸버 observedProcessID")을 지키고 분업도 유지하나, `AppState`가 리졸버를 생성·주입하는 배선 확장이 필요. 사용자 확정으로 기각.
- **`observedProcessID` 그대로 사용**: 배선 최소지만 메뉴 열림 순간 자기 pid 오표시. 기각.
- **번들 ID → pid 역조회(`NSRunningApplication`)**: 메뉴 평가마다 실행 중 앱 열거 + 같은 번들 다중 인스턴스 모호성. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (auto 프로브 관측 문단)
- `FrontmostAppGate`(`nonSelfTarget` 순수 파생·`lastNonSelfProcessID`·시드 단일 조회), `AppState.strategyStatusLine(for:)`, 메뉴 `VimActionApp`.

## Supersedes

- [20260802_frontmost-gate-non-self-cache-observable.md](20260802_frontmost-gate-non-self-cache-observable.md) — **부분**: 비자신 캐시 갱신이 "동등성 early-return 뒤"라는 문언(같은 번들 재실행의 pid 갱신이 걸리므로 가드 **앞** + 자체 동등성 검사로 이동) / 캐시의 게이트 소유·`@Observable`·판정 비사용 결정은 유효.

# 브라우저 클래스는 auto가 신뢰하지 않는다 — 계층 1의 동적 축(https 핸들러 앱)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-18

## 결정

auto 프로브의 계층 1(AX 접촉 없이 즉시 untrusted·재시도 없음)에 **브라우저 클래스** 축을 더한다. 브라우저 판별은 정적 목록이 아니라 **LaunchServices 등록**이다 — `NSWorkspace.shared.urlsForApplications(toOpen: https://…)`가 돌려주는 앱(= https URL 핸들러로 등록된 앱)의 번들 ID 집합을 앱 시작 시 1회 계산해 프로버에 주입한다. 탈락 계층은 새 케이스 `.browser`로 거부 목록(`.denyList`)과 구분해 관측한다(같은 종단 취급). 명시 `strategy: accessibility`는 거부 목록과 똑같이 이 축도 이긴다(사용자 지시 우선, override `.notice` 1회). 정적 거부 목록·등재 기준·YAML 비노출은 그대로다.

## 배경·근거 (왜)

- **pid 판정은 브라우저에서 범주 오류다.** 4일 도그푸딩(2026-08-15~18) 실측: Arc는 pid마다 판정이 갈렸고(08-17 pid trusted, 08-18 새 pid는 재프로브 3회가 각각 다른 신호 조합), 그 원인은 그 순간의 포커스 요소가 URL바(네이티브·정직)냐 웹 콘텐츠(사이트마다 다른 편집기)냐다. 의도적 테스트(08-18 20:53): URL바에서 첫 Vim 키 → trusted → 같은 pid로 Google Docs 편집 → `w`/`b` 무동작, **로그 0줄**(강등도 되읽어 불일치도 무발화). Comet도 같은 구조로 trusted였다. 판정 키(pid)가 요소 이질성을 못 담는 것이지 신호가 틀린 게 아니다.
- **앱 단위 정답이 없다** — Arc에는 "URL바 AX OK, Docs 불가, 일반 textarea 아마 OK"만 있다. 그래서 사용자 config(config-first)로도 못 풀고, per-element 판정만이 원리적 해법인데 그건 per-element 캐시·요소 동일성·PR-E `per_element` 스키마와 얽힌다. 지금 필요한 것은 "브라우저 웹 콘텐츠에 AX를 쓰지 않는다"는 보수적 기본이고, 잃는 것은 URL바 AX뿐(가치 미미)이다.
- **감지 불가한 거짓말은 정적 지식으로 막는다**는 거부 목록의 원칙 그대로다 — 다만 브라우저는 "앱"이 아니라 "클래스"라 번들 ID 목록은 무한(브라우저 신제품마다 등재)이고, https 핸들러 등록은 브라우저의 정의 그 자체다. 이 머신 실측: Arc·Safari·Chrome·Zen·Comet 전부 잡힘, 오탐은 Hammerspoon·iTerm(https 핸들러를 등록하는 유틸리티) — 둘 다 AX 텍스트 대상이 아니라 무해하다. 오탐의 비용은 "그 앱이 keyboard로 돈다"(D2 이전 동작)뿐이라 방향이 안전하다.
- **auto 자체는 유효하다**: 같은 4일 실측에서 단일 컨텍스트 앱은 전부 맞았다(Slack·Heynote·Zen untrusted 정직, Notion 거부 목록, TextEdit·Claude Desktop trusted 무사고, VS Code는 AX 캐럿 쓰기가 화면에 반영됨을 실측). auto를 접거나 config-first로 돌리지 않는 근거다.

## 검토한 대안

- **정적 브라우저 번들 ID 목록**: 무한 목록·신제품마다 등재. LaunchServices 등록이 같은 것을 정의로 준다. 기각.
- **요소가 https `AXWebArea` 하위인지 per-dispatch 판정(URL바 AX 유지)**: 원리적으로 더 정밀하고 `AXWebArea`가 `AXURL`을 노출함도 실측했지만, 판정이 요소 단위가 되면 pid 캐시로는 표현 못 해 per-element 캐시가 필요하다 — PR-E `per_element`와 합류시킨다. **이월**.
- **웹 콘텐츠 전반(Electron 포함) 불신**: Slack·Claude Desktop 같은 단일 사이트 앱은 번들 ID = 사이트라 per-app 거부 목록이 이미 정확히 겨눈다. 브라우저만이 멀티 컨텍스트다. 기각.
- **auto 폐기 / config-first**: 위 근거. 기각(사용자 확인).

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) — auto 프로브 계층 1 문단.
- `AXTrustProbeLayer.browser` 추가(종단), `AXTrustProber` 생성 시 브라우저 집합 주입(테스트는 기본 빈 집합 — inert seam, `forCurrentEnvironment()` 프로덕션 분기만 LaunchServices 조회), `noteReplaceDispatch`의 계층 1 판정, 판정 전이·override 로그 라벨.
- 도그푸딩 재검 항목: 브라우저(Arc·Comet·Safari)가 메뉴 `Strategy: Keyboard`, Docs·Notion 웹은 keyboard 경로.

## Supersedes

- [20260813_ax-trust-deny-list-code-constant.md](20260813_ax-trust-deny-list-code-constant.md) — **부분**: "계층 1 = 정적 번들 ID 목록 하나"라는 전제만. 등재 기준·명시 override·YAML 비노출은 유효.

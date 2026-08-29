# auto 전략 프로브

- **Last updated**: 2026-08-20 (문서 분할 — [strategy-dispatch.md](strategy-dispatch.md)에서 이관, 내용 변경 없음)

## 현재 구조

`strategy: auto` 앱의 라우팅은 **비동기 캐시 판정**이다: 리졸버 밖의 별도 협력자(`AXTrustProber`)가 전용 직렬 큐에서 판정하고(`AXRead` 50ms 상속 — 콜백·메인 스레드 AX 무접촉 불변식 유지), 결과는 `@MainActor` 판정 캐시에 실린다. **캐시 키·수명은 pid**(앱 실행 1회) — 앱 재시작이 곧 재프로브이고, 번들 ID(게이트)와 pid(리졸버)의 이원 캐시 경합 창도 pid 조회가 닫는다. 콜백은 스냅샷 시점에 `(profile.strategy, verdict[pid]) → 실효 전략`을 순수 함수로 접어 `DispatchContext`에 싣고, `usesAXWrite`는 접힌 전략만 본다(판정 단일 지점 계약 불변) ([20260813_auto-probe-async-cached-verdict-pid-lifetime.md](../../decisions/references/20260813_auto-probe-async-cached-verdict-pid-lifetime.md)).

**프로브 트리거는 그 앱의 첫 `.replace` 디스패치**다(콜백은 플래그만 세우고 프로브는 큐에서) — vim 키를 안 쓰는 앱은 AX 왕복 0건이고, Electron 기상 개입도 그 앱들에 한정된다. 마스터 토글 off·config.yaml off 앱은 프로브를 돌리지 않고, 설정 리로드는 판정 캐시를 비운다.

### 판정 계층 — default-deny, 전부 통과해야 trusted

([20260813_ax-lie-detection-read-attestation-settable.md](../../decisions/references/20260813_ax-lie-detection-read-attestation-settable.md))

1. **계층 1 — AX 무접촉 탈락, 두 축** (둘 다 즉시 untrusted·재시도 없음·pid 수명 종단, **auto 판정에만 적용** — 명시 `strategy: accessibility`가 이기며 override는 `.notice` 1회):
   - ⓐ **거부 목록**(`.denyList`) — 코드 상수, 초기값 `{notion.id}`. 등재 기준은 "프로브 신호가 잡지 못함이 실측된 거짓말 앱" ([20260813_ax-trust-deny-list-code-constant.md](../../decisions/references/20260813_ax-trust-deny-list-code-constant.md)).
   - ⓑ **브라우저 클래스**(`.browser`) — 정적 목록이 아니라 LaunchServices의 **https URL 핸들러 등록 앱** 집합(`NSWorkspace.urlsForApplications(toOpen:)`, 앱 시작 시 1회 계산해 프로버에 주입 — 테스트 기본은 빈 집합, 라이브 조회는 `forCurrentEnvironment()` 프로덕션 분기뿐). pid 단위 판정은 브라우저의 요소 이질성(네이티브 URL바 vs 사이트마다 다른 웹 콘텐츠 편집기)을 못 담아 URL바 trusted가 웹 콘텐츠로 전염하기 때문이다. 요소가 https `AXWebArea` 하위인지 보는 per-element 판정은 PR-E `per_element`로 이월 ([20260818_browser-class-auto-untrusted.md](../../decisions/references/20260818_browser-class-auto-untrusted.md)).
2. **요소 실증** — 포커스 요소 존재 + `AXSelectedTextRange` 속성 노출. **리졸버 family 값은 재사용하지 않는다**(그쪽 폴백은 `.textArea` 허용 방향, 이쪽은 default-deny) — 같은 검사를 재실행하되 신호 수집은 리졸버의 속성 목록 패스에 얹을 수 있다(값이 아니라 패스의 재사용). **콜드 형태 실패(요소 없음·미노출·읽기 실패 — settable=false 단독 제외) 시 그 앱에 `AXManualAccessibility=true`를 1회 쓰고 유계 재시도** — Electron 트리 기상. 기상을 쓴 실행은 재시도 4회·지수 백오프(200/400/800/1600ms, 프로브 전용 큐 위), 이미 깨운 앱의 재프로브는 2회·백오프. 트리거가 계층 2 탈락 한정이 아닌 것은 "요소는 보이는데 읽기만 콜드"인 반콜드 형태(Chromium auto-disable) 때문이다 ([20260814_probe-wake-on-cold-form-and-backoff.md](../../decisions/references/20260814_probe-wake-on-cold-form-and-backoff.md), [20260813_electron-tree-wake-on-probe-failure.md](../../decisions/references/20260813_electron-tree-wake-on-probe-failure.md)).
3. **요소 기하 실증**(`.geometry`) — 포커스 요소 `AXSize` 1회 읽기, **짧은 변 4pt 미만 또는 미노출이면 untrusted**. 숨은 입력 편집기(캔버스 렌더 + 숨은 contenteditable — Google Docs류)는 요소·읽기·settable·되읽기를 전부 통과해 기하만이 갈라 준다. **확정 답변**이라 콜드 형태가 아니다 — 재시도·기상 없음(settable=false 단독과 같은 편) ([20260818_hidden-input-geometry-signal.md](../../decisions/references/20260818_hidden-input-geometry-signal.md)).
4. **읽기·쓰기 가능성 실증**(`.readWrite`) — `selectedRange` 값·`characterCount`·`StringForRange` 창 읽기 + `AXUIElementIsAttributeSettable(selectedTextRange)`(무돌연변이 쓰기 축). **값을 바꾸는 쓰기 왕복은 없다**(캐럿·활성 선택·IME·타이핑 레이스가 전부 프로브 위험). visible 정합 검사도 없다(소비자는 `provenViewport`가 하류에서 가드).

### 판정 수명과 강등

pending(캐시 부재)·untrusted = key-mapping(완전 기능 — auto는 점진 강화), trusted = accessibility와 동일 라우팅. **프로브는 trusted 방향으로만 캐시를 움직이고, 반증은 런타임 증거뿐이다**: auto가 라우팅한 실행의 `.axUnavailable`이 슬라이딩 창 안 임계(10초 안 3회 — 도그푸딩 조절값 상수, `FailureBurstCounter` 재사용. 결정 문언 "연속 N회"의 창 근사다 — 신호가 execute당 최대 1건이고 표적 실패는 지속 상태라 실질 동일하며, 성공 리셋 seam을 새로 뚫지 않는다·사용자 확정)에 닿으면 untrusted(`.runtime`)로 강등한다(pid 수명 sticky — 왕복 없음). 진입점은 `update`(프로브 전용·단조성 가드)와 나란한 별도 간선 `noteAutoAXUnavailable`(신호는 어댑터 `.axUnavailable` 분기 → 게시 큐 시각 캡처 → main hop — `reportFailure` 선례 동형)이고, 강등은 **종단**이다 — 활성화 재장전과 늦게 착지한 프로브의 상향 덮어쓰기 모두 같은 가드(`Entry.isTerminal`)가 막는다. 실패한 액션은 현행대로 접고 **다음 액션부터** keyboard라 "쓰기 후 폴백 금지"와 충돌하지 않는다. 되읽어 검증 불일치는 강등 신호가 아니다(정상 앱 오탐 실측 — 관측 버킷만) ([20260813_auto-trusted-runtime-demotion-and-observability.md](../../decisions/references/20260813_auto-trusted-runtime-demotion-and-observability.md)).

untrusted(비종단)는 앱 활성화에서 재장전된다. keyboard로 진입한 Visual 세션 중 판정 착지는 세션 경로 pin이 막고, **AX로 pin된 Visual 세션 × 강등의 교차는 미결 질문**([strategy-dispatch.md](strategy-dispatch.md)) — 단 그 세션의 파괴 축 `.edit(op, .selection)`만은 위임 직전 재검증 가드가 강등 뒤에도 잡는다(가드 기준이 실효 전략이 아니라 `sessionPath` — [ax-adapter.md](ax-adapter.md)).

**선택 보고 진실성 축은 프로브가 원리적으로 못 본다**(프로브 시점에 살아 있는 선택이 없다) — 검출자는 런타임 Visual 자가 검증과 `.edit(op, .selection)` 위임 직전 선택 재검증이다(구현은 [ax-adapter.md](ax-adapter.md), [20260813_visual-selection-edit-pre-delegation-guard.md](../../decisions/references/20260813_visual-selection-edit-pre-delegation-guard.md)).

### 관측

릴리스에서 생존·디스크 영속되는 `.notice` 로그 4종 — auto 기본값 게이트·거부 목록 성장의 판정 데이터를 `log show`로 사후 회수한다 ([20260814_observation-notice-promotion-and-probe-completion-log.md](../../decisions/references/20260814_observation-notice-promotion-and-probe-completion-log.md)):

- **판정 전이** (번들 ID + 판정 + 탈락 계층)
- **auto발 `.axUnavailable` 요약** (어댑터 `.axUnavailable` 분기에서 auto 유래일 때만 상시·출처 라벨 포함 — 명시 accessibility의 같은 스킵은 DEBUG 그대로라 섞이지 않는다)
- **강등 이벤트** (강등 1줄이 판정 전이와 강등 관측을 겸한다)
- **untrusted 프로브 완료** (신호 Bool 5종(요소·노출·기하·읽기·settable) + 기상 여부 + 재프로브 횟수 — untrusted → untrusted 재프로브는 전이 로그의 사각이었다)

메뉴바가 최전면 앱의 현재 판정을 표시한다 — "Frontmost:" 줄 아래 `Strategy: AX / Keyboard / probing…` 1줄(`strategyStatusText(declared:verdict:)` 순수 함수 — 접기는 pending·untrusted를 못 가른다), **pid는 게이트 비자신 (bundleID, pid) 짝**(메뉴 열림의 자기 pid 오표시 봉쇄 — [20260814_menu-verdict-pid-from-gate-non-self-pair.md](../../decisions/references/20260814_menu-verdict-pid-from-gate-non-self-pair.md)), 프로버는 `@Observable`(발화는 실제 전이에만).

### 번들 기본 전략

**`defaultStrategy` 단일 상수 = `auto`** (2026-08-14 도그푸딩 게이트 통과 후 전환 완료) — 파서 기본값(필드 없음)과 프로파일 부재 경로가 함께 소비하고, `ResolvedProfile.empty`(builtIn 재조회 센티널)는 keyboard로 남는다 ([20260813_bundled-default-strategy-auto-flip-gated.md](../../decisions/references/20260813_bundled-default-strategy-auto-flip-gated.md)).

## 불변식·계약

- **auto 판정 캐시는 프로브로는 trusted 방향으로만 움직인다** — 반증(강등)은 런타임 증거뿐이고, 강등은 pid 수명 sticky다. 판정이 왕복(플립플롭)하는 경로는 없다.
- 프로브의 AX 호출은 전용 직렬 큐 위에서만 — 콜백·메인 스레드 AX 무접촉 불변식을 상속한다.
- 계층 1(거부 목록·브라우저 클래스)은 auto에만 적용된다 — 명시 `strategy: accessibility`는 항상 이긴다.

## 근거 요약

너무 많은 앱이 AX 지원을 거짓말하므로 auto는 default-deny로 실증된 앱만 AX에 태우되, 판정 실패의 대가는 "완전 기능인 keyboard"라 안전 방향이 보장된다. `auto` 파싱이 D2로 앞당겨진 경위는 [20260813_auto-parsing-in-d2.md](../../decisions/references/20260813_auto-parsing-in-d2.md).

## 관련

- 디스패치에서의 위치·미결 질문: [strategy-dispatch.md](strategy-dispatch.md)
- trusted 라우팅의 실행: [ax-adapter.md](ax-adapter.md)
- 프로파일 스키마 (`strategy` 필드): [profiles-and-config.md](profiles-and-config.md)
- 관측 로그 레벨 정책: [reentrancy-and-safety.md](reentrancy-and-safety.md)

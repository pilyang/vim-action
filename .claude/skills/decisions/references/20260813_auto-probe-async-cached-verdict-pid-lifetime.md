# auto 프로브 — 비동기 캐시 협력자, 판정 수명은 pid

- **결정일**: 2026-08-13

## 결정

auto 전략 프로브는 **리졸버 밖의 별도 협력자**다: 전용 직렬 큐에서 비동기로 판정하고(`AXRead` 50ms 상속), 결과는 `@MainActor` 판정 캐시에 실어 탭 콜백은 캐시만 읽는다. **판정 캐시의 키·수명은 pid**(앱 실행 1회)다. 콜백은 스냅샷 시점에 `(profile.strategy, verdict[pid]) → 실효 전략`을 **순수 함수로 접어** `DispatchContext`에 싣고, `usesAXWrite`의 시그니처·판정 단일 지점 계약은 불변이다. 판정값: 캐시 부재(pending)·untrusted = keyboard(key-mapping), trusted = accessibility와 동일. **트리거는 그 앱에서의 첫 `.replace` 디스패치**(콜백은 플래그만 세우고 프로브는 큐에서)이며, untrusted는 앱 활성화에서 재장전(재시도 가능)·재프로브는 백오프 상한·콜드 형태 실패(요소 없음/에러)만 유계 재시도(~200ms×1–2회)를 갖는다. 마스터 토글 off·config.yaml off 앱은 프로브를 돌리지 않고, 설정 리로드는 판정 캐시를 비운다. 판정 **전이 시점**에 `.info` 1줄(번들 ID + 판정 + 탈락 계층)을 남긴다.

## 배경·근거 (왜)

- 동기+소캡 프로브는 실측 기각이 확정돼 있다(3ms 캡 앱 6종 전부 실패, 앱 최초 접촉 ~20ms). 비동기 캐시형은 `FocusedElementResolver` 선례 그대로이고 "AX 호출은 콜백·메인 스레드 무접촉" 불변식을 유지한다.
- **pid 수명**이 독립 검토가 잡은 실이슈 셋을 한 번에 닫는다: ① 번들 ID 키 세션 캐시는 앱 재시작·업데이트를 넘어 생존해 잠든 트리 위에서 낡은 trusted가 남는다 ② `bundleID`(FrontmostAppGate)와 `pid`(리졸버)는 같은 알림의 **별개 옵저버**라 앱 전환 순간 어긋난 짝이 가능한데, 판정을 pid에 묶고 소비 시 `context.processID`로 조회하면 그 창이 원리적으로 닫힌다 ③ 앱 재실행이 곧 재프로브라 staleness 질문이 소거된다.
- **별도 협력자**인 이유: 리졸버는 pid 하나만 아는 계약인데 프로브는 번들 ID(거부 목록)·프로파일(auto 여부)·config(off 앱) 의존을 끌어온다 — 리졸버에 얹으면 그 계약이 오염되고, 직렬 읽기 큐를 공유하면 프로브 최악 ~200ms가 계열 판정을 지연시켜 `.unresolved` 창(실측 ~20ms 수용)이 수백 ms로 넓어진다 (독립 검토 실이슈). 단 **계층 2(요소 실증)의 신호는 리졸버가 이미 하는 `AXUIElementCopyAttributeNames` 패스에 얹을 수 있다** — 금지는 폴백 방향이 반대인 **값**(family)의 재사용이지 패스의 재사용이 아니다.
- **첫 디스패치 트리거**인 이유: 앱 활성화 트리거는 Vim 키를 한 번도 안 누른 앱까지 프로브한다 — "묻지 않는 어휘는 왕복 0건" 원칙 위반이고, Electron 기상([20260813_electron-tree-wake-on-probe-failure.md](20260813_electron-tree-wake-on-probe-failure.md))의 개입 범위를 "사용자가 실제 vim 키를 쓰는 앱"으로 한정하는 비례성의 근거이기도 하다. pending=keyboard가 완전 기능이라 첫 몇 키의 keyboard 실행은 수용 비용이다.
- trusted를 프로브로 재확인하지 않는 이유: 다중 표면 앱(브라우저 옴니박스 → 웹 캔버스)의 오판은 포커스별 재프로브로도 못 잡는다(그 표면도 읽기 실증은 통과한다) — 반증은 런타임 강등([20260813_auto-trusted-runtime-demotion-and-observability.md](20260813_auto-trusted-runtime-demotion-and-observability.md))이 담당한다. "프로브는 trusted 방향으로만, 반증은 런타임 증거로만"이 단조성의 문언이다.
- keyboard로 진입한 Visual 세션 중 판정 착지는 문제가 없음이 코드로 확인됐다 — `beginSelection`의 pin 리셋 + `sessionPath` 가드가 세션 경로를 이미 고정한다 (독립 검토 확인). 구현이 이 가드를 우회하는 자리를 만들지 않아야 한다.

## 검토한 대안

- **동기 프로브(콜백 안 소캡)**: 실측 기각 확정.
- **리졸버 갱신 파이프라인에 직접 얹기**: 계약 오염 + 큐 경합 (위). `ViewportReader`가 `FocusedTextReader`에서 갈라진 선례(수명이 다르면 프리미티브를 나눈다)를 따른다.
- **번들 ID 키 + 세션 수명**: 앱 재시작 생존이 이득이 아니라 위험 (위). 번들 ID는 거부 목록 축에만 남는다.
- **앱 활성화 즉시 프로브**: vim 미사용 앱까지 상시 왕복 + 기상 개입 범위 확대. 기각.
- **trusted의 포커스 변경마다 재프로브**: 판별력이 낮고(오판 표면도 읽기 실증은 통과) 상시 왕복만 는다. 런타임 강등으로 대체.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 신규 협력자(판정 캐시 + 프로브 큐, 순수 판정 함수와 갱신 진입점 분리 — 리졸버·게이트와 같은 테스트 형태), `DispatchContext`(실효 전략 탑재), 콜백 스냅샷 배선.

# AX 쓰기 전 단계 실패도 execute 잔여를 접는다 — `.success` 외 전부에서 중단

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1a 세션 2, 구현 수준 판단)

## 결정

"첫 미지원·첫 실패에서 execute 잔여를 통째로 스킵"([20260808_ax-write-failure-whitelist-no-fallback.md](20260808_ax-write-failure-whitelist-no-fallback.md) 구조 규칙 ①)의 적용 범위를 둘로 넓힌다.

- **(a) 쓰기 시도 후**: `.success`가 아닌 **모든** outcome에서 중단한다(문언은 "미지원·실패"였다). `.contentionSkip`·`.illegalArgument`·`.apiDisabled`·`.unexpected`도 포함이다.
- **(b) 쓰기 시도 전**: 포커스 요소 획득 실패·창 읽기 실패도 그 액션을 스킵하고 **execute 잔여까지 접는다**. 이것은 `.unproven`(창이 답 못 함 → keyboard 위임)과 **별개 축**이라 `Mapping`에 전용 케이스 `.axUnavailable`을 둔다. 보고도 폴백도 아닌 스킵인 것은 스펙 그대로다.
- 사전 경계 검증(`provenWriteRange`) 탈락은 (b)와 같은 처리이되, 우리 계산이 어긋났다는 신호라 요약이 아닌 **즉시 error 로그**를 남긴다.

## 배경·근거 (왜)

- (a)의 근거는 결정 문서 자신의 근거와 같다. 나머지 코드도 **앱의 정적 성질**(`.apiDisabled`)이거나 **50ms 타임아웃 승수**(`.contentionSkip`)라, 이어가서 얻는 것이 없고 `N × 50ms`의 게시 큐 점유만 산다. `.success`만 이어가는 default-deny가 화이트리스트 분류의 흐름 제어 판이기도 하다 — 새 코드가 늘어도 조용히 "계속 진행"으로 흘러들지 않는다.
- (b)가 필요한 이유는 **읽기 실패가 한 키 입력 안에서 일시적이지 않다**는 것이다. 전형은 Slack·VS Code처럼 포커스 요소를 아예 노출하지 않는 앱인데, 거기에 `strategy: accessibility`가 걸리면 `100j`가 액션 100건 × 50ms 캡 = 5초간 게시 큐를 잡는다. 중단 래치는 **새 키 입력이 올 때만** 끊으므로 방어가 되지 않는다.
- `.unproven`과 갈라 두는 것이 이 결정의 핵심이다. 둘은 겉보기 결과가 비슷하지만 원인이 반대다 — `.unproven`은 **창이 있는데 답을 못 한 것**(창 절단 등)이라 keyboard가 대신할 수 있고, 읽기 실패는 **물어볼 창이 없는 것**이라 keyboard 폴백이 "AX 전략을 조용히 무효화"하는 셈이 된다. 조용한 폴백은 `strategy: accessibility` 설정을 반증 불가능하게 만들어 D2가 볼 데이터를 가린다는 것이 폴백 금지 결정의 근거이기도 했다.
- 대가는 명확하고 한정적이다: AX를 안 여는 앱에 `accessibility`를 걸면 그 앱의 모션이 통째로 죽는다. 기본 전략이 keyboard라 피해 범위는 **명시 설정자 본인**(D1 구간에서는 개발자 1명)이고, 죽는 방향이 "무동작"이라 파괴적이지 않다.

## 검토한 대안

- **(b)를 그 액션만 스킵**: 스펙 문언("읽기 단계 실패는 스킵")에 가장 좁게 붙는다. 위의 5초 큐 점유가 그대로 남아 기각.
- **(b)를 `.unproven`으로 접어 keyboard 위임**: 사용자에게 가장 부드럽지만 AX 전략이 조용히 무효화되고, D2의 "AX 거짓말 감지"가 볼 표본이 사라진다.
- **(a)를 문언대로 두 코드에만 적용**: `.contentionSkip`이 곧 타임아웃이라 승수 문제가 그대로 남는다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `KeyboardAdapter`의 `Mapping.axUnavailable`과 execute의 `.ax` 분기.
- **도그푸딩 판독 주의**: AX를 안 여는 앱에서 모션이 통째로 죽는 것은 이 결정의 의도된 동작이다. DEBUG 로그 `AX 경로 스킵 — 포커스 요소·읽기 없음`이 그 증거이며, 그 앱은 프로파일에서 `strategy`를 빼는 것이 답이다(D2의 `auto`가 자동화할 자리).

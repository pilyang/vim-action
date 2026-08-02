# 캐럿 주변 읽기 API 모양 — 창 반경 256, pid 출처는 리졸버, 실패는 단일 nil

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

[게시 큐 위 읽기 결정](20260802_dispatch-read-on-posting-queue.md)이 프리미티브까지만 정하고 남긴
빈칸을, PR-B·C가 소비할 **API 모양**으로 확정한다.

1. **반환 타입 `FocusedText`는 네 필드**다: `selection`(`AXSelectedTextRange`),
   `characterCount`(`AXNumberOfCharacters`), `window`(`AXStringForRange`),
   그리고 **`windowRange`**. 마지막이 없으면 소비자가 창 안의 캐럿 위치를 계산할 수 없다 —
   절대↔상대 오프셋 변환의 유일한 근거다.
2. **창은 캐럿 기준 고정 ±256자**이고 문서 경계로 clamp한다. 선택이 범위일 때는 **양 끝 바깥**으로
   반경을 잡는다(Visual 앵커 쪽 텍스트도 창 안에 들어와야 한다). 호출자가 범위를 지정하는
   형태는 채택하지 않는다.
3. **pid 출처는 `FocusedElementResolver.observedProcessID`** 다 — `FrontmostAppGate`가 아니다.
4. **실패는 어느 단계에서든 단일 `nil`** 이다. 에러코드로 갈리지 않고(`attrUnsupported` /
   `noValue` / `cannotComplete` 구분 없음), pid 없음도 같은 `nil`이며, **그 실패는 액션 단위로
   기억된다**.
5. **타임아웃과 포커스 요소 조회는 `AXRead`가 단독 소유**한다 — 리졸버의 전용 큐 경로와
   디스패치 경로가 같은 타입을 거친다.

## 배경·근거 (왜)

### ① `windowRange`가 반환 타입에 있는 이유

창을 돌려주면서 그 창이 문서 어디인지를 빼면 소비자는 `selection.location`을 창 안 인덱스로
바꿀 수 없다. 문서 시작·끝에서 clamp가 걸리면 "창 시작 = 캐럿 − 256"이라는 가정도 깨진다 —
경계 포화 판정이 정확히 그 자리에서 필요하므로 가정으로 대신할 수 없다.

### ② 고정 반경인 이유

소비자가 요구하는 것은 단어 경계, 줄 경계, 문서 끝 포화 판정이고 전부 캐럿 근방이다. 반면
**창 읽기 비용은 실측상 크기와 무관하다**(200자 0.04~0.17ms) — 여유를 크게 잡는 비용이 사실상
0이라, 호출자마다 크기를 고민하게 만드는 유연성은 값을 치를 이유가 없다. 소비자가 생긴 뒤
반경이 모자라면 상수 하나를 올리면 된다.

### ③ pid 출처가 리졸버인 이유

`FrontmostAppGate`는 bundleID만 캐시하므로 새 상태를 들여야 하고, 무엇보다 **`family`와 pid가
다른 옵저버에서 나온다** — 앱 전환 순간 둘이 서로 다른 앱을 가리킬 수 있다. 리졸버는 이미
`observedProcessID`를 들고 있고 그것이 곧 리더가 겨냥하는 포커스 요소의 소유자라, 같은 곳에서
나온 두 값이 어긋날 자리가 구조적으로 없다. 새 상태도 0이다.

### ④ 실패를 기억하는 이유

한 액션 안에서 여러 소비자(모션 정확화 + 경계 판정)가 물을 수 있다. 실패를 기억하지 않으면
타임아웃이 나는 앱에서 물음 수만큼 캡(50ms)을 곱해 문다 — 게시 큐가 그만큼 잡힌다. 성공만
기억하고 실패를 되풀이하는 형태가 정확히 최악이다: 느린 경로에서만 반복이 일어난다.

### ⑤ `AXRead`가 타임아웃을 단독 소유하는 이유

"경로 불문 50ms 단일 상수"는 상수를 두 곳에 복사해 두면 지켜지는지 감사할 수 없다. 두 경로가
같은 진입 함수(`AXRead.focusedElement(ofProcess:)`)를 거치면 값이 갈리는 것이 애초에 불가능하다.

## 검토한 대안

- **호출자가 창 범위를 지정**: 유연하지만 PR-A 시점에 호출자가 없어 "누가 얼마를 요구하는가"를
  정할 근거가 없고, 창 읽기 비용이 크기 무관이라 얻는 것도 없다. 기각.
- **`FrontmostAppGate`에 pid 캐시 추가**: 앱 수준 값을 앱 수준 캐시에 둔다는 대칭성은 있으나,
  새 상태 + `family`와의 출처 불일치를 산다. 기각 (③).
- **에러코드별 분기** (`noValue`면 스킵, `cannotComplete`면 재시도 등): 소비자의 폴백이 무상태
  시퀀스 하나뿐이라 갈라 봐야 쓸 데가 없고, 분기가 늘면 "읽기 실패 = 무동작"이라는 최악의
  회귀 경로가 열린다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (디스패치 경로 AX 읽기 절 — 과도기 표기 해제)
- 신규 코드: `AXRead`, `FocusedText`·`FocusedTextReader`·`FocusedTextSnapshot`
- 배선: `DispatchContext.processID`, `FocusedElementResolver.observedProcessID` 노출,
  `KeyboardAdapter(reader:)`·`execute(processID:)`, `EventTapController.keyboardActionSink`
- **소비자는 아직 없다** — 매퍼가 읽기를 쓰는 것은 PR-B이고, PR-A의 동작 diff는 0이다
  (AX 호출 런타임 0건을 테스트가 고정한다)
- 상위 결정: [읽기 형태](20260802_dispatch-read-on-posting-queue.md), [타임아웃 50ms](20260802_ax-read-timeout-50ms-supersedes-3ms.md)

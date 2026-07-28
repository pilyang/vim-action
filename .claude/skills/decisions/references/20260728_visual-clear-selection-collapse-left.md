# Visual collapse는 `←` 1타 단일화 — .selection yank는 collapse 없음

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-28

## 결정

[yank collapse는 항상 왼쪽](20260727_yank-collapse-to-range-start.md)의 단일 규칙을 Visual로 확장한다:

- `clearSelection` → **`←` 1타**
- `.edit(op, .selection)` → 오퍼레이터 1타만. `.delete`/`.change`는 `Cmd-X`, **`.yank`는 `Cmd-C`만**이고 `←`를 붙이지 않는다.

**함정**: Visual `y`는 엔진이 `.edit(.yank, .selection)`과 `clearSelection`을 **한 `execute` 호출에 두 액션으로** 낸다([Visual y clearSelection 동반](20260723_visual-yank-clear-selection.md)). 양쪽 모두 `←`를 내면 캐럿이 한 칸 더 밀린다. collapse는 뒤따르는 `clearSelection`이 **전담**한다. 합산 결과가 `Cmd-C, ←`로 Normal `yw`와 같아지는 것이 정합성 확인이다. (Normal의 `yw`=`Cmd-C`+`←`는 그대로 유지된다 — 그쪽은 `clearSelection`이 안 따라온다.)

**수용 편차**: Vim의 `Esc`는 커서를 **active end**(선택을 만든 쪽 끝)에 두는데, macOS에서 선택 상태의 `←`는 항상 **왼쪽 끝**으로 접힌다.

| 상황 | Vim | 실제 | 판정 |
|---|---|---|---|
| 후진 선택 후 Esc (`v` `b` `Esc`) | active end = 왼쪽 끝 | 왼쪽 끝 | **일치** |
| 전진 선택 후 Esc (`v` `w` `Esc`) | active end = 오른쪽 끝 | 왼쪽 끝(= 시작 위치) | **편차** — 모션 폭만큼 |
| yank 후 (방향 무관) | 범위 시작 | 왼쪽 끝 = 범위 시작 | **일치** |
| `V` `j` `Esc` | 줄 L+1 | 줄 L 시작으로 올라감 | 편차 |

전부 **캐럿 위치만의 비파괴 편차**다.

## 배경·근거 (왜)

`←`가 방향 분기 없이 성립하는 이유는 원 결정 그대로다 — macOS 표준 텍스트 시스템에서 선택이 있는 상태의 `←`는 한 칸 더 이동하지 않고 **선택 시작으로 붙고**, 선택을 어느 방향으로 만들었든 "선택 시작"은 항상 왼쪽 끝이다.

핵심은 **하나의 `clearSelection` 액션이 서로 다른 두 Vim 시맨틱을 겸한다**는 점이다: yank 후의 collapse(Vim도 범위 시작)와 Esc 후의 복귀(Vim은 active end). 둘은 후진 선택에서만 우연히 일치한다. 그런데 엔진 출력은 두 경우를 구분해 주지 않는다 — 같은 `clearSelection` 케이스다. 구분하려면 어댑터가 선택 방향을 알아야 하고 그건 문서 상태 읽기(M5 AX)다.

그래서 **범위 시작 쪽으로 통일**했다. yank가 정확해지는 쪽을 택한 것인데, 근거는 두 가지다. ① yank 후 커서 위치는 곧바로 `p`의 착지점에 영향을 주는 **기능적** 값인 반면, Esc 후 커서 위치는 다음 명령의 출발점일 뿐이라 사용자가 즉시 교정한다. ② 원 결정이 이미 "왼쪽 끝 = 범위 시작"을 Normal 편집 전체의 단일 규칙으로 확정했으므로, Visual만 다른 규칙을 쓰면 같은 `y`가 Normal과 Visual에서 다르게 끝난다.

`.selection` yank에서 `←`를 빼는 것은 선택의 여지가 없다 — 엔진이 collapse를 별도 액션으로 명시했으므로 매퍼가 또 내면 중복이다. 이 중복은 골든 테스트로 고정한다(어댑터 레벨에서 `Cmd-C, ←`가 정확히 나오고 `←`가 한 번만 나가는지).

## 검토한 대안

- **`.selection` yank도 `←`를 내고 `clearSelection`은 무게시**: 게시 결과는 같지만 `clearSelection`이 Esc 경로(yank 없음)에서도 나오므로 그쪽 collapse가 사라진다. Esc 후 선택이 화면에 잔류한다. 기각.
- **Esc 전용 collapse 방향을 `→`로**: 전진 선택의 Esc는 맞아지지만 후진 선택이 틀어지고, 무엇보다 `clearSelection`이 yank 경로와 공유되므로 yank collapse가 Vim과 반대로 간다. 기각.
- **엔진에 collapse 목적지를 실어 보냄**: 원 계약이 "목적지는 어댑터 몫"으로 명시적으로 위임한 것이라([Visual y clearSelection 동반](20260723_visual-yank-clear-selection.md)) 뒤집으려면 그 결정부터 재검토해야 한다. 방향 정보는 엔진에도 없다(앵커는 어댑터 쪽 개념). 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [mode-engine.md](../../architecture/references/mode-engine.md)
- `VimAction/VisualKeyMapper.swift`의 `clearSelection`, `VimAction/EditKeyMapper.swift`의 `.selection` 분기(기존 `apply(_:)` 합성 **위**에 둔다 — `apply(.yank)`가 무조건 `←`를 덧붙이므로)
- `EditKeyMapper`의 타입 주석("모든 편집은 범위를 Shift+모션으로 선택한 뒤 오퍼레이터 1타")에 예외가 하나 생긴다 — 주석 갱신 필요
- 골든: `EditKeyMapperTests`의 `sequenceEndsWithOperatorKey`가 yank는 `[Cmd-C, ←]`로 끝난다고 단언하므로 `.selection` 분기 필요 (**이 테스트가 함정의 방어선이므로 삭제 금지**)
- 사용자 노출 편차: 전진 선택 후 Esc의 캐럿 위치 — 도그푸딩 시 버그로 오인 금지
- 관련: [yank collapse 원 결정](20260727_yank-collapse-to-range-start.md), [charwise 진입 1문자 선택](20260728_visual-charwise-entry-inclusive-selection.md) (진입이 무게시면 이 `←`가 캐럿을 표류시킨다)

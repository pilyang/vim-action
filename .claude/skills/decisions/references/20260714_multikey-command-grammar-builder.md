# 멀티키 커맨드는 문법 기반 누적 빌더로 일반화

- **결정일**: 2026-07-14

## 결정

`diw`, `dd`, `3w`, `d2w` 같은 오퍼레이터·카운트·텍스트 오브젝트 커맨드를 지원하기 위해, 엔진의 `pending`을 단일 enum(`case g`)에서 **Vim 커맨드 문법의 부분 파스 상태를 담는 구조체(누적 커맨드 빌더)** 로 일반화한다. `resolve`는 "다음 키 하나로 무조건 완결"하는 single-shot 함수에서 **extend(누적 유지) / complete(완성) / cancel(폐기)** 세 갈래를 내는 스텝 함수로 바뀐다.

대상 문법 (지원 예정 범위):

```
command     := [count] (motion | operator-cmd | mode-change)
operator-cmd := operator [count] (motion | operator 반복(dd) | text-object)
text-object := (i | a) object-char        예: iw, a", ip
```

부분 파스 상태의 골격 (세부 네이밍은 구현 시 확정):

```swift
struct PendingCommand {
    var count: Int?          // 선행 카운트 (3w의 3)
    var op: Operator?        // d, c, y …
    var opCount: Int?        // d3w의 3
    var prefix: Prefix?      // .g (gg·gi), .textObjectScope(.inner/.around) (diw의 i)
}
var pending: PendingCommand?   // nil == 대기 없음
```

**취소 규칙은 어느 깊이에서든 최우선으로 동일 적용** (cross-cutting):

- `Esc` → pending 전체 폐기 + `.swallow` + **Normal 유지**.
- 탈출 modifier 콤보(`normalModeEscapeModifiers` 교집합) → pending 전체 폐기 + `.passthrough` + **Insert 전이**.
- 무효 연속 키 → pending과 그 키를 함께 버리는 no-op (기존 결정 유지, supersede 아님).

현재 구현에서 `d[Esc]` 류 취소는 `handleNormal` 진입부의 "다음 키가 뭐든 무조건 pending 클리어"라는 single-shot 구조의 부수효과로 얻어지는데, pending이 여러 키에 걸쳐 **살아남아야 하는** 빌더 모델에서는 이 공짜 효과가 사라지므로 위 취소 규칙을 **명시적 최우선 분기**로 옮겨야 한다.

출력 계약도 확장이 필요하다: `VimAction`에 오퍼레이터+범위 합성(예: `.edit(op:, over: motion | textObject)`) 계열 추가. 세부 형태는 구현 시 확정.

기존 불변식은 전부 유지: 순수 Swift·no-macOS-import, pending 해소에 타임아웃 없음(결정론), 픽스처 단위 테스트 가능성.

## 배경·근거 (왜)

현재 `Pending`은 `case g` 하나뿐인 하드코딩 모델이고, `handleNormal`이 pending을 다음 키에서 무조건 비워 **2키를 초과하는 시퀀스의 중간 상태를 표현할 자리가 없다**. 다음 마일스톤(편집 키 x·dd, 카운트 3w — mode-engine reference에 예고됨)이 오퍼레이터·카운트·텍스트 오브젝트를 요구하므로, 케이스를 늘리기 전에 모델 자체를 정해둘 필요가 있었다.

문법 기반 부분 파스를 고른 이유: Vim 커맨드는 유한한 키 시퀀스 집합이 아니라 **문법**(카운트는 무한, 오퍼레이터는 모션/텍스트 오브젝트를 인자로 받음)이다. 상태를 문법의 슬롯(count/op/prefix)으로 두면 상태 공간이 구조적으로 닫혀 픽스처 테스트로 전수 검증하기 쉽고, 새 오퍼레이터·오브젝트 추가가 조합 등록이 아니라 슬롯 값 추가가 된다.

## 검토한 대안

- **enum 케이스 열거 확장** (`.d`, `.di`, `.g`, …): 오퍼레이터 × 카운트 × prefix 조합 폭발. 카운트(무한)는 케이스로 표현 자체가 불가. 기각.
- **시퀀스 트라이 / 제네릭 키맵** (키 시퀀스 → 액션 prefix tree): 임의 사용자 매핑엔 적합하지만, 카운트가 무한이라 트라이로 못 담고, "오퍼레이터가 모션을 인자로 받는다"는 문법 의미를 잃어 `d`×`w`, `d`×`iw`… 조합을 일일이 등록해야 한다. 기각.
- **raw 키 버퍼 누적 + 매 키 전체 재파싱**: 상태가 비구조적이라 중간 상태 불변식을 테스트하기 어렵고, 파싱이 매 키마다 처음부터 재실행된다. 기각.

## 영향 범위

- architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md) — **아직 갱신하지 않음.** 이 결정은 다음 마일스톤의 설계이고 현재 코드는 여전히 2키 single-shot 구조라, 구현이 반영될 때(plans의 해당 플랜 완료 플로우에서) 최종 상태를 갱신한다.
- 구현 시 영향 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `Pending`·`resolve(_:then:)`·`handleNormal`, `VimAction`/`Motion` 타입, `Tests/VimEngineTests/` 픽스처 전반.
- 관련 기존 결정 (유지·일반화, supersede 아님): [20260712_pending-invalid-sequence-noop.md](20260712_pending-invalid-sequence-noop.md)

# 멀티키 커맨드 빌더 (오퍼레이터·카운트·텍스트 오브젝트)

- **생성일**: 2026-07-14
- **갱신일**: 2026-07-17

## 목표

엔진이 `diw`, `dd`, `3w`, `d2w` 같은 오퍼레이터·카운트·텍스트 오브젝트 커맨드를 처리할 수 있도록, `pending`을 문법 기반 누적 빌더(부분 파스 상태)로, `resolve`를 extend/complete/cancel 스텝 함수로 재설계한다. 설계 모델은 결정 문서에 확정되어 있음 (관련 링크 참조).

**범위**: 엔진의 `VimAction` 출력까지만. 어댑터(AX/keyboard)의 오퍼레이터 실행은 이 플랜 밖. 1차 편집 키셋 = 카운트(`3w`), `x`, `dd`, `d`+모션(`dw`/`d$`/`d0`/`de`), `diw`/`daw`. 오퍼레이터는 `d`만, 텍스트 오브젝트는 `w`만 (c/y·`i"`/`ip`는 슬롯 추가로 이후 확장).

## 완료된 것

- [x] 설계 모델 결정·기록 — 문법 기반 누적 빌더 채택, 대안(케이스 열거·트라이·raw 버퍼) 기각 ([결정 문서](../../decisions/references/20260714_multikey-command-grammar-builder.md))
- [x] **구체 구현 계획 + 인터페이스 확정** (2026-07-17) — 아래 "확정 인터페이스"·"규칙"·"TDD 단계". 착수 기준선 확보 (agents mode 실행 대상).
- [x] **플랜 리뷰 반영** (2026-07-17): Esc 정확 매치 규칙 + Cmd+Esc 회귀 핀(Phase 0), count×절대 모션·`3gg` 의미 확정(Phase 1 핀), escapeCombo 선행 전제의 기록 항목(Phase 6) — 자율 실행 시 재량 판단이 필요하던 스펙 구멍 봉합.

## 확정 인터페이스 (구현 착수 기준선)

> 결정 문서가 "세부 네이밍/형태는 구현 시 확정"으로 남긴 슬롯을 아래로 못 박는다. 구현 중 문제가 드러나면 조정하되, 조정 시 Plan-1 조율 접점(맨 아래)을 함께 확인한다. **이 형태들이 실제로 동작 확인되면 Phase 6에서 decisions에 기록한다** (그 전까지는 제안 상태).

### 출력 타입 — `VimAction.swift` 확장

```swift
public enum VimAction: Hashable, Sendable {
    case move(Motion)                 // 기존 — 변경 없음
    case edit(Operator, TextRange)    // 신규
}

public enum Operator: Hashable, Sendable {
    case delete                       // d. (c/y는 이후 슬롯 추가)
}

/// 오퍼레이터가 적용될 범위.
public enum TextRange: Hashable, Sendable {
    case motion(Motion, count: Int)   // dw, d3w, d$, d0, de, x(=delete over charRight)
    case textObject(TextObject)       // diw, daw
    case line(count: Int)             // dd, 2dd
}

public enum TextObject: Hashable, Sendable {
    case word(Scope)                  // iw / aw (1차는 word만)
    public enum Scope: Hashable, Sendable { case inner, around }
}
```

### 엔진 내부 상태 — `VimEngine.swift`의 `Pending` 대체

```swift
private struct PendingCommand: Sendable {
    var count: Int?            // 선행 카운트 (3w의 3, 2dd의 2)
    var op: Operator?          // 오퍼레이터 대기 (d)
    var opCount: Int?          // d3w의 3
    var prefix: Prefix?        // g / 텍스트오브젝트 스코프

    enum Prefix: Sendable {
        case g                                 // gg (op == nil 일 때만)
        case textObjectScope(TextObject.Scope) // di/da 후 object-char 대기 (op != nil 보장)
    }
    var isEmpty: Bool { count == nil && op == nil && opCount == nil && prefix == nil }
}
private var pending: PendingCommand?   // nil == 대기 없음
```

### 확정한 설계 선택 3건 + 근거

1. **카운트 붙은 모션(`3w`)은 `.move` 반복으로 출력** (`.replace([.move(.wordForward), .move(.wordForward), .move(.wordForward)])`), `.move`에 count 슬롯을 추가하지 **않는다**. → `.move(Motion)` 시그니처가 그대로라 기존 모션 픽스처 전부가 count 1(단일 원소)로 회귀 통과. 반면 **에디트의 카운트는 반복이 아니라 `TextRange`의 `count`에 담는다**(`d3w`=6단어를 한 편집 단위로). 비대칭이지만 각 케이스에 자연스럽고 회귀 안전.
2. **`x`는 `.edit(.delete, .motion(.charRight, count: n))` 으로 표현** — 전용 케이스를 만들지 않고 delete-over-motion을 재사용. 줄 끝 문자 삭제 같은 경계는 어댑터 몫(charRight/charRightForAppend 분리와 동일 원칙). *(구현 중 어댑터 관점에서 애매하면 `TextRange.charForward(count:)` 전용 케이스로 승격 — 미미한 선택지, 기본은 재사용.)*
3. **텍스트 오브젝트 스코프는 별도 필드가 아니라 `prefix`에 합침**(`.textObjectScope`) — 결정 문서 골격 준수. `g`(op 없음)와 스코프(op 있음)를 같은 "완결 키를 기다리는 접두" 슬롯으로 통일, `op` 유무로 구분.

## 규칙 — `handleNormal` 최종 우선순위

```
handleNormal(key):
  1. [취소 — 최우선 cross-cutting, step 진입 전]
     Esc         → pending 전체 폐기 + .swallow + Normal 유지
     escapeCombo → pending 전체 폐기 + .passthrough + Insert 전이   (isEscapeCombo 기존 판정 재사용)
  2. step(pending ?? empty, key)   // fresh·continuation 통합
```

`step` 결정 트리 (위에서부터, 첫 매치):

```
A. prefix == .g            : key=='g' → complete .move(.documentStart) (선행 count 무시*) / 그 외 → invalid
B. prefix == .textObjectScope(s): key=='w' → complete .edit(op!, .textObject(.word(s))) / 그 외 → invalid
C. op != nil (오퍼레이터 대기):
     i → extend prefix=.textObjectScope(.inner)
     a → extend prefix=.textObjectScope(.around)
     digit → opCount 누적 (0-규칙*)      // 0 & opCount==nil → 모션 d0: complete .edit(op,.motion(.lineStart,1))
     == op의 키(d) → complete .edit(.delete, .line(count: eff))       // dd
     opMotion* → complete .edit(op, .motion(motion, count: eff))      // dw d$ de d3w
     그 외 → invalid                                                   // dj dk dG 포함 (linewise — 아래 참고)
D. 최상위 (op·prefix 없음, count만 있을 수 있음):
     i/a/I/A → mode=.insert, complete (기존 출력 그대로; 선행 count는 무시*)
     d → extend op=.delete
     g → extend prefix=.g
     digit → count 누적 (0-규칙*)         // 0 & count==nil → 모션 lineStart
     x → complete .edit(.delete, .motion(.charRight, count: eff))
     single-key motion → complete: count 있으면 .move 반복 ×count, 없으면 .move 단일
     미매핑 modifier 콤보 → .passthrough (Normal 유지)   // 비탈출 콤보(Ctrl+d 등)
     그 외 미매핑(모디파이어 없음) → .swallow (Normal 유지)
```

- **Esc 판정은 정확 매치**(`key == .escape` — 수식자 없음). 수식자 붙은 Esc(Cmd+Esc 등)는 규칙 1의 Esc 분기가 아니라 **escapeCombo 판정**을 탄다 — escape 셋 교집합이 있으면 passthrough+Insert, 없으면 step으로 진행. (현재 코드의 pending 경로 동작과 동치. base 매치로 구현하면 Cmd+Esc가 swallow+Normal이 되어 동작이 뒤집히는데, 기존 픽스처에 Cmd+Esc 핀이 없어 회귀 테스트가 못 잡는다 — Phase 0에서 핀 추가.)
- **count × 절대 목표 모션**(`3G`·`3$`·`3^`·`10G` 등): `.move` 반복 출력을 그대로 수용한다 — 멱등이라 결과는 무해하지만 **Vim 의미와 다름**(`3G`=3번째 줄로 이동, `3$`=2줄 아래 줄 끝)을 인지한 채로 이연 (line-target count는 `TextRange` linewise 확장과 함께 이후 확장). **`3gg`는 count 무시**하고 documentStart 단일 출력 (step A complete 시 count 버림 — mode-change 키의 count 무시와 같은 원칙). 둘 다 Phase 1 픽스처로 핀.
- `eff` = effectiveCount = `(count ?? 1) * (opCount ?? 1)` — 카운트 곱(`2d3w`=6).
- **opMotion 화이트리스트**: 오퍼레이터 뒤에 valid한 모션은 **charwise-safe 집합만** — `w e $ 0 h l b ^`. `j`/`k`/`G`는 Vim에서 **linewise** 범위(`dj`=두 줄 통삭제)인데 `TextRange.motion`엔 charwise/linewise 구분이 없어 어댑터가 의미를 복원할 수 없으므로 **invalid(no-op)로 이연** (linewise-over-motion은 `TextRange`에 구분 추가와 함께 이후 확장). 최상위 단독 모션(step D)은 기존 `singleKeyMotions` 전체 그대로 — 이 제한은 op 뒤(step C)에만 적용.
- **카운트 상한**: digit 누적은 **9,999에서 클램프** (초과 자리 digit은 무시하고 누적 상태 유지). 무제한이면 ① 19자리쯤에서 Int 오버플로 트랩(시스템 전역 훅 크래시), ② `.move` 반복 출력의 배열이 무한정 커져 탭 콜백 타임아웃 리스크. Phase 1에서 클램프 픽스처로 핀.
- **0-규칙**: `0`은 해당 카운트 슬롯이 nil이면 모션(lineStart), 이미 누적 중이면 자리값(`1`→`0`=10). digit 1–9는 항상 누적 시작/연장.
- **invalid** = pending과 그 키를 함께 버리는 no-op `.swallow` (기존 `pending-invalid-sequence-noop` 규칙 일반화).
- **count 무시(mode-change)**: `3i` 류 반복 삽입은 범위 밖 — 선행 count가 있어도 i/a/I/A는 그냥 Insert 진입.

## 남은 것 — TDD 단계 (각 단계 끝에 `swift test` 그린)

- [ ] **Phase 0 — 타입/발판 리팩터 (무동작, 회귀 핀만)**: 위 신규 타입 추가(`.edit`/`Operator`/`TextRange`/`TextObject`) + `Pending` enum → `PendingCommand` 구조체 전환 + `resolve`를 `취소 최우선 + step` 구조로 재배선. **새 키 없음** — 기존 픽스처 전부 그대로 통과가 성공 기준(리팩터를 기존 테스트로 방어). 단 **Cmd+Esc 회귀 핀 1건은 여기서 추가**(현재 동작 핀: escapeCombo로 passthrough+Insert — Esc 정확 매치 규칙이 재배선에서 base 매치로 잘못 구현되면 이 픽스처가 잡는다). `.edit` 케이스를 여기서 먼저 도입해 Plan-1 접점 조기 확정.
- [ ] **Phase 1 — 카운트**: `3w`→move×3, `3j`, `10j`(0-규칙, `1`→`0`→`j`), `0` 단독=lineStart 유지, **카운트 클램프**(`99999j`→move×9999), **절대 모션 핀**(`3G`→move(.documentEnd)×3 반복 수용, `3gg`→count 무시 documentStart 단일 — 위 규칙 참고), 카운트 후 무효/취소. GREEN: `count` 슬롯 + 모션 반복 + 클램프.
- [ ] **Phase 2 — `x`/`3x`**: `.edit(.delete,.motion(.charRight,count:))` 첫 사용. edit 출력 계약 최소 검증.
- [ ] **Phase 3 — `d`+모션·`dd`·카운트 곱**: `dw`/`d$`/`d0`/`de`, `dd`/`2dd`/`3dd`, `d3w`/`2d3w`, `d`후 Esc(취소), `d`후 무효(`dq`→no-op, **`dj`→no-op** — linewise 이연 핀). GREEN: `op`/`opCount` 슬롯, dd operator-repeat, `eff` 곱, opMotion 화이트리스트.
- [ ] **Phase 4 — 텍스트 오브젝트 `diw`/`daw`**: `diw`→inner, `daw`→around, `di`후 Esc(취소), `di`후 무효 object-char(`diq`→no-op). GREEN: `.textObjectScope` prefix + object-char `w`.
- [ ] **Phase 5 — 취소 깊이 매트릭스 전수**: Esc/escapeCombo를 각 깊이(카운트 입력 중, `d` 후, `di` 후, `d3` 후)에서 픽스처로 전수 + no-macOS-import 가드(`EngineInvariantTests`)·기존 회귀 핀 전부 그린 재확인. REFACTOR 정리.
- [ ] **Phase 6 — 기록·정리**: architecture `mode-engine.md` 최종 상태 갱신(PendingCommand 모델 + edit 출력 반영) → decisions에 **확정된 `VimAction.edit` 형태** 기록(결정 문서가 "구현 시 확정"으로 남긴 항목) + **규칙 1(취소 최우선)의 전제 기록**: escapeCombo를 모든 매핑보다 선행시키는 순서는 "현재 매핑에 modifier 콤보 키가 없다"는 사실 위에서만 동작 동치 — 향후 `Ctrl-d`(half-page) 등 modifier 매핑 추가 시 이 순서를 재검토해야 함 → 이 플랜 완료 처리(plans 완료 플로우).

## 회귀 핀 (절대 깨지면 안 됨)

- 기존 픽스처 전부: 모드 전환 8건, 모션(char/word/line/document/modifier-guard/insert) 전체, `gg`·`g`후무효·`g`후Esc·`g`후`i`, escape-modifier 8건.
- `EngineInvariantTests`의 no-macOS-import 불변식.
- 픽스처 형식(`KeySequenceFixture`/`step`/`expectFixture`) 재사용 — 새 그룹은 `EditFixtures.swift` 등 키셋별 파일로 추가.

## Plan-1 조율 접점 (단일 계약)

`VimAction` enum이 두 worktree가 공유하는 유일한 계약이다. Plan-2 = 생산자(`.edit` 케이스 추가), Plan-1(탭↔엔진 배선) = 소비자(`output.actions`를 이번 마일스톤엔 실행 없이 **로그만**).

**위험 — enum 케이스 추가는 exhaustive switch 소비자를 깨뜨린다.** Plan-1이 자연스럽게 이렇게 짜면:

```swift
// EventTapController 콜백 (위험: default 없는 switch)
for action in output.actions {
    switch action {
    case .move(let motion): log("move: \(motion)")
    }   // 지금은 .move 하나뿐이라 exhaustive → 컴파일됨
}
```

Phase 0에서 `.edit`가 추가되면 이 switch는 `error: Switch must be exhaustive`로 깨진다. **고약한 점**: 두 worktree가 다른 파일을 건드리므로(`VimAction.swift` vs `EventTapController.swift`) `git merge`는 충돌 없이 깨끗이 되는데 합쳐진 코드는 빌드가 안 된다 — 충돌 마커보다 발견이 늦다.

**방어 (두 겹):**

1. **(진짜 해결) Plan-1은 패턴 매칭을 안 한다.** 로깅이 목적이라 case 분기가 불필요 — `String(describing:)`이면 케이스가 늘어도 영원히 안 깨진다. **이 지침은 Plan-1 문서의 "탭↔엔진 배선" 항목에도 직접 기재되어 있다** (Plan-1 실행자는 이 문서를 읽지 않으므로 소비자 쪽 문서에 미러링, 2026-07-17). (`switch`가 필요하면 `default:` 하나로 흡수. `VimAction`은 library-evolution 아님이라 평범한 `default:`면 충분, `@unknown default` 불필요.)

   ```swift
   for action in output.actions {
       log("action: \(String(describing: action))")   // .move(...) / .edit(.delete, .line(count: 2))
   }
   ```

2. **(순서로 리스크 제거) `.edit`를 Phase 0에서 먼저 main에 머지.** Phase 0은 타입만 추가·무동작(기존 픽스처가 회귀 핀)이라 작고 안전한 선행 머지에 딱 맞다. 계약을 먼저 고정하면 Plan-1이 `.edit`가 있는 enum 위에서 개발하게 되어 머지 순서와 무관해진다.

두 worktree의 파일 교집합은 이 `.edit` 케이스 하나뿐 — 위 두 방어면 병렬이 안전하다.

## 진행 중 컨텍스트

- **실행 방식**: 두 활성 플랜은 worktree로 병렬 가능(Plan-1=앱 타깃 `VimAction/*.swift`, 이 플랜=엔진 타깃 `Packages/VimActionCore/*` — 파일 교집합 없음, 계약 안정). 이 플랜은 순수 로직+픽스처로 완결되어 **agents mode 자율 실행에 적합**(실기기 불필요). 실제 실행은 이후 세션에서.
- 착수 전 신선도 확인(엔진 코드가 계획 이후 바뀌었는지). 현재 기준선: `pending: Pending{case g}` + `resolve(_:then:)` single-shot (2026-07-17 확인).
- 현재 `d[Esc]` 류 취소는 `handleNormal` 진입부 무조건 pending 클리어의 부수효과 — 빌더 모델에선 pending이 여러 키에 걸쳐 살아남으므로 이 공짜 효과가 사라진다. 그래서 취소를 규칙 1의 명시적 최우선 분기로 옮긴다 (결정 문서 상세).

## 관련 링크

- decisions: [20260714_multikey-command-grammar-builder.md](../../decisions/references/20260714_multikey-command-grammar-builder.md)
- decisions: [20260712_pending-invalid-sequence-noop.md](../../decisions/references/20260712_pending-invalid-sequence-noop.md) (유지·일반화되는 기존 규칙)
- architecture: [mode-engine.md](../../architecture/references/mode-engine.md)

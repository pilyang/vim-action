# 엔진 확장 — c/y 오퍼레이터 · 텍스트 오브젝트 · linewise TextRange

- **생성일**: 2026-07-19
- **갱신일**: 2026-07-19

## 목표

엔진(`Packages/VimActionCore`)의 커맨드 문법이 c/y 오퍼레이터(`cc`/`yy`/`c$`/`yiw` 등), quote·pair 텍스트 오브젝트(`ci"`, `da(` 등), linewise 모션 범위(`dj`/`dk`/`dG`/`dgg` + c/y 조합)까지 확장되고 픽스처 테스트로 전부 커버된 상태. **순수 엔진 작업만** — 실행(어댑터)·앱 타깃 변경 없음. Plan-1(엔진↔탭 연결, 앱 타깃)과 worktree 병렬 실행용으로 파일 교집합이 없다.

**범위 밖**: Visual 모드(`Mode` 케이스 추가는 앱 글리프와 결합 발생 — Plan-1 머지 후 별도), 축약 커맨드 `C`/`D`/`Y`/`S`, tag(`it`/`at`)·문장/문단(`is`/`ip`)·`W` 계열 오브젝트, 실제 실행·클립보드(레지스터는 실행 계층 몫).

## 완료된 것

- [x] 플랜 수립 + 확정 설계 (2026-07-19, 사용자 요청 — 병렬 후보 1·2번 채택)
- [x] **c/y 오퍼레이터 일반화** (2026-07-19, `swift test` GREEN + 리뷰 패널 3종 통과) — `operatorKeys` 테이블(진입·자기 키 반복 공용), `complete` 헬퍼(change→Insert 전이 단일화), `OperatorFixtures.swift` 34케이스 + 취소 매트릭스 `c`/`ci` 깊이 추가. `cg`/`cj` 이연 핀은 linewise 단계에서 갱신될 churn을 사용자 승인 하에 추가.
- [x] **텍스트 오브젝트 확장** (2026-07-19, 커밋 8b886bb, `swift test` GREEN) — quote(double/single/backtick)·pair(paren/bracket/brace/angle) + 별칭 키 테이블, **카운트+텍스트 오브젝트 invalid(word 포함)** — 확정 설계에 없던 공백을 플랜 리뷰에서 발견, 사용자 확정(파괴적 오해석 방지, d3G와 같은 기준). `TextObjectFixtures.swift`.
- [x] **linewise TextRange** (2026-07-19, 커밋 cb76a41, `swift test` GREEN + 리뷰 패널 3종 통과 — 지적은 낡은 주석 1건뿐, 4efc9b9 반영) — additive `.linewiseMotion`, 상대(j/k) 카운트 곱·절대(G/gg)+카운트 invalid, op-pending `g` extend(카운트 판정은 완결 시점 — extend 거름은 잔류 pending 유발). 기존 `dj`/`dg`/`cj`/`cg` 이연 핀 갱신, 취소 매트릭스 `dg` 깊이 추가. `LinewiseFixtures.swift`.
- [x] **기록** (2026-07-19) — decisions 3건(change Insert 전이+cw 이연 / TextObject 확장+카운트 invalid / linewise+절대 카운트 invalid) + `mode-engine.md` 최종 상태 갱신(키셋·이연 문구 해소·픽스처 파일 목록).

## 확정 설계 (구현 착수 기준선)

> 병렬 실행자가 재량 판단 없이 착수할 수 있도록 못 박는다. 구현 중 문제가 드러나면 조정하되, 동작 확인된 형태는 "기록" 단계에서 decisions에 확정 기록한다.

### 오퍼레이터 일반화 — c/y

- `VimAction.Operator`에 `.change`, `.yank` 추가. 최상위 `c`/`y` 키는 기존 `d`와 동일 패턴으로 `op` 슬롯 채움(extend).
- **오퍼레이터 키 반복 = 줄 범위**: 현재 `key == "d" && op == .delete` 하드코딩을 "이번 키가 op 자신의 키와 일치"로 일반화 (d↔delete, c↔change, y↔yank) → `.edit(op, .line(count: effectiveCount))`. 혼합(`dc`, `yd` 등)은 화이트리스트 밖 → 기존 규칙대로 invalid.
- **`.change` 완결 시 `mode = .insert`** — `cc`/`c$`/`ciw`/`cj` 전부. 모드 전이 + replace 동시 출력은 기존 `a`/`A` 패턴과 동일. `.yank`는 Normal 유지.
- **`cw` 특례(Vim에서 `ce`처럼 동작)는 엔진이 흉내내지 않는다**: 특례의 정확한 조건(커서가 공백 위인지)은 버퍼 문맥이 필요해 엔진이 판단 불가. 엔진은 literal `.edit(.change, .motion(.wordForward, count:))`를 내고, 의미 복원은 어댑터 몫(op+모션 조합으로 식별 가능) — "기록" 단계에서 결정 문서화.
- opCount·곱 클램프·0-규칙·`i`/`a` 스코프 접두는 오퍼레이터 공통 경로라 그대로 적용됨 (코드상 이미 op-일반화되어 있음).

### 텍스트 오브젝트 확장 — quote · pair

- `VimAction.TextObject`에 케이스 추가 (기존 `word(Scope)` 형태와 일관되게 kind별 케이스 + Scope 연관값):

```swift
case quote(Quote, Scope)   // Quote { double("\""), single("'"), backtick("`") }
case pair(Pair, Scope)     // Pair { paren, bracket, brace, angle }
```

- 완결 키 매핑: `"` `'` `` ` `` → quote / `(` `)` `b` → paren / `[` `]` → bracket / `{` `}` `B` → brace / `<` `>` → angle. **여닫이 양쪽 키 + Vim 별칭(b/B) 모두 인정.**
- 경계의 실제 의미(따옴표 안/포함, 괄호 중첩 처리)는 기존 word와 같은 원칙으로 어댑터 몫 — 엔진은 kind와 scope만 낸다.
- 미매핑 완결 키는 기존 규칙대로 invalid(swallow).

### linewise TextRange — dj/dk/dG/dgg

- `TextRange`에 **additive 케이스** 추가 (기존 `.motion` 계약 불변 — 소비자 영향 없음):

```swift
/// 줄 단위 모션 범위 — `dj`(현재+아래 줄), `dG`(현재부터 마지막 줄까지).
case linewiseMotion(Motion, count: Int)
```

- 오퍼레이터 뒤 linewise 화이트리스트: `j`→lineDown, `k`→lineUp, `G`→documentEnd, `gg`→documentStart. 기존 charwise 화이트리스트(`operatorMotions`)와 별도 테이블.
- **상대 모션(j/k)만 카운트 적용** (`d2j` = `.linewiseMotion(.lineDown, count: 2)` — 총 몇 줄인지 해석은 어댑터 몫). **절대 모션(G/gg)은 카운트가 하나라도 있으면 invalid**: Vim의 `d3G`는 "3번 줄까지"라는 절대 줄 의미인데 표현할 수 없고, 파괴적 편집이라 오해석 수용 대신 invalid로 이연한다 (모션 `3G` 반복-수용과 다른 기준인 이유 — 기록 단계에 포함).
- **`dgg` 문법**: op-pending 상태에서 `g` 키가 prefix `.g`로 extend되도록 허용 (현재 `.g`는 `op == nil` 전용 — 주석·완결 분기 갱신). prefix `.g` 완결 시 `op != nil`이면 `.edit(op, .linewiseMotion(.documentStart, count:))`(카운트 있으면 invalid), `op == nil`이면 기존 `gg` 모션.

### 테스트

- 기존 픽스처 체계 그대로: `KeySequenceFixture` 테이블 + Swift Testing 파라미터라이즈드. 파일은 기존 그룹 관례를 따라 추가(예: `OperatorFixtures`/`TextObjectFixtures`/`LinewiseFixtures` — 명명은 구현 재량).
- 필수 커버: 각 오퍼레이터 완결(모드 전이 포함 — `cc` 후 `.insert`, `yy` 후 `.normal`), 혼합 오퍼레이터 invalid, quote/pair 각 kind·scope·별칭 키, linewise 카운트(`d2j`, `2dj` 곱), 절대+카운트 invalid(`d3G`, `3dgg`), `dgg`/`cgg`, 취소 경로(pending 중 Esc·탈출 콤보 — 기존 CancellationFixtures 패턴).

## 남은 것

(없음 — 전 항목 완료. 브랜치 `feat/engine-textobjects-linewise`의 PR/머지와 플랜 완료 처리(삭제)만 남음, 사용자 확인 대기.)

## 진행 중 컨텍스트

- **병렬 제약**: 이 플랜은 `Packages/VimActionCore/*`만 수정한다. Plan-1(엔진↔탭)의 남은 작업은 전부 앱 타깃 `VimAction/*.swift` — 파일 교집합 없음, worktree 병렬 안전. 앱 소비자는 `String(describing:)` 로깅이라 enum 케이스 추가 영향 없음 (소비자 exhaustive-switch 금지 계약). **`Mode`는 건드리지 않는다** — 케이스 추가 시 앱 글리프 코드와 결합 발생 (Visual이 범위 밖인 이유).
- **실행 방식**: 실기기 검증 불필요 (순수 엔진 — `swift test`만으로 GREEN) → **완전 자율 실행 가능**. Plan-2와 동일한 TDD workflow(RED→GREEN→리뷰 패널, 역할별 Opus/Sonnet 혼용) 권장.
- 취소-최우선 순서 전제(modifier 매핑 부재)는 유지된다 — 이 플랜은 modifier 매핑을 추가하지 않는다.
- `PendingCommand.Prefix`는 케이스 망라 switch라 케이스를 늘리면 컴파일이 깨지며 알려준다 (설계 의도 — 이 플랜은 Prefix 케이스 추가 없음, `.g`의 op-pending 허용만).

## 관련 링크

- architecture: [mode-engine.md](../../architecture/references/mode-engine.md)
- decisions: [20260714_multikey-command-grammar-builder.md](../../decisions/references/20260714_multikey-command-grammar-builder.md), [20260717_vimaction-edit-output-shape.md](../../decisions/references/20260717_vimaction-edit-output-shape.md), [20260717_cancellation-first-ordering-premise.md](../../decisions/references/20260717_cancellation-first-ordering-premise.md), [20260712_pending-invalid-sequence-noop.md](../../decisions/references/20260712_pending-invalid-sequence-noop.md)

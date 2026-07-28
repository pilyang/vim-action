# charwise Visual 진입은 1문자 선택 — Vim의 inclusive 시맨틱

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-28

## 결정

`beginSelection(linewise: false)` (`v` 진입)은 **`Shift-→` 1타**를 게시해 커서 아래 1문자를 즉시 선택한다. 무게시(`[]`)가 아니다.

Vim의 charwise Visual은 **inclusive**다 — `v` 직후 커서 문자가 이미 선택되어 있고 `vd`는 1문자를 지운다. 캐럿(문자 사이) 모델에 이를 옮기면 진입 시점에 1문자 폭의 선택이 존재해야 한다.

## 배경·근거 (왜)

무게시 안(`[]` — 앵커만 현재 캐럿에 두고 아무것도 게시하지 않음)은 처음에 자연스러워 보였지만 **두 부류의 오동작**을 낳는다.

**① 전 구간 off-by-one.** 선택이 exclusive가 되어 모든 전진 조작이 Vim보다 1문자씩 짧다:

| | Vim | 무게시(`[]`) | `Shift-→` |
|---|---|---|---|
| `vd` | 1문자 삭제 | **0문자** — 빈 선택에 `Cmd-X` | 1문자 ✓ |
| `vy` | 1문자 복사 | 복사 안 됨 (빈 선택 + `Cmd-C`) | 1문자 ✓ |
| `vld` | 2문자 | 1문자 | 2문자 ✓ |
| `vjd` | 다음 줄 같은 열까지 inclusive | 1문자 부족 | 정확 ✓ |

특히 `vd`·`vy`가 아무 일도 안 하는 것은 단순한 부정확이 아니라 **기능 부재로 읽힌다**. 게다가 빈 선택 + `Cmd-X`/`Cmd-C`는 "선택 없으면 줄 전체" 확장을 가진 앱(VS Code·JetBrains 계열)에서 **줄을 통째로 잘라낸다** — 이미 기록된 [경계 포화 엣지 5번](20260728_edit-boundary-saturation-accepted-edges.md)이 `v` 진입마다 발동하는 셈이다.

**② `clearSelection`의 캐럿 표류.** 엔진은 `v` 후 `Esc`와 `v` 후 `v`(이탈) 양쪽에서 `clearSelection`을 낸다. 무게시라면 그 시점에 화면 선택이 없고, [collapse 규칙](20260728_visual-clear-selection-collapse-left.md)의 `←` 1타가 **선택을 접는 대신 캐럿을 한 칸 왼쪽으로 옮긴다**. 열 0에서는 앞 줄 끝으로 감긴다. `v`/`Esc`를 반복하면 캐럿이 왼쪽으로 걸어간다 — 파괴적이지는 않지만 매우 눈에 띄고, "취소했더니 커서가 움직였다"는 가장 흔한 조작에서 나온다. `Shift-→`가 있으면 선택이 항상 존재하므로 `←`는 늘 왼쪽 끝(= 원래 캐럿)으로 접혀 **순 이동량이 0**이다.

**후진에는 손해가 없다.** 앵커는 어차피 진입 시점의 캐럿이고, 포커스가 앵커를 넘어 뒤로 가면 `Shift-→`가 만든 1문자는 그냥 흡수된다. `vb`는 두 안 모두 Vim보다 1문자 짧다(커서 문자 미포함) — 무게시 대비 **전진은 개선, 후진은 동일**이라 순수한 우위다.

수용 엣지 2종: 문서 끝에서는 `Shift-→`가 포화해 선택이 생기지 않아 ②의 표류가 그 한 위치에서 되살아난다. 줄 끝에서는 `Shift-→`가 개행을 잡아 `vd`가 줄을 병합한다 — 기존 [경계 포화 엣지 1번](20260728_edit-boundary-saturation-accepted-edges.md)과 같은 현상이며 새 엣지가 아니다.

## 검토한 대안

- **무게시 `[]`**: 위 두 부류의 오동작. 특히 `vd`/`vy` 무동작과 캐럿 표류. 기각.
- **`clearSelection`에서 선택 유무를 판정해 `←`를 조건부 게시**: 화면 상태 읽기 = AX의 영역이고, Keyboard 전략은 무상태가 전제다. 진입 쪽에서 선택을 보장하는 편이 판정 자체를 없앤다. 기각.
- **오퍼레이터 쪽에서 보정**(`.selection` 앞에 `Shift-→` 삽입): `vld`처럼 모션이 낀 경우 이미 선택이 있어 1문자를 더 먹는다. 진입 1회로 끝나는 곳에 두는 것이 옳다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/VisualKeyMapper.swift`의 `beginSelection(linewise: false)`, 골든 1행
- 이 결정으로 **세 매퍼 어디에서도 `[]`를 반환하지 않는다** — `V`→`v`의 `nil`([switchWise 근사](20260728_visual-switch-wise-focus-end-rounding.md))과 함께 "지원 ⟹ 빈 시퀀스 아님" 불변식이 매퍼 3종에 일관되게 유지된다
- 관련: [collapse 규칙](20260728_visual-clear-selection-collapse-left.md), [Visual 출력 계약](20260722_visual-mode-output-contract.md)

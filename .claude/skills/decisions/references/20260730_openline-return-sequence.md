# o/O 시퀀스 — 줄 시작 개행 후 복귀

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-30

## 결정

- `o` = `Cmd-→, Return` (줄 끝으로 간 뒤 개행)
- `O` = `Cmd-←, Return, ↑` (줄 시작에서 개행해 현재 줄을 아래로 밀고, 새로 생긴 빈 줄로 올라감)

엔진이 완결 시 이미 Insert로 전이하므로 뒤에 붙일 키는 없다. 카운트는 엔진이 무시한다(`3o`는 1회).

`Return`이 "개행"이 아니라 "전송/확정"인 앱들에서의 오동작은 **수용**한다 — Keyboard 전략에 회피 수단이 없다.

## 배경·근거 (왜)

`o`는 자명하다(줄 끝 + 개행, 단계 0 실측에서 undo 1단위 확인). 결정이 필요한 쪽은 `O`다.

`O`의 후보는 두 개였다:

| 후보 | 첫 줄에서 |
|---|---|
| `↑, Cmd-→, Return` | **`↑`가 no-op** → 현재 줄 끝에 개행 = 조용히 `o`로 퇴행 |
| `Cmd-←, Return, ↑` (채택) | 빈 첫 줄이 생기고 `↑`가 그리로 올라간다 — **정확** |

`O`를 가장 많이 쓰는 자리가 문서 맨 위인데 거기서 틀리는 후보는 쓸 수 없다. 채택안의 캐럿 추적: 캐럿을 줄 시작으로 → `Return`이 개행을 삽입해 원래 줄이 아래로 밀리고 캐럿은 그 줄 앞(=아래 줄) → `↑`가 위의 빈 줄로. 빈 줄에는 0열밖에 없으므로 착지 열도 맞는다.

**`↑`의 sticky-column 가정**: 세로 이동은 desired-x를 기억하는데, 직전의 `Cmd-←`(수평 이동)와 `Return`(삽입)이 그것을 무효화한다는 전제다. TextKit에서는 성립하고 Chromium/Electron에서는 보장이 아니라 가정이므로 도그푸딩 확인 항목이다.

**수용 편차 4종**:

1. **소프트 랩 문단에서 `O`는 빈 줄을 아예 만들지 못한다.** `Cmd-←`가 시각 행 시작이라 `Return`이 문단을 하드 분리하고, `↑`가 올라간 위 행은 빈 줄이 아니라 문단의 앞부분이다. `o`도 같은 원인으로 문단 중간에 하드 개행을 넣는다 — [linewise 시각 줄 수용 엣지](20260728_linewise-visual-line-wrap-accepted-edge.md)가 삭제에 대해 기술한 것의 **삽입 쪽 대응**이며, `O`의 실패가 더 크다(위치·내용 둘 다 틀림).
2. **autoindent 없음.** 들여쓴 줄에서 `O`/`o`는 0열에서 시작한다(Vim은 들여쓰기를 승계).
3. **단일행 필드에서 `Return`은 submit이다.** `family`가 단계 3의 리졸버까지 `.textArea` 고정이라, 검색 필드에서 `o`는 검색을 실행한다. 리졸버가 붙으면 TextField 계열에서 `nil`(정직한 스킵)로 갈 자리다.
4. **멀티라인이어도 `Return`이 전송인 앱이 있다** — Slack·Discord·Teams 컴포저는 진짜 텍스트 영역이라 **단계 3 리졸버로도 해소되지 않는다.** 자동완성 팝업이 떠 있는 코드 에디터도 같다(Return이 후보 확정). Keyboard 전략에는 앱을 아는 축이 없어 M4 프로파일의 몫이다.

## 검토한 대안

- **`↑, Cmd-→, Return`**: 첫 줄에서 `o`로 퇴행 — 기각(위 표).
- **`Ctrl-O`(`insertNewlineIgnoringFieldEditor:`)**: 표준 키바인딩에 있어 네이티브 필드의 submit 문제를 비켜갈 수 있고, 캐럿을 개행 앞에 남기면 `O` 프리미티브 자체가 된다. 다만 웹/Electron은 바인딩 사전을 참조하지 않아 커버리지가 반쪽이고, 캐럿 위치가 실측 전이라 확정할 수 없다 — **도그푸딩 측정 항목으로 이연**.
- **앱별 네이티브 프리미티브**(VS Code의 `Cmd-Enter`/`Shift-Cmd-Enter`): 랩·들여쓰기 편차를 둘 다 없애지만 앱 축이 필요하다 — M4 프로파일 몫으로 이연.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/CommandKeyMapper.swift`의 `openBelow`·`openAbove`, 골든 2행
- 관련: [openLine 출력 계약](20260723_openline-output-contract.md) (엔진 측: 카운트 무시·Insert 전이), [undo 단위 실측](20260726_undo-unit-cmdz-policy.md) (`o`의 1 undo 단위 실측), [매퍼 신설](20260730_command-key-mapper-scope.md)

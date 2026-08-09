# AX 범위 산출은 정확화 표가 침묵하는 자리에서 Vim 정확값 (실측 4건)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-09 (M5 PR-D1b 세션 1, 착수 전 사용자 확인 + Vim 실측)

## 결정

`FocusedTextOffsets`의 범위 산출은 `EditKeyMapper` 정확화 표가 **명시한** 자리에서는 그 표와 같은 답을 낸다(수단만 AX로 바뀐다). 표가 **침묵하는** 자리 — keyboard가 창을 못 물어봐서 비워 둔 곳 — 에서는 **Vim 시맨틱**을 따른다. 넷 다 실제 Vim(`vim -Nes -u NONE`)으로 확인했다.

| 자리 | keyboard(현행) | AX |
|---|---|---|
| **마지막 줄 linewise** (`dd`·`dj`·`dG`, delete/yank) | 빈 줄 잔류 | **앞 개행 흡수** — 빈 줄 없음 |
| **줄 마지막 단어의 `dw`** | 개행 포함(다음 줄로) | **줄 끝까지만** (뒤 공백은 포함) |
| **linewise 카운트 포화** (`3dd`·`5dk`) | 있는 만큼 | **있는 만큼(클램프)** — 같음 |
| **모션 성분이 0줄** (마지막 줄 `dj`·`2dd`, 첫 줄 `dk`) | 아래/위 줄을 잘못 지움 | **무효 스킵** |
| `iw`의 2자 이상 공백·구두점 런 | 다음 단어를 잡음(잔여 엣지) | 그 런 전체 |
| Visual 진입의 줄 끝 / 빈 줄 | 개행을 문다 | 마지막 글자 / `.unproven` 강등 |

부수 규칙 둘: **삽입 위치(`Insertion`)에는 `.invalid`가 없다**(`o`·`O`·`p`·`P`는 Vim에서 무효인 자리가 없다 — 그래서 `Span`과 타입이 갈린다). **Visual 진입에도 무효가 없다**(잡을 글자가 없으면 `.invalid`가 아니라 `.unproven`으로 강등 — 진입을 스킵하면 엔진은 이미 Visual로 전이한 뒤라 모드와 화면이 어긋난다).

## 배경·근거 (왜)

- **오프셋 계층 결정문의 자기 논리다.** 반경 4096을 산 이유가 "반경 256 유지 + 창 밖 위임은 AX가 keyboard가 이미 잘하던 자리에서만 정확해져 사용자 가치 상당 부분이 사라진다"였다([20260808_ax-offset-layer-window-logical-lines.md](20260808_ax-offset-layer-window-logical-lines.md)). 표 침묵 자리에서 패리티를 택하면 그 기각된 대안의 모양이 된다.
- **훨씬 큰 편차가 이미 승인돼 있다.** 논리 줄 `dd`(랩 문단 통째 삭제)는 화면 결과가 완전히 달라지는데도 "이제 그것이 정답"으로 채택됐다. 마지막 줄 빈 줄 잔류는 같은 축의 더 작은 편차이고, 20260727이 "감지가 원리적으로 불가"를 이유로 수용한 것인데 AX에서는 감지가 된다.
- **실패 방향이 전부 보수적이다** — "덜 지움" 또는 "무동작"이고 1 undo 단위다. **증명 못 하면 `.unproven`**(keyboard 위임)이라 조용한 무동작이 늘지 않는다. 마지막 줄 흡수도 창이 문서 끝에 닿았을 때만 하고(`endsWithoutTerminator`), 못 닿으면 흡수하지 않아 keyboard와 같은 답이다.
- **Vim의 버퍼는 줄의 목록**이라 마지막 줄을 지워도 빈 줄이 생기지 않는다. 우리 모델은 문자열이라 `[줄 시작, 문서 끝)`을 지우면 앞 개행이 남아 빈 줄로 보인다 — 흡수는 그 모델 차이의 번역이지 새 시맨틱이 아니다.

## 실측 (2026-08-09, `vim -Nes -u NONE` + `normal!`)

| 입력 | 결과 | 읽은 것 |
|---|---|---|
| `l1/l2/l3` 2행에서 `3dd` | `l1` | 남은 2줄을 **클램프**해 지운다 (무효가 아니다) |
| 같은 문서 3행(마지막)에서 `3dd`·`2dd` | 무변화 | **아래가 0줄이면 명령 전체가 무효** |
| `l1..l5` 4행에서 `9dd` / 5행에서 `9dd` | 4·5행 삭제 / 무변화 | 위 두 규칙의 재확인 |
| 2행에서 `5dk` (위 1줄) | `l3` | 위 방향도 클램프 |
| 1행에서 `dk`, 마지막 행에서 `dj` | 무변화 | 0 이동 = 무효 (엣지 2와 일치) |
| `abcde` 4열에서 `d5l`·`d5h` | `abc` / `de` | charwise도 클램프 (표와 일치) |
| `foo bar/baz`의 `bar`에서 `dw` | `foo /baz` | **개행을 넘지 않는다** |
| `foo bar  /baz`의 `bar`에서 `dw` | `foo /baz` | 뒤 공백은 **줄 끝까지** 포함 |
| 같은 문서에서 `d2w` | `foo ` | 클램프는 **마지막 스텝에만** — 카운트는 줄을 넘는다 |
| `foo/(빈 줄)/bar` 1행에서 `dw` | `//bar` | 다음 정지 지점이 빈 줄이어도 같은 규칙 |
| 빈 줄에서 `diw` | 무변화 | `iw`의 유일한 무효 |
| `a  b` 공백에서 `diw` | `ab` | 2자 공백 런 전체 |
| `foo bar`의 각 자리에서 `cw` | `foX bar`/`fooX bar`/`foo baX` | 런 끝·공백 런·줄 끝 전부 `changeWordRefinement`와 일치 |
| `foo bar`에서 `vlld`·`v$d` | ` bar` / `foo ` | Visual은 **inclusive**이고 `$`는 개행을 물지 않는다 |

## 검토한 대안

- **keyboard 완전 패리티**: 전략을 바꿔도 이 자리들의 동작이 안 갈린다는 이점이 있지만, "마지막 줄 `dd`가 빈 줄을 남긴다"를 AX 경로에 새로 이식하는 셈이고 AX가 공짜로 낼 수 있는 정확성을 버린다. 사용자 확인으로 기각.
- **카운트 포화를 무효로**(착수 시 초안): 엣지 2(`위 줄 수 < count → 무효`)의 대칭 확장으로 제안했으나 **실측이 뒤집었다** — Vim은 클램프하고 0 이동만 무효다. 그래서 AX는 count 1에서는 엣지 2와 같고, **count 2 이상에서만 갈린다**(`2dk`가 위 1줄뿐일 때 keyboard는 스킵, AX는 2줄 삭제). 엣지 2 문언의 전제가 count 1에서만 참이었다는 것이 이 실측의 부산물이다.
- **`dw`의 줄 끝 클램프를 "런 끝"으로**: `:help word-motions`의 문언("end of that word")을 그대로 옮기면 뒤 공백이 남는데, 실측은 **줄 끝까지** 지운다. 문언이 아니라 실측을 따랐다.
- **줄 끝 `dw`에도 블록 커서 모델 적용**(캐럿이 줄 끝일 때 마지막 글자 삭제): [20260803_line-end-charwise-vim-cursor-model.md](20260803_line-end-charwise-vim-cursor-model.md)가 "이 모델을 다른 모션으로 넓히지 않는다"를 명시해 기각. 그 자리는 빈 범위 = `.invalid`다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 신규 코드: `VimAction/FocusedTextOffsets.swift`의 `Span`·`Insertion`과 범위 함수 5종(`editSpan`·`openLineInsertion`·`pasteInsertion`·`visualEntrySpan`·`visualExtendSpan`), 검증은 `VimActionTests/FocusedTextOffsetsTests.swift`의 표 3개 + 전수 스윕.
- **소비자는 세션 2~4다** — 이 결정의 동작 편차는 편집·paste·Visual 하이브리드가 배선된 뒤에 실사용에 나타난다. D1b 도그푸딩 "버그로 오인 금지" 목록에 위 표가 들어간다.

## Supersedes

없음 — [20260808_ax-offset-layer-window-logical-lines.md](20260808_ax-offset-layer-window-logical-lines.md)와 [20260808_ax-motion-caret-model-vim-word-definition.md](20260808_ax-motion-caret-model-vim-word-definition.md)가 캐럿·안전 규칙만 정하고 열어 둔 "범위의 시맨틱"을 채운다. keyboard 경로의 수용 엣지([20260727_linewise-newline-rounding.md](20260727_linewise-newline-rounding.md)의 문서 끝 빈 줄)는 그 경로에서 그대로 유효하다.

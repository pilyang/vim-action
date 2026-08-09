# 마지막 줄 linewise 편집은 앞 개행을 흡수하지 않는다 — 클립보드가 곧 레지스터다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-09 (M5 PR-D1b 세션 3 도그푸딩 — 실측 후 결정, 사용자 확인)

## 결정

종결자 없이 끝나는 문서의 마지막 줄 linewise delete·yank는 **앞 개행을 흡수하지 않는다** — 범위는 `[줄 시작, 문서 끝)`이다(`dd`·`dj`·`dG` 공통, `spanOverLines`·`spanToDocumentEnd` 양쪽). 결과로 **빈 줄 1개가 남으며 이는 keyboard 경로와 같은 답**이다.

## 배경·근거 (왜)

- **도그푸딩 실측 (TextEdit·Notion 동일)**: `alpha⏎bravo`의 마지막 줄에서 `ddp`가 `alpha⏎⏎bravo`를 냈다 — 두 줄 교환이라는 idiom이 빈 줄을 만들었다.
- **원인은 `p`가 아니라 `dd`가 남기는 클립보드의 모양이다.** 흡수는 범위를 `[5, 11)`로 잡아 잘라낸 내용이 `"bravo"`가 아니라 **`"\nbravo"`** 가 된다 — 구분자가 **앞**에 붙는다. 문서는 `alpha`(종결자 없음)가 되고, 이어지는 linewise `p`는 규칙대로 `.appendingLine` → `Return` 합성 → `alpha` + `\n` + `"\nbravo"`.
- **뿌리는 레지스터 표현의 차이다.** Vim의 레지스터는 구조체(linewise 플래그 + 줄 텍스트)라 `dd`가 버퍼에서 빈 줄을 안 남기면서도 레지스터에는 `bravo\n`을 담는다. **우리 레지스터는 OS 클립보드의 생 텍스트**라 그 둘을 동시에 표현할 수 없다 — 한 번의 `Cmd-X`가 자르는 범위가 곧 레지스터의 모양이다.
- **흡수를 유지하면 틀리는 곳이 `ddp` 하나가 아니다**:
  - `yy`(마지막 줄)도 `"\nbravo"`를 복사한다 — **yank는 지울 것이 없으니 흡수의 이득이 0인데 손해만 남는다**.
  - 그 클립보드를 다른 앱에 `Cmd-V`하면 앞에 빈 줄이 붙는다.
  - wise 휴리스틱은 끝 글자만 보므로 `"\nbravo"`를 **charwise로 판정**한다 — 기억이 빗나가는 순간(델타 ≠ 1) 줄바꿈이 문장 중간에 박힌다.
- **잃는 것은 화면상의 빈 줄 1개**이며, 그것은 D1a 이전·keyboard 경로가 이미 수용해 온 편차다(`20260727_linewise-newline-rounding.md`의 "문서 끝에서는 빈 줄 1개가 남는다"). **기능적 정확성(레지스터)과 표시상 편차(빈 줄) 중 전자를 택한다.**
- 흡수 철회로 `ddp`가 실제로 맞는 것은 같은 세션에 들어온 `linewisePasteAfter`의 분기 덕이다(리뷰가 잡은 실이슈): `dd` 후 캐럿은 남은 빈 줄(문서 끝, **앞에 종결자 있음**)에 있고, 거기서는 구분 개행이 이미 있으므로 `.appendingLine`이 아니라 `.at`이라 `Return`이 나가지 않는다.

## 검토한 대안

- **흡수 유지 + 붙여넣기 보정**(클립보드 앞 글자를 읽어 삽입점을 줄 끝으로): `ddp`는 고쳐지지만 클립보드 자체는 계속 `"\nbravo"`라 외부 앱 붙여넣기·휴리스틱 폴백·`P`(앞에 붙여넣기)가 여전히 틀린다. 클립보드 내용을 오프셋 계층까지 배관해야 해 변경 폭도 크다. 기각 (사용자 확인).
- **흡수 유지 + `[Cmd-X, Backspace]` 2타**(잘라내기는 `[줄 시작, 문서 끝)`, 남은 빈 줄은 여벌 키로 제거): 둘 다 정확해지지만 "선택 + 오퍼레이터 1타" 계약을 깨고, `Cmd-X`가 착지하지 않으면 Backspace가 멀쩡한 글자를 먹는 **파괴적 실패 모드**가 생긴다. undo도 2단위가 될 수 있다. 기각 (사용자 확인).
- **`yank`만 흡수 철회, `delete`는 유지**: `dd` 뒤의 `p`(가장 흔한 idiom)가 그대로 깨진다. 축이 "지우는 효과"가 아니라 "레지스터 모양"이므로 오퍼레이터별로 갈리지 않는다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (표 침묵 자리 문단)
- `FocusedTextOffsets.Window.spanOverLines`·`spanToDocumentEnd` — `endsWithoutTerminator`는 남지만 소비자가 `linewisePasteAfter` 하나로 줄어든다(개행 **합성** 판정 전용).
- 도그푸딩 판독: **마지막 줄 `dd`가 빈 줄을 남기는 것이 다시 정답**이다 — 세션 2 도그푸딩 메모("마지막 줄 `dd`가 빈 줄을 안 남긴다")는 이 결정으로 무효다.
- 순수 함수 표 픽스처 5건 + 어댑터 seam 1건 갱신, `ddp` 관통 테스트 신설.

## Supersedes

- [20260809_ax-span-vim-exact-where-table-is-silent.md](20260809_ax-span-vim-exact-where-table-is-silent.md) — **부분**: "마지막 줄 linewise는 앞 개행을 흡수해 빈 줄을 남기지 않는다" 행만 뒤집는다. Vim 실측 14건의 나머지(줄 끝 `dw`의 개행 미포함, linewise 카운트 클램프, 0 이동만 무효, `Insertion`에 `.invalid` 없음, 증명 못 하면 `.unproven`)는 전부 유효하다.

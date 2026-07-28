# Visual 선택 확장은 무상태 — linewise 줄 반올림 미적용 수용

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-28

## 결정

`extendSelection(Motion)`은 **모션 매핑 결과에 Shift를 얹는 것이 전부**다. 어댑터는 현재 wise(charwise/linewise) 상태를 **들지 않으며**, `KeyboardAdapter`는 `Sendable` struct로 유지한다.

이는 **엔진이 문서화한 계약으로부터의 의도적 이탈**이다 — `VimAction.swift`는 "앵커·실제 범위는 어댑터 상태다", "linewise 세션에서의 줄 반올림은 wise를 아는 어댑터의 실행 규칙이다"라고 명시한다. v1 Keyboard 전략에서는 그 상태를 두지 않기로 하고, 대가로 아래 편차를 수용한다. AX 어댑터(M5)는 이 계약을 그대로 이행한다.

### linewise 세션(`V`)의 실제 동작

`V` 진입은 `Cmd-←, Shift-↓`라 **앵커가 줄 L의 시작점(= 하나의 점)**이다. Vim의 앵커는 **줄 L 전체**다. 이 차이가 아래 표 전부의 근원이다.

| 모션 | Vim | 실제 | 판정 |
|---|---|---|---|
| `j` | +1줄 | +1줄 | 일치 |
| `0` | no-op | no-op (포커스가 이미 열 0) | 일치 |
| `G` | 마지막 줄까지 | 줄 L 시작 → 문서 끝 | 일치 (기존 `dG` 편차와 동형) |
| `k` | 현재 + 위 줄 | **빈 선택으로 접힘** — `Vkd`가 아무것도 안 지운다 | 무해 |
| `kk` | 3줄 | 줄 L−1만 — **줄 L이 빠진다** | 파괴적(내용 오류) |
| `gg` | 문서 시작 ~ 줄 L | `[0, 줄 L 시작)` — **줄 L이 빠진다** | 파괴적(1줄 부족) |
| `h` | no-op | 줄 L에서 개행이 빠짐 — `Vhd`가 빈 줄을 남긴다 | 중간 |
| `l` | no-op | 줄 L + 개행 + 다음 줄 1문자 | 파괴적 |
| `w` `b` `e` | 줄 반올림 | 포커스가 다음 줄 단어 중간으로 샌다 | 파괴적 |
| `^` | no-op | 줄 L + 다음 줄 들여쓰기 | 파괴적 |
| `$` | no-op | 줄 L + 다음 줄 내용 | 파괴적 |

즉 `V` 세션에서 충실한 것은 **`j`·`0`·`G`와 오퍼레이터뿐**이다.

**후진 확장은 어느 설계로도 정확해질 수 없다**: 앵커가 줄 L의 *시작점*이라 위로 확장하면 줄 L이 범위에서 빠지고, 앵커를 줄 끝에 두면 이번엔 `Vj`가 줄 L을 잃는다. 정적 앵커 선택으로 양방향을 동시에 만족시킬 수 없다 — 튜닝 문제가 아니다.

## 배경·근거 (왜)

wise는 세션 속성이라 `beginSelection`/`switchSelectionWise`만 나르고 `extendSelection`에는 없다([Visual 출력 계약](20260722_visual-mode-output-contract.md)). 그래서 어댑터가 반올림을 하려면 **wise를 스스로 기억해야** 한다. 기억할지 말지가 이 결정의 실제 질문이었다.

들지 않기로 한 이유 넷:

1. **상태를 들어도 절반만 고쳐진다.** 반올림 후치 시퀀스(`Shift-↓, Shift-Cmd-←`)는 포커스가 앵커보다 **뒤**에 있을 때만 옳다. 후진 모션(`Vb`/`V0`/`Vh`)에서는 반대로 선택을 앵커 쪽으로 줄여 더 나빠지므로, 모션을 전진/후진으로 정적 분류하는 규칙이 추가로 필요하다. 그렇게 해도 위 표의 앵커 줄 누락(`Vkk`·`Vgg`)은 앵커가 앱에 박혀 있어 그대로 남는다 — 상태의 대가로 얻는 것이 **전진 charwise 조합뿐**이다.
2. **그 조합의 빈도가 낮다.** `V` 뒤에 오는 것은 압도적으로 `j`/`k`이고, `j`는 이미 정확하며 `k`는 상태가 있어도 못 고친다. `Vw`·`V$`는 Vim에서도 흔치 않은 타이핑이다.
3. **Visual의 근사 오차는 실행 전에 눈에 보인다.** 사용자는 선택 하이라이트를 보고 나서 오퍼레이터를 누른다. Normal `dw`가 맹목적으로 지우는 것과 달리 어긋난 범위는 `d`를 누르기 전에 드러나고, 사용자가 모션을 더 눌러 교정할 수 있다. 같은 크기의 부정확성이라도 파괴성이 훨씬 낮다 — [경계 포화 수용 엣지](20260728_edit-boundary-saturation-accepted-edges.md)가 "파괴적 편집에서 조건부로만 옳은 보정은 안 하느니만 못하다"고 세운 기준의 반대편이다.
4. **값 타입 계약이 깨진다.** 어댑터는 게시 직렬 큐에 캡처되는 `let`이라 가변 상태를 들려면 `struct`→`final class` + `@unchecked Sendable` 전환이 필요하다. `CGEvent` 비-`Sendable` 계약([nonisolated·Sendable](20260726_action-executor-nonisolated-sendable.md)) 위에 서 있는 게시 경로에 "큐 위에서만 접근" 주석 규약을 하나 더 얹는 비용이다.

무상태를 택하면 `extendSelection`이 **모션 매핑의 순수한 재사용**으로 남는다는 부수 효과도 크다 — 모션 매핑이 개선되면 Normal 편집과 Visual이 동시에 따라오고, Visual 전용 시퀀스 규칙이 0개다.

**다만 이것은 기술적 제약이 아니라 선택이다.** 어댑터는 단일 직렬 큐에서만 호출되므로 `linewise: Bool` 상자 하나를 두는 것은 이 코드베이스에 이미 있는 패턴(`TapPortBox`)으로 가능하다. 상자가 있으면 linewise 세션에서 `h l w b e ^ $`를 `[]`로 매핑해(Vim에서 그 모션들은 V 범위를 바꾸지 않는다) 위 표의 파괴적 편차 상당수를 없앨 수 있고, 상자가 desync됐을 때의 실패 모드는 "모션이 no-op이 된다"로 무해하다. **단계 2.5(실행 중단 래치) 후보로 남겨 둔다** — 지금 닫는 문이 아니다.

## 검토한 대안

- **어댑터가 wise 상태 보유 + linewise 세션에서 반올림 후치**: 위 4가지 이유로 v1에서는 기각. 단계 2.5 재검토 후보.
- **엔진이 `extendSelection`에 wise를 실어 보냄**: 어댑터 상태는 없앨 수 있지만 "wise는 세션 속성"이라는 출력 계약을 뒤집고, 엔진을 무변경으로 두는 이 단계의 전제도 깬다. 기각.
- **`V` 진입 시 앵커를 줄 끝에 두어 후진을 살림**: 후진(`Vk`)이 맞아지는 대신 전진(`Vj`)이 현재 줄을 잃는다. 빈도가 압도적으로 전진이라 손해. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [mode-engine.md](../../architecture/references/mode-engine.md)
- `VimAction/VisualKeyMapper.swift`의 `extendSelection`·`beginSelection`, `VimAction/MotionKeyMapper.swift`의 `selectionStrokes(for:)` 공유 추출
- `KeyboardAdapter`는 `Sendable` struct 유지 — 가변 상태 없음
- 사용자 노출 편차: 위 `V` 세션 표 전체 — 도그푸딩 시 버그로 오인 금지
- **상속된 엣지 2종**(새 엣지가 아님): ① 문서 마지막 단어에서 `w` 3타의 선택 반전([경계 포화 3번](20260728_edit-boundary-saturation-accepted-edges.md))이 `vw`에도 나타난다. ② Notion의 `Shift-Cmd-↑/↓` 블록 이동 충돌([Notion 충돌](20260727_notion-cmd-shift-vertical-conflict.md))이 `vgg vG Vgg VG` 4조합을 추가해 **6조합 → 10조합**이 된다.
- 관련: [모션 매핑 계약](20260726_motion-keystroke-mapping-contract.md), [편집 매핑 계약](20260727_edit-keystroke-mapping-contract.md), [switchWise 근사](20260728_visual-switch-wise-focus-end-rounding.md)

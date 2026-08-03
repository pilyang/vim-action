> Superseded (부분) by [20260803_line-end-cursor-model-for-word-objects.md](20260803_line-end-cursor-model-for-word-objects.md) — "다른 모션으로 넓히지 않는다"는 한정이 `iw`·`cw`의 줄 끝에 한해 완화됨 / `charRight`·`charLeft` 표와 방향 반전 수용 근거는 유효

# 줄 끝 charwise — 그 한 자리에서만 Vim의 블록 커서 모델을 따른다 (엣지 1)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-03

## 결정

[수용 엣지 1](20260728_edit-boundary-saturation-accepted-edges.md)(줄 끝 `x`/`dl`이 개행을
집어 줄이 병합되는 것)을 이렇게 해소한다 — 전부 캐럿일 때만 발동한다.

| 조건 | 결과 |
|---|---|
| 줄 끝 && 그 줄에 글자가 있음 | `Shift-←` **1타** — Vim처럼 마지막 글자를 지운다 |
| 줄 끝 && 줄이 비어 있음 | **무효** — 액션 통째 스킵 |
| 줄 끝 아님 && 줄에 남은 글자 `r < count` | `Shift-→ × r` (clamp) |

**후진(`dh`/`X`)은 방향을 뒤집지 않는다** — 줄 시작이면 무효, 앞에 남은 글자로 clamp만 한다.
Vim의 `h`는 앞 줄로 넘어가지 않기 때문이다.

이 결정은 [0폭 포화 억제](20260802_empty-selection-edit-suppression.md)의 **`charRight`/문서 끝
행을 덮어쓴다**: 문서 끝은 줄 끝의 특수 경우이므로 이제 무동작이 아니라 마지막 글자 삭제다.

## 배경·근거 (왜)

### ① 두 모델이 어긋나는 한 자리

Vim의 커서는 **문자 위**에 있고 Normal 모드에서 마지막 문자를 지나갈 수 없다. macOS의 캐럿은
**문자 사이**에 있고 줄 끝(마지막 문자 뒤)에 설 수 있다. 그래서 "캐럿이 줄 끝"은 Vim으로
옮기면 "커서가 마지막 글자 위"이고, 거기서 `x`는 그 글자를 지운다.

현행 시퀀스(`Shift-→`)는 그 자리에서 **개행을 집어 줄을 병합**한다 — 0폭이 아니라 "잘못된
것을 집는" 문제라, 세션 1의 0폭 억제 표에 넣지 않고 별건으로 미뤄 뒀던 항목이다.

### ② 이 채택을 넓히지 않는다

같은 모델을 일반화하면 줄 끝의 `dh`는 "마지막 글자 **앞**의 글자"를 지워야 하고, 모든 모션의
줄 끝 의미가 한 칸씩 밀린다. 그것은 캐럿 모델 위에 세운 실행 계층 전체를 다시 쓰는 일이며,
얻는 것보다 잃는 것이 크다(중간 상태에서 모션과 편집이 서로 다른 모델을 쓰게 된다).

그래서 채택 범위를 **`charRight`의 줄 끝 한 자리**로 못박는다. 나머지는 전부 캐럿 모델이다.

### ③ 문서 끝 억제를 덮어쓴 이유

세션 1은 문서 끝 `x`를 "0폭 → 게시하지 않음"으로 처리하고 도그푸딩 메모에 "안 먹는 것이
의도된 동작"이라고 적었다. 그 판단의 전제는 캐럿 모델이었다.

줄 끝에서 `x`가 마지막 글자를 지우기로 한 이상 그 전제가 깨진다. 문서 끝도 줄 끝이므로,
억제를 남겨 두면 **마지막 줄에서만 `x`가 다르게 동작한다** — 같은 키가 커서 위치에 따라 규칙을
바꾸는 것이 원래의 오동작보다 배우기 어렵다. 빈 줄·빈 문서에서만 무효가 유지되는데, 그때는
Vim에서도 지울 글자가 없다.

### ④ 이 재조립만 "현행 이하"가 아니다 — 명시 수용

[재조립 원칙](20260803_refinement-branches-not-stroke-counts.md)은 낡은 읽기의 최악이 현행
동작을 넘지 않게 하는 것인데, 방향 반전은 그 원칙의 **유일한 예외**다: 읽기가 낡아 캐럿이
실제로는 줄 중간이면 오른쪽 1글자 대신 **왼쪽 1글자**를 지운다.

수용 근거는 규모와 가시성이다 — 1글자, 1 undo 단위([실측](20260726_undo-unit-cmdz-policy.md)),
그리고 지워진 자리가 캐럿 바로 옆이라 눈에 즉시 보인다. 대안(clamp만 하고 줄 끝은 무동작)은
안전하지만 Vim 사용자가 매 줄 끝에서 `x`를 잃는다 — 일상 빈도가 레이스 빈도보다 압도적으로
높다. 사용자 결정으로 Vim 충실성을 택했다.

clamp 쪽(`r < count`)은 예외가 아니다: `min`이 카운트로 막혀 있어 현행보다 많이 낼 수 없다.

### ⑤ 재조립 결과가 **선택**이어야 한다

`Shift-←`이지 `←`가 아니다. Shift가 빠지면 캐럿만 움직이고 뒤이은 `Cmd-X`가 빈 선택에 나가
정확화가 오히려 엣지 5를 만든다 — 테스트가 이 플래그를 직접 고정한다.

## 검토한 대안

- **clamp만 하고 줄 끝은 무효로**(방향 반전 없음): 원칙의 예외가 사라져 레이스가 완전히
  안전해지지만, 줄 끝 `x`가 Vim과 달라진다. 사용자가 Vim 충실성을 선택해 기각.
- **문서 끝만 억제를 유지**(줄 끝은 반전, 문서 끝은 무동작): ③의 이유로 기각.
- **캐럿 모델 전체를 블록 커서로 재정의**: ②의 이유로 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 코드: `EditKeyMapper.charRightRefinement`·`charLeftRefinement`,
  `FocusedTextAnalysis`의 `charactersToLineEnd`·`charactersToLineStart`
- 도그푸딩: **문서 끝 `x`가 이제 마지막 글자를 지운다** — 세션 1의 "안 먹는 것이 의도"라는
  메모는 무효다.
- 나머지 엣지 정확화는 별건: [경계 포화 정확화 표](20260803_boundary-saturation-refinement-table.md)

## Supersedes

- [20260802_empty-selection-edit-suppression.md](20260802_empty-selection-edit-suppression.md)
  — **부분**. 억제 표의 `charRight`/문서 끝 행만 뒤집는다(빈 줄·빈 문서는 계속 무효).
  나머지 5종(`charLeft`·`wordEndForward`·`wordBackward`·`lineEnd`·`lineStart`)과 `.selection`
  제외 근거, 레이스 수용 논거는 유효하므로 인덱스에 남긴다.
- [20260728_edit-boundary-saturation-accepted-edges.md](20260728_edit-boundary-saturation-accepted-edges.md)
  — 엣지 1을 해소. 그 문서의 인덱스 제거는
  [정확화 표](20260803_boundary-saturation-refinement-table.md)가 처리한다.

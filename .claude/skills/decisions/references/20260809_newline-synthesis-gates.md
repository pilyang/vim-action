# 마지막 줄 `p`의 개행 합성은 `o`/`O`와 **같은 두 게이트**를 지난다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-09 (M5 PR-D1b 세션 3)

## 결정

마지막 줄 linewise `p`의 `[Return, Cmd-V]` 합성은 **줄을 만들어도 되는 자리에서만** 낸다. 게이트는 둘이고 `o`/`O`와 정확히 같다:

1. **계열이 `.textField`가 아닐 것** — 단일행 필드에서 `Return`은 대개 submit이다.
2. **프로파일이 `open_line`을 disable하지 않았을 것** — "이 앱에서 줄을 만들지 마라"는 사용자 지시다.

둘 중 하나라도 걸리면 `CommandKeyMapper.pasteDelegatedGroups(count:appendsLine:family:profile:)`가 `nil`을 내고, 호출측은 위임(현행 keyboard 경로 = [`P` 퇴행](20260808_last-line-linewise-paste-degrades-to-P.md))으로 낙하한다. 합성하지 않는 붙여넣기(charwise `p`/`P`, linewise `P`, 내부 줄 linewise `p`)는 두 게이트와 무관하게 하이브리드로 간다 — 게이트의 축은 계열이나 액션이 아니라 **"줄을 만드는가"** 다.

②의 구현은 `ResolvedProfile.newLineDisabled`(`actionOverrides[.openLine] == .disabled`)이고, `CommandKeyMapper.newLine(_:)`이 `[KeyStroke]?`가 되어 그 자리에서 `nil`을 낸다 — 매퍼는 설정 어휘(`ConfigAction`)를 계속 모른다.

## 배경·근거 (왜)

- **①: 단일행 필드는 항상 "종결자 없는 마지막 줄"이다.** 즉 그 필드의 linewise `p`는 드문 엣지가 아니라 **상시** `.appendingLine`으로 떨어진다 — 게이트가 없으면 주소창·검색창·폼 필드에서 `p` 한 번이 폼을 전송한다(되돌릴 수 없다). 근거는 [TextField 전용 편집 시퀀스 폐기](20260801_textfield-edit-sequences-scrapped.md)가 `o`/`O`를 막은 것과 같다.
- **②는 fail-open 버그였다** (3-에이전트 리뷰 발견). `ResolvedProfile.newLineStrokes`는 `.disabled`에서도 `nil`이고 — 그 프로퍼티의 doc이 "어댑터가 매핑 조회보다 앞에서 걸러내므로 매퍼까지 오지 않는다"를 근거로 그렇게 설계됐다 — `newLine()`이 `nil`을 기본 `[Return]`으로 폴백했다. 그런데 그 전제가 성립하는 것은 `.openLine` 액션뿐이다: 어댑터의 `actions:` disable 게이트는 `configAction(for:)`로 액션을 보는데, 마지막 줄 `p`는 **`.paste` 액션**이라 `open_line: disabled`를 지나지 않는다. 결과적으로 `Return`이 전송인 앱에서 disable을 택한 사용자에게 `p`가 메시지를 보낼 수 있었다 — 현행 keyboard의 linewise `p`는 `Return`을 한 번도 내지 않으므로 **새로 생긴 위험**이다.
- 방어선을 매퍼에 둔 것이 요점이다. 어댑터 게이트에 특례를 넣으면(`.paste`인데 `open_line`도 본다) 액션↔설정 대응이 1:1이 아니게 되어 `configAction` 표가 무너진다. 개행을 **실제로 합성하는 자리**에서 묻는 것이 축과 일치한다.
- **강등 결과가 안전 방향**이다 — 위임하면 현행 동작(`P` 퇴행: 위치는 한 줄 위, 구조는 온전)이고, 단일행 필드에서는 "위"가 없어 사실상 캐럿 자리 붙여넣기다. 그 필드에 linewise 개념이 애초에 없으므로 잃는 정확성이 없다.

## 검토한 대안

- **`.textField`에서 paste 하이브리드 통째 금지**: 필요 이상으로 넓다. 잃는 것은 charwise `p`의 정확한 삽입점인데, 그 자리는 하이브리드가 실제로 개선하는 자리다.
- **`Return` 없이 문서 끝 캐럿 + `Cmd-V`**: [세션 0 실측](20260808_last-line-linewise-paste-return-synthesis.md)에서 **병합 훼손**으로 기각된 naive 경로다. 게이트에 걸렸다고 되살릴 이유가 없다.
- **②를 어댑터 게이트에서 처리**(`.paste`일 때 `open_line` disable도 본다): 액션↔`ConfigAction` 대응이 깨지고, 다음에 개행을 합성하는 어휘가 늘면 게이트가 또 특례를 문다.
- **`new_line` 재정의에 기대기**(`Shift-Return`으로 바꾸면 안전하다): 사용자가 그 프로파일을 쓴 경우에만 성립한다. 프로파일은 완화 수단이지 방어선이 아니다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (위임 표 `.paste` 행, 명령 매퍼 문단)
- `ResolvedProfile.newLineDisabled` 신설, `CommandKeyMapper.newLine`이 옵셔널 반환 — `openLineDelegatedStrokes`도 같은 게이트를 지나므로 매퍼가 더는 어댑터의 앞선 게이트에 기대지 않는다(어댑터 경로의 동작은 그대로: `.disabledByProfile`).
- `KeyboardAdapter` `.paste` 분기: 위임분 `nil`이면 하이브리드를 만들지 않고 기존 위임 경로로 낙하한다(분류는 기존 규칙 그대로).

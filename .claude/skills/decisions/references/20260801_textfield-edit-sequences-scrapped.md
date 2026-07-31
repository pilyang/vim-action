# TextField 전용 편집 시퀀스는 만들지 않는다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

요소 리졸버(M3 단계 3)가 붙어도 **TextField 계열 전용 편집 시퀀스는 만들지 않는다**. `.textField`는 편집·Visual·붙여넣기·undo에서 `.textArea`와 **완전히 같은 시퀀스**를 쓴다. 원래 예시로 적혀 있던 `delete(.line)` → `Cmd-A, Delete` 같은 분기는 폐기한다.

리졸버의 역할은 시퀀스 다변화가 아니라 **걸러내기**로 축소된다.

## 배경·근거 (왜)

전략 디스패치 설계는 처음부터 "같은 `VimAction`이라도 계열마다 다른 키 시퀀스"를 전제했고, `EditKeyMapper`의 테이블 키를 `(op, range, family)`로 둔 것도 그 때문이다. 그런데 계열별 시퀀스를 실제로 설계하려고 보니 전제가 두 번 무너졌다.

**① 단일행 필드에서 TextArea 시퀀스가 이미 자연 수렴한다.** `dd`의 TextArea 시퀀스는 `Cmd-←, Shift-↓, Cmd-X`인데, 브라우저 주소창에서 `Shift-↓`는 **끝까지 선택**된다(실측). 즉 단일행 필드에서 이 시퀀스는 저절로 "전체 선택 후 잘라내기"가 되며, 이는 `Cmd-A, Delete`가 하려던 것과 같다. 전용 분기가 얻는 것이 없다.

**② 전용 분기는 오보고에 대해 실패 방향이 나쁘다.** role 보고는 앱마다 믿을 수 없다. 여러 줄 입력이 가능한데 role은 `AXTextField`로 보고하는 검색창이 실재하는데, 거기서 사용자가 원하는 `dd`는 **1줄 삭제**다. 전용 분기가 있으면 그 상황이 `Cmd-A, Delete` = **전체 삭제**로 개악된다. 분기가 없으면 오보고의 대가는 0이다:

| | 진짜 단일행 | 여러 줄인데 TextField로 오보고 |
|---|---|---|
| TextArea 시퀀스 유지 | 자연 수렴 (정상) | 정상 (1줄 삭제) |
| TextField 전용 분기 | 정상 | **전체 삭제 (파괴적)** |

한쪽 열이 전부 정상이고 다른 쪽에만 파괴적 칸이 있으면 선택의 여지가 없다.

**남는 실제 위험은 `o`/`O`의 Return 하나뿐이다** — 단일행 필드에서 Return은 대개 submit이다. 그것만 `nil` 스킵으로 걸러낸다([걸러내기 범위 결정](20260801_non-text-filter-keeps-motion-and-scroll.md)). `o` 스킵으로 생기는 "줄은 안 생겼는데 엔진은 Insert로 전이" 불일치는 **수용**한다 — 실패 모드가 Esc 한 번으로 끝나 무해하다.

Slack류 컴포저(role은 TextArea인데 Return이 전송)는 role로 구별할 수 없다 — 예정대로 M4 프로파일이 해소한다.

## 검토한 대안

- **`Cmd-A, Delete` 전용 시퀀스 채택**: 위 표의 파괴적 칸 때문에 기각. 얻는 것은 이미 자연 수렴으로 얻고 있다.
- **role 신뢰도를 높여 오보고를 줄인 뒤 분기**: 신뢰도를 올릴 수단이 앱별 지식(= 프로파일)뿐이라 M4로 미뤄지는데, 그때는 프로파일이 직접 해소하므로 분기 자체가 필요 없어진다 — 기각.
- **`family`를 매퍼 시그니처에서 제거**: `o`/`O` 분기가 실제로 `(action, family)` 테이블을 쓰므로 여전히 필요하다 — 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) — "Keyboard 어댑터 — 요소 계열" 절의 `Cmd-A, Delete` 예시가 이 결정으로 폐기됨
- `EditKeyMapper`: `switch family`에서 `.textArea`와 `.textField`가 같은 분기로 합류. 타입 정의 위의 doc 주석에 있던 `Cmd-A, Delete` 예시도 함께 정정
- `CommandKeyMapper`: `.openLine` × `.textField`만 `nil`
- 관련: [편집 매핑 계약](20260727_edit-keystroke-mapping-contract.md), [o/O 시퀀스](20260730_openline-return-sequence.md)(단일행 필드 submit 수용 항목이 여기서 걸러내기로 승격), [폴백 기본값](20260801_resolver-fallback-defaults-to-text-area.md)

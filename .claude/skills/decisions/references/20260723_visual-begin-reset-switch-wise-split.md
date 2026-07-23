# Visual 진입/전환 신호 분리 — beginSelection은 항상 리셋, 전환은 switchSelectionWise

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-23

## 결정

Visual 진입과 v↔V 전환을 **서로 다른 출력 신호로 분리**한다:

- `beginSelection(linewise:)` — **항상 새 세션**: 어댑터에 남아 있던 세션 상태가 있어도 폐기하고 앵커를 현재 캐럿으로 리셋한다. (기존 "세션 활성 중 재수신 = 앵커 유지" 의미 폐기.)
- `switchSelectionWise(linewise:)` (신설) — 세션 활성 중의 wise 전환: 앵커 유지 + wise 교체·재적용. **활성 세션이 없으면 begin처럼 새 세션으로 처리**한다 (방어 규칙 — `resetEngine()` 이후나 테스트용 `init(mode:)` 등 엔진·어댑터 상태가 어긋난 경우 대비).

함께, **탈출 modifier 콤보의 화면 선택·어댑터 세션 잔류는 수용**으로 확정한다: 콤보는 passthrough를 유지하며 `clearSelection`을 동반하지 않는다.

## 배경·근거 (왜)

코드리뷰(F2·F3)에서 같은 `beginSelection` 페이로드에 모순된 두 계약이 공존함이 확인됐다: 결정 문서는 "세션 활성 중 재수신 = 앵커 유지"(v↔V 전환용)라 하고, 엔진 주석은 "다음 beginSelection이 (stale) 세션을 리셋한다"(탈출 콤보 잔재 정리용)라 했다. 어댑터는 액션 스트림만 보므로(엔진 `mode` 참조는 racy로 기각된 설계) 둘을 구분할 수 없다 — stale charwise 세션에 `V` 진입이 오면 정상 v→V 전환과 페이로드가 동일해, "앵커 유지" 규칙을 구현한 어댑터는 수백 행 떨어진 stale 앵커에서 확장하고 이후 `d`가 의도치 않은 범위를 지운다.

엔진은 두 상황을 이미 코드 경로로 구분한다(진입은 `handleNormal`, 전환은 `handleVisual`) — 이 구분을 출력에 싣기만 하면 모호성이 사라진다.

- **케이스 분리(파라미터 아님)인 이유**: `beginSelection(linewise:, preservingAnchor:)` 파라미터안은 무효 조합(세션 없는데 preserve 등)이 표현 가능해진다 — 원 계약 결정이 wise-on-motion을 기각한 것과 같은 원칙. "소비자는 exhaustive switch 금지" 계약 덕에 케이스 추가는 소비자에 무해하다(현 소비자는 `String(describing:)` 로깅뿐).
- **탈출 콤보 잔류 수용의 근거**: 잔류 선택은 화면에 보이고, 그 위 타이핑의 대체는 표준 macOS 의미론이며 undo로 복구된다. begin이 항상 리셋이므로 잔류가 다음 Visual 세션을 오염시키는 실질 피해 경로가 없다.

## 검토한 대안

- **passthrough + actions 동반으로 `EngineOutput` 계약 확장** (탈출 콤보에 clearSelection 동반, stale 세션 원천 제거): Cmd+C처럼 선택에 작용하는 콤보 **전에** 지우면 원 계약이 passthrough를 택한 취지(콤보가 선택에 작용하는 유용성)가 깨지고, **후에** 지우면 이벤트 전달(비동기)과 AX 실행 사이 레이스 가능성이 있다. 엔진은 어떤 콤보가 선택에 작용하는지 모르므로 순서를 일반화할 수 없다. 기각.
- **어댑터가 "같은 wise의 begin 재수신 = 리셋"으로 추론**: stale 세션 + 반대 wise 진입이 정상 전환과 여전히 동일 페이로드라 불충분. 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `VimAction.swift`(케이스 신설·주석), `VimEngine.swift`(`visualStep` 전환 분기, `handleVisual` 주석), `ModeTransitionTests.swift`(전환 픽스처 2개).
- 어댑터 계약(향후 구현 시): begin = 무조건 신규 세션, switchSelectionWise = 앵커 유지 wise 교체(무세션이면 begin 취급).

## Supersedes

- [20260722_visual-mode-output-contract.md](20260722_visual-mode-output-contract.md)의 **일부** — "세션 활성 중 다시 수신하면 앵커 유지 + wise 교체" 조항만 이 문서가 대체한다. 그 외 계약(extendSelection 반복 카운트, wise는 세션 속성, clearSelection 이탈 신호, TextRange.selection)은 유효하므로 옛 문서는 인덱스에 유지.

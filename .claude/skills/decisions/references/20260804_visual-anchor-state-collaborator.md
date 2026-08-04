# Visual 앵커 상태는 게시 큐 소유의 주입 협력자

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-04

## 결정

Visual 세션의 앵커·wise 상태는 **`PasteWiseResolver` 동형의 협력자**로 둔다: `nonisolated final class` + `@unchecked Sendable`, `KeyboardAdapter.init`에 주입, **게시 직렬 큐가 단독 소유**하며 큐 밖에서 읽히지 않는다. 어댑터는 `Sendable` struct로 유지된다.

담는 것:

- **논리 앵커 A** — UTF-16 절대 오프셋. `v`는 진입 캐럿 P, `V`는 앵커 줄 기준점. `V`는 **원래 캐럿 P도 별도 보관**한다(`V`→`v` 복원의 유일한 원천).
- **wise** — charwise/linewise. [무상태 확장 결정](20260728_visual-extend-stateless-no-linewise-rounding.md)이 단계 2.5 후보로 남겨 둔 `linewise: Bool` 상자는 이 필드로 흡수된다 — 별도 상자를 만들지 않는다.
- **side** — 앱에 박힌 앵커가 논리 앵커의 어느 쪽 끝인가(`.left` 전진형 / `.right` 후진형). [재앵커](20260804_visual-backward-keyboard-reanchor.md)마다 갱신.
- **pid** — 수립 시점의 대상 앱. [무효화](20260804_visual-anchor-read-self-validation.md) 입력.
- **포커스 줄 거리** (linewise, 옵셔널) — 정확 모션(`j`/`k` ±n)으로만 추적하고 `gg`/`G` 뒤에는 미상(`nil`). [`V`→`v` 조건부 지원](20260804_visual-switch-charwise-conditional.md)의 입력.

수명: `beginSelection`에서 수립 → `clearSelection`·검증 실패·pid 불일치에서 폐기. **수립 시점은 진입 시퀀스 게시 직전의 캐럿 읽기다** — `Shift-→`·`Cmd-←`가 게시되면 원래 캐럿은 파괴되므로 이 시점 외에는 얻을 수 없다(갈림길이 아니라 필연). 상태가 없거나 읽기가 실패하면 모든 Visual 액션은 현행 무상태 시퀀스 그대로다.

## 배경·근거 (왜)

어댑터가 처음으로 상태를 드는 구조 변화라(PR-B까지의 정확화는 전부 무상태 재조립) 상태의 배치·소유가 첫 설계 결정이었다. 협력자 형태를 택한 이유:

1. **선례가 검증됐다.** `PasteWiseResolver`가 정확히 같은 형태다 — 게시 직렬 큐 위에서만 불리는 어댑터가 주입받는 상태 보유 참조 타입이고, `@unchecked Sendable`의 근거("큐가 단독 소유하므로 접근이 직렬화된다")가 그대로 이식된다.
2. **어댑터의 값 타입 계약이 유지된다.** [무상태 확장 결정](20260728_visual-extend-stateless-no-linewise-rounding.md)이 `struct`→`final class` 전환 비용("값 타입 계약이 깨진다")을 이미 기각 사유로 기록했다 — 협력자는 그 비용 없이 상태를 얻는 길이다.
3. **테스트 seam이 공짜다.** `ActionExecutor(postEvent:)`·`PasteWiseResolver(readClipboard:)`·`FocusedTextReader`와 같은 주입 자리라, 골든 테스트가 실기기 AX·클립보드 없이 상태 시나리오를 주입할 수 있다.

부수 효과: 엔진이 문서화한 계약("선택 앵커·실제 범위는 어댑터 상태다")으로부터의 **의도적 이탈이 읽기 성공 경로에서 해소**된다 — Keyboard 어댑터가 처음으로 그 계약을 이행한다.

## 검토한 대안

- **어댑터 자신이 보유 (`struct`→`final class`)**: 위 2번 비용. 기각 — 무상태 확장 결정의 근거 4가 이미 이 방향을 막아 두었다.
- **엔진이 상태 보유**: 엔진은 오프셋을 모른다(순수 Swift, 문서 접근 없음) — "앵커는 어댑터 상태"가 출력 계약인 이유 그 자체. 기각.
- **컨트롤러 보유 + 페이로드 전달**: 상태 갱신이 게시 큐 위(재앵커 시점)에서 일어나므로 콜백 스레드 소유는 격리를 역행한다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [mode-engine.md](../../architecture/references/mode-engine.md)
- `VimAction/KeyboardAdapter.swift` init 주입 목록, 새 파일(협력자 타입) — 구현은 후속 세션
- 관련: [재앵커](20260804_visual-backward-keyboard-reanchor.md), [자가 검증](20260804_visual-anchor-read-self-validation.md)

## Supersedes

- [20260728_visual-extend-stateless-no-linewise-rounding.md](20260728_visual-extend-stateless-no-linewise-rounding.md) — **부분**: "어댑터는 wise(앵커) 상태를 들지 않는다"를 뒤집는다. `V` 세션 편차 표·무상태 채택 근거 4종은 히스토리로 유효하고, **읽기 실패 폴백 경로의 동작은 여전히 그 문서의 무상태 시퀀스**다. `extendSelection`이 모션 매핑의 순수 재사용이라는 구조도 전진형 경로에서는 그대로다.

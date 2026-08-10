//
//  VisualAnchor.swift
//  VimAction
//

import Foundation

/// Visual 세션의 앵커 상태 — 어댑터가 처음으로 드는 상태다 (M5 PR-C1).
///
/// 키보드 합성의 근본 제약("앱에 박힌 앵커 너머로는 Shift+모션이 선택을 못 만든다")을
/// 재앵커 시퀀스로 풀려면, 논리 앵커가 어디이고 앱에 박힌 앵커가 그 어느 쪽 끝인지를
/// 알아야 한다 (`20260804_visual-backward-keyboard-reanchor.md`).
nonisolated struct VisualAnchorState: Equatable, Sendable {
    /// 선택 단위 — `v`(charwise) / `V`(linewise). 무상태 시절의 `linewise: Bool` 상자
    /// 재검토 후보는 이 필드로 흡수됐다 (`20260804_visual-anchor-state-collaborator.md`).
    enum Wise: Equatable, Sendable {
        case charwise
        case linewise
    }

    /// 앱에 박힌 앵커가 논리 앵커 A의 어느 쪽 끝인가.
    /// `.left` = 전진형 `[A, F+1)` / `.right` = 후진형 `[F, A+1)`. 재앵커마다 갱신된다.
    enum Side: Equatable, Sendable {
        case left
        case right
    }

    /// 논리 앵커 A — UTF-16 절대 오프셋. `v`는 진입 캐럿, `V`는 앵커 줄 시작.
    var anchor: Int
    var wise: Wise
    var side: Side
    /// 앱에 박힌 앵커의 절대 오프셋 — 자가 검증의 비교 대상이다. `anchor`에서 파생하지 않고
    /// 별도로 드는 이유: charwise는 `.right ⟹ A+1`로 파생되지만 linewise 재앵커(`←,↓`)의
    /// 앱 앵커는 앵커 **줄 끝 다음**이라 A만으로는 계산할 수 없다. 수립·재앵커 시점에는
    /// 착지를 항상 알므로 그때 기록하는 것이 공짜다.
    var pinnedEnd: Int
    /// 수립 시점의 대상 앱 — 무효화 입력 (`20260804_visual-anchor-read-self-validation.md`).
    var processID: pid_t
    /// `V` 진입 시퀀스가 파괴하기 직전의 원래 캐럿 — `V`→`v` 복원의 유일한 원천이라
    /// `V` 전용으로 보관한다 (`20260804_visual-switch-charwise-conditional.md`).
    var originalCaret: Int?
    /// 앵커 줄에서 포커스 줄까지의 부호 있는 거리 — 정확 모션(`j`/`k` ±n)으로만 추적하고
    /// `gg`/`G` 뒤에는 미상(`nil`)이다. `V`→`v` 조건부 지원의 두 번째 입력.
    var focusLineDistance: Int?
    /// 포커스의 **희망 열**(Vim curswant) — AX 경로 전용이다. charwise `j`/`k`가 물려받아
    /// 짧은 줄을 지나도 열을 복원하고(Vim 실측), `V` 세션에서는 `V`→`v` 복원의 포커스 열이다.
    /// `FocusedTextOffsets.lineEndColumn`은 `$` 뒤의 "줄 끝 고정"이다.
    ///
    /// **기본값 `nil`이 계약이다** — keyboard 세션은 열을 추적하지 않고(희망 열의 주인이 앱이다)
    /// `nil`이 그 경로의 정확한 값이라, 재앵커 기계의 상태 생성자들은 이 필드를 모른 채 남는다.
    var desiredColumn: Int?

    /// 산출 결과로 다음 상태를 만든다 — `side`·`pinnedEnd` 도출 규칙이 사는 유일한 자리다.
    ///
    /// 범위는 항상 앵커와 포커스를 잇는다 → **한쪽 끝이 반드시 앵커 쪽**이다. 시작이 앵커면
    /// 전진형이고(앱 앵커도 그 시작), 아니면 후진형이라 앱 앵커는 범위 끝이다. charwise 후진
    /// `[F, A+1)`·linewise 후진 `[포커스 줄 시작, 앵커 줄 끝 다음)`이 둘 다 이 규칙 안에 있다.
    /// 포커스 줄 거리는 **미상으로 좁힌다** — AX는 그것을 추적하지 않는다(포커스 오프셋
    /// 정확값이 그 대응물이다). 알던 값을 두면 전략이 keyboard로 넘어간 세션의 `V`→`v`가
    /// 낡은 거리로 잘못 재선택한다.
    func moved(to range: NSRange, anchor: Int, column: Int?) -> VisualAnchorState {
        var next = self
        next.anchor = anchor
        next.side = range.location == anchor ? .left : .right
        next.pinnedEnd = range.location == anchor ? anchor : range.upperBound
        next.desiredColumn = column
        next.focusLineDistance = nil
        return next
    }

    /// 읽은 선택이 이 상태와 맞는가 — 자가 검증 본체다. **앵커 쪽 끝만 본다**: 포커스 쪽은
    /// 모션 착지를 앱이 계산하므로 예측할 수 없고, 예측 가능한 쪽만 검증해야 헛실패가
    /// 최소다 (`20260804_visual-anchor-read-self-validation.md`).
    ///
    /// `length == 0` 폐기는 결정 문언(앵커 쪽 끝 + pid)보다 한 조건 많다 — Visual 세션이
    /// 살아 있다면 선택은 비어 있을 수 없으므로(진입이 이미 1자를 잡는다), 빈 선택은
    /// 세션이 화면에서 죽었다는 증거다. 틀리는 방향이 폐기(= 현행 강등)라 안전하다.
    func agrees(with text: FocusedText, processID: pid_t?) -> Bool {
        guard processID == self.processID, text.selection.length > 0 else { return false }
        switch side {
        case .left:
            return text.selection.location == pinnedEnd
        case .right:
            return text.selection.upperBound == pinnedEnd
        }
    }
}

/// 매퍼가 시퀀스와 함께 돌려주는 상태 변화 — 게시가 확정된 액션만 상태를 남기도록
/// (`recordEdit` 선례), 적용은 어댑터가 `.groups` 확정 뒤에 한다.
nonisolated enum VisualAnchorUpdate: Equatable, Sendable {
    case unchanged
    case set(VisualAnchorState)
    case discard
}

/// 매퍼가 받는 정확화 입력. **`.none`이면 무상태 폴백 경로와 바이트 동일**이어야 한다 —
/// 상태 부재·읽기 실패·검증 실패가 전부 이 케이스로 모인다 (Slack·VS Code 상시 경로).
nonisolated enum VisualAnchorContext: Equatable, Sendable {
    case none
    /// 진입(`beginSelection`) — 수립 재료. 진입 시퀀스가 게시되면 원래 캐럿은 파괴되므로
    /// 이 읽기가 캐럿을 얻을 유일한 시점이다 (`20260804_visual-anchor-state-collaborator.md`).
    case establishing(FocusedText, pid_t)
    /// 세션 중 액션 — 자가 검증을 통과한 상태 + 이번 액션의 읽기.
    case session(VisualAnchorState, FocusedText)

    /// 정확화 입력이 있는가 — 어댑터의 상태 프로브가 "매퍼의 `nil`이 정확화의 결과인가"를
    /// 판정하는 데 쓴다 (`classifyEdit`의 텍스트 프로브와 같은 자리).
    var isRefining: Bool {
        if case .none = self { return false }
        return true
    }
}

/// Visual 앵커 상태의 보유자 — `PasteWiseResolver`와 같은 형태다: 게시 직렬 큐 위에서만
/// 불리는 어댑터가 주입받는 상태 보유 참조 타입이고, **게시 직렬 큐가 단독 소유**하므로
/// 접근이 직렬화된다. `@unchecked Sendable`은 컴파일러가 못 보는 그 사실의 표현이다
/// (`20260804_visual-anchor-state-collaborator.md`).
nonisolated final class VisualAnchorTracker: @unchecked Sendable {
    /// 이 Visual 세션의 실행 경로 — 진입에서 정해지고 세션 내내 바뀌지 않는다
    /// (`20260808_ax-visual-session-path-pinning.md`).
    enum Path: Equatable, Sendable {
        case keyboard
        case accessibility
    }

    private var state: VisualAnchorState?

    /// **`beginSelection`에서만 쓰이고, 상태 폐기로는 지워지지 않는다.**
    ///
    /// 수명이 상태와 갈리는 것이 요점이다: 자가 검증 실패의 원인 중 하나가 "앱이 우리가 쓴
    /// 범위를 정규화·클램프"인데(TextEdit 실측), 그때 화면에 남은 선택은 **AX가 쓴 범위**라
    /// 무상태 `Shift-→`는 파괴 방향 동전 던지기다. 폐기와 함께 경로를 잊으면 정확히 그 자리에서
    /// 무상태 시퀀스가 나가므로, AX 세션은 상태를 잃어도 남은 확장·전환을 정직하게 스킵한다.
    ///
    /// 쓰는 자리가 진입 **둘**인 것도 계약이다: 진입 초입에서 `.keyboard`로 되돌리고(망각),
    /// AX 진입이 확정되면 `.accessibility`로 올린다. 후자만 두면 AX 분기를 골라 놓고 확정 전에
    /// 실패한 세션(요소·읽기 실패, 쓰기 실패)이 **AX가 된 적 없이** 옛 pin을 상속한다.
    private(set) var sessionPath: Path = .keyboard

    /// 초기 상태 주입은 테스트 seam이다 — 골든이 수립 없이 세션 중간 상태를 만들 수 있다.
    init(state: VisualAnchorState? = nil, sessionPath: Path = .keyboard) {
        self.state = state
        self.sessionPath = sessionPath
    }

    /// 세션 경로 고정 — 진입 초입의 망각(`.keyboard`)과 진입 확정 뒤의 승격(AX는 쓰기
    /// `.success` 뒤) 두 자리에서만 부른다.
    func pin(_ path: Path) {
        sessionPath = path
    }

    /// 상태 유무 — 읽기 전의 값싼 확인이다. 상태가 없으면 검증할 것도 없으므로 세션 중
    /// 액션은 AX 왕복 자체를 생략한다 (묻지 않으면 왕복이 0건인 lazy 규칙 그대로).
    var hasState: Bool { state != nil }

    /// 관측 전용 — 상태 수립·폐기를 검증하는 테스트가 쓴다.
    var current: VisualAnchorState? { state }

    /// 자가 검증을 통과한 상태만 돌려주고, 통과하지 못하면 **즉시 폐기**한다.
    /// 폐기는 "게시 확정 후" 규칙 밖이다 — 거짓임이 증명된 사실의 삭제이지 게시의 기억이
    /// 아니다. 반환 `nil` = 이 액션부터 현행 무상태 시퀀스 폴백.
    func validated(against text: FocusedText, processID: pid_t?) -> VisualAnchorState? {
        guard let state, state.agrees(with: text, processID: processID) else {
            self.state = nil
            return nil
        }
        return state
    }

    func apply(_ update: VisualAnchorUpdate) {
        switch update {
        case .unchanged:
            break
        case .set(let new):
            state = new
        case .discard:
            state = nil
        }
    }

    /// 포커스 줄 거리만 미상으로 좁힌다 — **읽기 실패 중에도 무상태 확장은 게시되므로**,
    /// 착지를 모른 채 알던 거리를 유지하면 `V`→`v`가 낡은 거리로 잘못 재선택한다.
    /// 좁히는 방향은 언제나 안전하다: 조건부 지원이 정직한 스킵으로 떨어질 뿐이다.
    func unknowFocusLineDistance() {
        state?.focusLineDistance = nil
    }
}

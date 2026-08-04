//
//  VisualKeyMapper.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import VimEngine

/// Visual 정확화 진입점의 반환 — 시퀀스와 함께 **상태 변화까지** 낸다. 재앵커가 side를
/// 뒤집는 것은 시퀀스 선택과 한 몸의 결정이라, 갈라 두면 두 곳이 조용히 어긋난다.
/// 적용은 어댑터가 `.groups` 확정 뒤에 한다 (`recordLinewiseEdit` 선례).
nonisolated struct VisualStrokes: Equatable, Sendable {
    var strokes: [KeyStroke]
    var anchor: VisualAnchorUpdate
}

/// Visual 선택 **세션**(진입·확장·wise 전환·이탈) → 합성 키스트로크 시퀀스.
/// `MotionKeyMapper`·`EditKeyMapper`와 같은 순수 함수다.
///
/// 세션 동작만 담당하고, 선택에 오퍼레이터를 적용하는 `.edit(op, .selection)`은
/// `EditKeyMapper`의 몫이다 — 그쪽이 `Cmd-X`/`Cmd-C` 상수와 "오퍼레이터 키로 끝난다"는
/// 불변식을 이미 들고 있다.
///
/// **앵커 상태가 뒷받침되면 시퀀스가 갈린다** (M5 PR-C1): 어댑터가 세션 액션마다 읽어
/// 검증한 상태를 `VisualAnchorContext`로 넘기고, 후진·방향 전환은 재앵커 시퀀스로
/// 재조립된다 (`20260804_visual-backward-keyboard-reanchor.md`). 상태 부재·읽기 실패·
/// 검증 실패는 전부 `.none`이며 그때의 시퀀스는 종전 무상태 매핑 그대로다 —
/// linewise 세션의 줄 반올림 미적용 등 수용 편차 표는 폴백 경로 전담이 됐다
/// (`20260728_visual-extend-stateless-no-linewise-rounding.md`).
///
/// 반환 `nil`은 **미지원**(스킵+로그)이다. 이 매퍼는 빈 배열을 반환하지 않는다 —
/// 세 매퍼 공통으로 "지원 ⟹ 빈 시퀀스 아님"이 불변식이라, 게시할 것이 없는 경우도
/// `nil`(정직한 스킵)이거나 실제 스트로크이거나 둘 중 하나다.
nonisolated enum VisualKeyMapper {
    /// 정확화 진입점 — 어댑터의 Visual 분기가 부르는 유일한 함수다.
    ///
    /// `anchor`에 기본값이 없는 것이 계약이다: 기본값을 두면 호출부가 상태를 조용히
    /// 빠뜨려도 컴파일이 통과한다 (`classifyEdit`이 `text` 받는 자리를 한 곳으로 닫은 것과
    /// 같은 이유). `.none`이면 시퀀스는 아래 무상태 매핑과 **바이트 동일**하다 — 구조가
    /// 그것을 보장한다: 스트로크는 항상 무상태 함수에 위임하고, 정확화 분기만 그보다
    /// 앞에 선다.
    static func keyStrokes(
        for action: VimAction, family: ElementFamily, profile: ResolvedProfile,
        anchor: VisualAnchorContext
    ) -> VisualStrokes? {
        if case .session(let state, let text) = anchor,
            let refined = refined(for: action, state: state, text: text, profile: profile) {
            return refined
        }
        guard let strokes = keyStrokes(for: action, family: family, profile: profile) else {
            return nil
        }
        return VisualStrokes(strokes: strokes, anchor: update(for: action, from: anchor))
    }

    /// 검증된 세션 상태가 증명하는 재조립 — 증명하지 못하면 `nil`로 아래 무상태 위임에
    /// 넘긴다 (기본값 "증명 못 함 = 현행 시퀀스"의 Visual판).
    ///
    /// 지금 갈라내는 것은 charwise `h` 하나다 (M5 PR-C1 최소 소비자) — `vb`·`Vk`·`Vgg`의
    /// 후진 전체와 wise 전환 재조립이 다음 세션에 이 자리로 들어온다.
    private static func refined(
        for action: VimAction, state: VisualAnchorState, text: FocusedText,
        profile: ResolvedProfile
    ) -> VisualStrokes? {
        guard case .extendSelection(.charLeft) = action, state.wise == .charwise,
            let backward = MotionKeyMapper.selectionStrokes(for: .charLeft, profile: profile)
        else {
            return nil
        }
        switch state.side {
        case .right:
            // 후진형 `[F, A+1)`의 앱 포커스는 정확히 F다 — 진입 `Shift-→`의 +1 원점 이동은
            // 전진형에만 있는 오차라, 연속 후진은 무보정 정확하다
            // (`20260804_visual-backward-keyboard-reanchor.md`).
            return VisualStrokes(strokes: backward, anchor: .unchanged)
        case .left:
            // 재앵커는 진입형 `[A, A+1)`에서만 필요하다 — Vim의 `h`는 앵커 왼쪽을 잡으려
            // 하는데 앱 앵커가 왼쪽 끝에 박혀 있어 `Shift-←`가 선택을 접기만 한다. 이미
            // 전진 확장된 선택(길이 ≥ 2)의 `h`는 축소라 현행 `Shift-←` 그대로 맞다.
            // (왼쪽 끝 == A는 자가 검증이 이미 보장했다 — 길이만 남는다.)
            //
            // 앵커가 **줄 시작(열 0)이면 재앵커하지 않는다** — Vim의 `h`는 앞 줄로 넘어가지
            // 않으므로(`EditKeyMapper`의 `charLeftRefinement`와 같은 규칙) 여기서 재앵커하면
            // 개행을 선택해, 뒤따르는 `d`가 줄을 병합하는 **파괴적 회귀**가 된다. 증명
            // 실패(`nil`)도 같은 편이다 — 증명 못 하면 정확화하지 않는다. 폴백 `Shift-←`는
            // 선택을 접을 뿐이라(무해) 다음 읽기의 빈 선택 검증이 상태를 정리한다.
            guard text.selection.length == 1,
                let toLineStart = text.charactersToLineStart, toLineStart > 0
            else {
                return VisualStrokes(strokes: backward, anchor: .unchanged)
            }
            // `←`(왼쪽 끝 A로 collapse) 뒤 `→`로 캐럿을 앵커 문자의 오른쪽 끝 A+1에 놓고,
            // `Shift-← ×2`로 `[A−1, A+1)`을 만든다 — 앱 앵커는 이제 오른쪽 끝이다(side 반전).
            // 접두 2타는 collapse·진입과 같은 **세션 메커니즘**이라 리터럴이고, 재확장만
            // 모션 매핑을 거친다(재정의 전파·disable 정직 스킵 유지).
            var reanchored = state
            reanchored.side = .right
            reanchored.pinnedEnd = state.anchor + 1
            return VisualStrokes(
                strokes: [collapseLeft, stepRight] + backward + backward,
                anchor: .set(reanchored))
        }
    }

    /// 무상태 시퀀스가 나갈 때의 상태 변화 — 폴백 경로가 상태를 낡게 두지 않는 것이
    /// ④~⑦ 재작업을 막는 핵심이다.
    private static func update(
        for action: VimAction, from context: VisualAnchorContext
    ) -> VisualAnchorUpdate {
        switch action {
        case .beginSelection(let linewise):
            return establishment(linewise: linewise, from: context)

        case .extendSelection:
            // charwise 폴백은 `.unchanged` — 후진 폴백이 앱 앵커를 넘어도 다음 액션의
            // 자가 검증이 잡아 폐기한다(강등 = 안전). linewise 세션은 포커스 줄 거리를
            // **미상으로 좁힌다**: 폴백 확장 뒤의 착지는 앱만 알므로, 알던 값을 그대로
            // 두면 `V`→`v`가 낡은 거리로 잘못 재선택한다.
            guard case .session(var state, _) = context, state.wise == .linewise else {
                return .unchanged
            }
            state.focusLineDistance = nil
            return .set(state)

        case .switchSelectionWise:
            // 게시되는 전환은 `v`→`V`뿐이다 (`V`→`v`는 위 위임이 `nil`로 걸렀다). 폴백은
            // 포커스 쪽만 반올림해 wise·논리 앵커가 상태와 어긋나는데 앱 앵커는 그대로라
            // 자가 검증을 **거짓 통과**한다 — 재앵커 정확화가 붙기 전까지 폐기가 유일하게
            // 정직하다.
            return .discard

        case .clearSelection:
            return .discard

        default:
            // 도달 불가 — 위 위임이 Visual 어휘 밖을 이미 `nil`로 걸렀다.
            return .unchanged
        }
    }

    /// 진입 수립 — 앵커 상태가 태어나는 유일한 자리다.
    ///
    /// 실패는 전부 `.discard`다: 새 진입이 옛 세션을 절대 남기지 않는다. 캐럿임을 증명하지
    /// 못한 진입(살아 있는 선택 위의 `v`)이나 줄 시작을 증명하지 못한 `V`(창이 줄 시작에
    /// 못 닿음)는 근사로 수립하면 "잘못된 앵커를 정확하게" 만들므로 수립하지 않는 쪽이
    /// 보수 방향이다 — 진입 시퀀스 자체는 그대로 나간다(무상태 폴백).
    private static func establishment(
        linewise: Bool, from context: VisualAnchorContext
    ) -> VisualAnchorUpdate {
        guard case .establishing(let text, let processID) = context,
            text.selection.length == 0
        else {
            return .discard
        }
        let caret = text.selection.location
        guard linewise else {
            // `v` — 진입 `Shift-→`가 `[P, P+1)`을 만들므로 앱 앵커는 왼쪽 끝 P다.
            return .set(
                VisualAnchorState(
                    anchor: caret, wise: .charwise, side: .left, pinnedEnd: caret,
                    processID: processID, originalCaret: nil, focusLineDistance: nil))
        }
        // `V` — 진입 `Cmd-←, Shift-↓`가 앵커를 줄 시작에 박는다. 원래 캐럿은 이 시퀀스가
        // 파괴하므로 지금 보관하는 것이 유일한 기회다 (`V`→`v` 복원의 원천).
        guard let toLineStart = text.charactersToLineStart else { return .discard }
        let lineStart = caret - toLineStart
        return .set(
            VisualAnchorState(
                anchor: lineStart, wise: .linewise, side: .left, pinnedEnd: lineStart,
                processID: processID, originalCaret: caret, focusLineDistance: 0))
    }

    /// `family`는 쓰이지 않는다. 리졸버가 붙은 지금도 그대로인 것은 **계열별 Visual 시퀀스를
    /// 만들지 않기로 했기** 때문이다 — TextField에서도 TextArea 시퀀스가 자연 수렴하고,
    /// 비텍스트 걸러내기는 어댑터 게이트가 전담한다
    /// (`20260801_textfield-edit-sequences-scrapped.md`,
    /// `20260801_non-text-filter-keeps-motion-and-scroll.md`). 시그니처에 남겨 두는 것은
    /// M5 AX에서 계열이 실제로 갈릴 여지를 열어 두기 위해서다.
    /// 프로파일은 `extendSelection`(모션 어휘)에만 미친다 — 진입·wise 전환·collapse는
    /// 모션이 아니라 **세션 메커니즘**이라 리터럴 시퀀스를 유지한다. 이 경계가 실사용에서
    /// 어긋나면(예: 재정의 앱에서 진입 시퀀스도 깨짐) 도그푸딩에서 재검토한다.
    static func keyStrokes(
        for action: VimAction, family: ElementFamily, profile: ResolvedProfile = .empty
    ) -> [KeyStroke]? {
        switch action {
        case .beginSelection(let linewise):
            return linewise ? enterLinewise : enterCharwise

        case .extendSelection(let motion):
            // 재정의는 자동 전파, disable은 `nil`(정직한 스킵) — `MotionKeyMapper` 조회
            // 단일 지점의 결과를 그대로 넘긴다.
            return MotionKeyMapper.selectionStrokes(for: motion, profile: profile)

        case .switchSelectionWise(let linewise):
            // `V`→`v`는 미지원이다 — 줄 반올림은 원래 엔드포인트를 파괴하므로 되돌릴 역연산이
            // 없다. 게시가 없다는 점은 무게시와 같지만, `nil`이라야 스킵 로그에 잡혀
            // 단계 4의 "무로그 삼킴 없음" 판정에 드러난다.
            return linewise ? roundFocusToLine : nil

        case .clearSelection:
            return [collapseLeft]

        default:
            // `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다.
            return nil
        }
    }

    /// `v` — Vim의 charwise Visual은 inclusive라 진입 시점에 커서 문자가 이미 잡혀 있다.
    /// 무게시로 두면 `vd`·`vy`가 빈 선택에 오퍼레이터를 날려 무동작이 되고, 이탈 시
    /// `clearSelection`의 `←`가 접을 선택을 못 찾아 캐럿을 왼쪽으로 표류시킨다
    /// (`20260728_visual-charwise-entry-inclusive-selection.md`).
    private static let enterCharwise = [KeyStroke(kVK_RightArrow, [.maskShift])]

    /// `V` — 현재 줄을 개행까지 통째로. `dd`의 선택 접두와 같은 시퀀스다
    /// (`20260727_linewise-newline-rounding.md`의 delete/yank 반올림과 일관).
    private static let enterLinewise = [
        KeyStroke(kVK_LeftArrow, [.maskCommand]),
        KeyStroke(kVK_DownArrow, [.maskShift]),
    ]

    /// `v`→`V` — 포커스를 다음 줄 시작까지 밀어 **포커스 줄만** 개행까지 포함시킨다.
    /// 앵커는 앱에 박혀 있어 손댈 수 없다(수용 편차). `Shift-↓` 단독이 아닌 이유는 포커스가
    /// 임의의 열에 있기 때문이다 — `↓`는 열을 보존하므로 다음 줄 중간에 떨어진다.
    private static let roundFocusToLine = [
        KeyStroke(kVK_DownArrow, [.maskShift]),
        KeyStroke(kVK_LeftArrow, [.maskShift, .maskCommand]),
    ]

    /// 선택을 왼쪽 끝(= 범위 시작)으로 접는다 — Normal 편집의 yank collapse와 단일 규칙이다
    /// (`20260728_visual-clear-selection-collapse-left.md`).
    private static let collapseLeft = KeyStroke(kVK_LeftArrow)

    /// 재앵커 접두의 둘째 타 — collapse된 캐럿을 앵커 문자의 오른쪽 끝으로 한 칸 옮긴다.
    /// 진입·collapse와 같은 세션 메커니즘이라 모션 매핑을 거치지 않는 리터럴이다.
    private static let stepRight = KeyStroke(kVK_RightArrow)
}

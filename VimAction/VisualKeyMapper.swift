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
    /// 스트로크 사이 페이싱(5ms) 대상인가 — **정확화 다타 시퀀스만** 참이다. Notion 실측에서
    /// 0간격 버스트는 재앵커의 Shift 확장을 소화하지 못했고(간격 문제로 확정), 페이싱 범위를
    /// 정확화 그룹으로 한정해야 스크롤·카운트 버스트·폴백 경로가 타이밍까지 현행 그대로다.
    var paced: Bool = false
}

/// Visual 선택 **세션**(진입·확장·wise 전환·이탈) → 합성 키스트로크 시퀀스.
/// `MotionKeyMapper`·`EditKeyMapper`와 같은 순수 함수다.
///
/// 세션 동작만 담당하고, 선택에 오퍼레이터를 적용하는 `.edit(op, .selection)`은
/// `EditKeyMapper`의 몫이다 — 그쪽이 `Cmd-X`/`Cmd-C` 상수와 "오퍼레이터 키로 끝난다"는
/// 불변식을 이미 들고 있다.
///
/// **앵커 상태가 뒷받침되면 시퀀스가 갈린다** (M5 PR-C1): 어댑터가 세션 액션마다 읽어
/// 검증한 상태를 `VisualAnchorContext`로 넘기고, 후진·방향 전환은 재앵커 시퀀스로,
/// wise 전환은 재수립·재선택 시퀀스로 재조립된다
/// (`20260804_visual-backward-keyboard-reanchor.md`,
/// `20260804_visual-switch-charwise-conditional.md`). 상태 부재·읽기 실패·
/// 검증 실패는 전부 `.none`이며 그때의 시퀀스는 종전 무상태 매핑 그대로다 —
/// linewise 세션의 줄 반올림 미적용 등 수용 편차 표는 폴백 경로 전담이다
/// (`20260728_visual-extend-stateless-no-linewise-rounding.md`).
///
/// 반환 `nil`은 **미지원**(스킵+로그) 또는 **정확화가 증명한 무게시**다 — 어댑터의
/// 3-프로브(`classifyVisual`)가 상태 없이 되물어 둘을 가른다. 이 매퍼는 빈 배열을 반환하지
/// 않는다 — 세 매퍼 공통으로 "지원 ⟹ 빈 시퀀스 아님"이 불변식이라, 게시할 것이 없는 경우도
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
        if case .session(let state, let text) = anchor {
            switch refined(for: action, state: state, text: text, profile: profile) {
            case .invalid:
                // 정확화가 무게시를 증명했다 — Vim에서 범위 무변화가 정답인 자리다.
                // 어댑터의 상태 프로브가 미지원과 가른다.
                return nil
            case .refined(let strokes):
                return strokes
            case .unproven:
                break
            }
        }
        guard let strokes = keyStrokes(for: action, family: family, profile: profile) else {
            return nil
        }
        return VisualStrokes(strokes: strokes, anchor: update(for: action, from: anchor))
    }

    /// 검증된 상태가 무상태 시퀀스에 대해 증명한 것 — `EditKeyMapper.Refinement`와 동형이다.
    ///
    /// **`unproven`이 기본값이라는 것이 계약이다** — 모션·케이스가 늘어도 증명을 명시적으로
    /// 세우기 전까지는 현행 무상태 시퀀스이고, 조용한 억제나 조용한 재조립이 생기지 않는다.
    private enum Refinement {
        /// 정확화가 무게시를 증명했다 — Vim 정확 동작이 "범위 무변화"인 조합. 매퍼 `nil`을
        /// 거쳐 어댑터에서 `.skipped`로 분류된다.
        case invalid
        /// 재조립된 시퀀스 + 상태 변화.
        case refined(VisualStrokes)
        /// 증명하지 못했다 — 현행 무상태 시퀀스로 간다.
        case unproven
    }

    /// 검증된 세션 상태가 증명하는 재조립 (M5 PR-C1 ④~⑦) — 후진·방향 전환은 재앵커,
    /// `V` 세션의 charwise 모션은 무게시, wise 전환은 재수립·재선택이다.
    private static func refined(
        for action: VimAction, state: VisualAnchorState, text: FocusedText,
        profile: ResolvedProfile
    ) -> Refinement {
        switch action {
        case .extendSelection(let motion):
            switch state.wise {
            case .charwise:
                return charwiseExtendRefinement(motion, state, text, profile)
            case .linewise:
                return linewiseExtendRefinement(motion, state, text, profile)
            }

        case .switchSelectionWise(let linewise):
            return linewise
                ? roundToLinewiseRefinement(state, text, profile)
                : restoreToCharwiseRefinement(state, profile)

        default:
            // 진입·이탈은 정확화 대상이 아니다 — 수립은 `establishment`, 폐기는 `update`가
            // 무상태 경로에서 담당한다.
            return .unproven
        }
    }

    // MARK: - charwise 확장 (④ 후진 + 전진 대칭)

    private static func charwiseExtendRefinement(
        _ motion: Motion, _ state: VisualAnchorState, _ text: FocusedText,
        _ profile: ResolvedProfile
    ) -> Refinement {
        switch motion {
        case .charLeft:
            return charLeftRefinement(state, text, profile)
        case .charRight:
            return charRightRefinement(state, text, profile)
        case .wordBackward:
            return wordBackwardRefinement(state, text, profile)
        default:
            // 전진 어휘는 현행 확장이 그대로 맞고, 후진형 위의 단어 전진 등 앵커를 한 번에
            // 넘는 모션은 착지를 앱만 알아 게시 전 판정이 불가하다(크로싱 — 수용 엣지).
            return .unproven
        }
    }

    /// `vh` — 진입형만 재앵커하고, 후진형은 무보정 1타가 이미 정확하다.
    private static func charLeftRefinement(
        _ state: VisualAnchorState, _ text: FocusedText, _ profile: ResolvedProfile
    ) -> Refinement {
        guard let backward = MotionKeyMapper.selectionStrokes(for: .charLeft, profile: profile)
        else { return .unproven }
        switch state.side {
        case .right:
            // 후진형 `[F, A+1)`의 앱 포커스는 정확히 F다 — 진입 `Shift-→`의 +1 원점 이동은
            // 전진형에만 있는 오차라, 연속 후진은 무보정 정확하다
            // (`20260804_visual-backward-keyboard-reanchor.md`).
            return refinement(backward, .unchanged)
        case .left:
            // 재앵커는 진입형 `[A, A+1)`에서만 필요하다 — Vim의 `h`는 앵커 왼쪽을 잡으려
            // 하는데 앱 앵커가 왼쪽 끝에 박혀 있어 `Shift-←`가 선택을 접기만 한다. 이미
            // 전진 확장된 선택(길이 ≥ 2)의 `h`는 축소라 현행 `Shift-←` 그대로 맞다.
            // (왼쪽 끝 == A는 자가 검증이 이미 보장했다 — 길이만 남는다.)
            //
            // 앵커가 **줄 시작(열 0)이면 재앵커하지 않는다** — Vim의 `h`는 앞 줄로 넘어가지
            // 않으므로(`EditKeyMapper`의 `charLeftRefinement`와 같은 규칙) 여기서 재앵커하면
            // 개행을 선택해, 뒤따르는 `d`가 줄을 병합하는 **파괴적 회귀**가 된다. 증명
            // 실패(`unproven`)도 같은 편이다 — 증명 못 하면 정확화하지 않는다. 폴백
            // `Shift-←`는 선택을 접을 뿐이라(무해) 다음 읽기의 빈 선택 검증이 상태를 정리한다.
            guard text.selection.length == 1,
                let toLineStart = text.charactersToLineStart, toLineStart > 0
            else { return .unproven }
            // `→` 1타가 선택을 오른쪽 끝(= A+1)으로 접는다 — 선택이 존재하는 진입형에서
            // `←,→` 2타와 동치라 짧은 쪽을 쓴다(접두 단축 결정). 이어지는 `Shift-← ×2`가
            // `[A−1, A+1)`을 만든다 — 앱 앵커는 이제 오른쪽 끝이다(side 반전). 접두는
            // collapse·진입과 같은 **세션 메커니즘**이라 리터럴이고, 재확장만 모션 매핑을
            // 거친다(재정의 전파·disable 정직 스킵 유지).
            var reanchored = state
            reanchored.side = .right
            reanchored.pinnedEnd = state.anchor + 1
            return refinement([stepRight] + backward + backward, .set(reanchored))
        }
    }

    /// `vl` 전진 대칭 — 후진형이 앵커에 정확히 닿은 뒤(`vhll`의 둘째 `l`)의 전진은 재앵커
    /// 없이는 `Shift-→`가 선택을 접기만 한다. `h` 재앵커의 거울상이다.
    private static func charRightRefinement(
        _ state: VisualAnchorState, _ text: FocusedText, _ profile: ResolvedProfile
    ) -> Refinement {
        // 전진형의 `l`은 현행 확장이 그대로 맞고, 후진형 길이 ≥ 2의 `l`은 축소라 역시 맞다.
        guard state.side == .right, text.selection.length == 1,
            let forward = MotionKeyMapper.selectionStrokes(for: .charRight, profile: profile)
        else { return .unproven }
        // 앵커가 **줄 끝이면 재앵커하지 않는다** — `h`의 열 0 봉쇄와 대칭이다: Vim의 `l`은
        // 줄을 넘지 않는데 재앵커하면 개행을 선택한다. `charactersToLineEnd`는 선택 끝(A+1)
        // 기준이라 0이면 A가 줄 마지막 글자다(문서 끝 폴백 포함).
        guard let remaining = text.charactersToLineEnd, remaining > 0 else { return .unproven }
        // `←`가 선택을 왼쪽 끝(= A)으로 접고, `Shift-→ ×2`가 `[A, A+2)`를 만든다.
        var reanchored = state
        reanchored.side = .left
        reanchored.pinnedEnd = state.anchor
        return refinement([collapseLeft] + forward + forward, .set(reanchored))
    }

    /// `vb` — 진입형의 후진 단어 확장. `h`와 같은 재앵커에 재확장만 `Shift-Opt-←`다.
    private static func wordBackwardRefinement(
        _ state: VisualAnchorState, _ text: FocusedText, _ profile: ResolvedProfile
    ) -> Refinement {
        // 후진형의 `b`는 무보정 1타가 폴백과 바이트 동일하게 이미 정확하고(`h`와 같은 이유),
        // 전진형 길이 ≥ 2의 `b`는 축소이거나 앵커 크로싱(수용 엣지)이다.
        guard state.side == .left, text.selection.length == 1,
            let backWord = MotionKeyMapper.selectionStrokes(for: .wordBackward, profile: profile)
        else { return .unproven }
        // 캐럿 문자가 단어 시작이면 `Shift-Opt-←` 1타는 A로 돌아와 선택이 자라지 않는다 —
        // Vim의 `b`는 그때 **이전** 단어 시작으로 뛰므로 ×2다 (결정 표, PR-B 단어 술어 재사용).
        // 증명 못 하면 ×1 — 덜 후진하는 쪽(보이는 편차)으로 틀린다.
        let reach = text.caretIsAtWordStart ? backWord + backWord : backWord
        var reanchored = state
        reanchored.side = .right
        reanchored.pinnedEnd = state.anchor + 1
        return refinement([stepRight] + reach, .set(reanchored))
    }

    // MARK: - linewise 확장 (④ `Vk`·`Vj`·`Vgg`, ⑤ charwise 모션 스킵)

    private static func linewiseExtendRefinement(
        _ motion: Motion, _ state: VisualAnchorState, _ text: FocusedText,
        _ profile: ResolvedProfile
    ) -> Refinement {
        switch motion {
        case .lineUp:
            return lineUpRefinement(state, text, profile)
        case .lineDown:
            return lineDownRefinement(state, text, profile)
        case .documentStart:
            return documentStartRefinement(state, text, profile)
        case .charLeft, .charRight, .wordForward, .wordBackward, .wordEndForward,
            .lineStart, .lineFirstNonBlank, .lineEnd:
            // ⑤ — Vim에서 `V` 세션의 charwise 모션은 커서 열만 움직이고 **범위를 바꾸지
            // 않는다**. 무게시가 곧 정확 동작이고, desync 실패 모드는 무해한 no-op다
            // (`20260804_visual-linewise-motion-range-noop.md`). 열 이동이 없는 것은 수용
            // 편차다 — 덕분에 `V`→`v` 복원의 열이 원래 캐럿 열과 실제로 일치한다.
            return .invalid
        default:
            // `documentEnd`(`VG`)의 전진은 현행 확장이 맞고, 후진형 위에서는 크로싱이다.
            return .unproven
        }
    }

    /// `Vk` — 축소는 거리만 ±1로 유지하고, 방향 전환(d = 0)만 재앵커한다.
    private static func lineUpRefinement(
        _ state: VisualAnchorState, _ text: FocusedText, _ profile: ResolvedProfile
    ) -> Refinement {
        guard let upward = MotionKeyMapper.selectionStrokes(for: .lineUp, profile: profile),
            let distance = state.focusLineDistance
        else { return .unproven }
        switch state.side {
        case .left:
            if distance > 0 {
                // 축소 — 스트로크는 폴백과 같고, 정확 경로만 거리를 유지한다(폴백은 미상으로
                // 좁힌다). 선택 위쪽에 줄이 있으므로(d > 0) `Shift-↑`는 포화하지 않는다.
                var narrowed = state
                narrowed.focusLineDistance = distance - 1
                return refinement(upward, .set(narrowed))
            }
            guard distance == 0 else { return .unproven }
            // 앵커 줄이 첫 줄이면 Vim의 `k`는 no-op다 — 증명이 절대적(오프셋 0 = 문서 시작)
            // 이라 무게시가 정확 동작이다.
            guard text.selection.location > 0 else { return .invalid }
            // 방향 전환 — `→`가 선택을 오른쪽 끝(= 앵커 줄 끝 다음)으로 접는다. 결정 표의
            // `←,↓`와 동치이되 1타이고, 마지막 줄에서 `↓`가 줄 끝으로 포화하는 엣지도 없다.
            // 단 그 동치는 오른쪽 끝이 **줄 시작(열 0)일 때만** 성립한다 — 아니면(개행 없는
            // 마지막 줄) `Shift-↑`가 열을 끌고 올라가 부분 줄을 선택하므로 증명을 요구한다.
            guard text.selectionEndIsAtLineStart else { return .unproven }
            var reanchored = state
            reanchored.side = .right
            reanchored.pinnedEnd = text.selection.upperBound
            reanchored.focusLineDistance = -1
            return refinement([stepRight] + upward + upward, .set(reanchored))
        case .right:
            guard distance <= 0 else { return .unproven }
            // 포커스가 문서 시작이면 위로 갈 줄이 없다 — Vim no-op (⑤와 같은 무게시).
            guard text.selection.location > 0 else { return .invalid }
            // 포커스가 줄 시작(열 0)임이 증명되어야 `Shift-↑`가 줄 시작으로 착지해 거리
            // 추적이 실제 줄 이동과 일치한다. 열 0 && 오프셋 > 0 ⟹ 위 줄이 존재한다.
            guard text.isAtLineStart else { return .unproven }
            var widened = state
            widened.focusLineDistance = distance - 1
            return refinement(upward, .set(widened))
        }
    }

    /// `Vj` 전진 대칭 — `Vk`의 거울상. 후진형이 앵커 줄로 돌아온 뒤(d = 0)의 `j`만 재앵커한다.
    private static func lineDownRefinement(
        _ state: VisualAnchorState, _ text: FocusedText, _ profile: ResolvedProfile
    ) -> Refinement {
        guard let downward = MotionKeyMapper.selectionStrokes(for: .lineDown, profile: profile),
            let distance = state.focusLineDistance
        else { return .unproven }
        switch state.side {
        case .left:
            // 확장 — 선택 끝 다음에 문자가 존재해야 `Shift-↓`가 실제로 한 줄을 소비한다.
            // 문서 끝(마지막 줄)에서는 포화해 화면은 안 움직이는데 거리만 늘면 `V`→`v`가
            // 낡은 거리로 어긋난다. 증명 못 하면 폴백이 거리를 미상으로 좁힌다(안전 방향).
            guard text.provesCharacterAfterSelectionEnd else { return .unproven }
            var widened = state
            widened.focusLineDistance = distance + 1
            return refinement(downward, .set(widened))
        case .right:
            if distance < 0 {
                // 축소 — 아래에 앵커 줄이 있으므로(d < 0) `Shift-↓`는 포화하지 않는다.
                var narrowed = state
                narrowed.focusLineDistance = distance + 1
                return refinement(downward, .set(narrowed))
            }
            guard distance == 0 else { return .unproven }
            // 방향 전환 — `←`가 선택을 왼쪽 끝(= 앵커 줄 시작)으로 접고 `Shift-↓ ×2`가
            // 앵커 줄 + 아래 줄을 만든다. 왼쪽 끝이 줄 시작임과 앵커 줄 아래에 줄이 실재함을
            // 둘 다 증명해야 한다 (`Vk` 재앵커의 두 증명과 대칭).
            guard text.isAtLineStart, text.provesCharacterAfterSelectionEnd else {
                return .unproven
            }
            var reanchored = state
            reanchored.side = .left
            reanchored.pinnedEnd = text.selection.location
            reanchored.focusLineDistance = 1
            return refinement([collapseLeft] + downward + downward, .set(reanchored))
        }
    }

    /// `Vgg` — 문서 시작까지의 후진. 재앵커 뒤 `Shift-Cmd-↑` 1타(상수)로 끝나고,
    /// 착지 줄 수는 알 수 없으므로 거리는 미상으로 좁힌다.
    private static func documentStartRefinement(
        _ state: VisualAnchorState, _ text: FocusedText, _ profile: ResolvedProfile
    ) -> Refinement {
        guard
            let toDocumentStart = MotionKeyMapper.selectionStrokes(
                for: .documentStart, profile: profile)
        else { return .unproven }
        switch state.side {
        case .right:
            // 앱 앵커가 이미 앵커 줄 끝 다음이라 재앵커 없이 1타다 — 폴백과 바이트 동일하되
            // 거리를 미상으로 좁히는 상태 갱신이 다르다.
            var unknowed = state
            unknowed.focusLineDistance = nil
            return refinement(toDocumentStart, .set(unknowed))
        case .left:
            // `←`(왼쪽 끝 = 앵커 줄 시작으로 collapse) 뒤 `↓`가 앵커 줄 끝 다음(다음 줄
            // 시작)에 착지한다 — 거리와 무관하게 성립해 d 미상(`gg`/`G` 경유 뒤)에도 정확화가
            // 선다. 착지 오프셋(= 새 pinnedEnd)은 앵커 줄의 개행을 창에서 증명해야 계산할 수
            // 있고, 증명 못 하면(개행 없는 마지막 줄 포함 — `↓`가 줄 끝으로 포화하는 자리다)
            // 현행 폴백이다.
            guard let toNewline = text.newlineDistanceAfterSelectionStart else {
                return .unproven
            }
            var reanchored = state
            reanchored.side = .right
            reanchored.pinnedEnd = text.selection.location + toNewline + 1
            reanchored.focusLineDistance = nil
            return refinement(
                [collapseLeft, stepDown] + toDocumentStart, .set(reanchored))
        }
    }

    // MARK: - wise 전환 (⑥ `v`→`V`, ⑦ `V`→`v`)

    /// ⑥ `v`→`V` — 앵커 쪽도 줄 반올림한다: 재앵커로 앵커를 줄 시작(전진형) 또는 줄 끝
    /// 다음(후진형)에 재수립하고 포커스 줄까지 재확장한다. 폴백(`.discard`)과 달리 전환 후
    /// 상태가 완전히 수립되어 세션이 이어진다 — 옛 charwise 앵커를 `originalCaret`으로
    /// 보관하므로 이후 `V`→`v` 재전환도 선다.
    private static func roundToLinewiseRefinement(
        _ state: VisualAnchorState, _ text: FocusedText, _ profile: ResolvedProfile
    ) -> Refinement {
        // 줄 거리 k(선택 내부의 개행 수)는 선택이 창 안에 완전히 들어올 때만 증명된다.
        guard state.wise == .charwise, let lineSpan = text.newlinesInsideSelection else {
            return .unproven
        }
        switch state.side {
        case .left:
            // `←`(A로 collapse), `Cmd-←`(앵커 줄 시작) 뒤 `Shift-↓ ×(k+1)` — 열 0에서
            // 출발하므로 줄 시작으로만 착지하고, 마지막 줄에서는 문서 끝으로 포화한다
            // (Vim의 마지막 줄 V와 같은 결과라 무해).
            guard let toLineStart = text.charactersToLineStart,
                let extend = MotionKeyMapper.selectionStrokes(for: .lineDown, profile: profile)
            else { return .unproven }
            let lineStart = state.anchor - toLineStart
            return refinement(
                [collapseLeft, stepLineStart] + repeated(extend, lineSpan + 1),
                .set(
                    VisualAnchorState(
                        anchor: lineStart, wise: .linewise, side: .left, pinnedEnd: lineStart,
                        processID: state.processID, originalCaret: state.anchor,
                        focusLineDistance: lineSpan)))
        case .right:
            // `→`(A+1로 collapse), `↓, Cmd-←`(앵커 줄 끝 다음) 뒤 `Shift-↑ ×(k+1)`.
            // 앵커 줄의 개행(= `↓`의 착지 보장이자 pinnedEnd 재료)과 앵커 줄 시작(논리 앵커
            // 재료)을 창에서 증명해야 한다. 줄 시작 거리 ≥ 1은 A 자신이 개행이 아님도
            // 함께 증명한다(0이면 앵커 줄 개념이 서지 않는다).
            guard let toNewline = text.newlineDistanceAfterSelectionEnd,
                let toLineStart = text.selectionEndCharactersToLineStart, toLineStart > 0,
                let extend = MotionKeyMapper.selectionStrokes(for: .lineUp, profile: profile)
            else { return .unproven }
            return refinement(
                [stepRight, stepDown, stepLineStart] + repeated(extend, lineSpan + 1),
                .set(
                    VisualAnchorState(
                        anchor: text.selection.upperBound - toLineStart, wise: .linewise,
                        side: .right,
                        pinnedEnd: text.selection.upperBound + toNewline + 1,
                        processID: state.processID, originalCaret: state.anchor,
                        focusLineDistance: -lineSpan)))
        }
    }

    /// ⑦ `V`→`v` — 원래 캐럿 P와 포커스 줄 거리 d를 **둘 다 알 때만** 재선택한다. 하나라도
    /// 모르면(`gg`/`G` 경유, 검증·읽기 실패) 현행 `nil`(정직한 스킵)이다 — 근사 재선택은
    /// "잘못된 범위를 정확하게" 만들고, 파괴적 오퍼레이터가 뒤따르는 자리라 스킵보다 나쁘다
    /// (`20260804_visual-switch-charwise-conditional.md`).
    ///
    /// 재선택의 포커스 열은 P의 열로 근사한다 — ⑤가 `V` 세션의 열 이동을 전부 스킵하므로
    /// Vim의 커서 열도 실제로 P의 열 그대로다(줄이 짧으면 양쪽 다 줄 끝으로 클램프).
    private static func restoreToCharwiseRefinement(
        _ state: VisualAnchorState, _ profile: ResolvedProfile
    ) -> Refinement {
        guard state.wise == .linewise, let caret = state.originalCaret,
            let distance = state.focusLineDistance
        else { return .unproven }
        // 열 거리 상한 — 극단 열에서 위치 접두가 폭주하고 페이싱(5ms/타)이 곱해지므로
        // 상한을 넘으면 정직한 스킵으로 후퇴한다. 도그푸딩 실측으로 확정하는 조절값이다
        // (결정 유보 항목).
        let column = caret - state.anchor
        guard column >= 0, column <= Self.reselectColumnClamp else { return .unproven }
        if distance >= 0 {
            guard state.side == .left,
                let down = MotionKeyMapper.selectionStrokes(for: .lineDown, profile: profile),
                let inclusive = MotionKeyMapper.selectionStrokes(
                    for: .charRight, profile: profile)
            else { return .unproven }
            // `←`(앵커 줄 시작으로 collapse), `→ ×열`(P로), `Shift-↓ ×d`(열 보존),
            // `Shift-→`(inclusive +1) → `[P, 포커스줄 열 위치 +1)`.
            return refinement(
                [collapseLeft] + repeated([stepRight], column) + repeated(down, distance)
                    + inclusive,
                .set(
                    VisualAnchorState(
                        anchor: caret, wise: .charwise, side: .left, pinnedEnd: caret,
                        processID: state.processID, originalCaret: nil,
                        focusLineDistance: nil)))
        }
        guard state.side == .right,
            let up = MotionKeyMapper.selectionStrokes(for: .lineUp, profile: profile),
            let adjust = MotionKeyMapper.selectionStrokes(for: .charLeft, profile: profile)
        else { return .unproven }
        // `→`(앵커 줄 끝 다음으로 collapse), `↑`(열 0 보존 — 앵커 줄 시작), `→ ×(열+1)`
        // (P+1로 — 화살표는 오프셋 +1씩이라 개행을 건너도 산술이 정확하다), `Shift-↑ ×|d|`
        // (열 보존), `Shift-←`(inclusive 보정) → `[포커스줄 열 위치, P+1)`.
        return refinement(
            [stepRight, stepUp] + repeated([stepRight], column + 1)
                + repeated(up, -distance) + adjust,
            .set(
                VisualAnchorState(
                    anchor: caret, wise: .charwise, side: .right, pinnedEnd: caret + 1,
                    processID: state.processID, originalCaret: nil, focusLineDistance: nil)))
    }

    /// `.refined` 생성 — 정확화 시퀀스의 페이싱 여부가 여기 한 곳에서 결정된다:
    /// 다타(2타 이상)면 스트로크 사이 간격 대상이다. 1타는 간격 자체가 없어 값이 무의미하다.
    private static func refinement(
        _ strokes: [KeyStroke], _ anchor: VisualAnchorUpdate
    ) -> Refinement {
        .refined(VisualStrokes(strokes: strokes, anchor: anchor, paced: strokes.count >= 2))
    }

    /// 무상태 시퀀스가 나갈 때의 상태 변화 — 폴백 경로가 상태를 낡게 두지 않는 것이
    /// 정확화 경로의 전제다.
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
            // 자가 검증을 **거짓 통과**한다 — 정확화(⑥)가 증명하지 못한 전환은 폐기가
            // 유일하게 정직하다.
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
            // `V`→`v`는 무상태로는 미지원이다 — 줄 반올림은 원래 엔드포인트를 파괴하므로
            // 되돌릴 역연산이 없다(⑦ 정확화가 게시 전 보관으로만 푼다). 게시가 없다는 점은
            // 무게시와 같지만, `nil`이라야 스킵 로그에 잡혀 단계 4의 "무로그 삼킴 없음"
            // 판정에 드러난다.
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

    /// `v`→`V` 폴백 — 포커스를 다음 줄 시작까지 밀어 **포커스 줄만** 개행까지 포함시킨다.
    /// 앵커는 앱에 박혀 있어 무상태로는 손댈 수 없다(⑥ 정확화가 재앵커로 푼다). `Shift-↓`
    /// 단독이 아닌 이유는 포커스가 임의의 열에 있기 때문이다 — `↓`는 열을 보존하므로 다음 줄
    /// 중간에 떨어진다.
    private static let roundFocusToLine = [
        KeyStroke(kVK_DownArrow, [.maskShift]),
        KeyStroke(kVK_LeftArrow, [.maskShift, .maskCommand]),
    ]

    /// 선택을 왼쪽 끝(= 범위 시작)으로 접는다 — Normal 편집의 yank collapse와 단일 규칙이고
    /// (`20260728_visual-clear-selection-collapse-left.md`), 재앵커에서는 왼쪽 끝 재수립
    /// 접두다. 진입과 같은 세션 메커니즘이라 모션 매핑을 거치지 않는 리터럴이다.
    private static let collapseLeft = KeyStroke(kVK_LeftArrow)

    /// 선택 위에서는 오른쪽 끝으로 접고(재앵커 접두 — `←,→` 2타와 동치인 1타 단축), 캐럿
    /// 위에서는 한 칸 전진한다(`V`→`v`의 위치 접두). `collapseLeft`와 같은 리터럴이다.
    private static let stepRight = KeyStroke(kVK_RightArrow)

    /// 재앵커·재선택 접두의 수직 이동 — 열 보존으로 다음/이전 줄에 착지한다. 리터럴이다.
    private static let stepDown = KeyStroke(kVK_DownArrow)
    private static let stepUp = KeyStroke(kVK_UpArrow)

    /// 줄 시작 접두 (`Cmd-←`) — `v`→`V` 재수립이 앵커를 줄 시작으로 옮길 때 쓴다. 리터럴이다.
    private static let stepLineStart = KeyStroke(kVK_LeftArrow, [.maskCommand])

    /// `V`→`v` 재선택의 열 거리 상한 — 위치 접두가 열에 비례하고 페이싱(5ms/타)이 곱해지므로
    /// 폭주를 자른다. 도그푸딩 실측으로 확정하는 조절값이다 (결정 유보 항목).
    private static let reselectColumnClamp = 32

    /// 카운트·거리 비례 반복 — `EditKeyMapper.repeated`와 같은 형태다.
    private static func repeated(_ strokes: [KeyStroke], _ count: Int) -> [KeyStroke] {
        count > 0 ? Array(repeating: strokes, count: count).flatMap { $0 } : []
    }
}

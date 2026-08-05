//
//  VisualKeyMapperTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine

@testable import VimAction

// MARK: - 표기 상수

private let left = KeyStroke(kVK_LeftArrow)
private let right = KeyStroke(kVK_RightArrow)
private let cmdLeft = KeyStroke(kVK_LeftArrow, [.maskCommand])

private let selLeft = KeyStroke(kVK_LeftArrow, [.maskShift])
private let selRight = KeyStroke(kVK_RightArrow, [.maskShift])
private let selUp = KeyStroke(kVK_UpArrow, [.maskShift])
private let selDown = KeyStroke(kVK_DownArrow, [.maskShift])
private let selOptLeft = KeyStroke(kVK_LeftArrow, [.maskShift, .maskAlternate])
private let selOptRight = KeyStroke(kVK_RightArrow, [.maskShift, .maskAlternate])
private let selCmdLeft = KeyStroke(kVK_LeftArrow, [.maskShift, .maskCommand])
private let selCmdRight = KeyStroke(kVK_RightArrow, [.maskShift, .maskCommand])
private let selCmdUp = KeyStroke(kVK_UpArrow, [.maskShift, .maskCommand])
private let selCmdDown = KeyStroke(kVK_DownArrow, [.maskShift, .maskCommand])

// MARK: - 픽스처

struct VisualMappingFixture: Sendable, CustomTestStringConvertible {
    var vim: String
    var action: VimAction
    /// `nil`은 **미지원**(스킵+로그)이다. 이 매퍼는 빈 배열을 내지 않는다.
    var expected: [KeyStroke]?

    init(_ vim: String, _ action: VimAction, _ expected: [KeyStroke]?) {
        self.vim = vim
        self.action = action
        self.expected = expected
    }

    var testDescription: String { vim }
}

/// 세션 진입·전환·이탈. **이 표가 곧 계약이다.**
///
/// `v`가 무게시가 아니라 `Shift-→` 1타인 것이 요점이다 — Vim의 charwise Visual은 inclusive라
/// 진입 시점에 커서 문자가 이미 잡혀 있고, 무게시면 `vd`·`vy`가 무동작이 되며 이탈 시
/// `←`가 접을 선택을 못 찾아 캐럿을 표류시킨다
/// (`20260728_visual-charwise-entry-inclusive-selection.md`).
///
/// `V`→`v`가 `nil`인 것도 의도다 — 줄 반올림은 원래 엔드포인트를 파괴해 역연산이 없다.
/// 무게시(`[]`)로 두면 "처리했다"고 주장하면서 화면은 반올림된 채 남는다
/// (`20260728_visual-switch-wise-focus-end-rounding.md`).
let visualSessionFixtures: [VisualMappingFixture] = [
    .init("v", .beginSelection(linewise: false), [selRight]),
    .init("V", .beginSelection(linewise: true), [cmdLeft, selDown]),
    .init("v→V", .switchSelectionWise(linewise: true), [selDown, selCmdLeft]),
    .init("V→v", .switchSelectionWise(linewise: false), nil),
    .init("Esc", .clearSelection, [left]),
]

/// 선택 확장 12종 — 모션 매핑에 Shift를 얹은 것이 전부다(어댑터는 wise를 모른다).
/// 카운트는 엔진이 반복 액션으로 펼쳐 주므로 매핑은 1회분만 낸다.
///
/// `w`·`^`의 3타 조합은 **세 스트로크 전부**에 Shift가 붙는다 — 앵커가 고정된 채
/// 엔드포인트만 움직이므로 중간 위치는 관측되지 않는다.
let visualExtendFixtures: [VisualMappingFixture] = [
    .init("h", .extendSelection(.charLeft), [selLeft]),
    .init("l", .extendSelection(.charRight), [selRight]),
    .init("k", .extendSelection(.lineUp), [selUp]),
    .init("j", .extendSelection(.lineDown), [selDown]),
    .init("w", .extendSelection(.wordForward), [selOptRight, selOptRight, selOptLeft]),
    .init("b", .extendSelection(.wordBackward), [selOptLeft]),
    .init("e", .extendSelection(.wordEndForward), [selOptRight]),
    .init("0", .extendSelection(.lineStart), [selCmdLeft]),
    .init("^", .extendSelection(.lineFirstNonBlank), [selCmdLeft, selOptRight, selOptLeft]),
    .init("$", .extendSelection(.lineEnd), [selCmdRight]),
    .init("gg", .extendSelection(.documentStart), [selCmdUp]),
    .init("G", .extendSelection(.documentEnd), [selCmdDown]),
]

let visualMappingFixtures = visualSessionFixtures + visualExtendFixtures

/// Visual이 실제로 받는 모션 12종. `Motion.allCases`(14종)와 다른 것이 의도다 —
/// `charRightForAppend`·`lineEndForAppend`는 `a`/`A` 전용이라 Visual에 도달하지 않는다.
let visualExtendMotions: [Motion] = [
    .charLeft, .charRight, .lineUp, .lineDown,
    .wordForward, .wordBackward, .wordEndForward,
    .lineStart, .lineFirstNonBlank, .lineEnd,
    .documentStart, .documentEnd,
]

// MARK: - 테스트

struct VisualKeyMapperTests {
    @Test("매핑표 골든 — Visual 세션이 계약대로 키스트로크가 된다", arguments: visualMappingFixtures)
    func mapsVisualAsContracted(_ fixture: VisualMappingFixture) {
        let actual = VisualKeyMapper.keyStrokes(for: fixture.action, family: .textArea)
        #expect(actual == fixture.expected, "\(fixture.vim)")
    }

    /// 세 매퍼 공통 불변식 — 빈 배열은 "조용히 아무것도 안 함"이라 미지원(`nil` → 스킵+로그)과
    /// 구분되지 않는다. Visual도 예외가 아니다: 게시할 것이 없으면 `nil`이어야 한다.
    @Test("지원 액션은 빈 시퀀스로 매핑되지 않는다", arguments: visualMappingFixtures)
    func supportedActionsNeverMapToEmpty(_ fixture: VisualMappingFixture) {
        guard let expected = fixture.expected else { return }
        #expect(!expected.isEmpty, "\(fixture.vim)")
    }

    /// 확장의 모든 스트로크에 Shift가 실린다 — 한 타라도 빠지면 선택이 그 자리에서 무너지고
    /// 캐럿만 이동해, 뒤이은 `Cmd-X`가 엉뚱한 범위를 자른다. 3타 조합을 지키는 것이 이 테스트다.
    @Test("선택 확장은 모든 스트로크에 Shift가 실린다", arguments: visualExtendFixtures)
    func extendAlwaysCarriesShift(_ fixture: VisualMappingFixture) {
        guard let expected = fixture.expected else { return }
        #expect(expected.allSatisfy { $0.flags.contains(.maskShift) }, "\(fixture.vim)")
    }

    /// 확장은 모션 매핑의 순수한 재사용이다 — 키코드·개수·순서가 모션과 같고 Shift만 다르다.
    /// 이것이 레이어링의 핵심 계약이라 골든을 복제하는 대신 관계로 고정한다:
    /// **모션 매핑이 개선되면 Visual이 자동으로 따라온다**.
    @Test("확장은 모션 매핑에 Shift만 얹은 것이다", arguments: visualExtendMotions)
    func extendMirrorsMotionMapping(_ motion: Motion) {
        let motionStrokes = MotionKeyMapper.keyStrokes(for: motion)
        let extended = VisualKeyMapper.keyStrokes(for: .extendSelection(motion), family: .textArea)

        #expect(extended?.map(\.keyCode) == motionStrokes?.map(\.keyCode), "\(motion)")
        #expect(
            extended?.map { $0.flags.subtracting(.maskShift) } == motionStrokes?.map(\.flags),
            "\(motion)")
    }

    /// 확장 골든이 Visual이 실제로 받는 모션 12종을 빠짐없이 덮는지.
    @Test("확장 골든은 대상 모션 12종을 전부 덮는다")
    func extendGoldenCoversTargetMotions() {
        let covered = visualExtendFixtures.compactMap { fixture -> Motion? in
            guard case .extendSelection(let motion) = fixture.action else { return nil }
            return motion
        }
        #expect(Set(covered) == Set(visualExtendMotions))
        #expect(covered.count == visualExtendMotions.count, "중복 행 없음")
    }

    /// v1 Visual 어휘 밖의 액션은 미지원으로 남는다 — `default:` 흡수가 살아 있는지의 확인이다.
    @Test("Visual 어휘 밖 액션은 nil이다")
    func nonVisualActionsAreUnsupported() {
        #expect(VisualKeyMapper.keyStrokes(for: .undo, family: .textArea) == nil)
        #expect(VisualKeyMapper.keyStrokes(for: .move(.charLeft), family: .textArea) == nil)
    }
}

// MARK: - 앵커 정확화 진입점 (M5 PR-C1)

/// `v` 진입 캐럿 4 (문서 "ab\ncde"의 `d` — **열 1**이라 왼쪽이 있다) 의 charwise 상태 —
/// 세션 컨텍스트 픽스처의 기본형. 열 0 앵커는 재앵커가 막히는 별도 케이스라 전용 테스트가 있다.
private func charwiseSession(side: VisualAnchorState.Side = .left) -> VisualAnchorState {
    VisualAnchorState(
        anchor: 4, wise: .charwise, side: side, pinnedEnd: side == .left ? 4 : 5,
        processID: 42, originalCaret: nil, focusLineDistance: nil)
}

struct VisualAnchorMappingTests {
    /// **폴백 바이트 동일** — `.none`이면 무상태 매핑과 시퀀스도 `nil`성도 같아야 한다.
    /// 상태 부재·읽기 실패·검증 실패(Slack·VS Code 상시)가 전부 이 경로다.
    @Test("anchor .none은 무상태 매핑과 바이트 동일이다", arguments: visualMappingFixtures)
    func noneContextMatchesStatelessMapping(_ fixture: VisualMappingFixture) {
        let stateless = VisualKeyMapper.keyStrokes(for: fixture.action, family: .textArea)
        let refined = VisualKeyMapper.keyStrokes(
            for: fixture.action, family: .textArea, profile: .empty, anchor: .none)

        #expect(refined?.strokes == stateless, "\(fixture.vim)")
        #expect((refined == nil) == (stateless == nil), "\(fixture.vim)")
    }

    // MARK: 수립

    @Test("v 진입은 캐럿을 앵커로 수립한다 — side .left, pinnedEnd = 캐럿")
    func charwiseEntryEstablishesCaretAnchor() {
        let entry = focusedText("ab\ncd", caret: 3)

        let result = VisualKeyMapper.keyStrokes(
            for: .beginSelection(linewise: false), family: .textArea, profile: .empty,
            anchor: .establishing(entry, 42))

        #expect(result?.strokes == [selRight])
        #expect(
            result?.anchor
                == .set(
                    VisualAnchorState(
                        anchor: 3, wise: .charwise, side: .left, pinnedEnd: 3, processID: 42,
                        originalCaret: nil, focusLineDistance: nil)))
    }

    /// `V`는 앵커가 줄 시작이고, 진입 시퀀스가 파괴하기 전의 원래 캐럿을 함께 보관한다.
    @Test("V 진입은 줄 시작을 앵커로, 원래 캐럿을 별도 보관한다")
    func linewiseEntryEstablishesLineStartAnchor() {
        let entry = focusedText("ab\ncd", caret: 4)  // 둘째 줄 "cd"의 c와 d 사이

        let result = VisualKeyMapper.keyStrokes(
            for: .beginSelection(linewise: true), family: .textArea, profile: .empty,
            anchor: .establishing(entry, 42))

        #expect(result?.strokes == [cmdLeft, selDown])
        #expect(
            result?.anchor
                == .set(
                    VisualAnchorState(
                        anchor: 3, wise: .linewise, side: .left, pinnedEnd: 3, processID: 42,
                        originalCaret: 4, focusLineDistance: 0)))
    }

    /// 창이 줄 시작에 못 닿으면 `V`의 앵커를 증명할 수 없다 — 근사 수립은 "잘못된 앵커를
    /// 정확하게"라 수립하지 않는다. 진입 시퀀스는 그대로 나간다(무상태 폴백).
    @Test("줄 시작을 증명 못 한 V 진입은 수립하지 않는다")
    func linewiseEntryWithoutProvableLineStartDiscards() {
        let truncated = FocusedText(
            selection: NSRange(location: 11, length: 0), characterCount: 20,
            window: "xyz", windowRange: NSRange(location: 10, length: 3))

        let result = VisualKeyMapper.keyStrokes(
            for: .beginSelection(linewise: true), family: .textArea, profile: .empty,
            anchor: .establishing(truncated, 42))

        #expect(result?.strokes == [cmdLeft, selDown])
        #expect(result?.anchor == .discard)
    }

    /// 살아 있는 선택 위의 진입은 캐럿을 증명하지 못한다 — 수용 편차의 자리(charwise `P`
    /// 접두 없음과 같은 뿌리)라 수립 없이 폴백이다.
    @Test("선택이 살아 있는 진입은 수립하지 않는다")
    func entryOnLiveSelectionDiscards() {
        let live = focusedText("ab\ncd", caret: 1, length: 2)

        let result = VisualKeyMapper.keyStrokes(
            for: .beginSelection(linewise: false), family: .textArea, profile: .empty,
            anchor: .establishing(live, 42))

        #expect(result?.strokes == [selRight])
        #expect(result?.anchor == .discard)
    }

    /// 읽기가 실패한 진입도 `.discard`다 — 새 세션이 화면에 생기는데 옛 상태가 남으면
    /// 다음 검증이 우연히 통과할 수 있다. 새 진입은 옛 세션을 절대 남기지 않는다.
    @Test("읽기 없는 진입은 옛 상태를 폐기한다")
    func entryWithoutReadDiscards() {
        let result = VisualKeyMapper.keyStrokes(
            for: .beginSelection(linewise: false), family: .textArea, profile: .empty,
            anchor: .none)

        #expect(result?.anchor == .discard)
    }

    // MARK: 폴백 경로의 상태 계약

    @Test("charwise 세션의 폴백 확장은 상태를 건드리지 않는다")
    func charwiseFallbackExtendLeavesStateUnchanged() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.wordForward), family: .textArea, profile: .empty,
            anchor: .session(charwiseSession(), focusedText("ab\ncde", caret: 4, length: 1)))

        #expect(result?.anchor == .unchanged)
    }

    /// linewise 세션의 폴백 확장 뒤에는 포커스 줄 거리를 아는 척할 수 없다 — 착지는 앱만
    /// 안다. 알던 값을 두면 `V`→`v`가 낡은 거리로 잘못 재선택하므로 미상으로 좁힌다.
    @Test("linewise 세션의 폴백 확장은 포커스 줄 거리를 미상으로 만든다")
    func linewiseFallbackExtendUnknowsFocusLineDistance() {
        let state = VisualAnchorState(
            anchor: 3, wise: .linewise, side: .left, pinnedEnd: 3, processID: 42,
            originalCaret: 4, focusLineDistance: 0)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineDown), family: .textArea, profile: .empty,
            anchor: .session(state, focusedText("ab\ncd", caret: 3, length: 2)))

        var expected = state
        expected.focusLineDistance = nil
        #expect(result?.anchor == .set(expected))
    }

    /// `v`→`V` 폴백은 포커스만 반올림해 wise·논리 앵커가 상태와 어긋나는데 앱 앵커는
    /// 그대로라 자가 검증을 거짓 통과한다 — 정확화(⑥)가 증명하지 못하면 폐기가 유일하게
    /// 정직하다. 창이 선택을 다 덮지 못하면 줄 거리를 셀 수 없어 이 폴백이다.
    @Test("증명 못 한 v→V는 폴백 + 상태 폐기다")
    func switchToLinewiseFallbackDiscards() {
        // 창이 선택 시작(4)에 못 닿는다 — `newlinesInsideSelection`이 증명 실패하는 자리.
        let truncated = FocusedText(
            selection: NSRange(location: 4, length: 1), characterCount: 6,
            window: "e", windowRange: NSRange(location: 5, length: 1))

        let result = VisualKeyMapper.keyStrokes(
            for: .switchSelectionWise(linewise: true), family: .textArea, profile: .empty,
            anchor: .session(charwiseSession(), truncated))

        #expect(result?.strokes == [selDown, selCmdLeft])
        #expect(result?.anchor == .discard)
    }

    @Test("clearSelection은 상태를 폐기한다")
    func clearSelectionDiscards() {
        let result = VisualKeyMapper.keyStrokes(
            for: .clearSelection, family: .textArea, profile: .empty, anchor: .none)

        #expect(result?.strokes == [left])
        #expect(result?.anchor == .discard)
    }

    // MARK: `vh` 재앵커 (최소 소비자)

    /// 진입형 `[A, A+1)`의 `h` — 앱 앵커가 왼쪽 끝이라 `Shift-←`로는 왼쪽을 잡을 수 없다.
    /// `→` 1타가 선택을 오른쪽 끝 A+1로 접고(선택이 존재하는 진입형에서 `←,→`와 동치인
    /// 접두 단축), `Shift-←×2`가 `[A−1, A+1)`을 만든다 (side 반전). 정확화 다타 시퀀스라
    /// 페이싱 대상이다.
    @Test("진입형 h는 재앵커한다 — → 후 Shift-←×2, side .right")
    func entryShapedCharLeftReanchors() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.charLeft), family: .textArea, profile: .empty,
            anchor: .session(
                charwiseSession(side: .left), focusedText("ab\ncde", caret: 4, length: 1)))

        #expect(result?.strokes == [right, selLeft, selLeft])
        var expected = charwiseSession(side: .left)
        expected.side = .right
        expected.pinnedEnd = 5
        #expect(result?.anchor == .set(expected))
        #expect(result?.paced == true)
    }

    /// 앵커가 줄 시작(열 0)이면 재앵커하지 않는다 — Vim의 `h`는 앞 줄로 넘어가지 않는데,
    /// 재앵커하면 개행을 선택해 뒤따르는 `d`가 줄을 병합하는 파괴적 회귀가 된다. 폴백
    /// `Shift-←`는 선택을 접을 뿐이라(현행 수용 동작) 다음 읽기의 빈 선택 검증이 정리한다.
    @Test("줄 시작 앵커의 진입형 h는 재앵커하지 않는다")
    func entryShapedCharLeftAtLineStartStaysStateless() {
        let atLineStart = VisualAnchorState(
            anchor: 3, wise: .charwise, side: .left, pinnedEnd: 3,
            processID: 42, originalCaret: nil, focusLineDistance: nil)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.charLeft), family: .textArea, profile: .empty,
            anchor: .session(atLineStart, focusedText("ab\ncde", caret: 3, length: 1)))

        #expect(result?.strokes == [selLeft])
        #expect(result?.anchor == .unchanged)
    }

    /// 이미 전진 확장된 선택(길이 ≥ 2)의 `h`는 축소다 — 현행 `Shift-←` 1타가 그대로 맞아
    /// 재앵커하지 않는다.
    @Test("전진 확장된 선택의 h는 축소 — 현행 1타 그대로")
    func extendedSelectionCharLeftShrinksWithoutReanchor() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.charLeft), family: .textArea, profile: .empty,
            anchor: .session(
                charwiseSession(side: .left), focusedText("ab\ncde", caret: 4, length: 2)))

        #expect(result?.strokes == [selLeft])
        #expect(result?.anchor == .unchanged)
    }

    /// 후진형 `[F, A+1)`의 앱 포커스는 정확히 F — +1 원점 이동은 전진형에만 있어 연속
    /// 후진은 무보정 1타다.
    @Test("후진형 h는 무보정 Shift-← 1타다")
    func backwardShapedCharLeftIsExact() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.charLeft), family: .textArea, profile: .empty,
            anchor: .session(
                charwiseSession(side: .right), focusedText("ab\ncde", caret: 2, length: 3)))

        #expect(result?.strokes == [selLeft])
        #expect(result?.anchor == .unchanged)
    }
}

// MARK: - 정확화 본체 골든 (M5 PR-C1 세션 2 — ④~⑦)

private let down = KeyStroke(kVK_DownArrow)
private let up = KeyStroke(kVK_UpArrow)

/// 문서 `"ab\ncd\nef"` — 오프셋: a0 b1 \n2 c3 d4 \n5 e6 f7, 문서 끝 8. 둘째 줄("cd")이
/// 앵커 줄인 linewise 픽스처의 기본형이다.
private let threeLines = "ab\ncd\nef"

/// `V`로 둘째 줄(앵커 줄 시작 3)에 진입한 linewise 세션 — 원래 캐럿 4(`d` 앞), 거리 0.
private func linewiseSession(
    side: VisualAnchorState.Side = .left, anchor: Int = 3, pinnedEnd: Int = 3,
    originalCaret: Int? = 4, distance: Int? = 0
) -> VisualAnchorState {
    VisualAnchorState(
        anchor: anchor, wise: .linewise, side: side, pinnedEnd: pinnedEnd,
        processID: 42, originalCaret: originalCaret, focusLineDistance: distance)
}

/// ④ — 후진 전체(`vb`)와 전진 대칭(`vl`). `vh`(위 최소 소비자)와 같은 자리의 거울상들이다.
struct VisualBackwardRefinementTests {
    /// `vhll`의 둘째 `l` — 후진형이 앵커에 정확히 닿은 뒤의 전진. `←`가 왼쪽 끝 A로 접고
    /// `Shift-→×2`가 `[A, A+2)`를 만든다 (side 반전 — `h` 재앵커의 거울상).
    @Test("앵커에 닿은 후진형의 l은 재앵커한다 — ← 후 Shift-→×2, side .left")
    func anchorTouchingCharRightReanchors() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.charRight), family: .textArea, profile: .empty,
            anchor: .session(
                charwiseSession(side: .right), focusedText("ab\ncde", caret: 4, length: 1)))

        #expect(result?.strokes == [left, selRight, selRight])
        var expected = charwiseSession(side: .right)
        expected.side = .left
        expected.pinnedEnd = 4
        #expect(result?.anchor == .set(expected))
        #expect(result?.paced == true)
    }

    /// 앵커가 줄 끝(마지막 글자)이면 재앵커하지 않는다 — Vim의 `l`은 줄을 넘지 않는데
    /// 재앵커하면 개행을 선택한다 (`h`의 열 0 봉쇄와 대칭).
    @Test("줄 끝 앵커의 후진형 l은 재앵커하지 않는다")
    func anchorAtLineEndCharRightStaysStateless() {
        let atLineEnd = VisualAnchorState(
            anchor: 5, wise: .charwise, side: .right, pinnedEnd: 6,
            processID: 42, originalCaret: nil, focusLineDistance: nil)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.charRight), family: .textArea, profile: .empty,
            anchor: .session(atLineEnd, focusedText("ab\ncde", caret: 5, length: 1)))

        #expect(result?.strokes == [selRight])
        #expect(result?.anchor == .unchanged)
    }

    /// 진입형 `vb` — `h` 재앵커와 같은 접두에 재확장만 `Shift-Opt-←`다.
    @Test("진입형 b는 재앵커한다 — 단어 중간이면 ×1")
    func entryShapedWordBackwardReanchors() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.wordBackward), family: .textArea, profile: .empty,
            anchor: .session(
                charwiseSession(side: .left), focusedText("ab\ncde", caret: 4, length: 1)))

        #expect(result?.strokes == [right, selOptLeft])
        var expected = charwiseSession(side: .left)
        expected.side = .right
        expected.pinnedEnd = 5
        #expect(result?.anchor == .set(expected))
        #expect(result?.paced == true)
    }

    /// 커서 글자가 단어 시작이면 Vim의 `b`는 **이전** 단어 시작으로 뛴다 — macOS 1타는
    /// 제자리로 돌아올 뿐이라 ×2다 (PR-B 단어 술어 재사용).
    @Test("단어 시작 위의 진입형 b는 ×2다")
    func wordStartEntryShapedWordBackwardDoubles() {
        let atWordStart = VisualAnchorState(
            anchor: 3, wise: .charwise, side: .left, pinnedEnd: 3,
            processID: 42, originalCaret: nil, focusLineDistance: nil)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.wordBackward), family: .textArea, profile: .empty,
            anchor: .session(atWordStart, focusedText("ab\ncde", caret: 3, length: 1)))

        #expect(result?.strokes == [right, selOptLeft, selOptLeft])
    }

    /// 후진형의 `b`는 무보정 1타가 이미 정확하다 — 폴백과 바이트 동일이라 위임한다.
    @Test("후진형 b는 무보정 Shift-Opt-← 1타다")
    func backwardShapedWordBackwardIsExact() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.wordBackward), family: .textArea, profile: .empty,
            anchor: .session(
                charwiseSession(side: .right), focusedText("ab\ncde", caret: 2, length: 3)))

        #expect(result?.strokes == [selOptLeft])
        #expect(result?.anchor == .unchanged)
    }
}

/// ④ — linewise 후진(`Vk`·`Vgg`)과 전진 대칭(`Vj`), 그리고 거리 ±1 추적.
struct VisualLinewiseRefinementTests {
    /// `Vk` 방향 전환 — `→`가 오른쪽 끝(= 앵커 줄 끝 다음)으로 접고 `Shift-↑×2`가
    /// 현재 줄 + 위 줄을 만든다. 결정 표의 `←,↓`와 동치인 1타 접두다.
    @Test("d=0의 Vk는 재앵커한다 — → 후 Shift-↑×2, side .right")
    func lineUpAtAnchorLineReanchors() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineUp), family: .textArea, profile: .empty,
            anchor: .session(linewiseSession(), focusedText(threeLines, caret: 3, length: 3)))

        #expect(result?.strokes == [right, selUp, selUp])
        var expected = linewiseSession()
        expected.side = .right
        expected.pinnedEnd = 6
        expected.focusLineDistance = -1
        #expect(result?.anchor == .set(expected))
        #expect(result?.paced == true)
    }

    /// 첫 줄의 `Vk`는 Vim no-op다 — 증명이 절대적(오프셋 0 = 문서 시작)이라 무게시가
    /// 정확 동작이고, 매퍼 `nil`을 어댑터의 상태 프로브가 `.skipped`로 가른다.
    @Test("첫 줄의 Vk는 무게시 nil이다")
    func lineUpAtFirstLineIsInvalid() {
        let firstLine = linewiseSession(anchor: 0, pinnedEnd: 0, originalCaret: 1)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineUp), family: .textArea, profile: .empty,
            anchor: .session(firstLine, focusedText(threeLines, caret: 0, length: 3)))

        #expect(result == nil)
    }

    /// 아래로 확장된 선택의 `k`는 축소다 — 스트로크는 폴백과 같고 거리만 −1로 유지한다
    /// (폴백은 미상으로 좁힌다 — 그 차이가 `V`→`v` 조건부 지원의 생명선이다).
    @Test("확장된 선택의 Vk는 축소 — 거리만 -1")
    func lineUpOnExtendedSelectionShrinksAndNarrowsDistance() {
        let extended = linewiseSession(distance: 1)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineUp), family: .textArea, profile: .empty,
            anchor: .session(extended, focusedText(threeLines, caret: 3, length: 5)))

        #expect(result?.strokes == [selUp])
        var expected = extended
        expected.focusLineDistance = 0
        #expect(result?.anchor == .set(expected))
    }

    /// 후진형의 연속 `k`는 무보정 1타다 — 포커스가 줄 시작(열 0)임이 증명될 때만 거리를
    /// 좁힌다 (위 줄 존재 증명을 겸한다).
    @Test("후진형 Vk는 무보정 1타 + 거리 -1")
    func backwardLineUpIsExactAndTracksDistance() {
        let fourLines = "ab\ncd\nef\ngh"  // a0 b1 \n2 c3 d4 \n5 e6 f7 \n8 g9 h10
        let backward = linewiseSession(
            side: .right, anchor: 6, pinnedEnd: 9, originalCaret: 7, distance: -1)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineUp), family: .textArea, profile: .empty,
            anchor: .session(backward, focusedText(fourLines, caret: 3, length: 6)))

        #expect(result?.strokes == [selUp])
        var expected = backward
        expected.focusLineDistance = -2
        #expect(result?.anchor == .set(expected))
    }

    /// `Vj` 확장 — 선택 끝 다음 문자의 실재가 증명될 때만 거리를 +1로 넓힌다.
    @Test("Vj 확장은 거리 +1 — 문서 끝이 증명 안 되면 폴백이 미상으로 좁힌다")
    func lineDownWidensDistanceOnlyWhenProven() {
        let proven = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineDown), family: .textArea, profile: .empty,
            anchor: .session(linewiseSession(), focusedText(threeLines, caret: 3, length: 3)))
        #expect(proven?.strokes == [selDown])
        var expected = linewiseSession()
        expected.focusLineDistance = 1
        #expect(proven?.anchor == .set(expected))

        // 선택 끝이 문서 끝 — `Shift-↓`는 포화한다. 증명 실패라 폴백이 거리를 좁힌다.
        let saturated = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineDown), family: .textArea, profile: .empty,
            anchor: .session(
                linewiseSession(distance: 1), focusedText(threeLines, caret: 3, length: 5)))
        #expect(saturated?.strokes == [selDown])
        var narrowed = linewiseSession(distance: 1)
        narrowed.focusLineDistance = nil
        #expect(saturated?.anchor == .set(narrowed))
    }

    /// `Vkjj`의 둘째 `j` — 후진형이 앵커 줄로 돌아온 뒤(d = 0)의 전진. `←`가 왼쪽 끝
    /// (= 앵커 줄 시작)으로 접고 `Shift-↓×2`가 앵커 줄 + 아래 줄을 만든다 (`Vk`의 거울상).
    @Test("d=0의 후진형 Vj는 재앵커한다 — ← 후 Shift-↓×2, side .left")
    func lineDownAtAnchorLineReanchors() {
        let returned = linewiseSession(side: .right, pinnedEnd: 6, distance: 0)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineDown), family: .textArea, profile: .empty,
            anchor: .session(returned, focusedText(threeLines, caret: 3, length: 3)))

        #expect(result?.strokes == [left, selDown, selDown])
        var expected = returned
        expected.side = .left
        expected.pinnedEnd = 3
        expected.focusLineDistance = 1
        #expect(result?.anchor == .set(expected))
        #expect(result?.paced == true)
    }

    /// 후진형의 `j`는 축소다 — 아래에 앵커 줄이 있어 포화가 없고, 거리만 +1로 좁힌다.
    @Test("후진형 Vj는 축소 — 거리 +1")
    func backwardLineDownShrinks() {
        let backward = linewiseSession(side: .right, pinnedEnd: 6, distance: -1)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineDown), family: .textArea, profile: .empty,
            anchor: .session(backward, focusedText(threeLines, caret: 0, length: 6)))

        #expect(result?.strokes == [selDown])
        var expected = backward
        expected.focusLineDistance = 0
        #expect(result?.anchor == .set(expected))
    }

    /// `Vgg` 전진형 — `←`(앵커 줄 시작으로 collapse), `↓`(앵커 줄 끝 다음 착지) 뒤
    /// `Shift-Cmd-↑` 1타(상수). 거리와 무관하게 성립해 `G` 경유 뒤(d 미상)에도 선다.
    @Test("전진형 Vgg는 재앵커한다 — ←,↓ 후 Shift-Cmd-↑, side .right")
    func documentStartOnForwardReanchors() {
        let unknownDistance = linewiseSession(distance: nil)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.documentStart), family: .textArea, profile: .empty,
            anchor: .session(unknownDistance, focusedText(threeLines, caret: 3, length: 5)))

        #expect(result?.strokes == [left, down, selCmdUp])
        var expected = unknownDistance
        expected.side = .right
        expected.pinnedEnd = 6
        expected.focusLineDistance = nil
        #expect(result?.anchor == .set(expected))
        #expect(result?.paced == true)
    }

    /// 앵커 줄의 개행을 증명 못 하면(개행 없는 마지막 줄 — `↓`가 포화하는 자리) 폴백이다.
    @Test("마지막 줄 앵커의 Vgg는 재앵커하지 않는다")
    func documentStartOnLastLineAnchorStaysStateless() {
        let lastLine = linewiseSession(anchor: 6, pinnedEnd: 6, originalCaret: 7)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.documentStart), family: .textArea, profile: .empty,
            anchor: .session(lastLine, focusedText(threeLines, caret: 6, length: 2)))

        #expect(result?.strokes == [selCmdUp])
        var narrowed = lastLine
        narrowed.focusLineDistance = nil
        #expect(result?.anchor == .set(narrowed))
    }

    /// 후진형 `Vgg` — 앱 앵커가 이미 앵커 줄 끝 다음이라 1타다. 착지 줄 수는 알 수 없어
    /// 거리만 미상으로 좁힌다 (폴백과 바이트 동일하되 상태 갱신이 다르다).
    @Test("후진형 Vgg는 1타 + 거리 미상")
    func documentStartOnBackwardIsSingleStroke() {
        let backward = linewiseSession(side: .right, pinnedEnd: 6, distance: -1)

        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.documentStart), family: .textArea, profile: .empty,
            anchor: .session(backward, focusedText(threeLines, caret: 0, length: 6)))

        #expect(result?.strokes == [selCmdUp])
        var expected = backward
        expected.focusLineDistance = nil
        #expect(result?.anchor == .set(expected))
    }
}

/// ⑤ — `V` 세션의 charwise 모션은 Vim에서 범위를 바꾸지 않는다. 무게시(`nil`)가 곧 정확
/// 동작이고, desync 실패 모드는 무해한 no-op다
/// (`20260804_visual-linewise-motion-range-noop.md`).
struct VisualLinewiseMotionSkipTests {
    private static let charwiseMotions: [Motion] = [
        .charLeft, .charRight, .wordForward, .wordBackward, .wordEndForward,
        .lineStart, .lineFirstNonBlank, .lineEnd,
    ]

    @Test("V 세션의 charwise 모션 8종은 무게시 nil이다", arguments: Self.charwiseMotions)
    func linewiseSessionSkipsCharwiseMotions(_ motion: Motion) {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(motion), family: .textArea, profile: .empty,
            anchor: .session(linewiseSession(), focusedText(threeLines, caret: 3, length: 3)))

        #expect(result == nil, "\(motion)")
    }

    /// 무상태 폴백에서는 종전 그대로 게시된다 — 스킵은 검증된 상태가 있을 때만이다.
    @Test("같은 모션도 상태가 없으면 종전 시퀀스다")
    func statelessFallbackStillPublishes() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.lineEnd), family: .textArea, profile: .empty, anchor: .none)

        #expect(result?.strokes == [selCmdRight])
    }
}

/// ⑥·⑦ — wise 전환 양방향. `v`→`V`는 재앵커로 앵커 쪽도 줄 반올림하고(폴백 `.discard`의
/// 해소), `V`→`v`는 보관된 원래 캐럿과 줄 거리로 재선택한다.
struct VisualSwitchWiseRefinementTests {
    /// 같은 줄 안의 `v`→`V` — `←`(A로 collapse), `Cmd-←`(줄 시작), `Shift-↓`(줄 통째).
    /// 전환 후 상태가 완전히 수립되고 옛 charwise 앵커가 `originalCaret`으로 보관되어
    /// 이후 `V`→`v` 재전환도 선다.
    @Test("v→V는 앵커 줄을 재수립한다 — 같은 줄")
    func roundToLinewiseSameLine() {
        let result = VisualKeyMapper.keyStrokes(
            for: .switchSelectionWise(linewise: true), family: .textArea, profile: .empty,
            anchor: .session(charwiseSession(), focusedText("ab\ncde", caret: 4, length: 1)))

        #expect(result?.strokes == [left, cmdLeft, selDown])
        #expect(
            result?.anchor
                == .set(
                    VisualAnchorState(
                        anchor: 3, wise: .linewise, side: .left, pinnedEnd: 3, processID: 42,
                        originalCaret: 4, focusLineDistance: 0)))
        #expect(result?.paced == true)
    }

    /// 여러 줄에 걸친 전진형 — 줄 거리(k)는 선택 내부의 개행 수로 증명하고, `Shift-↓`가
    /// k+1회 나가 포커스 줄까지 통째로 잡는다.
    @Test("여러 줄 v→V는 줄 거리만큼 재확장한다")
    func roundToLinewiseAcrossLines() {
        let spanning = VisualAnchorState(
            anchor: 3, wise: .charwise, side: .left, pinnedEnd: 3,
            processID: 42, originalCaret: nil, focusLineDistance: nil)

        let result = VisualKeyMapper.keyStrokes(
            for: .switchSelectionWise(linewise: true), family: .textArea, profile: .empty,
            anchor: .session(spanning, focusedText(threeLines, caret: 3, length: 4)))

        #expect(result?.strokes == [left, cmdLeft, selDown, selDown])
        #expect(
            result?.anchor
                == .set(
                    VisualAnchorState(
                        anchor: 3, wise: .linewise, side: .left, pinnedEnd: 3, processID: 42,
                        originalCaret: 3, focusLineDistance: 1)))
    }

    /// 후진형 — `→`(A+1로 collapse), `↓, Cmd-←`(앵커 줄 끝 다음) 뒤 `Shift-↑ ×(k+1)`.
    /// 앵커 줄의 개행과 줄 시작을 창에서 증명해야 한다.
    @Test("후진형 v→V는 앵커 줄 끝 다음에 재수립한다")
    func roundToLinewiseBackward() {
        let backward = VisualAnchorState(
            anchor: 4, wise: .charwise, side: .right, pinnedEnd: 5,
            processID: 42, originalCaret: nil, focusLineDistance: nil)

        let result = VisualKeyMapper.keyStrokes(
            for: .switchSelectionWise(linewise: true), family: .textArea, profile: .empty,
            anchor: .session(backward, focusedText(threeLines, caret: 1, length: 4)))

        #expect(result?.strokes == [right, down, cmdLeft, selUp, selUp])
        #expect(
            result?.anchor
                == .set(
                    VisualAnchorState(
                        anchor: 3, wise: .linewise, side: .right, pinnedEnd: 6, processID: 42,
                        originalCaret: 4, focusLineDistance: -1)))
    }

    /// ⑦ 전진형 — `←`(앵커 줄 시작), `→ ×열`(P로), `Shift-↓ ×d`(열 보존), `Shift-→`
    /// (inclusive). 원래 캐럿과 줄 거리를 둘 다 알 때만이다.
    @Test("V→v는 원래 캐럿에서 재선택한다 — 전진형")
    func restoreToCharwiseForward() {
        let result = VisualKeyMapper.keyStrokes(
            for: .switchSelectionWise(linewise: false), family: .textArea, profile: .empty,
            anchor: .session(
                linewiseSession(distance: 1), focusedText(threeLines, caret: 3, length: 5)))

        #expect(result?.strokes == [left, right, selDown, selRight])
        #expect(
            result?.anchor
                == .set(
                    VisualAnchorState(
                        anchor: 4, wise: .charwise, side: .left, pinnedEnd: 4, processID: 42,
                        originalCaret: nil, focusLineDistance: nil)))
        #expect(result?.paced == true)
    }

    /// ⑦ 후진형 — `→`(앵커 줄 끝 다음), `↑`(열 0 보존 — 앵커 줄 시작), `→ ×(열+1)`(P+1),
    /// `Shift-↑ ×|d|`, `Shift-←`(inclusive 보정).
    @Test("V→v는 원래 캐럿에서 재선택한다 — 후진형")
    func restoreToCharwiseBackward() {
        let backward = linewiseSession(side: .right, pinnedEnd: 6, distance: -1)

        let result = VisualKeyMapper.keyStrokes(
            for: .switchSelectionWise(linewise: false), family: .textArea, profile: .empty,
            anchor: .session(backward, focusedText(threeLines, caret: 0, length: 6)))

        #expect(result?.strokes == [right, up, right, right, selUp, selLeft])
        #expect(
            result?.anchor
                == .set(
                    VisualAnchorState(
                        anchor: 4, wise: .charwise, side: .right, pinnedEnd: 5, processID: 42,
                        originalCaret: nil, focusLineDistance: nil)))
    }

    /// 조건 불충족은 현행 `nil`(정직한 스킵) 그대로다 — 근사 재선택은 "잘못된 범위를
    /// 정확하게"라 파괴적 오퍼레이터 앞에서 스킵보다 나쁘다.
    @Test("원래 캐럿·줄 거리·열 상한 — 하나라도 어긋나면 V→v는 nil이다")
    func restoreToCharwiseRequiresBothInputs() {
        let text = focusedText(threeLines, caret: 3, length: 3)
        let noCaret = linewiseSession(originalCaret: nil)
        let noDistance = linewiseSession(distance: nil)
        // 열 33 — 상한(32) 초과. 위치 접두 폭주를 자르는 클램프다 (실측으로 확정할 조절값).
        let farColumn = linewiseSession(originalCaret: 36)

        for state in [noCaret, noDistance, farColumn] {
            let result = VisualKeyMapper.keyStrokes(
                for: .switchSelectionWise(linewise: false), family: .textArea, profile: .empty,
                anchor: .session(state, text))
            #expect(result == nil)
        }
    }
}

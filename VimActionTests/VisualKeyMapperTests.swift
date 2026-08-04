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
    /// 그대로라 자가 검증을 거짓 통과한다 — 폐기가 유일하게 정직하다.
    @Test("v→V 폴백은 상태를 폐기한다")
    func switchToLinewiseFallbackDiscards() {
        let result = VisualKeyMapper.keyStrokes(
            for: .switchSelectionWise(linewise: true), family: .textArea, profile: .empty,
            anchor: .session(charwiseSession(), focusedText("ab\ncde", caret: 4, length: 1)))

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
    /// `←,→`로 캐럿을 A+1에 재수립한 뒤 `Shift-←×2`가 `[A−1, A+1)`을 만든다 (side 반전).
    @Test("진입형 h는 재앵커한다 — ←,→ 후 Shift-←×2, side .right")
    func entryShapedCharLeftReanchors() {
        let result = VisualKeyMapper.keyStrokes(
            for: .extendSelection(.charLeft), family: .textArea, profile: .empty,
            anchor: .session(
                charwiseSession(side: .left), focusedText("ab\ncde", caret: 4, length: 1)))

        #expect(result?.strokes == [left, right, selLeft, selLeft])
        var expected = charwiseSession(side: .left)
        expected.side = .right
        expected.pinnedEnd = 5
        #expect(result?.anchor == .set(expected))
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

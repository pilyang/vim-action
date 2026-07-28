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

        #expect(extended?.map(\.keyCode) == motionStrokes.map(\.keyCode), "\(motion)")
        #expect(
            extended?.map { $0.flags.subtracting(.maskShift) } == motionStrokes.map(\.flags),
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

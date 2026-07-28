//
//  EditKeyMapperTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine

@testable import VimAction

// MARK: - 표기 상수

// 선택 없는 이동 — 선택 시작점을 잡는 접두에만 쓰인다.
private let cmdLeft = KeyStroke(kVK_LeftArrow, [.maskCommand])
private let cmdRight = KeyStroke(kVK_RightArrow, [.maskCommand])
private let up = KeyStroke(kVK_UpArrow)
private let down = KeyStroke(kVK_DownArrow)
private let optLeft = KeyStroke(kVK_LeftArrow, [.maskAlternate])
private let optRight = KeyStroke(kVK_RightArrow, [.maskAlternate])

// 선택 확장 — 모션 스트로크에 Shift를 얹은 형태.
private let selLeft = KeyStroke(kVK_LeftArrow, [.maskShift])
private let selRight = KeyStroke(kVK_RightArrow, [.maskShift])
private let selDown = KeyStroke(kVK_DownArrow, [.maskShift])
private let selOptLeft = KeyStroke(kVK_LeftArrow, [.maskShift, .maskAlternate])
private let selOptRight = KeyStroke(kVK_RightArrow, [.maskShift, .maskAlternate])
private let selCmdLeft = KeyStroke(kVK_LeftArrow, [.maskShift, .maskCommand])
private let selCmdRight = KeyStroke(kVK_RightArrow, [.maskShift, .maskCommand])
private let selCmdUp = KeyStroke(kVK_UpArrow, [.maskShift, .maskCommand])
private let selCmdDown = KeyStroke(kVK_DownArrow, [.maskShift, .maskCommand])

// 오퍼레이터 1타 + yank collapse.
private let cutKey = KeyStroke(kVK_ANSI_X, [.maskCommand])
private let copyKey = KeyStroke(kVK_ANSI_C, [.maskCommand])
private let collapseLeft = KeyStroke(kVK_LeftArrow)

// MARK: - 픽스처

/// 매핑 계약표 한 행. **이 표가 곧 계약이다** — 시퀀스가 바뀌면 여기가 먼저 바뀐다.
/// `expected == nil`은 "이 계열에서 미지원" = 어댑터가 스킵+로그할 대상이다.
struct EditMappingFixture: Sendable, CustomTestStringConvertible {
    var vim: String
    var op: VimAction.Operator
    var range: VimAction.TextRange
    var expected: [KeyStroke]?

    init(
        _ vim: String, _ op: VimAction.Operator, _ range: VimAction.TextRange,
        _ expected: [KeyStroke]?
    ) {
        self.vim = vim
        self.op = op
        self.range = range
        self.expected = expected
    }

    var testDescription: String { vim }
}

/// charwise 한 모션의 3 오퍼레이터 행. 선택 시퀀스는 모션별로 직접 적고,
/// 오퍼레이터 접미(`Cmd-X` / `Cmd-C`+`←`)만 공통으로 붙인다.
private func charwise(
    _ vim: String, _ motion: Motion, _ selection: [KeyStroke], change: [KeyStroke]? = nil
) -> [EditMappingFixture] {
    [
        .init("d\(vim)", .delete, .motion(motion, count: 1), selection + [cutKey]),
        .init("c\(vim)", .change, .motion(motion, count: 1), (change ?? selection) + [cutKey]),
        .init("y\(vim)", .yank, .motion(motion, count: 1), selection + [copyKey, collapseLeft]),
    ]
}

/// charwise 24조합 — 오퍼레이터 3종 × opMotion 화이트리스트 8종.
/// `cw`만 특례로 `ce`(단어 끝) 선택이 된다.
let charwiseEditFixtures: [EditMappingFixture] =
    charwise("h", .charLeft, [selLeft])
    + charwise("l", .charRight, [selRight])
    + charwise("w", .wordForward, [selOptRight, selOptRight, selOptLeft], change: [selOptRight])
    + charwise("b", .wordBackward, [selOptLeft])
    + charwise("e", .wordEndForward, [selOptRight])
    + charwise("0", .lineStart, [selCmdLeft])
    + charwise("^", .lineFirstNonBlank, [selCmdLeft, selOptRight, selOptLeft])
    + charwise("$", .lineEnd, [selCmdRight])

/// linewise 15조합. delete/yank는 개행을 포함하고(`Shift-↓`), change는 줄을 유지한 채
/// 마지막 확장만 `Shift-Cmd-→`로 바꿔 내용만 비운다.
/// 절대 모션은 비대칭이다: `gg`는 한 줄 내려가 잡아 정확하고, `G`는 아래 개행이 없어
/// 빈 줄 1개가 남는다(수용).
let linewiseEditFixtures: [EditMappingFixture] = [
    .init("dd", .delete, .line(count: 1), [cmdLeft, selDown, cutKey]),
    .init("cc", .change, .line(count: 1), [cmdLeft, selCmdRight, cutKey]),
    .init("yy", .yank, .line(count: 1), [cmdLeft, selDown, copyKey, collapseLeft]),

    .init("dj", .delete, .linewiseMotion(.lineDown, count: 1), [cmdLeft, selDown, selDown, cutKey]),
    .init("cj", .change, .linewiseMotion(.lineDown, count: 1), [cmdLeft, selDown, selCmdRight, cutKey]),
    .init(
        "yj", .yank, .linewiseMotion(.lineDown, count: 1),
        [cmdLeft, selDown, selDown, copyKey, collapseLeft]),

    .init(
        "dk", .delete, .linewiseMotion(.lineUp, count: 1),
        [cmdLeft, up, cmdLeft, selDown, selDown, cutKey]),
    .init(
        "ck", .change, .linewiseMotion(.lineUp, count: 1),
        [cmdLeft, up, cmdLeft, selDown, selCmdRight, cutKey]),
    .init(
        "yk", .yank, .linewiseMotion(.lineUp, count: 1),
        [cmdLeft, up, cmdLeft, selDown, selDown, copyKey, collapseLeft]),

    // G는 delete/change가 같은 시퀀스다 — 남는 빈 줄이 change에서는 곧 정답이다.
    .init("dG", .delete, .linewiseMotion(.documentEnd, count: 1), [cmdLeft, selCmdDown, cutKey]),
    .init("cG", .change, .linewiseMotion(.documentEnd, count: 1), [cmdLeft, selCmdDown, cutKey]),
    .init(
        "yG", .yank, .linewiseMotion(.documentEnd, count: 1),
        [cmdLeft, selCmdDown, copyKey, collapseLeft]),

    .init(
        "dgg", .delete, .linewiseMotion(.documentStart, count: 1),
        [cmdLeft, down, cmdLeft, selCmdUp, cutKey]),
    .init("cgg", .change, .linewiseMotion(.documentStart, count: 1), [cmdRight, selCmdUp, cutKey]),
    .init(
        "ygg", .yank, .linewiseMotion(.documentStart, count: 1),
        [cmdLeft, down, cmdLeft, selCmdUp, copyKey, collapseLeft]),
]

/// word 텍스트 오브젝트 근사 — 단어 시작으로 물러난 뒤 단어 끝까지 선택.
let wordObjectEditFixtures: [EditMappingFixture] = [
    .init("diw", .delete, .textObject(.word(.inner)), [optRight, optLeft, selOptRight, cutKey]),
    .init("ciw", .change, .textObject(.word(.inner)), [optRight, optLeft, selOptRight, cutKey]),
    .init(
        "yiw", .yank, .textObject(.word(.inner)),
        [optRight, optLeft, selOptRight, copyKey, collapseLeft]),
]

/// 카운트 변형 — 엔진이 두 카운트를 곱으로 접어 전달하므로 매퍼는 선택만 그만큼 반복한다.
let countEditFixtures: [EditMappingFixture] = [
    .init("3x", .delete, .motion(.charRight, count: 3), [selRight, selRight, selRight, cutKey]),
    .init(
        "d3w", .delete, .motion(.wordForward, count: 3),
        [
            selOptRight, selOptRight, selOptLeft,
            selOptRight, selOptRight, selOptLeft,
            selOptRight, selOptRight, selOptLeft,
            cutKey,
        ]),
    // cw 특례는 카운트에도 그대로 — 3회 모두 단어 끝 선택이다.
    .init(
        "c3w", .change, .motion(.wordForward, count: 3),
        [selOptRight, selOptRight, selOptRight, cutKey]),
    // 2d3w = 곱 6 (엔진이 접어 준다).
    .init(
        "2y3w", .yank, .motion(.wordForward, count: 6),
        Array(repeating: [selOptRight, selOptRight, selOptLeft], count: 6).flatMap { $0 }
            + [copyKey, collapseLeft]),
    .init("2dd", .delete, .line(count: 2), [cmdLeft, selDown, selDown, cutKey]),
    // 2cc는 두 줄을 비우고 **한 줄**을 남긴다 — 마지막 확장만 줄 끝으로.
    .init("2cc", .change, .line(count: 2), [cmdLeft, selDown, selCmdRight, cutKey]),
    .init(
        "d2j", .delete, .linewiseMotion(.lineDown, count: 2),
        [cmdLeft, selDown, selDown, selDown, cutKey]),
    .init(
        "d2k", .delete, .linewiseMotion(.lineUp, count: 2),
        [cmdLeft, up, up, cmdLeft, selDown, selDown, selDown, cutKey]),
]

/// 미지원 — 어댑터가 스킵+로그할 대상. **무로그 삼킴 금지**가 릴리스 게이트 규칙이라
/// "빈 배열"이 아니라 `nil`이어야 한다.
let unsupportedEditFixtures: [EditMappingFixture] = [
    .init("daw", .delete, .textObject(.word(.around)), nil),
    .init("ci\"", .change, .textObject(.quote(.double, .inner)), nil),
    .init("ya(", .yank, .textObject(.pair(.paren, .around)), nil),
    // 엔진은 내지 않지만 매퍼는 total function이다 — linewise 자리의 낯선 모션도 답이 있다.
    .init("d<linewise w>", .delete, .linewiseMotion(.wordForward, count: 1), nil),
]

/// Visual 선택 동작 — 화면에 선택이 이미 있으므로 **선택 시퀀스 없이 오퍼레이터 1타뿐**이고,
/// 요소 계열과도 무관하다(이미 있는 선택에 대한 `Cmd-X`/`Cmd-C`는 TextField에서도 같다).
///
/// `v_y`에 `←`가 없는 것이 핵심이다 — Visual `y`는 엔진이 `.edit(.yank, .selection)`과
/// `clearSelection`을 연달아 내므로 collapse는 뒤따르는 `clearSelection`이 전담한다.
/// 양쪽이 다 내면 캐럿이 한 칸 더 밀린다
/// (`20260728_visual-clear-selection-collapse-left.md`). Normal의 `yw`는 그대로 `Cmd-C`+`←`다.
let selectionEditFixtures: [EditMappingFixture] = [
    .init("v_d", .delete, .selection, [cutKey]),
    .init("v_c", .change, .selection, [cutKey]),
    .init("v_y", .yank, .selection, [copyKey]),
]

let editMappingFixtures: [EditMappingFixture] =
    charwiseEditFixtures + linewiseEditFixtures + wordObjectEditFixtures + countEditFixtures
    + unsupportedEditFixtures + selectionEditFixtures

// MARK: - 테스트

struct EditKeyMapperTests {
    @Test("매핑표 골든 — 편집이 계약대로 키스트로크가 된다", arguments: editMappingFixtures)
    func mapsEditAsContracted(_ fixture: EditMappingFixture) {
        let actual = EditKeyMapper.keyStrokes(for: fixture.op, range: fixture.range, family: .textArea)
        #expect(actual == fixture.expected, "\(fixture.vim)")
    }

    /// 지원 범위는 반드시 실행 가능한 형태로 매핑된다 — 빈 배열은 "조용히 아무것도 안 함"이라
    /// 미지원(`nil` → 스킵+로그)과 구분되지 않는다.
    @Test("지원 범위는 빈 시퀀스로 매핑되지 않는다", arguments: editMappingFixtures)
    func supportedRangesNeverMapToEmpty(_ fixture: EditMappingFixture) {
        guard let expected = fixture.expected else { return }
        #expect(!expected.isEmpty)
    }

    /// 모든 편집은 선택 후 오퍼레이터 1타로 끝난다 — yank만 collapse가 뒤따른다.
    /// 접미가 어긋나면 선택만 해 놓고 아무것도 안 하거나, 선택이 남아 다음 입력을 오염시킨다.
    ///
    /// `.selection` yank만 예외로 collapse가 없다 — 엔진이 뒤이어 내는 `clearSelection`이
    /// 전담하므로 여기서 또 내면 캐럿이 한 칸 더 밀린다. **이 분기가 그 함정의 방어선이다.**
    @Test("시퀀스는 오퍼레이터 키로 끝난다", arguments: editMappingFixtures)
    func sequenceEndsWithOperatorKey(_ fixture: EditMappingFixture) {
        guard let expected = fixture.expected else { return }
        switch fixture.op {
        case .delete, .change:
            #expect(expected.last == cutKey, "\(fixture.vim)")
        case .yank where fixture.range == .selection:
            #expect(expected == [copyKey], "\(fixture.vim)")
        case .yank:
            #expect(expected.suffix(2) == [copyKey, collapseLeft], "\(fixture.vim)")
        }
    }

    /// 선택 구간은 전부 Shift를 싣는다 — 한 타라도 Shift가 빠지면 선택이 그 자리에서
    /// 무너지고 캐럿만 이동해, 뒤이은 `Cmd-X`가 엉뚱한 범위를 자른다.
    /// (Shift 없이 허용되는 것은 선택 시작점을 잡는 접두와 yank collapse뿐이다.)
    @Test("charwise 선택은 모든 스트로크에 Shift가 실린다", arguments: charwiseEditFixtures)
    func charwiseSelectionAlwaysCarriesShift(_ fixture: EditMappingFixture) {
        guard let expected = fixture.expected else { return }
        let selection = fixture.op == .yank ? expected.dropLast(2) : expected.dropLast()
        #expect(selection.allSatisfy { $0.flags.contains(.maskShift) }, "\(fixture.vim)")
    }
}

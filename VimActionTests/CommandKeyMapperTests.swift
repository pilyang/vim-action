//
//  CommandKeyMapperTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine

@testable import VimAction

// MARK: - 표기 상수

// 위치 잡는 접두 — 전부 모션 매핑의 재사용이다.
private let right = KeyStroke(kVK_RightArrow)
private let up = KeyStroke(kVK_UpArrow)
private let down = KeyStroke(kVK_DownArrow)
private let cmdLeft = KeyStroke(kVK_LeftArrow, [.maskCommand])
private let cmdRight = KeyStroke(kVK_RightArrow, [.maskCommand])

// 명령 키 — 시퀀스의 끝(단 `O`는 `↑`로, 스크롤은 아예 명령 키 없이 끝난다).
private let ret = KeyStroke(kVK_Return)
private let pasteKey = KeyStroke(kVK_ANSI_V, [.maskCommand])
private let undoKey = KeyStroke(kVK_ANSI_Z, [.maskCommand])
private let redoKey = KeyStroke(kVK_ANSI_Z, [.maskShift, .maskCommand])

/// 명령 키 집합 — "명령 키는 시퀀스당 1타"(paste·스크롤 제외) 불변식이 이 집합을 센다.
private let commandKeys: Set<CGKeyCode> = [ret.keyCode, pasteKey.keyCode, undoKey.keyCode]

// MARK: - 픽스처

/// 매핑 계약표 한 행. **이 표가 곧 계약이다.**
/// `expected == nil`은 미지원 = 어댑터가 스킵+로그할 대상이다.
///
/// paste는 진입점이 달라 `wise`·`count`를 함께 들고, 나머지는 `action`만 쓴다 — 두 진입점의
/// 행을 **한 배열로 합치는 것이 요점**이다. 따로 두면 paste 행이 공통 불변식 테스트를
/// 조용히 빠져나간다.
struct CommandMappingFixture: Sendable, CustomTestStringConvertible {
    var vim: String
    var action: VimAction
    var wise: PasteWise?
    var expected: [KeyStroke]?

    init(_ vim: String, _ action: VimAction, wise: PasteWise? = nil, _ expected: [KeyStroke]?) {
        self.vim = vim
        self.action = action
        self.wise = wise
        self.expected = expected
    }

    var testDescription: String { vim }

    /// 진입점 선택까지 픽스처가 안다 — 테스트 본문이 분기를 들지 않게.
    var actual: [KeyStroke]? {
        guard case .paste(let before, let count) = action, let wise else {
            return CommandKeyMapper.keyStrokes(for: action, family: .textArea)
        }
        return CommandKeyMapper.pasteStrokes(
            before: before, count: count, wise: wise, family: .textArea)
    }
}

/// `o`/`O` — 엔진이 이미 Insert로 전이했으므로 뒤에 붙일 키가 없다.
///
/// `O`가 `↑, Cmd-→, Return`이 아닌 것이 핵심이다 — 그 순서는 **첫 줄에서 `↑`가 no-op이라
/// 조용히 `o`로 퇴행**한다(`20260730_openline-return-sequence.md`).
let openLineFixtures: [CommandMappingFixture] = [
    .init("o", .openLine(above: false), [cmdRight, ret]),
    .init("O", .openLine(above: true), [cmdLeft, ret, up]),
]

/// `u`/`Ctrl-r` — 네이티브 undo 위임. 시퀀스 설계에 undo 쪼개짐 제약이 없다는 것이
/// 단계 0 실측의 결론이다(`20260726_undo-unit-cmdz-policy.md`).
let undoRedoFixtures: [CommandMappingFixture] = [
    .init("u", .undo, [undoKey]),
    .init("Ctrl-r", .redo, [redoKey]),
]

/// 스크롤 4조합 — 화살표 반복이다. 이 매퍼에서 **유일하게 네이티브 명령에 위임하지 않는**
/// 어휘인데, macOS에 "캐럿을 한 뷰포트만큼 옮기는" 프리미티브가 없기 때문이다. PageUp/PageDown은
/// 뷰만 옮겨 다음 모션 한 번에 되돌아온다(실측). Vim의 `Ctrl-d`/`Ctrl-f`도 본래 커서 이동이다
/// (`20260730_scroll-arrow-repetition.md`).
let scrollFixtures: [CommandMappingFixture] = [
    .init("Ctrl-d", .scroll(.halfPage, forward: true), Array(repeating: down, count: 15)),
    .init("Ctrl-u", .scroll(.halfPage, forward: false), Array(repeating: up, count: 15)),
    .init("Ctrl-f", .scroll(.fullPage, forward: true), Array(repeating: down, count: 30)),
    .init("Ctrl-b", .scroll(.fullPage, forward: false), Array(repeating: up, count: 30)),
]

/// 붙여넣기 8조합 — wise 2종 × before 2종 × count 변형.
///
/// 위치 접두는 **1회만**이고 `Cmd-V`만 반복한다. linewise `p`의 꼬리 `Cmd-←`는 멱등
/// 보정자다 — 내부 줄에서는 no-op, 마지막 줄에서는 `→` 포화를 보정해 "이어붙이기+개행"
/// 대신 "한 줄 위에 붙여넣기"로 퇴행시킨다
/// (`20260730_paste-wise-trailing-newline-heuristic.md`).
let pasteFixtures: [CommandMappingFixture] = [
    .init("p (charwise)", .paste(before: false, count: 1), wise: .charwise, [right, pasteKey]),
    .init("P (charwise)", .paste(before: true, count: 1), wise: .charwise, [pasteKey]),
    .init(
        "p (linewise)", .paste(before: false, count: 1), wise: .linewise,
        [cmdRight, right, cmdLeft, pasteKey]),
    .init("P (linewise)", .paste(before: true, count: 1), wise: .linewise, [cmdLeft, pasteKey]),

    .init(
        "3p (charwise)", .paste(before: false, count: 3), wise: .charwise,
        [right, pasteKey, pasteKey, pasteKey]),
    .init(
        "3P (charwise)", .paste(before: true, count: 3), wise: .charwise,
        [pasteKey, pasteKey, pasteKey]),
    .init(
        "3p (linewise)", .paste(before: false, count: 3), wise: .linewise,
        [cmdRight, right, cmdLeft, pasteKey, pasteKey, pasteKey]),
    .init(
        "3P (linewise)", .paste(before: true, count: 3), wise: .linewise,
        [cmdLeft, pasteKey, pasteKey, pasteKey]),
]

/// 이 매퍼의 어휘 밖 — `default:` 흡수가 살아 있는지의 확인이다. 다른 세 매퍼가 담당하는
/// 액션이 여기로 새면 같은 액션이 두 시퀀스를 내게 된다.
let outOfVocabularyFixtures: [CommandMappingFixture] = [
    .init("h", .move(.charLeft), nil),
    .init("v", .beginSelection(linewise: false), nil),
    .init("dd", .edit(.delete, .line(count: 1)), nil),
    .init("Esc (Visual)", .clearSelection, nil),
    // 엔진은 내지 않지만 매퍼는 total function이다.
    .init("p (count 0)", .paste(before: false, count: 0), wise: .charwise, nil),
]

let commandMappingFixtures: [CommandMappingFixture] =
    openLineFixtures + undoRedoFixtures + scrollFixtures + pasteFixtures + outOfVocabularyFixtures

/// 이 매퍼가 덮어야 하는 어휘 전수. 골든이 하나라도 빠뜨리면 그 액션은 배선 후에도
/// 조용히 스킵된다.
let commandVocabulary: [VimAction] = [
    .openLine(above: false), .openLine(above: true),
    .undo, .redo,
    .scroll(.halfPage, forward: true), .scroll(.halfPage, forward: false),
    .scroll(.fullPage, forward: true), .scroll(.fullPage, forward: false),
]

// MARK: - wise 휴리스틱 픽스처

struct PasteWiseFixture: Sendable, CustomTestStringConvertible {
    var label: String
    var text: String?
    var expected: PasteWise?

    init(_ label: String, _ text: String?, _ expected: PasteWise?) {
        self.label = label
        self.text = text
        self.expected = expected
    }

    var testDescription: String { label }
}

/// 끝 개행 휴리스틱. 우리 편집과의 정합이 이 표의 존재 이유다 — `dd`·`yy`는 `Shift-↓`로
/// 개행까지 잡아 linewise로 판정되고, `cc`는 `Shift-Cmd-→`라 개행이 없어 charwise가 된다
/// (수용 편차, `20260730_paste-wise-trailing-newline-heuristic.md`).
let pasteWiseFixtures: [PasteWiseFixture] = [
    .init("텍스트 없음(비텍스트 클립보드)", nil, nil),
    .init("빈 문자열", "", nil),
    .init("한 단어 (dw 결과)", "word", .charwise),
    .init("개행 1개 (dd 결과)", "line\n", .linewise),
    .init("개행만", "\n", .linewise),
    .init("CRLF", "line\r\n", .linewise),
    .init("CR만", "line\r", .linewise),
    .init("여러 줄, 끝 개행 없음 (cG 결과)", "a\nb", .charwise),
    .init("여러 줄, 끝 개행 있음 (2yy 결과)", "a\nb\n", .linewise),
    .init("끝 공백", "word ", .charwise),
]

// MARK: - 테스트

struct CommandKeyMapperTests {
    @Test("매핑표 골든 — 명령 어휘가 계약대로 키스트로크가 된다", arguments: commandMappingFixtures)
    func mapsCommandsAsContracted(_ fixture: CommandMappingFixture) {
        #expect(fixture.actual == fixture.expected, "\(fixture.vim)")
    }

    /// 네 매퍼 공통 불변식 — 빈 배열은 "조용히 아무것도 안 함"이라 미지원(`nil` → 스킵+로그)과
    /// 구분되지 않는다. 무로그 삼킴 금지가 릴리스 게이트 규칙이다.
    @Test("지원 액션은 빈 시퀀스로 매핑되지 않는다", arguments: commandMappingFixtures)
    func supportedActionsNeverMapToEmpty(_ fixture: CommandMappingFixture) {
        guard let expected = fixture.expected else { return }
        #expect(!expected.isEmpty, "\(fixture.vim)")
    }

    /// 골든이 이 매퍼의 어휘를 빠짐없이 덮는지. paste는 count·wise 축이 따로 있어
    /// 별도 픽스처가 덮는다.
    @Test("골든은 명령 어휘 8종을 전부 덮는다")
    func goldenCoversVocabulary() {
        let covered = (openLineFixtures + undoRedoFixtures + scrollFixtures).map(\.action)
        #expect(Set(covered) == Set(commandVocabulary))
        #expect(covered.count == commandVocabulary.count, "중복 행 없음")
    }

    /// **화살표 스트로크에 Shift가 실리면 안 된다** — 접두는 위치를 잡는 것이지 선택하는 것이
    /// 아니고, Shift가 새면 뒤이은 `Cmd-V`가 그 선택을 **덮어쓴다**. 화살표에 한정해 세는 이유는
    /// `Shift-Cmd-Z`가 정당하게 Shift를 싣기 때문이다.
    @Test("접두 화살표는 Shift를 싣지 않는다", arguments: commandMappingFixtures)
    func positioningArrowsCarryNoShift(_ fixture: CommandMappingFixture) {
        guard let expected = fixture.expected else { return }
        let arrows: Set<CGKeyCode> = [
            CGKeyCode(kVK_LeftArrow), CGKeyCode(kVK_RightArrow),
            CGKeyCode(kVK_UpArrow), CGKeyCode(kVK_DownArrow),
        ]
        #expect(
            expected.allSatisfy { !arrows.contains($0.keyCode) || !$0.flags.contains(.maskShift) },
            "\(fixture.vim)")
    }

    /// 명령 키는 시퀀스당 1타다 — 접두가 명령 키를 섞으면 위치잡기가 부작용을 낸다.
    /// 예외가 둘이다: paste는 `Cmd-V`가 count만큼이며 **연속 런**이어야 하고(사이에 이동이
    /// 끼면 두 번째 붙여넣기가 엉뚱한 곳으로 간다), 스크롤은 화살표뿐이라 명령 키가 **0타**다.
    @Test("명령 키는 1타, paste만 연속 런 × count, 스크롤은 0타", arguments: commandMappingFixtures)
    func commandKeyAppearsOnce(_ fixture: CommandMappingFixture) {
        guard let expected = fixture.expected else { return }
        if case .scroll = fixture.action {
            #expect(expected.allSatisfy { !commandKeys.contains($0.keyCode) }, "\(fixture.vim)")
            return
        }
        guard case .paste(_, let count) = fixture.action else {
            #expect(expected.filter { commandKeys.contains($0.keyCode) }.count == 1, "\(fixture.vim)")
            return
        }
        #expect(expected.filter { $0 == pasteKey }.count == count, "\(fixture.vim)")
        #expect(expected.suffix(count).allSatisfy { $0 == pasteKey }, "\(fixture.vim) — 연속 런")
    }

    /// `O`는 명령 키가 아니라 `↑`로 끝난다 — 개행 뒤에 새로 생긴 빈 줄로 올라가야 하기
    /// 때문이다. "시퀀스는 명령 키로 끝난다"를 불변식으로 두면 안 되는 이유가 이것이다.
    @Test("O는 ↑로 끝난다")
    func openAboveEndsWithMoveUp() {
        let strokes = CommandKeyMapper.keyStrokes(for: .openLine(above: true), family: .textArea)
        #expect(strokes?.last == up)
        #expect(strokes?.contains(ret) == true)
    }

    /// 스크롤은 **한 종류의 화살표만** 반복한다 — 다른 키가 섞이면 캐럿이 옆으로 새거나
    /// 편집이 나간다. full은 half의 정확히 2배이며, 방향은 화살표 종류로만 갈린다.
    @Test("스크롤은 한 종류 화살표의 반복이고 full은 half의 2배다")
    func scrollRepeatsSingleArrow() {
        for (forward, arrow) in [(true, down), (false, up)] {
            let half = CommandKeyMapper.keyStrokes(
                for: .scroll(.halfPage, forward: forward), family: .textArea)
            let full = CommandKeyMapper.keyStrokes(
                for: .scroll(.fullPage, forward: forward), family: .textArea)
            #expect(half?.allSatisfy { $0 == arrow } == true, "forward: \(forward)")
            #expect(full?.allSatisfy { $0 == arrow } == true, "forward: \(forward)")
            #expect(full?.count == (half?.count ?? 0) * 2, "forward: \(forward)")
        }
    }

    @Test("wise 휴리스틱 — 끝 개행이 linewise를 가른다", arguments: pasteWiseFixtures)
    func classifiesPasteWise(_ fixture: PasteWiseFixture) {
        #expect(PasteWise(clipboardText: fixture.text) == fixture.expected, "\(fixture.label)")
    }
}

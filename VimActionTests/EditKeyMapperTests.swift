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

// MARK: - 정확화 픽스처 (수용 엣지 1~5 + `^`)

/// 읽기가 무상태 시퀀스에 대해 증명한 것.
enum EditRefinementOutcome: Sendable, Equatable {
    /// 증명하지 못했다 — 무상태 시퀀스가 **한 타도 다르지 않게** 그대로 나가야 한다.
    case unchanged
    /// Vim에서 무효 — 매퍼가 `nil`을 내고 어댑터가 `.skipped`로 분류한다(미지원이 아니다).
    case invalid
    /// 재조립된 **선택** 시퀀스. 오퍼레이터 접미는 표가 자동으로 붙인다 — 그래야 세 오퍼레이터가
    /// 한 행으로 검증되고, 접미를 잘못 적은 픽스처가 계약을 흉내내지 못한다.
    case selection([KeyStroke])
}

/// 정확화 판정표 한 행.
struct EditRefinementFixture: Sendable, CustomTestStringConvertible {
    var vim: String
    var op: VimAction.Operator
    var range: VimAction.TextRange
    var document: String
    var caret: Int
    var selectionLength: Int
    var outcome: EditRefinementOutcome

    init(
        _ vim: String, _ op: VimAction.Operator, _ range: VimAction.TextRange,
        document: String = refinementDocument, caret: Int, selectionLength: Int = 0,
        _ outcome: EditRefinementOutcome
    ) {
        self.vim = vim
        self.op = op
        self.range = range
        self.document = document
        self.caret = caret
        self.selectionLength = selectionLength
        self.outcome = outcome
    }

    var testDescription: String { "\(vim) @\(caret) in \(document.debugDescription)" }
}

/// 판정이 딛는 기본 문서 — `"ab\ncd"`. 오프셋: a0 b1 `\n`2 c3 d4, 문서 끝은 5.
/// 줄 경계(2·3)와 문서 경계(0·5)가 서로 다른 자리라 둘을 혼동한 구현이 걸린다.
let refinementDocument = "ab\ncd"

/// 오퍼레이터 접미 — 표의 `.selection`에 붙는다.
private func operatorSuffix(_ op: VimAction.Operator) -> [KeyStroke] {
    op == .yank ? [copyKey, collapseLeft] : [cutKey]
}

let editRefinementFixtures: [EditRefinementFixture] = [
    // MARK: 엣지 1 — 전진 charwise의 줄 경계
    // 줄 끝에서 `Shift-→`는 0폭이 아니라 **개행을 집는다**. Vim의 커서는 마지막 글자 위이므로
    // 그 글자를 지운다 — 이 한 자리에서만 선택 방향이 뒤집힌다.
    .init("x", .delete, .motion(.charRight, count: 1), caret: 2, .selection([selLeft])),
    // 문서 끝은 **줄 끝의 특수 경우**다 — 마지막 줄에서만 `x`가 무동작이면 같은 키가 줄에
    // 따라 다르게 군다. 세션 1의 0폭 억제(문서 끝 `x` → 스킵)를 여기서 덮어쓴다.
    .init("x", .delete, .motion(.charRight, count: 1), caret: 5, .selection([selLeft])),
    .init("3x", .delete, .motion(.charRight, count: 3), caret: 5, .selection([selLeft])),
    // 줄이 비어 있으면 지울 글자가 없다 — 그때만 무효다.
    .init(
        "x", .delete, .motion(.charRight, count: 1), document: "ab\n\ncd", caret: 3, .invalid),
    .init("x", .delete, .motion(.charRight, count: 1), document: "", caret: 0, .invalid),
    // 줄 끝이 아니면 clamp만 한다 — `min`이 카운트로 막혀 있어 현행보다 나빠질 수 없다.
    .init("x", .delete, .motion(.charRight, count: 1), caret: 0, .unchanged),
    .init("x", .delete, .motion(.charRight, count: 1), caret: 1, .unchanged),
    .init("3x", .delete, .motion(.charRight, count: 3), caret: 0, .selection([selRight, selRight])),
    .init("3x", .delete, .motion(.charRight, count: 3), caret: 3, .selection([selRight, selRight])),
    .init("2x", .delete, .motion(.charRight, count: 2), caret: 0, .unchanged),

    // MARK: 엣지 1의 대칭 — 후진 charwise는 방향을 뒤집지 않는다
    // Vim의 `h`는 앞 줄로 넘어가지 않으므로 줄 시작에서는 그냥 무효다 (문서 시작도 그 특수 경우).
    .init("dh", .delete, .motion(.charLeft, count: 1), caret: 0, .invalid),
    .init("dh", .delete, .motion(.charLeft, count: 1), caret: 3, .invalid),
    .init("dh", .delete, .motion(.charLeft, count: 1), caret: 1, .unchanged),
    .init("dh", .delete, .motion(.charLeft, count: 1), caret: 5, .unchanged),
    .init("d3h", .delete, .motion(.charLeft, count: 3), caret: 1, .selection([selLeft])),
    .init("d3h", .delete, .motion(.charLeft, count: 3), caret: 4, .selection([selLeft])),

    // MARK: 엣지 3 — 마지막 단어 `dw`의 선택 반전
    // 남은 것이 현재 단어뿐이면 Vim의 `w`도 그 단어 끝에서 멈춘다 = `e`의 1타. 카운트 무관.
    .init("dw", .delete, .motion(.wordForward, count: 1), caret: 5, .selection([selOptRight])),
    .init("yw", .yank, .motion(.wordForward, count: 1), caret: 5, .selection([selOptRight])),
    .init("d3w", .delete, .motion(.wordForward, count: 3), caret: 5, .selection([selOptRight])),
    .init(
        "dw", .delete, .motion(.wordForward, count: 1), document: "foo bar", caret: 5,
        .selection([selOptRight])),
    .init(
        "dw", .delete, .motion(.wordForward, count: 1), document: "foo bar", caret: 1, .unchanged),
    .init("dw", .delete, .motion(.wordForward, count: 1), caret: 0, .unchanged),
    // `cw`는 리타깃을 거쳐 `ce` 행으로 간다 — 문서 끝에서 0폭이라 무효다(재조립이 아니다).
    .init("cw", .change, .motion(.wordForward, count: 1), caret: 5, .invalid),

    // MARK: 세션 1이 세운 0폭 억제 — 그대로 유효하다
    .init("de", .delete, .motion(.wordEndForward, count: 1), caret: 5, .invalid),
    .init("de", .delete, .motion(.wordEndForward, count: 1), caret: 0, .unchanged),
    .init("db", .delete, .motion(.wordBackward, count: 1), caret: 0, .invalid),
    .init("db", .delete, .motion(.wordBackward, count: 1), caret: 5, .unchanged),
    .init("d$", .delete, .motion(.lineEnd, count: 1), caret: 2, .invalid),
    .init("d$", .delete, .motion(.lineEnd, count: 1), caret: 5, .invalid),
    .init("d$", .delete, .motion(.lineEnd, count: 1), caret: 1, .unchanged),
    .init("d0", .delete, .motion(.lineStart, count: 1), caret: 3, .invalid),
    .init("d0", .delete, .motion(.lineStart, count: 1), caret: 0, .invalid),
    .init("d0", .delete, .motion(.lineStart, count: 1), caret: 1, .unchanged),
    // 오퍼레이터는 판정을 가르지 않는다 — 0폭이면 `Cmd-X`든 `Cmd-C`든 낼 것이 없다.
    .init("y$", .yank, .motion(.lineEnd, count: 1), caret: 2, .invalid),
    .init("c$", .change, .motion(.lineEnd, count: 1), caret: 2, .invalid),

    // MARK: `^` — 세션 1의 보류 해제
    // 첫 비공백 **위**일 때만 무효다. 전부 공백인 줄에서 `^`는 no-op이 아니라 다음 줄까지
    // 넘어가는 별건의 오동작이라, 거기서 억제하면 진짜 편집을 삼킨다.
    .init("d^", .delete, .motion(.lineFirstNonBlank, count: 1), caret: 0, .invalid),
    .init("d^", .delete, .motion(.lineFirstNonBlank, count: 1), caret: 3, .invalid),
    .init("d^", .delete, .motion(.lineFirstNonBlank, count: 1), caret: 1, .unchanged),
    .init(
        "d^", .delete, .motion(.lineFirstNonBlank, count: 1), document: "  ab", caret: 2, .invalid),
    .init(
        "d^", .delete, .motion(.lineFirstNonBlank, count: 1), document: "  ab", caret: 0,
        .unchanged),
    .init(
        "d^", .delete, .motion(.lineFirstNonBlank, count: 1), document: "  \nx", caret: 1,
        .unchanged),

    // MARK: 엣지 2 — 첫 줄 `dk`
    // 현행 시퀀스는 `↑`가 포화한 채 아래로 확장해 **아래 줄을 지운다**. Vim은 명령 전체가 무효다.
    .init("dk", .delete, .linewiseMotion(.lineUp, count: 1), caret: 1, .invalid),
    .init("dk", .delete, .linewiseMotion(.lineUp, count: 1), caret: 3, .unchanged),
    .init("d2k", .delete, .linewiseMotion(.lineUp, count: 2), caret: 3, .invalid),
    .init(
        "d2k", .delete, .linewiseMotion(.lineUp, count: 2), document: "a\nb\nc", caret: 4,
        .unchanged),

    // MARK: 엣지 4 — 마지막 줄 `dgg`
    // 선행 `↓`가 줄 끝으로 포화해 마지막 줄이 범위에서 빠진다. `cgg`가 이미 쓰는
    // "줄 끝에서 위로"가 그 자리의 정답이다.
    .init(
        "dgg", .delete, .linewiseMotion(.documentStart, count: 1), caret: 3,
        .selection([cmdRight, selCmdUp])),
    .init(
        "ygg", .yank, .linewiseMotion(.documentStart, count: 1), caret: 5,
        .selection([cmdRight, selCmdUp])),
    .init("dgg", .delete, .linewiseMotion(.documentStart, count: 1), caret: 1, .unchanged),
    // `cgg`는 이미 그 시퀀스라 정확화가 필요 없다 — 재조립이 중복으로 얹히면 안 된다.
    .init("cgg", .change, .linewiseMotion(.documentStart, count: 1), caret: 3, .unchanged),

    // MARK: 묻지 않는 범위 — 읽기가 있어도 시퀀스가 갈리지 않는다
    .init("dd", .delete, .line(count: 1), caret: 5, .unchanged),
    .init("dj", .delete, .linewiseMotion(.lineDown, count: 1), caret: 5, .unchanged),
    .init("dG", .delete, .linewiseMotion(.documentEnd, count: 1), caret: 5, .unchanged),
    .init("diw", .delete, .textObject(.word(.inner)), caret: 5, .unchanged),
    .init("v_d", .delete, .selection, caret: 5, .unchanged),

    // 살아 있는 선택이 있으면 우리가 만들 선택이 어디서 출발할지 알 수 없다 — 증명 불가.
    .init(
        "x", .delete, .motion(.charRight, count: 1), caret: 4, selectionLength: 1, .unchanged),
    .init(
        "dgg", .delete, .linewiseMotion(.documentStart, count: 1), caret: 3, selectionLength: 2,
        .unchanged),
]

// MARK: - 테스트

struct EditKeyMapperTests {
    @Test("매핑표 골든 — 편집이 계약대로 키스트로크가 된다", arguments: editMappingFixtures)
    func mapsEditAsContracted(_ fixture: EditMappingFixture) {
        let actual = EditKeyMapper.keyStrokes(for: fixture.op, range: fixture.range, family: .textArea)
        #expect(actual == fixture.expected, "\(fixture.vim)")
    }

    /// **TextField 전용 시퀀스를 만들지 않기로 한 결정을 표 전체에 대해 못박는다**
    /// (`20260801_textfield-edit-sequences-scrapped.md`). 단일행 필드에서는 TextArea 시퀀스가
    /// 자연 수렴하고(주소창에서 `Shift-↓`는 끝까지 선택된다), 전용 분기는 role 오보고 시
    /// 여러 줄 검색창의 `dd` 1줄 삭제를 전체 삭제로 개악한다 — 실패 방향이 비대칭이다.
    @Test("TextField는 TextArea와 같은 시퀀스를 낸다", arguments: editMappingFixtures)
    func textFieldConvergesOnTextArea(_ fixture: EditMappingFixture) {
        let asField = EditKeyMapper.keyStrokes(
            for: fixture.op, range: fixture.range, family: .textField)
        #expect(asField == fixture.expected, "\(fixture.vim)")
    }

    /// 비텍스트는 어댑터 게이트가 먼저 걸러내므로 실제로는 도달하지 않지만, 매퍼의 봉쇄가
    /// 살아 있어야 게이트를 매퍼로 옮기려는 변경이 Finder 선택에 `Cmd-X`를 내지 않는다.
    /// **`.selection`이 계열 분기보다 앞에 있던 구조가 정확히 그 함정이었다.**
    @Test("비텍스트에서는 전부 미지원이다", arguments: editMappingFixtures)
    func nonTextIsAlwaysUnsupported(_ fixture: EditMappingFixture) {
        let asNonText = EditKeyMapper.keyStrokes(
            for: fixture.op, range: fixture.range, family: .nonText)
        #expect(asNonText == nil, "\(fixture.vim)")
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

/// 캐럿 주변 읽기를 **소비하는** 쪽의 계약 — 읽기가 증명한 만큼만 시퀀스가 갈린다.
struct EditRefinementTests {
    /// 정확화 골든. `.unchanged`를 **무상태 시퀀스와 직접 비교**하는 것이 요점이다 —
    /// 기대 스트로크를 손으로 다시 적으면 무상태 쪽이 바뀔 때 두 표가 조용히 갈라진다.
    @Test("정확화 골든 — 읽기가 증명한 자리에서만 시퀀스가 갈린다", arguments: editRefinementFixtures)
    func refinesAsContracted(_ fixture: EditRefinementFixture) {
        let text = focusedText(
            fixture.document, caret: fixture.caret, length: fixture.selectionLength)
        let stateless = EditKeyMapper.keyStrokes(
            for: fixture.op, range: fixture.range, family: .textArea)
        let actual = EditKeyMapper.keyStrokes(
            for: fixture.op, range: fixture.range, family: .textArea, text: text)

        switch fixture.outcome {
        case .unchanged:
            #expect(actual == stateless, "\(fixture.testDescription)")
        case .invalid:
            #expect(actual == nil, "\(fixture.testDescription)")
            #expect(stateless != nil, "무상태로는 지원하는 어휘여야 한다 — 아니면 미지원과 뒤섞인다")
        case .selection(let selection):
            #expect(actual == selection + operatorSuffix(fixture.op), "\(fixture.testDescription)")
            #expect(actual != stateless, "재조립인데 무상태와 같으면 표가 낡은 것이다")
        }
    }

    /// 정확화 결과도 실행 가능한 형태여야 한다 — 빈 배열은 "조용히 아무것도 안 함"이라
    /// 무효(`nil` → `.skipped`)와 구분되지 않는다.
    @Test("정확화는 빈 시퀀스를 내지 않는다", arguments: editRefinementFixtures)
    func refinementNeverMapsToEmpty(_ fixture: EditRefinementFixture) {
        let text = focusedText(
            fixture.document, caret: fixture.caret, length: fixture.selectionLength)
        guard
            let actual = EditKeyMapper.keyStrokes(
                for: fixture.op, range: fixture.range, family: .textArea, text: text)
        else { return }

        #expect(!actual.isEmpty, "\(fixture.testDescription)")
    }

    /// **범위 표가 두 곳으로 갈라지는 것을 막는다.** 어댑터는 `consultsFocusedText`만 보고
    /// 읽을지 정하므로, 묻지 않는 범위에서 정확화가 발동하면 그것은 코드에 있는 채 영원히
    /// 죽어 있다 — 반대로 정확화가 조용히 사라지는 것도 여기서 걸린다.
    @Test("묻지 않는 범위는 어느 캐럿에서도 시퀀스가 갈리지 않는다", arguments: editMappingFixtures)
    func refinementOnlyHappensWhereTheReadIsConsulted(_ fixture: EditMappingFixture) {
        guard !EditKeyMapper.consultsFocusedText(fixture.range) else { return }

        for caret in 0...refinementDocument.utf16.count {
            let text = focusedText(refinementDocument, caret: caret)
            #expect(
                EditKeyMapper.keyStrokes(
                    for: fixture.op, range: fixture.range, family: .textArea, text: text)
                    == fixture.expected, "\(fixture.vim) @\(caret)")
        }
    }

    /// 묻는 범위는 `.motion` 전체 + `dk`·`dgg` 둘뿐이다. **넓히면 그만큼 AX 왕복이 늘어난다**
    /// (Notion 실측 ~7ms/회) — 세션 3이 `.textObject`를 더하면 여기가 먼저 바뀐다.
    @Test("읽기를 묻는 범위는 표에 적힌 것뿐이다", arguments: editMappingFixtures)
    func onlyTabulatedRangesConsultTheRead(_ fixture: EditMappingFixture) {
        let expected: Bool
        switch fixture.range {
        case .motion, .linewiseMotion(.lineUp, _), .linewiseMotion(.documentStart, _):
            expected = true
        default:
            expected = false
        }

        #expect(EditKeyMapper.consultsFocusedText(fixture.range) == expected, "\(fixture.vim)")
    }
}

//
//  FocusedTextOffsetsTests.swift
//  VimActionTests
//

import Foundation
import Testing
import VimEngine

@testable import VimAction

/// AX 캐럿 모션 1건의 계약. 표가 곧 어휘 정의라, 새 모션이 조용히 미구현으로 흘러들지 않도록
/// 아래에 전수 스윕을 함께 둔다 (`LogicalCommandKeyCodeExclusivityTests` 선례).
struct OffsetFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let text: FocusedText
    let motion: Motion
    let target: FocusedTextOffsets.Target

    var testDescription: String { name }
}

private func fixture(
    _ name: String, _ text: FocusedText, _ motion: Motion, _ target: FocusedTextOffsets.Target
) -> OffsetFixture {
    OffsetFixture(name: name, text: text, motion: motion, target: target)
}

/// 창이 문서의 **일부**인 읽기 — 창 절단(경계 미증명) 케이스용이다.
private func windowed(
    _ window: String, at location: Int, characterCount: Int, caret: Int
) -> FocusedText {
    FocusedText(
        selection: NSRange(location: caret, length: 0), characterCount: characterCount,
        window: window, windowRange: NSRange(location: location, length: window.utf16.count))
}

/// `"foo.bar  baz"` — 오프셋: f0 o1 o2 .3 b4 a5 r6 ␣7 ␣8 b9 a10 z11, 문서 끝 12.
/// 구두점 런과 2칸 공백 런이 한 줄에 다 있어 `w`/`b`/`e`의 갈림이 전부 여기서 난다.
private let words = "foo.bar  baz"

/// `"ab\ncd"` — 오프셋: a0 b1 \n2 c3 d4, 문서 끝 5.
private let twoLines = "ab\ncd"

/// `"  ab"` — 들여쓴 줄. `^`가 `0`과 갈리는 최소 형태다.
private let indented = "  ab"

let offsetFixtures: [OffsetFixture] = [
    // MARK: h / l — 줄을 넘지 않는다 (현행 keyboard와 갈리는 지점)
    fixture("h — 줄 한가운데", focusedText(words, caret: 4), .charLeft, .caret(3)),
    fixture("h — 줄 시작은 Vim no-op", focusedText(twoLines, caret: 3), .charLeft, .invalid),
    fixture("h — 문서 시작", focusedText(words, caret: 0), .charLeft, .invalid),
    fixture("l — 줄 한가운데", focusedText(words, caret: 4), .charRight, .caret(5)),
    fixture("l — 줄 끝은 Vim no-op", focusedText(twoLines, caret: 2), .charRight, .invalid),
    fixture("l — 문서 끝", focusedText(twoLines, caret: 5), .charRight, .invalid),
    // 캐럿 모델에서 `a`의 목표는 `l`과 같다 — "마지막 글자 위 vs 뒤"는 블록 커서 모델의 구분이다.
    fixture("a — l과 같은 자리", focusedText(words, caret: 4), .charRightForAppend, .caret(5)),

    // MARK: w — Vim 단어 정의(구두점이 자기 런)라 현행 3타 근사와 갈린다
    fixture("w — keyword 런 끝의 구두점 앞", focusedText(words, caret: 0), .wordForward, .caret(3)),
    fixture("w — 구두점 런을 지나 다음 단어", focusedText(words, caret: 3), .wordForward, .caret(4)),
    fixture("w — 공백 런을 건너뛴다", focusedText(words, caret: 5), .wordForward, .caret(9)),
    fixture("w — 공백 위에서는 다음 단어 시작", focusedText(words, caret: 7), .wordForward, .caret(9)),
    fixture("w — 줄을 넘는다", focusedText(twoLines, caret: 1), .wordForward, .caret(3)),
    fixture("w — 마지막 단어에서는 문서 끝", focusedText(words, caret: 9), .wordForward, .caret(12)),
    fixture("w — 문서 끝은 무효", focusedText(words, caret: 12), .wordForward, .invalid),
    // 빈 줄은 Vim에서 그 자체로 단어다.
    fixture("w — 빈 줄이 정지 지점", focusedText("a\n\nb", caret: 0), .wordForward, .caret(2)),

    // MARK: b
    fixture("b — 런 시작으로", focusedText(words, caret: 6), .wordBackward, .caret(4)),
    fixture("b — 이미 런 시작이면 앞 런으로", focusedText(words, caret: 4), .wordBackward, .caret(3)),
    fixture("b — 공백 런을 건너뛴다", focusedText(words, caret: 9), .wordBackward, .caret(4)),
    fixture("b — 줄을 넘는다", focusedText(twoLines, caret: 3), .wordBackward, .caret(0)),
    fixture("b — 문서 시작은 무효", focusedText(words, caret: 0), .wordBackward, .invalid),
    fixture("b — 빈 줄이 정지 지점", focusedText("a\n\nb", caret: 3), .wordBackward, .caret(2)),

    // MARK: e — 캐럿 모델이라 "마지막 글자 뒤"(= Opt-→ 자리)다
    fixture("e — 런 끝 뒤", focusedText(words, caret: 0), .wordEndForward, .caret(3)),
    // 캐럿이 런의 마지막 글자 위면 Vim처럼 다음 런의 끝으로 뛴다.
    // caret 2 = `foo`의 마지막 글자 `o` 위. 다음 런은 구두점 `.`이라 그 끝(뒤)인 4다.
    fixture("e — 런 마지막 글자 위에서는 다음 런 끝", focusedText(words, caret: 2), .wordEndForward, .caret(4)),
    fixture("e — 공백 위에서는 다음 런 끝", focusedText(words, caret: 7), .wordEndForward, .caret(12)),
    fixture("e — 문서 끝은 무효", focusedText(words, caret: 12), .wordEndForward, .invalid),

    // MARK: 0 / ^ / $ — 논리 줄 기준
    fixture("0 — 줄 시작으로", focusedText(twoLines, caret: 4), .lineStart, .caret(3)),
    fixture("0 — 이미 줄 시작", focusedText(twoLines, caret: 3), .lineStart, .invalid),
    fixture("^ — 첫 비공백으로", focusedText(indented, caret: 0), .lineFirstNonBlank, .caret(2)),
    fixture("^ — 이미 첫 비공백", focusedText(indented, caret: 2), .lineFirstNonBlank, .invalid),
    // 전부 공백인 줄에서는 Vim처럼 줄 끝이다.
    fixture("^ — 전부 공백인 줄은 줄 끝", focusedText("  \nx", caret: 0), .lineFirstNonBlank, .caret(2)),
    fixture("$ — 개행 앞", focusedText(twoLines, caret: 0), .lineEnd, .caret(2)),
    fixture("$ — 마지막 줄은 문서 끝", focusedText(twoLines, caret: 3), .lineEnd, .caret(5)),
    fixture("$ — 이미 줄 끝", focusedText(twoLines, caret: 2), .lineEnd, .invalid),
    fixture("A — $와 같은 자리", focusedText(twoLines, caret: 0), .lineEndForAppend, .caret(2)),

    // MARK: gg / G — 상수 끝점이라 창과 무관하게 증명된다
    fixture("gg — 문서 시작", focusedText(words, caret: 5), .documentStart, .caret(0)),
    fixture("gg — 이미 문서 시작", focusedText(words, caret: 0), .documentStart, .invalid),
    fixture("G — 문서 끝", focusedText(words, caret: 5), .documentEnd, .caret(12)),
    fixture("G — 이미 문서 끝", focusedText(words, caret: 12), .documentEnd, .invalid),
    // 창이 문서 일부여도 끝점 둘은 상수라 답이 선다 — 파라미터화 속성이 필요 없는 이유다.
    fixture(
        "G — 창이 문서 일부여도 증명된다",
        windowed("cdef", at: 100, characterCount: 999, caret: 102), .documentEnd, .caret(999)),

    // MARK: j / k — 위임 확정 (희망 열 소실)
    fixture("j는 오프셋 계층에 오지 않는다", focusedText(twoLines, caret: 0), .lineDown, .unproven),
    fixture("k는 오프셋 계층에 오지 않는다", focusedText(twoLines, caret: 3), .lineUp, .unproven),

    // MARK: 창 절단 — 답이 창 밖이면 증명 실패(위임)
    fixture(
        "0 — 줄 시작이 창 밖", windowed("cdef", at: 100, characterCount: 999, caret: 102),
        .lineStart, .unproven),
    fixture(
        "$ — 줄 끝이 창 밖", windowed("cdef", at: 100, characterCount: 999, caret: 102),
        .lineEnd, .unproven),
    fixture(
        "w — 다음 단어가 창 밖", windowed("cdef", at: 100, characterCount: 999, caret: 101),
        .wordForward, .unproven),
    fixture(
        "b — 런이 창 왼쪽 끝에 닿는다", windowed("cdef", at: 100, characterCount: 999, caret: 102),
        .wordBackward, .unproven),
    // 창 안쪽이면 절단된 창에서도 답이 선다.
    fixture(
        "h — 창 안쪽은 절단과 무관", windowed("cd\nef", at: 100, characterCount: 999, caret: 104),
        .charLeft, .caret(103)),

    // MARK: 살아 있는 선택 — 캐럿이 어디인지 애매하므로 증명하지 않는다
    fixture(
        "선택이 살아 있으면 증명하지 않는다", focusedText(words, caret: 0, length: 3), .charRight,
        .unproven),
]

/// 줄 종결자 4형태에서 `0`·`$`·`h`·`l`이 같은 답을 낸다 — `\n` 단독 스캔은 `\r\n` 문서에서
/// 떠돌이 `\r`를 남긴다. `\r\n`이 Swift `Character` 하나라는 것이 이 계약의 구현이다.
let lineTerminators = ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"]

// MARK: - 범위 픽스처

/// AX 편집 범위 1건의 계약. 답은 `EditKeyMapper` 정확화 표와 같아야 하고, 표가 침묵하는
/// 자리(줄 끝 `dw`·linewise 클램프)는 Vim 실측을 따른다.
struct SpanFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let text: FocusedText
    let op: VimAction.Operator
    let range: VimAction.TextRange
    let span: FocusedTextOffsets.Span

    var testDescription: String { name }
}

private func span(
    _ name: String, _ text: FocusedText, _ op: VimAction.Operator, _ range: VimAction.TextRange,
    _ span: FocusedTextOffsets.Span
) -> SpanFixture {
    SpanFixture(name: name, text: text, op: op, range: range, span: span)
}

/// `NSRange` 리터럴을 줄인다 — 표가 오프셋 산수로 읽히게.
private func range(_ location: Int, _ length: Int) -> FocusedTextOffsets.Span {
    .range(NSRange(location: location, length: length))
}

/// `"l1\nl2\nl3"` — **끝 개행 없음**. l0 1(1) \n2 l3 2(4) \n5 l6 3(7), 문서 끝 8.
/// 마지막 줄 반올림·클램프가 전부 여기서 갈린다.
private let threeLines = "l1\nl2\nl3"

/// `"l1\nl2\n"` — 끝 개행 있음. 오프셋 6이 빈 마지막 줄이다.
private let trailingNewline = "l1\nl2\n"

/// `"a\n\nb"` — 빈 줄을 낀 최소 형태. a0 \n1 \n2 b3, 문서 끝 4. 오프셋 2가 빈 줄이다.
private let blankLine = "a\n\nb"

/// `"abcdef\nxy\nghijkl"` — 줄 길이 6/2/6. 짧은 가운데 줄이 희망 열(curswant)의 시험대다:
/// 열 2에서 `j`는 `xy`의 종결자 위에 서고, 한 번 더 `j`하면 열 2가 **복원**된다.
/// 오프셋: a0…f5 ⏎6 x7 y8 ⏎9 g10…l15, 문서 끝 16.
private let ragged = "abcdef\nxy\nghijkl"

let spanFixtures: [SpanFixture] = [
    // MARK: .motion — charRight (`x`·`dl`)
    span("x — 줄 한가운데", focusedText(words, caret: 4), .delete, .motion(.charRight, count: 1), range(4, 1)),
    // 엣지 1 — 줄 끝에서는 Vim 커서가 마지막 글자 위라 그 글자를 지운다(방향 반전).
    span("x — 줄 끝은 직전 글자", focusedText(twoLines, caret: 2), .delete, .motion(.charRight, count: 1), range(1, 1)),
    span("x — 문서 끝도 같다", focusedText(twoLines, caret: 5), .delete, .motion(.charRight, count: 1), range(4, 1)),
    span("x — 빈 줄은 지울 글자가 없다", focusedText(blankLine, caret: 2), .delete, .motion(.charRight, count: 1), .invalid),
    span("d5l — 남은 글자로 클램프", focusedText(words, caret: 10), .delete, .motion(.charRight, count: 5), range(10, 2)),

    // MARK: .motion — charLeft (`dh`·`X`) — 방향을 뒤집지 않는다
    span("dh — 줄 한가운데", focusedText(words, caret: 4), .delete, .motion(.charLeft, count: 1), range(3, 1)),
    span("dh — 줄 시작은 무효", focusedText(twoLines, caret: 3), .delete, .motion(.charLeft, count: 1), .invalid),
    span("d5h — 앞 글자로 클램프", focusedText(words, caret: 2), .delete, .motion(.charLeft, count: 5), range(0, 2)),

    // MARK: .motion — wordForward (`dw`) — 줄을 넘지 않는다 (Vim 실측)
    span("dw — 같은 줄 다음 단어", focusedText(words, caret: 0), .delete, .motion(.wordForward, count: 1), range(0, 3)),
    span("dw — 뒤 공백까지 (같은 줄)", focusedText(words, caret: 4), .delete, .motion(.wordForward, count: 1), range(4, 5)),
    span("dw — 줄 끝 단어는 개행 미포함", focusedText(twoLines, caret: 0), .delete, .motion(.wordForward, count: 1), range(0, 2)),
    span("dw — 마지막 단어는 문서 끝", focusedText(words, caret: 9), .delete, .motion(.wordForward, count: 1), range(9, 3)),
    span("dw — 문서 끝은 무효", focusedText(words, caret: 12), .delete, .motion(.wordForward, count: 1), .invalid),
    // 카운트는 마지막 스텝에만 걸린다 — `d2w`는 줄을 넘는다(실측).
    span("d2w — 줄을 넘는다", focusedText(twoLines, caret: 0), .delete, .motion(.wordForward, count: 2), range(0, 5)),

    // MARK: .motion — 나머지
    span("de — 런 끝까지", focusedText(words, caret: 0), .delete, .motion(.wordEndForward, count: 1), range(0, 3)),
    span("de — 문서 끝은 무효", focusedText(words, caret: 12), .delete, .motion(.wordEndForward, count: 1), .invalid),
    span("db — 런 시작까지", focusedText(words, caret: 6), .delete, .motion(.wordBackward, count: 1), range(4, 2)),
    span("db — 문서 시작은 무효", focusedText(words, caret: 0), .delete, .motion(.wordBackward, count: 1), .invalid),
    span("d$ — 줄 끝까지", focusedText(twoLines, caret: 0), .delete, .motion(.lineEnd, count: 1), range(0, 2)),
    span("d$ — 이미 줄 끝은 무효", focusedText(twoLines, caret: 2), .delete, .motion(.lineEnd, count: 1), .invalid),
    span("d0 — 줄 시작까지", focusedText(twoLines, caret: 4), .delete, .motion(.lineStart, count: 1), range(3, 1)),
    span("d0 — 이미 줄 시작은 무효", focusedText(twoLines, caret: 3), .delete, .motion(.lineStart, count: 1), .invalid),
    span("d^ — 첫 비공백까지", focusedText(indented, caret: 0), .delete, .motion(.lineFirstNonBlank, count: 1), range(0, 2)),
    span("d^ — 이미 첫 비공백은 무효", focusedText(indented, caret: 2), .delete, .motion(.lineFirstNonBlank, count: 1), .invalid),
    span("dgg(모션형) — 문서 시작까지", focusedText(words, caret: 4), .delete, .motion(.documentStart, count: 1), range(0, 4)),
    span("dG(모션형) — 문서 끝까지", focusedText(words, caret: 4), .delete, .motion(.documentEnd, count: 1), range(4, 8)),
    // 줄 모션은 `.linewiseMotion`으로만 오고, append 2종은 편집 범위에 오지 않는다.
    span("dj(모션형)은 오지 않는다", focusedText(twoLines, caret: 0), .delete, .motion(.lineDown, count: 1), .unproven),
    span("dk(모션형)은 오지 않는다", focusedText(twoLines, caret: 3), .delete, .motion(.lineUp, count: 1), .unproven),
    span("a 모션은 편집 범위에 없다", focusedText(words, caret: 4), .delete, .motion(.charRightForAppend, count: 1), .unproven),
    span("A 모션은 편집 범위에 없다", focusedText(words, caret: 4), .delete, .motion(.lineEndForAppend, count: 1), .unproven),

    // MARK: cw 리타깃 — 캐럿 런의 끝까지
    span("cw — 런 중간", focusedText(words, caret: 0), .change, .motion(.wordForward, count: 1), range(0, 3)),
    span("cw — 런 마지막 글자", focusedText(words, caret: 2), .change, .motion(.wordForward, count: 1), range(2, 1)),
    span("cw — 공백 런", focusedText(words, caret: 7), .change, .motion(.wordForward, count: 1), range(7, 2)),
    span("cw — 줄 끝은 직전 글자", focusedText(twoLines, caret: 2), .change, .motion(.wordForward, count: 1), range(1, 1)),
    span("cw — 빈 줄은 무효", focusedText(blankLine, caret: 2), .change, .motion(.wordForward, count: 1), .invalid),
    // 카운트 2 이상은 표 그대로 `e` 반복이다(리타깃 특례는 count 1 전용).
    span("c2w — e 반복", focusedText(words, caret: 0), .change, .motion(.wordForward, count: 2), range(0, 7)),

    // MARK: .line (`dd`) — 마지막 줄은 문서 끝까지 (앞 개행을 흡수하지 않는다)
    span("dd — 내부 줄", focusedText(threeLines, caret: 0), .delete, .line(count: 1), range(0, 3)),
    span("dd — 마지막 줄은 문서 끝까지", focusedText(threeLines, caret: 6), .delete, .line(count: 1), range(6, 2)),
    span("dd — 끝 개행이 있으면 종결자까지", focusedText(trailingNewline, caret: 3), .delete, .line(count: 1), range(3, 3)),
    span("yy — delete와 같은 반올림", focusedText(threeLines, caret: 0), .yank, .line(count: 1), range(0, 3)),
    span("cc — 줄을 남긴다", focusedText(threeLines, caret: 0), .change, .line(count: 1), range(0, 2)),
    span("2dd — 두 줄", focusedText(threeLines, caret: 0), .delete, .line(count: 2), range(0, 6)),
    span("2cc — 마지막 줄 끝까지", focusedText(threeLines, caret: 0), .change, .line(count: 2), range(0, 5)),
    // 클램프 — 남은 줄이 카운트보다 적으면 있는 만큼(실측). 아래가 아예 없으면 무효.
    span("3dd — 남은 줄로 클램프", focusedText(threeLines, caret: 3), .delete, .line(count: 3), range(3, 5)),
    span("2dd — 마지막 줄은 무효", focusedText(threeLines, caret: 6), .delete, .line(count: 2), .invalid),

    // MARK: .linewiseMotion
    span("dj — 현재+아래 줄", focusedText(threeLines, caret: 0), .delete, .linewiseMotion(.lineDown, count: 1), range(0, 6)),
    span("dj — 마지막 줄은 무효", focusedText(threeLines, caret: 6), .delete, .linewiseMotion(.lineDown, count: 1), .invalid),
    span("dk — 위+현재 줄", focusedText(threeLines, caret: 3), .delete, .linewiseMotion(.lineUp, count: 1), range(0, 6)),
    span("dk — 첫 줄은 무효 (엣지 2)", focusedText(threeLines, caret: 0), .delete, .linewiseMotion(.lineUp, count: 1), .invalid),
    span("2dk — 위가 부족하면 클램프", focusedText(threeLines, caret: 3), .delete, .linewiseMotion(.lineUp, count: 2), range(0, 6)),
    span("dgg — 문서 시작부터 현재 줄", focusedText(threeLines, caret: 3), .delete, .linewiseMotion(.documentStart, count: 1), range(0, 6)),
    span("cgg — 줄을 남긴다", focusedText(threeLines, caret: 3), .change, .linewiseMotion(.documentStart, count: 1), range(0, 5)),
    span("dgg — 마지막 줄이면 문서 통째", focusedText(threeLines, caret: 6), .delete, .linewiseMotion(.documentStart, count: 1), range(0, 8)),
    span("dG — 현재 줄 시작부터 문서 끝", focusedText(threeLines, caret: 3), .delete, .linewiseMotion(.documentEnd, count: 1), range(3, 5)),
    span("dG — 끝 개행이 있어도 같다", focusedText(trailingNewline, caret: 3), .delete, .linewiseMotion(.documentEnd, count: 1), range(3, 3)),
    span("cG — delete와 같다 (반올림할 종결자가 없다)", focusedText(threeLines, caret: 3), .change, .linewiseMotion(.documentEnd, count: 1), range(3, 5)),

    // MARK: iw — 캐럿 런 전체 (2자 이상 런까지 정확)
    span("diw — keyword 런", focusedText(words, caret: 1), .delete, .textObject(.word(.inner)), range(0, 3)),
    span("diw — 1자 구두점 런", focusedText(words, caret: 3), .delete, .textObject(.word(.inner)), range(3, 1)),
    span("diw — 2자 공백 런", focusedText(words, caret: 7), .delete, .textObject(.word(.inner)), range(7, 2)),
    span("diw — 줄 끝은 직전 글자의 런", focusedText(twoLines, caret: 2), .delete, .textObject(.word(.inner)), range(0, 2)),
    span("diw — 빈 줄은 무효", focusedText(blankLine, caret: 2), .delete, .textObject(.word(.inner)), .invalid),

    // MARK: 미지원 범위 — 위임(= 현행 keyboard 경로 그대로)
    span("selection은 위임", focusedText(words, caret: 4), .delete, .selection, .unproven),
    span("aw는 위임", focusedText(words, caret: 4), .delete, .textObject(.word(.around)), .unproven),
    span("따옴표 오브젝트는 위임", focusedText(words, caret: 4), .delete, .textObject(.quote(.double, .inner)), .unproven),
    span("괄호쌍 오브젝트는 위임", focusedText(words, caret: 4), .delete, .textObject(.pair(.paren, .inner)), .unproven),

    // MARK: 살아 있는 선택 — 출발점을 증명할 수 없다
    span("선택이 살아 있으면 위임", focusedText(words, caret: 0, length: 3), .delete, .motion(.charRight, count: 1), .unproven),

    // MARK: 창 절단 — 답이 창 밖이면 위임
    span("dd — 줄 시작이 창 밖", windowed("cdef", at: 100, characterCount: 999, caret: 102), .delete, .line(count: 1), .unproven),
    span("dw — 다음 단어가 창 밖", windowed("cdef", at: 100, characterCount: 999, caret: 101), .delete, .motion(.wordForward, count: 1), .unproven),
    span("diw — 런이 창 끝에 닿는다", windowed("cdef", at: 100, characterCount: 999, caret: 102), .delete, .textObject(.word(.inner)), .unproven),
    span("d$ — 줄 끝이 창 밖", windowed("cdef", at: 100, characterCount: 999, caret: 102), .delete, .motion(.lineEnd, count: 1), .unproven),
    // 끝점이 상수인 `dG`는 창이 잘려도 선다 — 파라미터화 속성이 필요 없는 이유다.
    span("dG — 창이 잘려도 증명된다", windowed("cd\nef", at: 100, characterCount: 999, caret: 104), .delete, .linewiseMotion(.documentEnd, count: 1), range(103, 896)),
]

// MARK: - 삽입 위치 픽스처

struct InsertionFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let text: FocusedText
    /// `nil`이면 openLine, 값이 있으면 paste(`(before, wise)`).
    let paste: (before: Bool, wise: PasteWise)?
    let above: Bool
    let insertion: FocusedTextOffsets.Insertion

    var testDescription: String { name }
}

private func openLine(
    _ name: String, _ text: FocusedText, above: Bool, _ insertion: FocusedTextOffsets.Insertion
) -> InsertionFixture {
    InsertionFixture(name: name, text: text, paste: nil, above: above, insertion: insertion)
}

private func paste(
    _ name: String, _ text: FocusedText, before: Bool, wise: PasteWise,
    _ insertion: FocusedTextOffsets.Insertion
) -> InsertionFixture {
    InsertionFixture(
        name: name, text: text, paste: (before, wise), above: false, insertion: insertion)
}

let insertionFixtures: [InsertionFixture] = [
    // MARK: openLine — **접지 않는다**가 계약이다 (이미 줄 끝인 `o`도 유효)
    openLine("o — 줄 끝으로", focusedText(twoLines, caret: 0), above: false, .at(2)),
    openLine("o — 이미 줄 끝이어도 유효", focusedText(twoLines, caret: 2), above: false, .at(2)),
    openLine("O — 줄 시작으로", focusedText(twoLines, caret: 4), above: true, .at(3)),
    openLine("O — 이미 줄 시작이어도 유효", focusedText(twoLines, caret: 3), above: true, .at(3)),
    openLine("o — 창이 잘리면 위임", windowed("cdef", at: 100, characterCount: 999, caret: 102), above: false, .unproven),

    // MARK: charwise paste
    paste("P — 캐럿 그 자리", focusedText(words, caret: 4), before: true, wise: .charwise, .at(4)),
    paste("p — 한 글자 오른쪽", focusedText(words, caret: 4), before: false, wise: .charwise, .at(5)),
    paste("p — 줄 끝이면 캐럿 그대로", focusedText(twoLines, caret: 2), before: false, wise: .charwise, .at(2)),
    paste("p — 문서 끝도 같다", focusedText(twoLines, caret: 5), before: false, wise: .charwise, .at(5)),

    // MARK: linewise paste — 마지막 줄만 `.appendingLine`
    paste("P — 줄 시작", focusedText(threeLines, caret: 4), before: true, wise: .linewise, .at(3)),
    paste("p — 다음 줄 시작", focusedText(threeLines, caret: 0), before: false, wise: .linewise, .at(3)),
    paste("p — 마지막 줄은 Return 합성", focusedText(threeLines, caret: 6), before: false, wise: .linewise, .appendingLine(8)),
    paste("p — 끝 개행이 있으면 빈 마지막 줄로", focusedText(trailingNewline, caret: 3), before: false, wise: .linewise, .at(6)),
    // 캐럿이 **끝 개행 뒤**(빈 마지막 줄)면 구분 개행이 이미 있다 — 여기서 `Return`을 합성하면
    // 빈 줄이 하나 더 생겨 keyboard 경로보다 나빠진다(`"l1\nl2\n"`의 마지막 줄 `dd` 뒤 `p`).
    paste("p — 끝 개행 뒤 빈 줄에서는 합성하지 않는다", focusedText(trailingNewline, caret: 6), before: false, wise: .linewise, .at(6)),
    paste("p — 창이 잘리면 위임", windowed("cdef", at: 100, characterCount: 999, caret: 102), before: false, wise: .linewise, .unproven),

    // MARK: 살아 있는 선택
    paste("선택이 살아 있으면 위임", focusedText(words, caret: 0, length: 3), before: false, wise: .charwise, .unproven),
    openLine("openLine도 선택 위에서는 위임", focusedText(words, caret: 0, length: 3), above: false, .unproven),
]

// MARK: - Visual 범위 픽스처

struct VisualSpanFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let text: FocusedText
    /// `nil`이면 진입(`linewise` 사용), 값이 있으면 확장.
    let anchor: VisualAnchorState?
    let linewise: Bool
    let motion: Motion
    let span: FocusedTextOffsets.Span

    var testDescription: String { name }
}

private func entry(
    _ name: String, _ text: FocusedText, linewise: Bool, _ span: FocusedTextOffsets.Span
) -> VisualSpanFixture {
    VisualSpanFixture(
        name: name, text: text, anchor: nil, linewise: linewise, motion: .charRight, span: span)
}

private func extend(
    _ name: String, _ document: String, selection: NSRange, anchor: Int,
    _ wise: VisualAnchorState.Wise, _ side: VisualAnchorState.Side, _ motion: Motion,
    _ span: FocusedTextOffsets.Span, column: Int? = nil, originalCaret: Int? = nil
) -> VisualSpanFixture {
    VisualSpanFixture(
        name: name, text: liveText(document, selection: selection),
        anchor: sessionState(
            anchor: anchor, wise: wise, side: side, selection: selection, column: column,
            originalCaret: originalCaret),
        linewise: false, motion: motion, span: span)
}

/// 살아 있는 선택 위의 읽기 — 확장·전환의 공통 입력이다.
private func liveText(_ document: String, selection: NSRange) -> FocusedText {
    let count = document.utf16.count
    return FocusedText(
        selection: selection, characterCount: count, window: document,
        windowRange: NSRange(location: 0, length: count))
}

/// 세션 중간 상태 — `pinnedEnd`는 side에서 도출된다(어댑터가 `moved(to:...)`로 세우는 값과
/// 같은 규칙이라, 픽스처가 그 규칙을 두 번 적지 않는다).
private func sessionState(
    anchor: Int, wise: VisualAnchorState.Wise, side: VisualAnchorState.Side, selection: NSRange,
    column: Int? = nil, originalCaret: Int? = nil
) -> VisualAnchorState {
    VisualAnchorState(
        anchor: anchor, wise: wise, side: side,
        pinnedEnd: side == .left ? selection.location : selection.upperBound, processID: 0,
        originalCaret: originalCaret, focusLineDistance: nil, desiredColumn: column)
}

let visualSpanFixtures: [VisualSpanFixture] = [
    // MARK: 진입 — `v`는 캐럿이 놓인 글자 하나
    entry("v — 줄 한가운데", focusedText(words, caret: 4), linewise: false, range(4, 1)),
    entry("v — 줄 끝은 직전 글자", focusedText(twoLines, caret: 2), linewise: false, range(1, 1)),
    entry("v — 문서 끝도 같다", focusedText(twoLines, caret: 5), linewise: false, range(4, 1)),
    // 진입에는 Vim 무효가 없다 — 잡을 글자가 없으면 위임으로 강등한다.
    entry("v — 빈 줄은 위임", focusedText(blankLine, caret: 2), linewise: false, .unproven),
    entry("v — 창이 잘리면 위임", windowed("cdef", at: 100, characterCount: 999, caret: 104), linewise: false, .unproven),

    // MARK: 진입 — `V`는 논리 줄 전체 + 종결자
    entry("V — 내부 줄", focusedText(threeLines, caret: 0), linewise: true, range(0, 3)),
    entry("V — 마지막 줄은 문서 끝까지", focusedText(threeLines, caret: 6), linewise: true, range(6, 2)),
    entry("V — 빈 마지막 줄은 위임", focusedText(trailingNewline, caret: 6), linewise: true, .unproven),
    entry("V — 창이 잘리면 위임", windowed("cdef", at: 100, characterCount: 999, caret: 102), linewise: true, .unproven),

    // MARK: charwise 확장 — 앵커 4(`b` of bar), 진입 선택 [4,5)
    extend("vl — 한 글자 넓힘", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .charRight, range(4, 2)),
    extend("vh — 앵커 왼쪽으로 (재앵커 없이 정확)", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .charLeft, range(3, 2)),
    extend("ve — 단어 끝까지 (뒤 공백 미포함)", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .wordEndForward, range(4, 3)),
    extend("vw — 다음 단어 글자까지", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .wordForward, range(4, 6)),
    extend("vb — 앞 런 시작까지", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .wordBackward, range(3, 2)),
    extend("v$ — 줄 끝까지", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .lineEnd, range(4, 8)),
    extend("v0 — 줄 시작까지", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .lineStart, range(0, 5)),
    extend("vgg — 문서 시작까지", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .documentStart, range(0, 5)),
    extend("vG — 문서 끝까지", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .documentEnd, range(4, 8)),
    // 후진형 — 앵커는 오른쪽 끝이고, 앱 앵커도 그쪽이다.
    extend("vhh — 연속 후진", words, selection: NSRange(location: 3, length: 2), anchor: 4, .charwise, .right, .charLeft, range(2, 3)),
    // 후진 선택에서 `l`은 커서를 앵커 글자로 되돌린다 — 선택이 1자로 줄지 무효가 아니다.
    extend("vhl — 앵커 글자로 되돌아옴", words, selection: NSRange(location: 3, length: 2), anchor: 4, .charwise, .right, .charRight, range(4, 1)),
    // **후진형의 `e`** — 목표가 커서 **다음**이라 방향 판정·후진 하한을 커서 자리로 되돌리지
    // 않으면 커서 글자가 선택에서 빠진다(Vim 실측 `9lvbe` = `"r  b"`).
    extend("ve — 후진형도 커서 글자를 잡는다", words, selection: NSRange(location: 4, length: 6), anchor: 9, .charwise, .right, .wordEndForward, range(6, 4)),
    // 목표가 앵커와 만나는 경계 — 되돌리지 않으면 0폭이 되어 무효로 오분류된다(실측 `"r "`).
    extend("ve — 목표가 앵커와 만나도 무효가 아니다", words, selection: NSRange(location: 4, length: 4), anchor: 7, .charwise, .right, .wordEndForward, range(6, 2)),
    // 줄 마지막 글자 위의 `l`은 **개행을 문다** — Vim 실측(`lvl`의 레지스터가 `"b\n"`)이다.
    // Normal `l`이 줄을 안 넘는 것과 갈리는 자리이고(그쪽은 다음 줄로 가지 않는다), 여기서
    // 멈추는 것은 포커스가 이미 종결자 위일 때다(아래).
    extend("vl — 줄 마지막 글자에서는 개행까지", twoLines, selection: NSRange(location: 1, length: 1), anchor: 1, .charwise, .left, .charRight, range(1, 2)),
    extend("vll — 종결자 위에서는 무변화", twoLines, selection: NSRange(location: 1, length: 2), anchor: 1, .charwise, .left, .charRight, .invalid),
    // charwise 세션의 `j`/`k`는 **희망 열을 알 때만** 선다 — 모르면 근사하지 않고 스킵이다.
    extend("vj — 희망 열 미상이면 위임", words, selection: NSRange(location: 4, length: 1), anchor: 4, .charwise, .left, .lineDown, .unproven),
    // `v$`는 개행을 문다 — Vim 실측(비-마지막 줄 레지스터가 `"ab\n"`)이며, 세션 1의 반대
    // 문언(마지막 줄에서만 재어 일반화한 것)을 이 픽스처가 고정한다.
    extend("v$ — 개행까지 문다", twoLines, selection: NSRange(location: 0, length: 1), anchor: 0, .charwise, .left, .lineEnd, range(0, 3)),

    // MARK: charwise `j`/`k` — 희망 열(curswant) 추적. `ragged`는 줄 길이가 6/2/6이다.
    // 열 2에서 내려가면 짧은 줄 `xy`의 **종결자 위**에 서고 그 개행까지 문다 (Vim 실측
    // `llvjd` → `abghi`, 줄 병합).
    extend("vj — 짧은 줄은 종결자까지", ragged, selection: NSRange(location: 2, length: 1), anchor: 2, .charwise, .left, .lineDown, range(2, 8), column: 2),
    // 다시 내려가면 열이 **복원**된다 — 짧은 줄이 열을 깎지 않는 것이 curswant다 (실측 `4lvjj`).
    extend("vjj — 짧은 줄을 지나도 열 복원", ragged, selection: NSRange(location: 2, length: 8), anchor: 2, .charwise, .left, .lineDown, range(2, 11), column: 2),
    extend("vk — 후진도 같은 열", ragged, selection: NSRange(location: 12, length: 1), anchor: 12, .charwise, .left, .lineUp, range(9, 4), column: 2),
    // 문서 끝/시작에서는 갈 줄이 없다 — Vim no-op이라 무게시다.
    extend("vj — 마지막 줄은 무효", ragged, selection: NSRange(location: 12, length: 1), anchor: 12, .charwise, .left, .lineDown, .invalid, column: 2),
    extend("vk — 첫 줄은 무효", ragged, selection: NSRange(location: 2, length: 1), anchor: 2, .charwise, .left, .lineUp, .invalid, column: 2),
    // `$` 뒤의 열은 **줄 끝 고정**이라 다음 줄의 길이와 무관하게 종결자에 붙는다 (실측 `v$j`).
    extend("v$j — 줄 끝 고정", ragged, selection: NSRange(location: 0, length: 7), anchor: 0, .charwise, .left, .lineDown, range(0, 10), column: FocusedTextOffsets.lineEndColumn),
    // 빈 줄에 착지하면 그 줄의 개행을 문다 (실측 `vjd` → `def`).
    extend("vj — 빈 줄은 그 개행까지", blankLine, selection: NSRange(location: 0, length: 1), anchor: 0, .charwise, .left, .lineDown, range(0, 3), column: 0),

    // MARK: linewise 확장 — 앵커 줄은 첫 줄, 진입 선택 [0,3)
    extend("Vj — 아래 줄까지", threeLines, selection: NSRange(location: 0, length: 3), anchor: 0, .linewise, .left, .lineDown, range(0, 6)),
    extend("Vk — 첫 줄에서는 무변화", threeLines, selection: NSRange(location: 0, length: 3), anchor: 0, .linewise, .left, .lineUp, .invalid),
    extend("VG — 문서 끝까지", threeLines, selection: NSRange(location: 0, length: 3), anchor: 0, .linewise, .left, .documentEnd, range(0, 8)),
    extend("Vgg — 문서 시작까지", threeLines, selection: NSRange(location: 3, length: 3), anchor: 3, .linewise, .left, .documentStart, range(0, 6)),
    extend("Vj — 마지막 줄은 무변화", threeLines, selection: NSRange(location: 6, length: 2), anchor: 6, .linewise, .left, .lineDown, .invalid),
    // 후진형 linewise — 앱 앵커는 앵커 줄 끝 다음이다.
    extend("Vk — 후진", threeLines, selection: NSRange(location: 3, length: 3), anchor: 3, .linewise, .right, .lineUp, range(0, 6)),
    // `V` 세션의 charwise 모션 8종은 범위 무변화라 무게시다.
    extend("V 세션의 l은 무게시", threeLines, selection: NSRange(location: 0, length: 3), anchor: 0, .linewise, .left, .charRight, .invalid),
    extend("V 세션의 w는 무게시", threeLines, selection: NSRange(location: 0, length: 3), anchor: 0, .linewise, .left, .wordForward, .invalid),
    extend("V 세션의 $는 무게시", threeLines, selection: NSRange(location: 0, length: 3), anchor: 0, .linewise, .left, .lineEnd, .invalid),
]

// MARK: - wise 전환 픽스처

/// 전환 1건의 계약. 확장과 달리 **앵커까지** 단언한다 — 전환은 논리 앵커 자체가 이동하는
/// 유일한 자리라, 범위만 맞고 앵커가 어긋나면 다음 액션이 조용히 죽는다.
struct VisualSwitchFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let text: FocusedText
    let state: VisualAnchorState
    let toLinewise: Bool
    let selection: FocusedTextOffsets.Selection

    var testDescription: String { name }
}

private func switchFixture(
    _ name: String, _ document: String, selection: NSRange, anchor: Int,
    _ wise: VisualAnchorState.Wise, _ side: VisualAnchorState.Side, toLinewise: Bool,
    column: Int? = nil, originalCaret: Int? = nil, _ expected: FocusedTextOffsets.Selection
) -> VisualSwitchFixture {
    VisualSwitchFixture(
        name: name, text: liveText(document, selection: selection),
        state: sessionState(
            anchor: anchor, wise: wise, side: side, selection: selection, column: column,
            originalCaret: originalCaret),
        toLinewise: toLinewise, selection: expected)
}

let visualSwitchFixtures: [VisualSwitchFixture] = [
    // MARK: ⑥ `v`→`V` — 선택이 걸친 논리 줄 전체, 새 앵커는 **앵커 줄 시작**
    switchFixture(
        "v→V 전진형 — 앵커도 줄 시작으로", ragged, selection: NSRange(location: 2, length: 8),
        anchor: 2, .charwise, .left, toLinewise: true, column: 2,
        .range(NSRange(location: 0, length: 10), anchor: 0, column: 2)),
    // 후진형의 새 앵커는 범위의 끝점이 **아니다**(범위 한가운데다) — `Span`으로는 못 나르는 값.
    switchFixture(
        "v→V 후진형 — 새 앵커가 범위 한가운데", ragged, selection: NSRange(location: 9, length: 4),
        anchor: 12, .charwise, .right, toLinewise: true, column: 2,
        .range(NSRange(location: 7, length: 9), anchor: 10, column: 2)),
    switchFixture(
        "v→V — 이미 linewise면 증명하지 않는다", ragged, selection: NSRange(location: 0, length: 7),
        anchor: 0, .linewise, .left, toLinewise: true, column: 0, .unproven),

    // MARK: ⑦ `V`→`v` — 원래 캐럿 P와 포커스 줄의 희망 열
    switchFixture(
        "V→v — P와 포커스 줄 열을 잇는다", threeLines, selection: NSRange(location: 0, length: 6),
        anchor: 0, .linewise, .left, toLinewise: false, column: 1, originalCaret: 1,
        .range(NSRange(location: 1, length: 4), anchor: 1, column: 1)),
    // 포커스 줄이 열보다 짧으면 **종결자 위**다 — keyboard ⑦이 초집합 봉쇄로 스킵하던 자리를
    // AX는 Vim 그대로 클램프한다(범위 1회 쓰기라 스트로크 초과가 없다).
    switchFixture(
        "V→v — 짧은 포커스 줄은 종결자까지", ragged, selection: NSRange(location: 0, length: 10),
        anchor: 0, .linewise, .left, toLinewise: false, column: 4, originalCaret: 4,
        .range(NSRange(location: 4, length: 6), anchor: 4, column: 4)),
    // ⑥으로 만들어진 세션은 P를 모른다 — 근사하지 않고 정직하게 스킵한다.
    switchFixture(
        "V→v — 원래 캐럿 미상이면 스킵", threeLines, selection: NSRange(location: 0, length: 6),
        anchor: 0, .linewise, .left, toLinewise: false, column: 1, .unproven),
    switchFixture(
        "V→v — 희망 열 미상이면 스킵", threeLines, selection: NSRange(location: 0, length: 6),
        anchor: 0, .linewise, .left, toLinewise: false, originalCaret: 1, .unproven),
    switchFixture(
        "V→v — 이미 charwise면 증명하지 않는다", threeLines, selection: NSRange(location: 0, length: 2),
        anchor: 0, .charwise, .left, toLinewise: false, column: 0, originalCaret: 0, .unproven),
]

// MARK: - 스윕 헬퍼

/// `"e\u{0301} x"` — 결합 문자 `é`(1 grapheme·2 UTF-16 단위) ␣ x. 오프셋 경계는 0·2·3·4다.
/// 이모지와 달리 두 스칼라가 모두 BMP라, UTF-16으로 세는 코드가 반쪽을 만들어도 값이 그럴듯해
/// 조용히 통과한다 — UTF-16 함정 5종 중 이것만 미커버였다.
private let combining = "e\u{0301} x"

extension FocusedTextOffsets.Span {
    var isRange: Bool { if case .range = self { true } else { false } }
}

/// 이 창이 증명하는 grapheme 경계 오프셋 전부 + 문서 경계 상수 둘.
/// 산출이 이 집합 밖이면 어딘가에서 편의 산술이 있었다는 뜻이다.
func graphemeBoundaries(of text: FocusedText) -> Set<Int> {
    var result: Set<Int> = [0, text.characterCount, text.windowRange.location]
    var cursor = text.windowRange.location
    for character in text.window {
        cursor += character.utf16.count
        result.insert(cursor)
    }
    return result
}

func expectBoundedSpan(
    _ span: FocusedTextOffsets.Span, in text: FocusedText,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .range(let range) = span else { return }
    let boundaries = graphemeBoundaries(of: text)
    #expect(range.location >= 0, sourceLocation: sourceLocation)
    #expect(range.upperBound <= text.characterCount, sourceLocation: sourceLocation)
    #expect(boundaries.contains(range.location), sourceLocation: sourceLocation)
    #expect(boundaries.contains(range.upperBound), sourceLocation: sourceLocation)
    // 빈 범위는 `.invalid`로 표현한다 — 0폭 편집은 오퍼레이터만 나가는 조용한 오동작이다.
    #expect(range.length > 0, sourceLocation: sourceLocation)
}

/// Visual 산출의 **범위만** 본다 — 앵커·희망 열은 아래 전용 표가 따로 고정한다.
func span(of selection: FocusedTextOffsets.Selection) -> FocusedTextOffsets.Span {
    switch selection {
    case .invalid: return .invalid
    case .unproven: return .unproven
    case .range(let range, _, _): return .range(range)
    }
}

func expectBoundedSelection(
    _ selection: FocusedTextOffsets.Selection, in text: FocusedText,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    expectBoundedSpan(span(of: selection), in: text, sourceLocation: sourceLocation)
    // 새 앵커도 산출이다 — 경계 밖 앵커는 다음 액션의 `index(of:)`를 조용히 `.unproven`으로
    // 만들어 세션이 죽는다.
    guard case .range(_, let anchor, let column) = selection else { return }
    #expect(anchor >= 0, sourceLocation: sourceLocation)
    #expect(anchor <= text.characterCount, sourceLocation: sourceLocation)
    #expect(graphemeBoundaries(of: text).contains(anchor), sourceLocation: sourceLocation)
    // 열은 음수가 될 수 없다 — 줄 끝 고정 sentinel만 예외적으로 크다.
    if let column { #expect(column >= 0, sourceLocation: sourceLocation) }
}

func expectBoundedInsertion(
    _ insertion: FocusedTextOffsets.Insertion, in text: FocusedText,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    switch insertion {
    case .at(let offset), .appendingLine(let offset):
        #expect(offset >= 0, sourceLocation: sourceLocation)
        #expect(offset <= text.characterCount, sourceLocation: sourceLocation)
        #expect(graphemeBoundaries(of: text).contains(offset), sourceLocation: sourceLocation)
    case .unproven:
        break
    }
}

/// AX 진입이 세우는 세션 — 어댑터의 `beginSelection` 분기와 같은 재료를 만든다.
func beginSession(
    _ document: String, caret: Int, linewise: Bool
) -> (text: FocusedText, state: VisualAnchorState) {
    let text = focusedText(document, caret: caret)
    guard case .range(let range, let anchor, let column) =
        FocusedTextOffsets.visualEntrySelection(linewise: linewise, in: text)
    else { fatalError("진입이 증명되지 않는 픽스처") }
    var live = text
    live.selection = range
    return (
        live,
        VisualAnchorState(
            anchor: anchor, wise: linewise ? .linewise : .charwise, side: .left, pinnedEnd: anchor,
            processID: 0, originalCaret: linewise ? caret : nil, focusLineDistance: nil,
            desiredColumn: column)
    )
}

/// 산출 → 상태 → 다음 산출로 이어 붙인다 — 어댑터가 도는 모양 그대로다.
@discardableResult
func advance(
    _ session: inout (text: FocusedText, state: VisualAnchorState), _ motion: Motion
) -> FocusedTextOffsets.Selection {
    let selection = FocusedTextOffsets.visualExtendSelection(
        for: motion, anchor: session.state, in: session.text)
    if case .range(let range, let anchor, let column) = selection {
        session.state = session.state.moved(to: range, anchor: anchor, column: column)
        session.text.selection = range
    }
    return selection
}

/// 진입 범위로 살아 있는 선택을 만들어 확장 스윕의 입력을 얻는다. 진입이 증명되지 않으면
/// 캐럿 그대로이고, 그때 확장은 `.unproven`이다.
func sweepSession(_ text: FocusedText, linewise: Bool) -> (FocusedText, VisualAnchorState)? {
    guard case .range(let selection, let anchor, let column) =
        FocusedTextOffsets.visualEntrySelection(linewise: linewise, in: text)
    else { return nil }
    var live = text
    live.selection = selection
    // `originalCaret`·`desiredColumn`은 AX 진입이 채우는 값이라 스윕도 채운 채 돌린다 —
    // 비워 두면 `j`/`k`와 `V`→`v`가 전부 `.unproven`으로 빠져 스윕이 그 경로를 못 밟는다.
    let state = VisualAnchorState(
        anchor: anchor, wise: linewise ? .linewise : .charwise, side: .left,
        pinnedEnd: anchor, processID: 0, originalCaret: text.selection.location,
        focusLineDistance: nil, desiredColumn: column)
    return (live, state)
}

struct FocusedTextOffsetsTests {
    @Test("캐럿 모션 오프셋 표", arguments: offsetFixtures)
    func caretTargets(_ fixture: OffsetFixture) {
        #expect(FocusedTextOffsets.caretTarget(for: fixture.motion, in: fixture.text) == fixture.target)
    }

    /// 표가 어휘 전체를 덮는가 — 새 모션이 늘면 여기서 걸린다. `j`/`k`도 위임 케이스로
    /// 표에 있어야 한다("답을 안 낸다"가 명시적 계약이라서다).
    @Test("표는 Motion 전 케이스를 덮는다")
    func tableCoversEveryMotion() {
        let covered = Set(offsetFixtures.map(\.motion))
        for motion in Motion.allCases {
            #expect(covered.contains(motion), "표에 없는 모션: \(motion)")
        }
    }

    /// 경계 불변식 — 산출은 언제나 문서 안이다. 이것이 깨지면 `provenWriteRange`가 걸러 주지만,
    /// 걸러진다는 것은 곧 그 어휘가 조용히 죽는다는 뜻이라 여기서 먼저 잡는다.
    @Test("산출은 항상 0...characterCount 안이다", arguments: offsetFixtures)
    func targetsStayInsideDocument(_ fixture: OffsetFixture) {
        guard case .caret(let offset) = fixture.target else { return }
        #expect(offset >= 0)
        #expect(offset <= fixture.text.characterCount)
    }

    @Test("줄 종결자 5형태가 같은 답을 낸다", arguments: lineTerminators)
    func lineTerminatorsAgree(_ terminator: String) {
        let document = "ab\(terminator)cd"
        let secondLine = ("ab" + terminator).utf16.count

        // 첫 줄 끝(종결자 앞)에서: `$`는 무효, `l`도 무효(줄을 넘지 않는다).
        #expect(FocusedTextOffsets.caretTarget(for: .lineEnd, in: focusedText(document, caret: 2)) == .invalid)
        #expect(
            FocusedTextOffsets.caretTarget(for: .charRight, in: focusedText(document, caret: 2))
                == .invalid)
        // 둘째 줄 시작에서: `0`은 무효, `h`도 무효.
        #expect(
            FocusedTextOffsets.caretTarget(
                for: .lineStart, in: focusedText(document, caret: secondLine)) == .invalid)
        #expect(
            FocusedTextOffsets.caretTarget(
                for: .charLeft, in: focusedText(document, caret: secondLine)) == .invalid)
        // 첫 줄 시작에서 `$`는 종결자 앞이다.
        #expect(
            FocusedTextOffsets.caretTarget(for: .lineEnd, in: focusedText(document, caret: 0))
                == .caret(2))
    }

    /// **산출은 항상 grapheme cluster 경계 위다.** 서로게이트 쌍 한가운데 오프셋을 Notion은
    /// 무보정으로 받아들이는 것이 실측됐고(세션 1), 되읽어 검증도 그것을 잡지 못하므로 이
    /// 불변식이 유일한 방어선이다.
    @Test("이모지·결합 문자 위에서도 경계 위로만 산출한다")
    func targetsLandOnGraphemeBoundaries() {
        // "a👨‍👩‍👧x" — ZWJ 가족 이모지는 UTF-16 여러 단위 한 클러스터다.
        let document = "a👨‍👩‍👧x"
        let afterEmoji = document.utf16.count - 1

        // `l`은 이모지를 통째로 건너뛴다 (UTF-16 1단위가 아니다).
        #expect(
            FocusedTextOffsets.caretTarget(for: .charRight, in: focusedText(document, caret: 1))
                == .caret(afterEmoji))
        // 되돌아오는 `h`도 같은 경계다.
        #expect(
            FocusedTextOffsets.caretTarget(
                for: .charLeft, in: focusedText(document, caret: afterEmoji)) == .caret(1))
    }

    /// 캐럿 자체가 경계 위가 아니면(mid-surrogate) 아무것도 증명하지 않는다 — 보정해서
    /// 진행하면 "정확하게 엉뚱한 자리"를 쓴다.
    @Test("클러스터 한가운데 캐럿은 증명하지 않는다")
    func midClusterCaretIsUnproven() {
        let document = "a👍b"  // 👍는 UTF-16 2단위 — 오프셋 2가 쌍 한가운데다.
        #expect(
            FocusedTextOffsets.caretTarget(for: .charRight, in: focusedText(document, caret: 2))
                == .unproven)
    }

    /// 창 길이가 `windowRange`와 어긋나는 앱은 창을 근거로 쓸 수 없다 — Analysis와 공유하는
    /// 가드다(`offsetInWindow`).
    @Test("창 길이가 어긋나면 증명하지 않는다")
    func inconsistentWindowIsUnproven() {
        let text = FocusedText(
            selection: NSRange(location: 1, length: 0), characterCount: 12,
            window: "ab", windowRange: NSRange(location: 0, length: 5))
        #expect(FocusedTextOffsets.caretTarget(for: .charRight, in: text) == .unproven)
    }

    // MARK: 범위 표

    @Test("편집 범위 표", arguments: spanFixtures)
    func editSpans(_ fixture: SpanFixture) {
        #expect(
            FocusedTextOffsets.editSpan(for: fixture.op, range: fixture.range, in: fixture.text)
                == fixture.span)
    }

    @Test("삽입 위치 표", arguments: insertionFixtures)
    func insertions(_ fixture: InsertionFixture) {
        let actual =
            if let paste = fixture.paste {
                FocusedTextOffsets.pasteInsertion(
                    before: paste.before, wise: paste.wise, in: fixture.text)
            } else {
                FocusedTextOffsets.openLineInsertion(above: fixture.above, in: fixture.text)
            }
        #expect(actual == fixture.insertion)
    }

    @Test("Visual 범위 표", arguments: visualSpanFixtures)
    func visualSpans(_ fixture: VisualSpanFixture) {
        let actual =
            if let anchor = fixture.anchor {
                FocusedTextOffsets.visualExtendSelection(
                    for: fixture.motion, anchor: anchor, in: fixture.text)
            } else {
                FocusedTextOffsets.visualEntrySelection(
                    linewise: fixture.linewise, in: fixture.text)
            }
        #expect(span(of: actual) == fixture.span)
    }

    @Test("wise 전환 표", arguments: visualSwitchFixtures)
    func visualSwitches(_ fixture: VisualSwitchFixture) {
        #expect(
            FocusedTextOffsets.visualSwitchSelection(
                toLinewise: fixture.toLinewise, anchor: fixture.state, in: fixture.text)
                == fixture.selection)
    }

    /// **세션을 이어 붙인 관통 테스트** — 한 액션짜리 표가 못 잡는 것이 여기 있다: 희망 열은
    /// 액션 사이를 건너야 의미가 있고(`vjj`의 열 복원), 전환은 앞선 확장이 만든 상태를 입력으로
    /// 받는다. 어댑터가 도는 모양 그대로(`산출 → moved(to:) → 다음 산출`)라 상태 도출 규칙도
    /// 함께 고정된다.
    @Test("vjj — 짧은 줄을 지나도 열이 복원된다")
    func desiredColumnSurvivesShortLine() {
        var session = beginSession(ragged, caret: 2, linewise: false)
        // `abcdef`의 `c`(열 2)에서 `j` — 짧은 줄 `xy`의 종결자 위에 서고 그 개행까지 문다.
        #expect(advance(&session, .lineDown) == .range(NSRange(location: 2, length: 8), anchor: 2, column: 2))
        // 한 번 더 `j` — 열 2가 복원되어 `ghijkl`의 `i`까지다(짧은 줄이 열을 깎지 않는다).
        #expect(advance(&session, .lineDown) == .range(NSRange(location: 2, length: 11), anchor: 2, column: 2))
        #expect(session.state.side == .left)
        #expect(session.state.pinnedEnd == 2)
    }

    /// `e` 뒤의 희망 열은 **커서 자리**(목표 −1)로 세야 한다 — 목표로 세면 이어지는 `j`가
    /// 한 열 더 문다. 1자 차이라 `j`/`k`가 안 섞이면 드러나지 않고 조용히 누적된다.
    /// Vim 실측: `vej`가 `"foo.bar\nabc"`(둘째 줄 열 2까지)를 낸다.
    @Test("vej — e의 커서 열이 다음 줄로 이어진다")
    func wordEndColumnIsCursorColumn() {
        var session = beginSession("foo.bar\nabcdefg", caret: 0, linewise: false)
        #expect(advance(&session, .wordEndForward) == .range(NSRange(location: 0, length: 3), anchor: 0, column: 2))
        #expect(advance(&session, .lineDown) == .range(NSRange(location: 0, length: 11), anchor: 0, column: 2))
    }

    /// **열은 Character 델타여야 한다** — 절대 오프셋 뺄셈은 UTF-16 델타라 이모지 앞의 캐럿에서
    /// 부풀고, 그 값이 `V`→`v`의 포커스가 되어 선택이 한 글자 넓어진다. grapheme 경계
    /// 불변식은 결과가 `offsets` 원소이기만 하면 통과시켜 이 오류를 못 잡는다.
    @Test("V 진입의 열은 UTF-16이 아니라 문자 단위다")
    func linewiseEntryColumnIsCharacterDelta() {
        // "a👍bc\ndef" — a0 👍1(2단위) b3 c4 ⏎5 d6…, `b`(오프셋 3)가 문자 인덱스 2다.
        let text = focusedText("a👍bc\ndef", caret: 3)
        #expect(
            FocusedTextOffsets.visualEntrySelection(linewise: true, in: text)
                == .range(NSRange(location: 0, length: 6), anchor: 0, column: 2))

        var live = text
        live.selection = NSRange(location: 0, length: 6)
        let state = sessionState(
            anchor: 0, wise: .linewise, side: .left, selection: live.selection, column: 2,
            originalCaret: 3)
        // 열이 3(UTF-16 델타)이면 `c`까지 잡아 `"bc"`가 된다.
        #expect(
            FocusedTextOffsets.visualSwitchSelection(toLinewise: false, anchor: state, in: live)
                == .range(NSRange(location: 3, length: 1), anchor: 3, column: 2))
    }

    /// `$` 뒤의 열은 줄 끝 고정이다 — Vim curswant MAXCOL(실측 `v$j`가 다음 줄의 개행까지 문다).
    @Test("v$j — 줄 끝에 붙는다")
    func lineEndColumnSticks() {
        var session = beginSession(ragged, caret: 0, linewise: false)
        #expect(advance(&session, .lineEnd) == .range(NSRange(location: 0, length: 7), anchor: 0, column: FocusedTextOffsets.lineEndColumn))
        #expect(advance(&session, .lineDown) == .range(NSRange(location: 0, length: 10), anchor: 0, column: FocusedTextOffsets.lineEndColumn))
    }

    /// `G`는 열을 세려면 마지막 줄 시작이 필요한데 창이 거기 못 닿는다 — 모른다고 남기면
    /// 이어지는 `j`/`k`가 근사 대신 정직하게 스킵한다.
    @Test("vG 뒤의 j는 열을 몰라 스킵한다")
    func unknownColumnSkipsVerticalMotion() {
        var session = beginSession(ragged, caret: 2, linewise: false)
        #expect(advance(&session, .documentEnd) == .range(NSRange(location: 2, length: 14), anchor: 2, column: nil))
        #expect(advance(&session, .lineUp) == .unproven)
    }

    /// `v`→`V`→`v`가 **원래 선택을 복원**한다 — Vim 실측(`llvjVv`가 `llvj`와 같은 선택)이고,
    /// keyboard ⑥이 열 근사 때문에 포기했던 자리를 AX는 정확값으로 되돌린다.
    @Test("vjVv — 원래 charwise 선택으로 되돌아온다")
    func switchRoundTripRestoresSelection() {
        var session = beginSession(ragged, caret: 2, linewise: false)
        let extended = advance(&session, .lineDown)
        #expect(extended == .range(NSRange(location: 2, length: 8), anchor: 2, column: 2))

        // `V` — 논리 줄로 반올림하고, charwise 앵커를 `originalCaret`으로 보관한다(어댑터 규칙).
        guard case .range(let rounded, let roundedAnchor, let roundedColumn) =
            FocusedTextOffsets.visualSwitchSelection(
                toLinewise: true, anchor: session.state, in: session.text)
        else { return #expect(Bool(false), "v→V가 증명되지 않았다") }
        let charwiseAnchor = session.state.anchor
        session.state = session.state.moved(
            to: rounded, anchor: roundedAnchor, column: roundedColumn)
        session.state.wise = .linewise
        session.state.originalCaret = charwiseAnchor
        session.text.selection = rounded
        #expect(rounded == NSRange(location: 0, length: 10))

        // `v` — 되돌아온 선택이 `vj`의 것과 같다.
        #expect(
            FocusedTextOffsets.visualSwitchSelection(
                toLinewise: false, anchor: session.state, in: session.text) == extended)
    }

    // MARK: 전수 스윕

    /// `.motion` 범위 표가 어휘 전체를 덮는가 — 새 모션이 조용히 미구현으로 흘러들지 않게.
    @Test("범위 표는 Motion 전 케이스를 덮는다")
    func spanTableCoversEveryMotion() {
        var covered: Set<Motion> = []
        for fixture in spanFixtures {
            if case .motion(let motion, _) = fixture.range { covered.insert(motion) }
        }
        for motion in Motion.allCases {
            #expect(covered.contains(motion), "범위 표에 없는 모션: \(motion)")
        }
    }

    /// `TextRange`·`Operator` 전 케이스가 표에 있는가. `TextRange`는 연관값이 있어
    /// `CaseIterable`이 못 되므로 exhaustive switch가 그 역할을 한다 — 케이스가 늘면
    /// 여기서 컴파일이 깨진다.
    @Test("범위 표는 TextRange·Operator 전 케이스를 덮는다")
    func spanTableCoversEveryRangeKind() {
        var kinds: Set<String> = []
        var linewiseMotions: Set<Motion> = []
        var operators: Set<VimAction.Operator> = []
        for fixture in spanFixtures {
            operators.insert(fixture.op)
            switch fixture.range {
            case .motion: kinds.insert("motion")
            case .line: kinds.insert("line")
            case .linewiseMotion(let motion, _):
                kinds.insert("linewiseMotion")
                linewiseMotions.insert(motion)
            case .textObject: kinds.insert("textObject")
            case .selection: kinds.insert("selection")
            }
        }
        #expect(kinds == ["motion", "line", "linewiseMotion", "textObject", "selection"])
        #expect(linewiseMotions == [.lineUp, .lineDown, .documentStart, .documentEnd])
        #expect(operators == [.delete, .change, .yank])
    }

    /// 세 갈래가 전부 표에 있는가 — 하나라도 비면 그 갈래가 코드에만 있고 검증되지 않는다.
    @Test("표가 세 갈래를 다 덮는다")
    func tablesCoverEveryOutcome() {
        #expect(spanFixtures.contains { $0.span == .invalid })
        #expect(spanFixtures.contains { $0.span.isRange })
        #expect(spanFixtures.contains { $0.span == .unproven })

        #expect(insertionFixtures.contains { if case .at = $0.insertion { true } else { false } })
        #expect(
            insertionFixtures.contains {
                if case .appendingLine = $0.insertion { true } else { false }
            })
        #expect(insertionFixtures.contains { $0.insertion == .unproven })

        #expect(visualSpanFixtures.contains { $0.span == .invalid })
        #expect(visualSpanFixtures.contains { $0.span.isRange })
        #expect(visualSpanFixtures.contains { $0.span == .unproven })
    }

    /// **openLine은 `.appendingLine`을 내지 않는다** — 그 케이스는 마지막 줄 linewise `p`
    /// 전용이고, `o`/`O`는 `Return`을 언제나 게시한다.
    @Test("openLine은 appendingLine을 내지 않는다")
    func openLineNeverAppendsLine() {
        for fixture in insertionFixtures where fixture.paste == nil {
            if case .appendingLine = fixture.insertion {
                Issue.record("openLine이 appendingLine을 냈다: \(fixture.name)")
            }
        }
    }

    /// 경계 불변식 + **grapheme 경계** — 산출이 `Window.offsets` 원소나 문서 경계 상수를
    /// 경유했는지 본다. 편의 산술(`caret + 1`을 UTF-16으로 더하는 류)이 여기서 걸린다.
    @Test("범위 양 끝은 문서 안의 grapheme 경계다", arguments: spanFixtures)
    func spansLandOnGraphemeBoundaries(_ fixture: SpanFixture) {
        expectBoundedSpan(fixture.span, in: fixture.text)
    }

    @Test("Visual 범위도 같은 불변식을 지킨다", arguments: visualSpanFixtures)
    func visualSpansLandOnGraphemeBoundaries(_ fixture: VisualSpanFixture) {
        expectBoundedSpan(fixture.span, in: fixture.text)
    }

    @Test("삽입 위치도 grapheme 경계다", arguments: insertionFixtures)
    func insertionsLandOnGraphemeBoundaries(_ fixture: InsertionFixture) {
        let boundaries = graphemeBoundaries(of: fixture.text)
        switch fixture.insertion {
        case .at(let offset), .appendingLine(let offset):
            #expect(boundaries.contains(offset))
            #expect(offset >= 0)
            #expect(offset <= fixture.text.characterCount)
        case .unproven:
            break
        }
    }

    /// 모든 문서 × 모든 캐럿 × 모든 어휘 — 표가 답을 고정한다면 이 스윕은 **답이 없는
    /// 자리에서도 트랩하지 않고 경계를 지킨다**를 고정한다. 인덱스 산술의 off-by-one이
    /// 여기서 죽는다.
    @Test("전수 스윕 — 어떤 캐럿에서도 경계를 벗어나지 않는다")
    func exhaustiveSweep() {
        let documents = [
            words, twoLines, indented, threeLines, trailingNewline, blankLine, combining,
            "", "\n", "  \n", "\r\n\r\n", "a",
        ]
        for document in documents {
            for caret in 0...document.utf16.count {
                let text = focusedText(document, caret: caret)
                let sessions = [sweepSession(text, linewise: false), sweepSession(text, linewise: true)]
                for motion in Motion.allCases {
                    for op in [VimAction.Operator.delete, .change, .yank] {
                        expectBoundedSpan(
                            FocusedTextOffsets.editSpan(
                                for: op, range: .motion(motion, count: 2), in: text), in: text)
                        expectBoundedSpan(
                            FocusedTextOffsets.editSpan(
                                for: op, range: .linewiseMotion(motion, count: 2), in: text),
                            in: text)
                    }
                    for case .some(let (live, anchor)) in sessions {
                        expectBoundedSelection(
                            FocusedTextOffsets.visualExtendSelection(
                                for: motion, anchor: anchor, in: live), in: live)
                    }
                }
                for op in [VimAction.Operator.delete, .change, .yank] {
                    expectBoundedSpan(
                        FocusedTextOffsets.editSpan(for: op, range: .line(count: 2), in: text),
                        in: text)
                    expectBoundedSpan(
                        FocusedTextOffsets.editSpan(
                            for: op, range: .textObject(.word(.inner)), in: text), in: text)
                }
                for linewise in [false, true] {
                    expectBoundedSelection(
                        FocusedTextOffsets.visualEntrySelection(linewise: linewise, in: text),
                        in: text)
                    for case .some(let (live, anchor)) in sessions {
                        expectBoundedSelection(
                            FocusedTextOffsets.visualSwitchSelection(
                                toLinewise: linewise, anchor: anchor, in: live), in: live)
                    }
                }
                expectBoundedInsertion(
                    FocusedTextOffsets.openLineInsertion(above: caret.isMultiple(of: 2), in: text),
                    in: text)
                for wise in [PasteWise.charwise, .linewise] {
                    for before in [false, true] {
                        expectBoundedInsertion(
                            FocusedTextOffsets.pasteInsertion(
                                before: before, wise: wise, in: text), in: text)
                    }
                }
            }
        }
    }

    // MARK: UTF-16 함정

    /// **결합 문자** — `e` + U+0301은 1 grapheme·2 UTF-16 단위다. 이모지(서로게이트)와 달리
    /// 두 스칼라가 각각 BMP라, UTF-16 단위로 세는 코드가 "반쪽"을 만들어도 값이 그럴듯하다.
    @Test("결합 문자를 통째로 다룬다")
    func combiningMarkIsOneCharacter() {
        // "é x" — é0(2단위) ␣2 x3, 문서 끝 4.
        let text = focusedText(combining, caret: 0)
        #expect(
            FocusedTextOffsets.editSpan(for: .delete, range: .motion(.charRight, count: 1), in: text)
                == .range(NSRange(location: 0, length: 2)))
        #expect(
            FocusedTextOffsets.editSpan(for: .delete, range: .textObject(.word(.inner)), in: text)
                == .range(NSRange(location: 0, length: 2)))
        #expect(
            FocusedTextOffsets.visualEntrySelection(linewise: false, in: text)
                == .range(NSRange(location: 0, length: 2), anchor: 0, column: 0))
        #expect(FocusedTextOffsets.pasteInsertion(before: false, wise: .charwise, in: text) == .at(2))
        // 되돌아오는 `dh`도 같은 경계다.
        #expect(
            FocusedTextOffsets.editSpan(
                for: .delete, range: .motion(.charLeft, count: 1), in: focusedText(combining, caret: 2))
                == .range(NSRange(location: 0, length: 2)))
    }

    /// 결합 문자 한가운데 캐럿은 아무것도 증명하지 않는다 — 서로게이트와 같은 규칙이다.
    @Test("결합 문자 한가운데 캐럿은 증명하지 않는다")
    func midCombiningCaretIsUnproven() {
        let text = focusedText(combining, caret: 1)
        #expect(FocusedTextOffsets.editSpan(for: .delete, range: .line(count: 1), in: text) == .unproven)
        #expect(FocusedTextOffsets.visualEntrySelection(linewise: false, in: text) == .unproven)
        #expect(FocusedTextOffsets.openLineInsertion(above: false, in: text) == .unproven)
    }

    /// 줄 종결자 5형태에서 **범위**도 같은 답을 낸다 — `\r\n`이 한 `Character`라 종결자
    /// **`ddp` 관통** — 두 함수를 이어 붙여 idiom 전체를 고정한다. 어느 한쪽만 보면 잡히지
    /// 않는 회귀가 여기 있다: 마지막 줄 `dd`가 앞 개행을 흡수하면 클립보드가 `"\nl3"`가 되어
    /// 이어지는 `p`가 빈 줄을 만든다(도그푸딩 실측). 클립보드가 곧 레지스터라 잘라내는 범위가
    /// 레지스터의 모양을 정한다 (`20260809_no-leading-newline-absorb-clipboard-is-the-register.md`).
    @Test("ddp — 마지막 줄에서 두 줄이 교환된다")
    func lastLineDeleteThenPasteSwapsLines() {
        // ① `dd`는 줄 시작부터 문서 끝까지 — 앞 개행을 남긴다(빈 줄 1개 잔류).
        #expect(
            FocusedTextOffsets.editSpan(
                for: .delete, range: .line(count: 1), in: focusedText(threeLines, caret: 6))
                == .range(NSRange(location: 6, length: 2)))
        // ② 잘라낸 뒤 문서는 `"l1\nl2\n"`이고 캐럿은 빈 마지막 줄(6)이다. 구분 개행이 이미
        //    있으므로 `p`는 개행을 합성하지 않고 그 자리에 붙인다 → `l1\nl2\nl3`.
        #expect(
            FocusedTextOffsets.pasteInsertion(
                before: false, wise: .linewise, in: focusedText(trailingNewline, caret: 6))
                == .at(6))
    }

    /// 길이가 2인 문서에서도 반올림이 어긋나지 않는다.
    @Test("줄 종결자 5형태에서 범위가 같다", arguments: lineTerminators)
    func lineTerminatorsAgreeForSpans(_ terminator: String) {
        let document = "ab\(terminator)cd"
        let width = terminator.utf16.count
        let secondLine = 2 + width
        let first = focusedText(document, caret: 0)
        let last = focusedText(document, caret: secondLine)

        // `dd`는 종결자를 포함하고, `cc`는 줄을 남긴다.
        #expect(
            FocusedTextOffsets.editSpan(for: .delete, range: .line(count: 1), in: first)
                == .range(NSRange(location: 0, length: secondLine)))
        #expect(
            FocusedTextOffsets.editSpan(for: .change, range: .line(count: 1), in: first)
                == .range(NSRange(location: 0, length: 2)))
        // 마지막 줄은 문서 끝까지다 — 앞 종결자는 흡수하지 않는다(빈 줄 1개가 남는다).
        #expect(
            FocusedTextOffsets.editSpan(for: .delete, range: .line(count: 1), in: last)
                == .range(NSRange(location: secondLine, length: 2)))
        // `V` 진입도 종결자를 문다 — 열은 캐럿에서 줄 시작까지의 거리(0)다.
        #expect(
            FocusedTextOffsets.visualEntrySelection(linewise: true, in: first)
                == .range(NSRange(location: 0, length: secondLine), anchor: 0, column: 0))
        // 줄 끝 `diw`는 직전 글자의 런이다(종결자를 넘지 않는다).
        #expect(
            FocusedTextOffsets.editSpan(
                for: .delete, range: .textObject(.word(.inner)), in: focusedText(document, caret: 2))
                == .range(NSRange(location: 0, length: 2)))
        // linewise `p`의 삽입점은 다음 줄 시작이다.
        #expect(
            FocusedTextOffsets.pasteInsertion(before: false, wise: .linewise, in: first)
                == .at(secondLine))
    }

    /// **비ASCII는 `keyword`** 다 — `FocusedText.RunClass`(비ASCII = `other`)와 정반대이며,
    /// 그것이 이 계층이 별도 이름공간인 이유다. CJK 문서에서 `w`가 살아야 한다.
    @Test("CJK는 하나의 단어 런이다")
    func cjkIsOneKeywordRun() {
        let document = "한글 abc"  // 한0 글1 ␣2 a3 b4 c5, 문서 끝 6
        #expect(
            FocusedTextOffsets.caretTarget(for: .wordForward, in: focusedText(document, caret: 0))
                == .caret(3))
        #expect(
            FocusedTextOffsets.caretTarget(
                for: .wordEndForward, in: focusedText(document, caret: 0)) == .caret(2))
    }
}

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

//
//  FocusedTextAnalysisTests.swift
//  VimActionTests
//

import Foundation
import Testing

@testable import VimAction

// MARK: - 픽스처

/// 파생 질의 계약표 한 행. **이 표가 곧 계약이다** — 경계 판정이 바뀌면 여기가 먼저 바뀐다.
struct FocusedTextQueryFixture: Sendable, CustomTestStringConvertible {
    var name: String
    var text: FocusedText
    var caretOffsetInWindow: Int?
    var isAtDocumentStart: Bool
    var isAtDocumentEnd: Bool
    var isAtLineStart: Bool
    var isAtLineEnd: Bool
    var charactersToLineEnd: Int?
    var charactersToLineStart: Int?
    var linesAboveCaret: Int?
    var isOnLastLine: Bool
    var provesNoWordStartAhead: Bool
    var isAtLineFirstNonBlank: Bool

    var testDescription: String { name }
}

/// 창이 문서 전체인 읽기를 만든다 — 리더의 clamp가 짧은 문서에서 내는 모양 그대로다.
/// (`EditKeyMapperTests`의 포화 표도 이 헬퍼를 쓴다 — 두 표가 같은 문서 모델을 딛는다.)
func focusedText(_ document: String, caret: Int, length: Int = 0) -> FocusedText {
    let count = document.utf16.count
    return FocusedText(
        selection: NSRange(location: caret, length: length), characterCount: count,
        window: document, windowRange: NSRange(location: 0, length: count))
}

/// 문서 `"ab\ncd"` — 개행 하나를 낀 최소 형태. 오프셋: a0 b1 \n2 c3 d4, 문서 끝은 5.
private let twoLines = "ab\ncd"

let focusedTextQueryFixtures: [FocusedTextQueryFixture] = [
    .init(
        name: "첫 줄 한가운데 (a|b)", text: focusedText(twoLines, caret: 1),
        caretOffsetInWindow: 1, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: false, isAtLineEnd: false,
        charactersToLineEnd: 1, charactersToLineStart: 1, linesAboveCaret: 0,
        isOnLastLine: false, provesNoWordStartAhead: false, isAtLineFirstNonBlank: false),
    .init(
        name: "문서 시작 (|ab)", text: focusedText(twoLines, caret: 0),
        caretOffsetInWindow: 0, isAtDocumentStart: true, isAtDocumentEnd: false,
        isAtLineStart: true, isAtLineEnd: false,
        charactersToLineEnd: 2, charactersToLineStart: 0, linesAboveCaret: 0,
        isOnLastLine: false, provesNoWordStartAhead: false, isAtLineFirstNonBlank: true),
    .init(
        name: "첫 줄 끝 — 개행 직전 (ab|\\n)", text: focusedText(twoLines, caret: 2),
        caretOffsetInWindow: 2, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: false, isAtLineEnd: true,
        charactersToLineEnd: 0, charactersToLineStart: 2, linesAboveCaret: 0,
        isOnLastLine: false, provesNoWordStartAhead: false, isAtLineFirstNonBlank: false),
    .init(
        name: "둘째 줄 시작 — 개행 직후 (\\n|cd)", text: focusedText(twoLines, caret: 3),
        caretOffsetInWindow: 3, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: true, isAtLineEnd: false,
        charactersToLineEnd: 2, charactersToLineStart: 0, linesAboveCaret: 1,
        isOnLastLine: true, provesNoWordStartAhead: true, isAtLineFirstNonBlank: true),
    .init(
        name: "문서 끝 (cd|) — 마지막 줄 끝이기도 하다", text: focusedText(twoLines, caret: 5),
        caretOffsetInWindow: 5, isAtDocumentStart: false, isAtDocumentEnd: true,
        isAtLineStart: false, isAtLineEnd: true,
        charactersToLineEnd: 0, charactersToLineStart: 2, linesAboveCaret: 1,
        isOnLastLine: true, provesNoWordStartAhead: true, isAtLineFirstNonBlank: false),
    .init(
        name: "빈 문서 — 시작이자 끝", text: focusedText("", caret: 0),
        caretOffsetInWindow: 0, isAtDocumentStart: true, isAtDocumentEnd: true,
        isAtLineStart: true, isAtLineEnd: true,
        charactersToLineEnd: 0, charactersToLineStart: 0, linesAboveCaret: 0,
        isOnLastLine: true, provesNoWordStartAhead: true, isAtLineFirstNonBlank: false),
    .init(
        name: "빈 줄 위 (ab\\n|\\ncd)", text: focusedText("ab\n\ncd", caret: 3),
        caretOffsetInWindow: 3, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: true, isAtLineEnd: true,
        charactersToLineEnd: 0, charactersToLineStart: 0, linesAboveCaret: 1,
        isOnLastLine: false, provesNoWordStartAhead: false, isAtLineFirstNonBlank: false),
    // 선택이 살아 있으면 줄 끝 판정은 **선택 끝** 기준이다 — 시작 기준으로 보면 Visual 확장
    // 뒤의 판정이 통째로 어긋난다. (줄 **시작** 쪽 질의만 선택 시작을 본다.)
    .init(
        name: "선택 범위 (a[b]\\ncd) — 끝이 줄 끝", text: focusedText(twoLines, caret: 1, length: 1),
        caretOffsetInWindow: 1, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: false, isAtLineEnd: true,
        charactersToLineEnd: 0, charactersToLineStart: 1, linesAboveCaret: 0,
        isOnLastLine: false, provesNoWordStartAhead: false, isAtLineFirstNonBlank: false),
]

// MARK: - 테스트

struct FocusedTextAnalysisTests {
    @Test("파생 질의 골든 — 경계 판정이 계약대로다", arguments: focusedTextQueryFixtures)
    func derivesQueriesAsContracted(_ fixture: FocusedTextQueryFixture) {
        #expect(fixture.text.caretOffsetInWindow == fixture.caretOffsetInWindow, "\(fixture.name)")
        #expect(fixture.text.isAtDocumentStart == fixture.isAtDocumentStart, "\(fixture.name)")
        #expect(fixture.text.isAtDocumentEnd == fixture.isAtDocumentEnd, "\(fixture.name)")
        #expect(fixture.text.isAtLineStart == fixture.isAtLineStart, "\(fixture.name)")
        #expect(fixture.text.isAtLineEnd == fixture.isAtLineEnd, "\(fixture.name)")
        #expect(fixture.text.charactersToLineEnd == fixture.charactersToLineEnd, "\(fixture.name)")
        #expect(
            fixture.text.charactersToLineStart == fixture.charactersToLineStart, "\(fixture.name)")
        #expect(fixture.text.linesAboveCaret == fixture.linesAboveCaret, "\(fixture.name)")
        #expect(fixture.text.isOnLastLine == fixture.isOnLastLine, "\(fixture.name)")
        #expect(
            fixture.text.provesNoWordStartAhead == fixture.provesNoWordStartAhead, "\(fixture.name)")
        #expect(
            fixture.text.isAtLineFirstNonBlank == fixture.isAtLineFirstNonBlank, "\(fixture.name)")
    }

    /// 줄 경계 질의는 `isAtLine*`와 **같은 사실을 다르게 센다** — 갈라지면 clamp가 0인데
    /// 억제는 안 하는(또는 그 반대) 모순이 생겨 정확화가 서로를 무너뜨린다.
    @Test("거리 0과 경계 판정은 같은 답을 낸다", arguments: focusedTextQueryFixtures)
    func distanceAndBoundaryQueriesAgree(_ fixture: FocusedTextQueryFixture) {
        if let toEnd = fixture.charactersToLineEnd {
            #expect((toEnd == 0) == fixture.isAtLineEnd, "\(fixture.name)")
        }
        if let toStart = fixture.charactersToLineStart {
            #expect((toStart == 0) == fixture.isAtLineStart, "\(fixture.name)")
        }
        if fixture.isAtDocumentEnd { #expect(fixture.isOnLastLine, "\(fixture.name)") }
    }

    /// 창이 문서 일부일 때 — 리더의 반경 clamp가 긴 문서에서 내는 실제 모양이다.
    /// 절대 오프셋을 창 안 상대로 옮기는 것이 `windowRange`가 반환 타입에 있는 이유다.
    @Test("창이 문서 일부면 오프셋이 창 시작만큼 당겨진다")
    func convertsAbsoluteOffsetIntoTheWindow() {
        let text = FocusedText(
            selection: NSRange(location: 1_002, length: 0), characterCount: 5_000,
            window: "ab\ncd", windowRange: NSRange(location: 1_000, length: 5))

        #expect(text.caretOffsetInWindow == 2)
        #expect(text.isAtDocumentStart == false)
        #expect(text.isAtDocumentEnd == false)
        #expect(text.isAtLineEnd, "창 안 오프셋 2가 개행이다")
        #expect(text.isAtLineStart == false)
    }

    /// 캐럿이 창 밖이면 그 창을 근거로 쓸 수 없다 — 증명 실패는 전부 "정확화하지 않음"이다.
    @Test("창 밖 캐럿은 증명 불가")
    func caretOutsideTheWindowProvesNothing() {
        let text = FocusedText(
            selection: NSRange(location: 10, length: 0), characterCount: 5_000,
            window: "ab\ncd", windowRange: NSRange(location: 1_000, length: 5))

        #expect(text.caretOffsetInWindow == nil)
        #expect(text.isAtLineStart == false)
        #expect(text.isAtLineEnd == false)
    }

    /// 창 텍스트 길이와 `windowRange`가 어긋나면 인덱싱이 통째로 밀린다 — 그 창은 버린다.
    /// (아래 `isAtDocumentEnd`도 같은 이유로 창이 문서 끝에 닿았다는 방증을 요구한다.)
    @Test("창 길이가 자기 범위와 어긋나면 증명 불가")
    func inconsistentWindowLengthProvesNothing() {
        let text = FocusedText(
            selection: NSRange(location: 4, length: 0), characterCount: 40,
            window: "the quick brown fox", windowRange: NSRange(location: 0, length: 19))

        #expect(text.caretOffsetInWindow == 4, "길이는 맞다 — 여기까지는 증명된다")
        #expect(text.isAtLineEnd == false, "오른쪽에 개행이 없다고 줄 끝인 것은 아니다")

        let mismatched = FocusedText(
            selection: NSRange(location: 4, length: 0), characterCount: 40,
            window: "the quick brown fox", windowRange: NSRange(location: 0, length: 30))

        #expect(mismatched.caretOffsetInWindow == nil)
        #expect(mismatched.isAtLineEnd == false)
    }

    /// `AXNumberOfCharacters`를 선택 범위와 어긋나게 보고하는 앱(Chromium·Electron 계열)에서
    /// `>=` 비교는 "항상 문서 끝"이 되어 그 앱의 편집 키를 영구히 삼킨다.
    @Test("캐럿이 보고된 문서 길이를 넘어서면 문서 끝이 아니다")
    func caretPastReportedLengthIsNotDocumentEnd() {
        let text = FocusedText(
            selection: NSRange(location: 12, length: 0), characterCount: 5,
            window: twoLines, windowRange: NSRange(location: 0, length: 5))

        #expect(text.isAtDocumentEnd == false)
    }

    /// 창이 문서 끝에 닿지 않았는데 `characterCount`만 맞아떨어지는 보고도 증명이 아니다.
    @Test("창이 문서 끝에 닿아야 문서 끝이다")
    func documentEndRequiresTheWindowToReachIt() {
        let text = FocusedText(
            selection: NSRange(location: 40, length: 0), characterCount: 40,
            window: "the quick brown fox", windowRange: NSRange(location: 0, length: 19))

        #expect(text.isAtDocumentEnd == false)
    }

    /// **UTF-16 정합** — `Character` 단위로 인덱싱하면 이모지가 있는 창에서 개행 위치가 밀려
    /// "잘못 정확화"(안전하지 않은 방향)가 된다. 이모지 하나가 UTF-16 2단위다.
    @Test("이모지가 있어도 개행 위치가 밀리지 않는다")
    func indexesInUTF16Units() {
        // "👍ab\ncd" — 👍0..1, a2, b3, \n4, c5, d6. 문서 끝은 7.
        let document = "👍ab\ncd"
        #expect(document.utf16.count == 7)
        #expect(document.count == 6, "Character 단위로 세면 하나 짧다 — 밀림의 원인")

        #expect(focusedText(document, caret: 4).isAtLineEnd, "개행 직전")
        #expect(focusedText(document, caret: 5).isAtLineStart, "개행 직후")
        #expect(focusedText(document, caret: 3).isAtLineEnd == false)
        #expect(focusedText(document, caret: 4).isAtLineStart == false)

        // 거리 질의도 같은 단위여야 한다 — `Character` 단위면 clamp가 한 타 어긋난다.
        #expect(focusedText(document, caret: 2).charactersToLineEnd == 2, "a,b 두 글자")
        #expect(focusedText(document, caret: 2).charactersToLineStart == 2, "👍는 2단위")
    }

    /// 창이 문서 시작·끝에 닿지 않으면 줄이 어디서 끊기는지 증명할 수 없다 — `nil`이 답이고,
    /// **창 끝을 줄 끝으로 착각하면 clamp가 엉뚱한 수만큼 자른다**(덜 자르는 쪽이 아니다).
    @Test("창이 문서 경계에 안 닿으면 개행 없는 줄은 증명 불가")
    func lineDistancesNeedTheWindowToReachTheDocumentEdge() {
        // 창이 문서 한가운데를 잘라 온 모양 — 안에 개행이 하나도 없다.
        let text = FocusedText(
            selection: NSRange(location: 1_004, length: 0), characterCount: 5_000,
            window: "the quick brown fox", windowRange: NSRange(location: 1_000, length: 19))

        #expect(text.charactersToLineEnd == nil)
        #expect(text.charactersToLineStart == nil)
        #expect(text.linesAboveCaret == nil)
        #expect(text.isOnLastLine == false)
        #expect(text.provesNoWordStartAhead == false)
        #expect(text.isAtLineFirstNonBlank == false)

        // 같은 창에 개행이 **있으면** 그 방향만 증명된다.
        let withNewline = FocusedText(
            selection: NSRange(location: 1_004, length: 0), characterCount: 5_000,
            window: "the\nquick brown fox", windowRange: NSRange(location: 1_000, length: 19))

        #expect(withNewline.charactersToLineStart == 0, "개행 직후다")
        #expect(withNewline.charactersToLineEnd == nil, "오른쪽 개행은 여전히 못 봤다")
        #expect(withNewline.linesAboveCaret == nil, "창이 문서 시작에 안 닿아 셀 수 없다")
    }

    /// `dk`가 Vim처럼 무효인지를 가르는 근거 — 창 안의 개행만 세면 항상 실제보다 적게 나와
    /// 멀쩡한 `dk`를 삼키므로, 문서 시작에 닿은 창에서만 답한다.
    @Test("위 줄 수는 문서 시작에 닿은 창에서만 센다")
    func countsLinesAboveOnlyFromTheDocumentStart() {
        let document = "one\ntwo\nthree"

        #expect(focusedText(document, caret: 1).linesAboveCaret == 0, "첫 줄")
        #expect(focusedText(document, caret: 4).linesAboveCaret == 1, "둘째 줄 시작")
        #expect(focusedText(document, caret: 8).linesAboveCaret == 2, "셋째 줄 시작")
        #expect(focusedText(document, caret: 3).linesAboveCaret == 0, "첫 줄 끝 — 개행은 아직 앞이 아니다")
    }

    /// 엣지 3의 조건 — 캐럿 뒤에 "공백류 다음 비공백"이 하나도 없어야 참이다.
    /// 캐럿 **바로 위**의 단어 시작은 세지 않는다: `w`는 다음 단어로 가므로 그것은 현재 단어다.
    @Test("다음 단어 시작 부재는 문서 끝까지 봐야 증명된다")
    func provesNoWordStartOnlyWithinTheLastWord() {
        let document = "foo bar baz"

        #expect(focusedText(document, caret: 9).provesNoWordStartAhead, "마지막 단어 안 (ba|z)")
        #expect(focusedText(document, caret: 8).provesNoWordStartAhead, "마지막 단어 시작 (|baz)")
        #expect(focusedText(document, caret: 11).provesNoWordStartAhead, "문서 끝")
        #expect(focusedText(document, caret: 7).provesNoWordStartAhead == false, "공백 위 — 뒤에 baz")
        #expect(focusedText(document, caret: 5).provesNoWordStartAhead == false, "b|ar — 뒤에 baz")

        // 끝 공백은 단어가 아니다 — 마지막 단어 안에서는 여전히 참이다.
        #expect(focusedText("foo baz   ", caret: 6).provesNoWordStartAhead, "ba|z + 끝 공백")
        // 개행도 단어 경계다 — 아래 줄에 단어가 있으면 거짓이다.
        #expect(focusedText("foo baz\nqux", caret: 6).provesNoWordStartAhead == false)
    }

    /// `^` 억제의 조건. 전부 공백인 줄은 **거짓**이다 — 그 줄에서 `^`는 no-op이 아니라
    /// 다음 줄까지 넘어가는 별건의 오동작이라, 참을 내면 진짜 편집을 삼킨다.
    @Test("첫 비공백 판정은 들여쓰기를 건너뛴 자리 하나뿐이다")
    func detectsTheFirstNonBlankOfTheLine() {
        let document = "\t  foo\n   \nbar"

        #expect(focusedText(document, caret: 3).isAtLineFirstNonBlank, "\\t·공백2 뒤 f 앞")
        #expect(focusedText(document, caret: 0).isAtLineFirstNonBlank == false, "들여쓰기 위")
        #expect(focusedText(document, caret: 4).isAtLineFirstNonBlank == false, "f 다음")
        #expect(focusedText(document, caret: 6).isAtLineFirstNonBlank == false, "줄 끝 — 개행 위")
        #expect(focusedText(document, caret: 7).isAtLineFirstNonBlank == false, "전부 공백인 줄")
        #expect(focusedText(document, caret: 10).isAtLineFirstNonBlank == false, "전부 공백인 줄의 끝")
        #expect(focusedText(document, caret: 11).isAtLineFirstNonBlank, "마지막 줄 (|bar)")
        #expect(focusedText(document, caret: 14).isAtLineFirstNonBlank == false, "문서 끝")
    }
}

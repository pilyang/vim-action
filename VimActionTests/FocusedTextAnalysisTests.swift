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
        isAtLineStart: false, isAtLineEnd: false),
    .init(
        name: "문서 시작 (|ab)", text: focusedText(twoLines, caret: 0),
        caretOffsetInWindow: 0, isAtDocumentStart: true, isAtDocumentEnd: false,
        isAtLineStart: true, isAtLineEnd: false),
    .init(
        name: "첫 줄 끝 — 개행 직전 (ab|\\n)", text: focusedText(twoLines, caret: 2),
        caretOffsetInWindow: 2, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: false, isAtLineEnd: true),
    .init(
        name: "둘째 줄 시작 — 개행 직후 (\\n|cd)", text: focusedText(twoLines, caret: 3),
        caretOffsetInWindow: 3, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: true, isAtLineEnd: false),
    .init(
        name: "문서 끝 (cd|) — 마지막 줄 끝이기도 하다", text: focusedText(twoLines, caret: 5),
        caretOffsetInWindow: 5, isAtDocumentStart: false, isAtDocumentEnd: true,
        isAtLineStart: false, isAtLineEnd: true),
    .init(
        name: "빈 문서 — 시작이자 끝", text: focusedText("", caret: 0),
        caretOffsetInWindow: 0, isAtDocumentStart: true, isAtDocumentEnd: true,
        isAtLineStart: true, isAtLineEnd: true),
    .init(
        name: "빈 줄 위 (ab\\n|\\ncd)", text: focusedText("ab\n\ncd", caret: 3),
        caretOffsetInWindow: 3, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: true, isAtLineEnd: true),
    // 선택이 살아 있으면 줄 끝 판정은 **선택 끝** 기준이다 — 시작 기준으로 보면 Visual 확장
    // 뒤의 판정이 통째로 어긋난다.
    .init(
        name: "선택 범위 (a[b]\\ncd) — 끝이 줄 끝", text: focusedText(twoLines, caret: 1, length: 1),
        caretOffsetInWindow: 1, isAtDocumentStart: false, isAtDocumentEnd: false,
        isAtLineStart: false, isAtLineEnd: true),
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
    }
}

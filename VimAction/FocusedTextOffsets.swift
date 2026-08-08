//
//  FocusedTextOffsets.swift
//  VimAction
//

import Foundation
import VimEngine

/// **AX 쓰기 경로의 오프셋 산출** — 캐럿 주변 창(`FocusedText`)에서 모션의 목표 절대 오프셋을
/// 계산하는 순수 함수 계층이다.
///
/// `FocusedTextAnalysis`의 extension으로 얹지 않고 별도 이름공간인 것이 계약이다: **런 클래스가
/// 갈린다.** Analysis는 비ASCII를 `other`로 두어 런이 길게 세어지고 정확화가 **포기**하는 쪽으로
/// 떨어지지만(그쪽의 보수 방향), 여기서는 비ASCII가 `keyword`여야 CJK 문서의 `w`·`b`·`e`가
/// 성립한다. 같은 extension에 `runClass`가 둘 공존하면 호출부가 조용히 잘못 고른다
/// (`20260808_ax-offset-layer-window-logical-lines.md`).
///
/// **UTF-16 배관은 공유한다** — 절대↔창 상대 변환과 `window.utf16.count == windowRange.length`
/// 가드는 `FocusedText.offsetInWindow`를 그대로 쓴다.
///
/// **스캔은 `Character`(grapheme cluster) 단위다.** Analysis가 UTF-16 단위인 것과 갈리는데,
/// 이유가 이 계층의 안전 규칙 그 자체다: 산출이 항상 grapheme 경계 위여야 하고(서로게이트 쌍
/// 한가운데 쓰기를 Notion은 무보정으로 받는다는 세션 1 실측 — 이 불변식이 유일한 방어선이다),
/// 줄 종결자 `\r\n`이 Swift에서 한 `Character`라 떠돌이 `\r`가 원천 소거된다. Analysis 쪽은
/// "캐럿 ±1자 술어"라 단위를 바꿀 이유가 없었다.
///
/// **읽기는 분기의 근거이지 스트로크 수의 근거가 아니다** 불변식은 여기 적용되지 않는다 —
/// 그것은 keyboard 경로 전용이고(낡은 읽기 창), AX는 읽기·쓰기가 같은 큐에서 동기라 그 창이
/// 구조적으로 없으며 오프셋이 실행 수단 그 자체다.
nonisolated enum FocusedTextOffsets {
    /// 모션 1건의 산출 — `EditKeyMapper.Refinement`·`VisualKeyMapper.Refinement` 동형의 3상태다.
    ///
    /// 2상태로 뭉치면 "무동작이 정답"인 자리(첫 줄 `k`, 줄 끝 `l`)가 keyboard로 위임돼 실제로
    /// 캐럿이 움직인다 — 정직한 스킵과 위임은 반드시 갈려야 한다.
    enum Target: Equatable, Sendable {
        /// Vim 자체가 무효 — 그 액션만 정직한 스킵이다(게시도 쓰기도 없다).
        case invalid
        /// 증명된 목표 **절대 UTF-16 오프셋** — AX 캐럿 쓰기로 간다.
        case caret(Int)
        /// 창이 답하지 못했다 — keyboard 위임. 쓰기 시도 **전**이라 이중 실행이 원리적으로
        /// 불가하며, 쓰기 시도 **후** 실패의 폴백 금지와는 별개 축이다.
        case unproven
    }

    /// 단어를 가르는 런 클래스. **비ASCII는 전부 `keyword`** 다 — `FocusedText.RunClass`와
    /// 정반대이며 그것이 이 타입이 별도 이름공간인 이유다(위 doc). 개행은 어느 런에도 속하지
    /// 않는 종결자라 이 타입으로 표현하지 않는다.
    enum RunClass: Equatable, Sendable {
        case blank
        case keyword
        case punctuation
    }

    /// 모션의 목표 캐럿 오프셋.
    ///
    /// `j`/`k`(`.lineUp`/`.lineDown`)는 **여기 오지 않는다** — 오프셋 대입이 희망 열(desired
    /// column)을 잃어 위임이 확정이다. 방어적으로 `.unproven`을 돌려준다(호출자가 실수로
    /// 넘겨도 현행 동작으로 떨어진다).
    static func caretTarget(for motion: Motion, in text: FocusedText) -> Target {
        // 살아 있는 선택 위에서는 "캐럿이 어디인가"가 애매하다 — Normal 모션의 전제가 아니므로
        // 증명하지 않는다 (정확화 표가 `selection.length == 0`만 다루는 것과 같은 규칙).
        guard text.selection.length == 0 else { return .unproven }

        switch motion {
        case .lineUp, .lineDown:
            return .unproven
        case .documentStart:
            // 상수 끝점이라 창과 무관하게 증명된다.
            return moved(from: text.selection.location, to: 0)
        case .documentEnd:
            return moved(from: text.selection.location, to: text.characterCount)
        default:
            break
        }

        guard let window = Window(text) else { return .unproven }
        switch motion {
        case .charLeft:
            return window.result(window.charLeft())
        case .charRight, .charRightForAppend:
            // 캐럿 모델에서 `l`과 `a`의 목표는 같다 — "마지막 글자 위 vs 뒤"의 구분은 블록
            // 커서 모델에서만 존재하고, 이 프로젝트는 줄 끝 어휘 셋 밖에서는 캐럿 모델이다.
            return window.result(window.charRight())
        case .wordForward:
            return window.result(window.wordForward())
        case .wordBackward:
            return window.result(window.wordBackward())
        case .wordEndForward:
            return window.result(window.wordEndForward())
        case .lineStart:
            return window.result(window.lineStart())
        case .lineFirstNonBlank:
            return window.result(window.lineFirstNonBlank())
        case .lineEnd, .lineEndForAppend:
            // `$`와 `A`도 캐럿 모델에서 같은 자리다 (위 `l`/`a`와 같은 이유).
            return window.result(window.lineEnd())
        case .lineUp, .lineDown, .documentStart, .documentEnd:
            return .unproven  // 위에서 처리됨 — 도달하지 않는다.
        }
    }

    /// 절대 오프셋 목표를 3상태로 접는다 — **목표 == 현재 캐럿이면 `.invalid`** 다.
    /// no-op을 굳이 AX로 왕복시킬 이유가 없고, 화면 결과가 정직한 스킵과 같다.
    private static func moved(from caret: Int, to target: Int) -> Target {
        target == caret ? .invalid : .caret(target)
    }

    /// 창 안 스캔의 좌표계 — `Character` 인덱스와 절대 UTF-16 오프셋의 대응표다.
    ///
    /// 인덱스는 **문자 사이 위치**라 `0...characters.count` 범위이고, `offsets[i]`가 그 위치의
    /// 절대 오프셋이다(마지막 원소는 창 끝). 산출이 이 배열의 원소로만 나오는 것이 "항상
    /// grapheme 경계 위" 불변식의 구현이다.
    private struct Window {
        /// 스캔 결과 — 인덱스이거나, 창이 답하지 못했거나, Vim 무효다.
        enum Step {
            case index(Int)
            case invalid
            case unproven
        }

        let characters: [Character]
        let offsets: [Int]
        /// 캐럿의 문자 인덱스. 캐럿이 grapheme 경계 위가 아니면 창을 만들지 않는다(아래 init).
        let caret: Int
        let reachesDocumentStart: Bool
        let reachesDocumentEnd: Bool

        init?(_ text: FocusedText) {
            // 창 길이 일치 가드와 범위 확인은 Analysis와 공유한다 — 통과했다는 것 자체가
            // "이 창을 근거로 써도 된다"의 증명이라 반환된 상대 오프셋은 여기서 쓰지 않는다.
            guard text.offsetInWindow(text.selection.location) != nil else { return nil }

            var characters: [Character] = []
            var offsets: [Int] = []
            var cursor = 0
            characters.reserveCapacity(text.window.count)
            offsets.reserveCapacity(text.window.count + 1)
            for character in text.window {
                offsets.append(text.windowRange.location + cursor)
                characters.append(character)
                cursor += character.utf16.count
            }
            offsets.append(text.windowRange.location + cursor)

            // 캐럿이 경계 위가 아니면(서로게이트 쌍 한가운데 등) 이 창으로는 아무것도 증명하지
            // 않는다 — 보정해서 진행하면 "정확하게 엉뚱한 자리"를 쓴다.
            guard let caret = offsets.firstIndex(of: text.selection.location) else { return nil }

            self.characters = characters
            self.offsets = offsets
            self.caret = caret
            self.reachesDocumentStart = text.windowRange.location == 0
            self.reachesDocumentEnd = text.windowRange.upperBound == text.characterCount
        }

        var count: Int { characters.count }

        func result(_ step: Step) -> Target {
            switch step {
            case .invalid: return .invalid
            case .unproven: return .unproven
            case .index(let index):
                return index == caret ? .invalid : .caret(offsets[index])
            }
        }

        // MARK: 문자 술어

        /// 줄 종결자 — `\r\n`(Swift에서 한 `Character`)·`\n`·`\r`·U+2028·U+2029.
        /// `\n` 단독 스캔은 `\r\n` 문서에서 떠돌이 `\r`를 남긴다.
        static func isLineTerminator(_ character: Character) -> Bool {
            switch character {
            case "\r\n", "\n", "\r", "\u{2028}", "\u{2029}": return true
            default: return false
            }
        }

        /// 줄 안의 공백 — 종결자는 여기 들어가지 않는다.
        static func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }

        /// 런 클래스. 종결자는 어느 런에도 속하지 않아 `nil`이다.
        static func runClass(_ character: Character) -> RunClass? {
            if isLineTerminator(character) { return nil }
            if isBlank(character) { return .blank }
            guard let ascii = character.asciiValue else {
                // **비ASCII는 전부 keyword** — CJK 문서의 `w`가 성립하는 지점이다.
                return .keyword
            }
            let isKeyword =
                (ascii >= 0x30 && ascii <= 0x39) || (ascii >= 0x41 && ascii <= 0x5A)
                || (ascii >= 0x61 && ascii <= 0x7A) || ascii == 0x5F
            return isKeyword ? .keyword : .punctuation
        }

        func isTerminator(at index: Int) -> Bool {
            index >= 0 && index < count && Self.isLineTerminator(characters[index])
        }

        // MARK: 모션

        /// `h` — 줄 시작(문서 시작 포함)에서는 Vim이 no-op이다.
        func charLeft() -> Step {
            if caret == 0 { return reachesDocumentStart ? .invalid : .unproven }
            if isTerminator(at: caret - 1) { return .invalid }
            return .index(caret - 1)
        }

        /// `l`·`a` — 줄 끝(문서 끝 포함)에서는 Vim이 no-op이다.
        func charRight() -> Step {
            if caret == count { return reachesDocumentEnd ? .invalid : .unproven }
            if isTerminator(at: caret) { return .invalid }
            return .index(caret + 1)
        }

        /// `0` — 현재 논리 줄의 시작.
        func lineStart() -> Step { lineStartIndex(from: caret) }

        /// `$`·`A` — 현재 논리 줄의 끝(종결자 앞, 마지막 줄이면 문서 끝).
        func lineEnd() -> Step { lineEndIndex(from: caret) }

        /// `^` — 줄 시작부터 첫 비공백. 줄이 전부 공백이면 줄 끝이다(Vim과 같다).
        func lineFirstNonBlank() -> Step {
            let start = lineStartIndex(from: caret)
            guard case .index(let index0) = start else { return start }
            var index = index0
            while index < count, !Self.isLineTerminator(characters[index]),
                Self.isBlank(characters[index])
            {
                index += 1
            }
            // 창 끝에서 멈췄다면 그 줄이 정말 거기서 끝나는지 알 수 없다.
            if index == count, !reachesDocumentEnd { return .unproven }
            return .index(index)
        }

        /// `w` — 현재 런을 지나 공백·개행을 건너뛴 다음 단어의 시작. 빈 줄도 정지 지점이다.
        func wordForward() -> Step {
            if caret == count { return reachesDocumentEnd ? .invalid : .unproven }
            var index = caret
            // 비공백 위에서는 그 런의 끝까지 먼저 나간다.
            if let own = Self.runClass(characters[index]), own != .blank {
                while index < count, Self.runClass(characters[index]) == own { index += 1 }
                if index == count, !reachesDocumentEnd { return .unproven }
            }
            // 공백·개행 건너뛰기 — 개행 뒤에 곧바로 개행이 오면 그 빈 줄이 정지 지점이다.
            while index < count {
                let character = characters[index]
                if !Self.isLineTerminator(character), !Self.isBlank(character) { break }
                if Self.isLineTerminator(character), isTerminator(at: index + 1) {
                    return .index(index + 1)
                }
                index += 1
            }
            if index == count, !reachesDocumentEnd { return .unproven }
            return .index(index)
        }

        /// `b` — 뒤쪽 공백·개행을 건너뛴 다음 그 런의 시작.
        func wordBackward() -> Step {
            if caret == 0 { return reachesDocumentStart ? .invalid : .unproven }
            var index = caret - 1
            while index >= 0 {
                let character = characters[index]
                if !Self.isLineTerminator(character), !Self.isBlank(character) { break }
                // 빈 줄(종결자 바로 앞이 또 종결자)은 `w`와 대칭으로 정지 지점이다.
                if Self.isLineTerminator(character), index > 0, isTerminator(at: index - 1),
                    index < caret
                {
                    return .index(index)
                }
                index -= 1
            }
            if index < 0 { return reachesDocumentStart ? .index(0) : .unproven }
            guard let own = Self.runClass(characters[index]) else { return .unproven }
            while index > 0, Self.runClass(characters[index - 1]) == own { index -= 1 }
            // 런이 창 왼쪽 끝에 닿았다면 더 왼쪽으로 이어질 수 있다.
            if index == 0, !reachesDocumentStart { return .unproven }
            return .index(index)
        }

        /// `e` — 단어 마지막 글자 **뒤**(캐럿 모델 = `Opt-→` 자리). 이미 그 자리에 커서가 있으면
        /// (= 캐럿이 런의 마지막 글자 위) Vim처럼 다음 단어의 끝으로 뛴다.
        func wordEndForward() -> Step {
            if caret == count { return reachesDocumentEnd ? .invalid : .unproven }
            var index = caret
            // 런 안쪽이면 이 런의 끝, 단 마지막 글자 위면 다음 런으로 넘어간다.
            if let own = Self.runClass(characters[index]), own != .blank {
                var end = index
                while end < count, Self.runClass(characters[end]) == own { end += 1 }
                if end == count, !reachesDocumentEnd { return .unproven }
                if end > caret + 1 { return .index(end) }
                index = end
            }
            // 공백·개행을 건너뛴 다음 런의 끝.
            while index < count,
                Self.isLineTerminator(characters[index]) || Self.isBlank(characters[index])
            {
                index += 1
            }
            if index == count { return reachesDocumentEnd ? .index(count) : .unproven }
            guard let next = Self.runClass(characters[index]) else { return .unproven }
            while index < count, Self.runClass(characters[index]) == next { index += 1 }
            if index == count, !reachesDocumentEnd { return .unproven }
            return .index(index)
        }

        // MARK: 줄 경계

        private func lineStartIndex(from index: Int) -> Step {
            var scan = index
            while scan > 0 {
                if isTerminator(at: scan - 1) { return .index(scan) }
                scan -= 1
            }
            return reachesDocumentStart ? .index(0) : .unproven
        }

        private func lineEndIndex(from index: Int) -> Step {
            var scan = index
            while scan < count {
                if isTerminator(at: scan) { return .index(scan) }
                scan += 1
            }
            return reachesDocumentEnd ? .index(count) : .unproven
        }
    }
}

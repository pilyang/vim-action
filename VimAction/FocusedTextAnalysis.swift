//
//  FocusedTextAnalysis.swift
//  VimAction
//

import Foundation

/// 캐럿 주변 읽기(`FocusedText`)에서 **무상태 시퀀스를 정확화하는 데 필요한 사실**만 뽑아내는
/// 순수 파생 질의. 읽기 자체(`FocusedTextReader`)와 분리해 두는 것은 소비자가 늘어나는 쪽이
/// 여기이기 때문이다 — 경계 포화·단어 경계 정확화가 전부 이 질의들을 딛는다.
///
/// **증명하지 못하면 전부 `false`(또는 `nil`)** 라는 것이 공통 계약이다. 다섯 질의 모두
/// `false`가 "정확화하지 않음 = 현행 무상태 시퀀스"로 이어져 보수적 방향이 균일하고,
/// 그래서 "모른다"를 별도 값으로 들 이유가 없다. 반경 `windowRadius` clamp 덕분에 캐럿 양옆
/// 1자는 읽기가 성공한 이상 항상 창 안이라, 실제로 이 폴백에 빠지는 것은 자기 범위와 어긋난
/// 값을 보고하는 앱뿐이다.
///
/// **오프셋 단위는 UTF-16이다** — `selection`·`windowRange`는 AX가 준 `NSRange`이고 `window`는
/// Swift `String`이다. `String.Index`나 `Array(window)`(= `Character` 단위)로 인덱싱하면
/// 이모지·결합 문자가 있는 창에서 어긋나 개행을 오탐하고, 오탐의 방향은 "잘못 정확화"라
/// 안전하지 않다.
/// `nonisolated`가 붙어 있는 것은 소비자가 전부 게시 직렬 큐 위이기 때문이다 — 매퍼
/// (`nonisolated enum`)에서 부르므로, 이것 없이는 파생 질의마다 격리 경고가 난다.
nonisolated extension FocusedText {
    /// Vim이 단어를 가르는 런 클래스. 같은 클래스가 이어지는 구간이 하나의 런이고, `iw`는 그
    /// 런을, `cw`는 그 런의 끝까지를 대상으로 한다.
    ///
    /// **개행은 어느 런에도 속하지 않는다**(`runClass`가 `nil`) — 런 종결자다. 개행을 런에
    /// 넣으면 줄 끝의 `iw`가 개행을 지워 줄을 병합한다.
    ///
    /// 비ASCII를 `keyword`에 넣지 않고 `other`로 따로 두는 것이 요점이다: 넣으면 CJK·이모지
    /// 위에서 정확화가 **발동해** 틀리고, 따로 두면 이웃과 클래스가 같아 런 길이가 2 이상으로
    /// 세어져 **포기**한다 — 이 확장의 보수 방향과 같은 편이다.
    enum RunClass: Sendable {
        case blank
        case keyword
        case punctuation
        case other
    }
}

nonisolated extension FocusedText {
    /// 캐럿(선택 시작)의 **창 안 상대 오프셋**. 이 변환이 `windowRange`가 반환 타입에 있는
    /// 이유 그 자체다 (`20260802_focused-text-read-api-shape.md` ①).
    var caretOffsetInWindow: Int? { offsetInWindow(selection.location) }

    /// 캐럿이 문서 시작인가 — 후진 모션이 포화하는 자리다.
    var isAtDocumentStart: Bool { selection.location == 0 }

    /// 캐럿이 문서 끝인가 — 전진 모션이 포화하는 자리다.
    ///
    /// `>=`가 아니라 `==`이며, 창이 문서 끝까지 닿았다는 방증까지 함께 요구한다.
    /// `AXNumberOfCharacters`를 선택 범위와 어긋나게 보고하는 앱(Chromium·Electron 계열)에서
    /// `>=`는 "항상 문서 끝"이 되어 그 앱의 편집 키를 영구히 삼킨다.
    var isAtDocumentEnd: Bool {
        selection.upperBound == characterCount && windowRange.upperBound == characterCount
    }

    /// 캐럿이 줄 시작인가 (캐럿 직전이 개행).
    var isAtLineStart: Bool {
        if isAtDocumentStart { return true }
        guard let offset = offsetInWindow(selection.location), offset > 0 else { return false }
        return utf16Unit(at: offset - 1) == Self.newline
    }

    /// 캐럿(선택 끝)이 줄 끝인가 (그 자리가 개행).
    ///
    /// **논리 줄 기준이다.** 소프트 랩 문단에서 시각 줄의 끝은 여기서 `false`이고, `$`가
    /// 매핑되는 `Cmd-→`는 시각 줄 끝으로 간다 — 그래서 랩 문단 중간의 포화는 탐지되지 않는다.
    /// 놓치는 방향(정확화 포기 = 현행 동작)이며, 뿌리는
    /// `20260728_linewise-visual-line-wrap-accepted-edge.md`와 같다.
    var isAtLineEnd: Bool {
        if isAtDocumentEnd { return true }
        guard let offset = offsetInWindow(selection.upperBound) else { return false }
        return utf16Unit(at: offset) == Self.newline
    }

    /// 캐럿(선택 끝)에서 이 **논리 줄**의 끝까지 남은 문자 수 (개행 자체는 세지 않는다).
    ///
    /// 줄 끝 clamp의 근거다 — `Shift-→`를 이 수보다 많이 내면 개행을 집어 줄이 병합된다.
    /// 창 안에 개행이 없고 창이 문서 끝에도 닿지 않았으면 `nil`이다: 줄이 어디서 끝나는지
    /// 이 창으로는 증명할 수 없고, 모르는 채로 clamp하면 **덜 지우는 것이 아니라 엉뚱한 수만큼**
    /// 지우게 된다.
    var charactersToLineEnd: Int? {
        guard let offset = offsetInWindow(selection.upperBound) else { return nil }
        let units = windowUnits
        for index in offset..<units.count where units[index] == Self.newline {
            return index - offset
        }
        guard windowRange.upperBound == characterCount else { return nil }
        return units.count - offset
    }

    /// 캐럿(선택 시작) 앞으로 이 **논리 줄**의 시작까지 남은 문자 수. 위와 대칭이며
    /// `Shift-←`의 clamp 근거다 (Vim의 `h`는 앞 줄로 넘어가지 않는다).
    var charactersToLineStart: Int? {
        offsetInWindow(selection.location).flatMap(lineStartDistance(from:))
    }

    /// 캐럿이 놓인 줄 **위에 있는 줄의 개수**. `dk`가 Vim처럼 무효인지(위로 갈 줄이 없는지)를
    /// 가르는 근거다. 창이 문서 시작에 닿지 않으면 셀 수 없으므로 `nil`이다 — 창 안의 개행만
    /// 세면 항상 실제보다 적게 나와 멀쩡한 `dk`를 삼킨다.
    var linesAboveCaret: Int? {
        guard windowRange.location == 0, let offset = offsetInWindow(selection.location) else {
            return nil
        }
        return windowUnits[..<offset].filter { $0 == Self.newline }.count
    }

    /// 캐럿이 문서의 **마지막 줄** 위인가 — 캐럿과 문서 끝 사이에 개행이 없다.
    /// `dgg`의 선행 `↓`가 줄 끝으로 포화해 마지막 줄을 범위에서 빠뜨리는 자리다.
    var isOnLastLine: Bool {
        guard let remaining = charactersToLineEnd else { return false }
        return selection.upperBound + remaining == characterCount
    }

    /// 캐럿 뒤 문서 끝까지 **다음 단어 시작이 없음**을 증명했는가.
    ///
    /// `w`의 3타(`Opt-→ ×2, Opt-←`)가 선택을 반전시키는 조건이다 — 두 전진이 문서 끝에서
    /// 포화하면 마지막 후퇴가 앵커를 지나쳐 캐럿 **왼쪽**을 잡는다.
    ///
    /// 단어 시작은 "공백류(space·tab·개행) 다음의 비공백"으로만 본다. macOS `Opt-→`의 단어
    /// 개념(구두점을 경계로 본다)보다 **좁게** 잡는 것이 의도다: 좁게 보면 실제로는 단어가
    /// 있는데 없다고 볼 위험이 아니라 그 반대 — 있다고 보고 정확화를 포기하는 쪽으로 틀린다.
    /// 이름이 `hasWordStartAhead`가 아닌 이유도 같다: **`false`가 항상 "정확화하지 않음"** 이라야
    /// 이 확장의 보수 방향이 균일하다.
    var provesNoWordStartAhead: Bool {
        guard windowRange.upperBound == characterCount,
            let offset = offsetInWindow(selection.upperBound)
        else { return false }
        let units = windowUnits
        // `offset + 1`부터 보는 것이 요점 — 캐럿 바로 위의 단어 시작은 `w`가 이미 지나친
        // **현재** 단어다 (`w`는 다음 단어로 간다).
        for index in stride(from: offset + 1, to: units.count, by: 1)
        where !Self.isWhitespace(units[index]) && Self.isWhitespace(units[index - 1]) {
            return false
        }
        return true
    }

    /// 캐럿이 이 줄의 **첫 비공백 문자** 바로 앞인가 — `^`가 제자리인 유일한 자리다.
    ///
    /// 전부 공백인 줄에서는 `false`다(첫 비공백이 없다). 그 줄에서 `^`는 no-op이 아니라
    /// 다음 줄의 단어까지 넘어가는 **별건의 오동작**이라, 여기서 참을 내면 진짜 편집을 삼킨다.
    var isAtLineFirstNonBlank: Bool {
        guard let before = charactersToLineStart, let offset = offsetInWindow(selection.location),
            let unit = utf16Unit(at: offset), !Self.isWhitespace(unit)
        else { return false }
        return windowUnits[(offset - before)..<offset].allSatisfy { Self.isBlank($0) }
    }

    /// 캐럿 위 문자의 런이 **정확히 1자**임을 증명했는가 — `iw`가 `Shift-→` 1타로 끝나는 조건.
    ///
    /// 공백 1칸, 1자 구두점(`.`·`,`·`(`), 1자 단어가 전부 여기다. 런 길이가 2 이상이면 그만큼
    /// 스트로크를 내야 하는데 그것은 오프셋 비례라 채택하지 않는다
    /// (`20260803_refinement-branches-not-stroke-counts.md`) — 현행 3타로 간다.
    var caretRunIsSingleCharacter: Bool {
        guard let offset = offsetInWindow(selection.location), let own = runClass(at: offset)
        else { return false }
        return runEnds(leftOf: offset, own) && runEnds(rightOf: offset, own)
    }

    /// 캐럿 위 문자가 그 런의 **마지막 글자**임을 증명했는가 — `cw`(= `ce`)가 그 한 글자로
    /// 끝나는 조건이다. 공백 런에서도 참이 옳다: 공백 위의 `cw`는 다음 단어 시작까지 바꾸므로,
    /// 런의 마지막 공백에서는 그것이 곧 그 한 칸이다.
    var caretIsAtRunEnd: Bool {
        guard let offset = offsetInWindow(selection.location), let own = runClass(at: offset)
        else { return false }
        return runEnds(rightOf: offset, own)
    }

    /// 캐럿(선택 시작) 위 문자가 **단어 시작**임을 증명했는가 — `vb` 재앵커가 `Shift-Opt-←`를
    /// ×2로 늘리는 조건이다. Vim의 `b`는 커서가 단어 시작이면 **이전** 단어 시작으로 뛰는데,
    /// macOS의 1타는 그 자리로 돌아올 뿐이라 선택이 자라지 않는다.
    ///
    /// 단어 시작의 정의는 `provesNoWordStartAhead`와 같은 좁은 것("공백류 다음의 비공백")이다 —
    /// macOS `Opt-←`도 공백 경계에서는 확실히 멈추므로 이 좁은 정의에서만 ×2의 동치가 선다.
    /// 구두점 경계는 앱마다 갈려 증명이 서지 않고, `false`는 ×1(덜 후진 — 보이는 편차)로
    /// 떨어져 보수 방향이 유지된다.
    var caretIsAtWordStart: Bool {
        guard let offset = offsetInWindow(selection.location),
            let unit = utf16Unit(at: offset), !Self.isWhitespace(unit)
        else { return false }
        guard offset > 0 else { return windowRange.location == 0 }
        return utf16Unit(at: offset - 1).map(Self.isWhitespace) ?? false
    }

    /// 선택 끝 위치에 문자가 존재함을 증명했는가 (개행 포함) — `Vj`가 포커스 줄 거리를 +1로
    /// 넓히기 전의 근거다. 문서 끝에서는 `Shift-↓`가 포화해 화면은 안 움직이는데 거리만 늘면
    /// `V`→`v`가 낡은 거리로 어긋난다. 창이 그 위치에 닿지 않으면 증명 실패(= 정확화 포기)다.
    var provesCharacterAfterSelectionEnd: Bool {
        guard let offset = offsetInWindow(selection.upperBound) else { return false }
        return utf16Unit(at: offset) != nil
    }

    /// 선택 끝이 **줄 시작**(직전이 개행)임을 증명했는가 — `Vk` 재앵커의 `→` collapse가
    /// 열 0에 착지함을 요구하는 근거다. 개행 없는 마지막 줄에서는 거짓이라, 재앵커의
    /// `Shift-↑`가 열을 끌고 올라가 부분 줄을 선택하는 것을 막는다.
    var selectionEndIsAtLineStart: Bool {
        guard let offset = offsetInWindow(selection.upperBound), offset > 0 else {
            return false
        }
        return utf16Unit(at: offset - 1) == Self.newline
    }

    /// 선택 **내부**의 개행 수 — 선택이 창 안에 완전히 들어올 때만 증명된다. `v`→`V` 반올림이
    /// 앵커 줄에서 포커스 줄까지 재확장할 줄 거리가 이것이다.
    var newlinesInsideSelection: Int? {
        guard let lower = offsetInWindow(selection.location),
            let upper = offsetInWindow(selection.upperBound)
        else { return nil }
        return windowUnits[lower..<upper].filter { $0 == Self.newline }.count
    }

    /// 선택 시작에서 **증명된 개행**까지의 거리 (개행 자체는 세지 않는다). `charactersToLineEnd`
    /// 와 달리 문서 끝 폴백이 없다 — 개행의 존재 자체가 필요한 소비자(`Vgg` 재앵커의 앵커 줄 끝
    /// 다음 계산)용이라, 창 안에 개행이 없으면 마지막 줄이든 창 부족이든 `nil`이다.
    var newlineDistanceAfterSelectionStart: Int? {
        guard let offset = offsetInWindow(selection.location) else { return nil }
        return provenNewlineDistance(from: offset)
    }

    /// 위와 같되 선택 **끝** 기준 — `v`→`V` 후진형이 앵커 줄 끝을 증명하는 근거다.
    var newlineDistanceAfterSelectionEnd: Int? {
        guard let offset = offsetInWindow(selection.upperBound) else { return nil }
        return provenNewlineDistance(from: offset)
    }

    /// 선택 **끝** 기준, 그 줄의 시작까지의 문자 수 — `charactersToLineStart`(선택 시작 기준)의
    /// 끝쪽 대칭이다. `v`→`V` 후진형이 앵커 줄 시작(논리 앵커)을 계산하는 근거다.
    var selectionEndCharactersToLineStart: Int? {
        offsetInWindow(selection.upperBound).flatMap(lineStartDistance(from:))
    }

    /// 선택 안의 **마지막 줄**의 길이 — `V`→`v` 전진형 재선택이 "포커스 줄에 목표 열의 문자가
    /// 실재하는가"를 묻는 근거다. 선택 끝이 줄 시작이면(V형 — 개행까지 포함) 그 **앞** 줄이고,
    /// 선택 끝이 문서 끝이면(개행 없는 마지막 줄로 포화) 끝이 속한 줄이다. 어느 쪽도 증명하지
    /// 못하면 `nil` — 그 줄이 어디서 시작하는지 창으로 알 수 없다.
    var selectionLastLineLength: Int? {
        guard let offset = offsetInWindow(selection.upperBound) else { return nil }
        if offset > 0, utf16Unit(at: offset - 1) == Self.newline {
            return lineStartDistance(from: offset - 1)
        }
        guard isAtDocumentEnd else { return nil }
        return lineStartDistance(from: offset)
    }

    /// 창 안 상대 오프셋에서 다음 개행까지의 거리 — 개행을 **찾은 경우에만** 값이 있다
    /// (문서 끝 폴백 없음).
    private func provenNewlineDistance(from offset: Int) -> Int? {
        let units = windowUnits
        for index in offset..<units.count where units[index] == Self.newline {
            return index - offset
        }
        return nil
    }

    /// 창 안 상대 오프셋에서 그 줄의 시작까지의 거리 — 위의 후진 대칭이되, 창 시작이 문서
    /// 시작에 닿은 경우만 줄 시작으로 인정하는 폴백이 있다 (`charactersToLineStart` 원형).
    private func lineStartDistance(from offset: Int) -> Int? {
        let units = windowUnits
        for index in stride(from: offset, to: 0, by: -1) where units[index - 1] == Self.newline {
            return offset - index
        }
        guard windowRange.location == 0 else { return nil }
        return offset
    }

    /// 캐럿이 논리 줄 끝(문서 끝 포함)일 때 **직전 문자**의 런 클래스. 줄 끝이 아니거나 직전이
    /// 개행이거나 증명할 수 없으면 `nil`.
    ///
    /// 캐럿이 줄 끝이면 Vim 커서는 **마지막 글자 위**이므로 `iw`·`cw`의 대상은 그 글자의 런이다
    /// (`20260803_line-end-charwise-vim-cursor-model.md`의 모델을 이 한 자리에서 단어 어휘까지
    /// 넓힌다). 그러지 않으면 `$` 뒤의 `diw`가 **다음 줄의 첫 단어를 파괴한다**.
    var runClassBeforeLineEnd: RunClass? {
        guard isAtLineEnd, let offset = offsetInWindow(selection.upperBound), offset > 0
        else { return nil }
        return runClass(at: offset - 1)
    }

    /// 창 안 상대 오프셋 위치 문자의 런 클래스. 문자가 없거나 개행이면 `nil`.
    private func runClass(at offset: Int) -> RunClass? {
        utf16Unit(at: offset).flatMap(Self.runClass)
    }

    /// 오프셋 왼쪽에서 런 `own`이 끝남을 증명했는가. 창 끝이면 **문서 경계에 닿았을 때만**
    /// 경계로 인정한다 — 닿지 않았으면 잘린 런의 나머지가 창 밖에 있을 수 있다.
    private func runEnds(leftOf offset: Int, _ own: RunClass) -> Bool {
        guard offset > 0 else { return windowRange.location == 0 }
        return runClass(at: offset - 1) != own
    }

    /// 위의 대칭.
    private func runEnds(rightOf offset: Int, _ own: RunClass) -> Bool {
        guard offset + 1 < window.utf16.count else {
            return windowRange.upperBound == characterCount
        }
        return runClass(at: offset + 1) != own
    }

    /// 절대 오프셋 → 창 안 상대 오프셋. 창 텍스트의 길이가 `windowRange`와 어긋나면 그 창을
    /// 근거로 쓸 수 없으므로 `nil`이다 — 어긋난 채로 인덱싱하면 개행 위치가 통째로 밀린다.
    ///
    /// `internal`인 것은 **AX 오프셋 계층(`FocusedTextOffsets`)과 공유**하기 때문이다 — 특히
    /// 위의 길이 일치 가드는 두 계층이 같은 것을 써야 한다. 런 클래스만은 공유하지 않는다
    /// (그쪽 doc 참조 — 비ASCII 취급이 정반대다).
    func offsetInWindow(_ location: Int) -> Int? {
        guard window.utf16.count == windowRange.length else { return nil }
        let offset = location - windowRange.location
        // 상한이 `length`인 것은 오프셋이 문자가 아니라 **문자 사이 위치**이기 때문이다.
        guard (0...windowRange.length).contains(offset) else { return nil }
        return offset
    }

    /// 창 안 상대 오프셋 위치의 UTF-16 단위. 창 끝(= 문자가 없는 위치)이면 `nil`.
    private func utf16Unit(at offset: Int) -> UInt16? {
        let units = window.utf16
        guard offset >= 0, offset < units.count else { return nil }
        return units[units.index(units.startIndex, offsetBy: offset)]
    }

    /// 창 텍스트의 UTF-16 단위 배열. `String.UTF16View`는 인덱스 이동이 선형이라 스캔에
    /// 그대로 쓰면 O(n²)가 된다 — 창은 반경 clamp로 최대 ~512단위라 한 번 펼치는 편이 싸다.
    private var windowUnits: [UInt16] { Array(window.utf16) }

    /// 줄 안의 들여쓰기 문자 — 개행은 줄 경계라 여기 들어가지 않는다.
    private static func isBlank(_ unit: UInt16) -> Bool { unit == space || unit == tab }

    /// 단어 경계로 보는 공백류 — `w`는 줄을 넘어가므로 개행도 포함한다.
    private static func isWhitespace(_ unit: UInt16) -> Bool { isBlank(unit) || unit == newline }

    /// UTF-16 단위 → 런 클래스. 개행은 런 종결자라 `nil`이다.
    private static func runClass(_ unit: UInt16) -> RunClass? {
        if unit == newline { return nil }
        if isBlank(unit) { return .blank }
        guard unit < 0x80 else { return .other }
        return isKeyword(unit) ? .keyword : .punctuation
    }

    /// Vim의 기본 `iskeyword`에 맞춘 ASCII 영숫자와 `_`. 비ASCII는 여기 오지 않는다 — 서로게이트
    /// 쌍을 단위 하나로 판정할 수 없어 `other`로 빠지고, 그쪽이 포기(= 현행 시퀀스)다.
    private static func isKeyword(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        default: return unit == underscore
        }
    }

    private static let newline = UInt16(UnicodeScalar("\n").value)
    private static let space = UInt16(UnicodeScalar(" ").value)
    private static let tab = UInt16(UnicodeScalar("\t").value)
    private static let underscore = UInt16(UnicodeScalar("_").value)
}

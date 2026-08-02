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
        guard let offset = offsetInWindow(selection.location) else { return nil }
        let units = windowUnits
        for index in stride(from: offset, to: 0, by: -1) where units[index - 1] == Self.newline {
            return offset - index
        }
        guard windowRange.location == 0 else { return nil }
        return offset
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

    /// 절대 오프셋 → 창 안 상대 오프셋. 창 텍스트의 길이가 `windowRange`와 어긋나면 그 창을
    /// 근거로 쓸 수 없으므로 `nil`이다 — 어긋난 채로 인덱싱하면 개행 위치가 통째로 밀린다.
    private func offsetInWindow(_ location: Int) -> Int? {
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

    private static let newline = UInt16(UnicodeScalar("\n").value)
    private static let space = UInt16(UnicodeScalar(" ").value)
    private static let tab = UInt16(UnicodeScalar("\t").value)
}

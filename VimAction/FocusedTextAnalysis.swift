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
extension FocusedText {
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

    private static let newline = UInt16(UnicodeScalar("\n").value)
}

//
//  ModeIndicatorColor.swift
//  VimAction
//

import AppKit
import VimEngine

/// 인디케이터 색의 **순수 계층** — 저장 문자열 ↔ 색 변환과 모드→색 표다. 화면도 UserDefaults도
/// 모르고(소유·영속·반영은 `ModeIndicatorController`), 그래서 전부 표로 검증된다.
///
/// 저장 형식이 sRGB `#RRGGBBAA` 문자열인 이유: `defaults`로 읽고 쓸 수 있고, 파싱·직렬화가 순수
/// 함수이며, 외양(라이트/다크)에 묶이지 않는다 (`20260916_mode-indicator-per-mode-colors.md`).
nonisolated enum ModeIndicatorColor {
    /// 저장 문자열 → 색. `#` + 정확히 8자리 hex만 받고 대소문자는 관용한다 — 사용자가
    /// `defaults write`로 직접 넣을 수 있는 값이라서다. 그 밖은 전부 `nil`(= 미설정 = 강조색):
    /// 못 읽는 값 하나 때문에 인디케이터가 안 뜨는 일은 없어야 한다.
    ///
    /// `UInt32(_:radix:)`가 부호(`+FFFFFFF`)를 받아 주므로 **hex 자릿수 검사가 따로 필요하다**.
    static func color(fromHex hex: String) -> NSColor? {
        let digits = hex.dropFirst()
        guard hex.count == 9, hex.hasPrefix("#"), digits.allSatisfy(\.isHexDigit),
            let value = UInt32(digits, radix: 16)
        else { return nil }
        func component(_ shift: UInt32) -> CGFloat {
            CGFloat((value >> shift) & 0xFF) / 255
        }
        return NSColor(
            srgbRed: component(24), green: component(16), blue: component(8), alpha: component(0))
    }

    /// 색 → 저장 문자열. sRGB로 옮길 수 없는 색(패턴·이미지 색)은 `nil`이다.
    ///
    /// **성분 clamp가 계약이다**: `ColorPicker`는 Display P3 색을 주고, sRGB 변환은 색역 밖 성분을
    /// 음수나 1 초과로 돌려준다. 그대로 `%02X`에 넣으면 8자리가 아닌 문자열이 나와 다시 읽히지
    /// 않는다 — 저장은 됐는데 다음 실행에 미설정으로 돌아간다.
    static func hex(from color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X%02X", byte(srgb.redComponent), byte(srgb.greenComponent),
            byte(srgb.blueComponent), byte(srgb.alphaComponent))
    }

    /// 모드 → 사용자 색. `nil`이면 시스템 강조색으로 그린다(미설정의 표현이다).
    ///
    /// 세 모드가 같은 규칙을 탄다 — 모델에 예외가 없다("모드별 색, 미설정은 강조색").
    /// Insert에는 상시 표시가 없으므로 그 색이 보이는 곳은 전환 순간의 INSERT flash뿐이고
    /// (`20260916_mode-indicator-insert-color.md`), VISUAL·V-LINE은 한 색을 나눠 쓴다: 둘은 같은
    /// 모드 계열이고, 색은 모드 계열을 가르는 두 번째 신호다(첫째는 항상 동반되는 라벨).
    static func color(for mode: Mode, normal: NSColor?, insert: NSColor?, visual: NSColor?)
        -> NSColor?
    {
        switch mode {
        case .normal: normal
        case .insert: insert
        case .visualChar, .visualLine: visual
        }
    }
}

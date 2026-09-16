//
//  ModeIndicatorColorTests.swift
//  VimActionTests
//

import AppKit
import Foundation
import Testing
import VimEngine

@testable import VimAction

/// 저장 문자열 ↔ 색 변환 — 순수 함수라 표로 고정한다. 값은 `defaults write`로 사용자가 직접
/// 넣을 수 있으므로 **관용(대소문자)과 거절(그 밖 전부)의 경계가 곧 계약**이다.
struct ModeIndicatorColorHexTests {
    @Test("hex 왕복 — 파싱한 색을 다시 쓰면 같은 문자열")
    func roundTripsThroughColor() throws {
        for hex in ["#FF8000CC", "#00000000", "#FFFFFFFF", "#123456AB"] {
            let color = try #require(ModeIndicatorColor.color(fromHex: hex))
            #expect(ModeIndicatorColor.hex(from: color) == hex)
        }
    }

    /// 손으로 쓴 값이 소문자인 것은 흔하다 — 읽어 주되 쓸 때는 한 형태(대문자)로 모은다.
    @Test("소문자 입력을 읽고 대문자로 직렬화한다")
    func lowercaseInputNormalizesToUppercase() throws {
        let color = try #require(ModeIndicatorColor.color(fromHex: "#ff8000cc"))
        #expect(ModeIndicatorColor.hex(from: color) == "#FF8000CC")
    }

    @Test("성분 순서는 RGBA다")
    func componentsAreRedGreenBlueAlpha() throws {
        let color = try #require(ModeIndicatorColor.color(fromHex: "#FF000080"))
        let srgb = try #require(color.usingColorSpace(.sRGB))
        #expect(srgb.redComponent == 1)
        #expect(srgb.greenComponent == 0)
        #expect(srgb.blueComponent == 0)
        #expect(abs(srgb.alphaComponent - 128.0 / 255) < 0.0001)
    }

    /// 못 읽는 값은 전부 미설정(강조색)으로 접힌다 — 오타 하나로 인디케이터가 사라지면 안 된다.
    /// `#+FFFFFFF`가 표에 있는 이유: `UInt32(_:radix:)`는 부호를 받아 주므로 자릿수 검사가 없으면
    /// 조용히 통과한다.
    @Test("잘못된 입력은 전부 nil")
    func malformedInputIsRejected() {
        for hex in [
            "FF8000CC", "#FF8000", "#FF8000CCC", "#GGGGGGGG", "", "#", "#+FFFFFFF", "#FF8000C",
        ] {
            #expect(ModeIndicatorColor.color(fromHex: hex) == nil, "\(hex)")
        }
    }

    /// `ColorPicker`는 Display P3 색을 준다 — sRGB 변환이 색역 밖 성분(음수·1 초과)을 내므로
    /// clamp가 없으면 `%02X`가 8자리가 아닌 문자열을 만들어 **저장은 되는데 다시 읽히지 않는다**.
    @Test("색역 밖 색도 유효한 8자리로 직렬화되고 다시 읽힌다")
    func outOfGamutColorSerializesAndParsesBack() throws {
        let p3 = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        let hex = try #require(ModeIndicatorColor.hex(from: p3))
        #expect(hex.count == 9)
        #expect(hex.hasPrefix("#"))
        // `#expect` 안에서 `allSatisfy`를 부르면 매크로 확장이 rethrows를 잃는다 — 밖에서 값을
        // 만들어 넘긴다.
        let digitsAreHex = hex.dropFirst().allSatisfy(\.isHexDigit)
        #expect(digitsAreHex)
        #expect(ModeIndicatorColor.color(fromHex: hex) != nil)
    }
}

/// 모드 → 색 표. 세 모드가 같은 규칙을 타고(모델에 예외가 없다) VISUAL·V-LINE만 한 색을 나눠
/// 쓰는 것이 결정이다 (`20260916_mode-indicator-per-mode-colors.md`,
/// `20260916_mode-indicator-insert-color.md`).
struct ModeIndicatorColorForModeTests {
    private let normal = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let insert = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
    private let visual = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    private func color(_ mode: Mode) -> NSColor? {
        ModeIndicatorColor.color(for: mode, normal: normal, insert: insert, visual: visual)
    }

    /// 색이 섞이면 전환이 색으로 보이지 않는다 — 셋이 각자의 색을 받는지가 표의 핵심이다.
    @Test("모드마다 자기 색, Visual 둘만 한 색을 나눠 쓴다")
    func modesMapToTheirColor() {
        #expect(color(.normal) == normal)
        #expect(color(.insert) == insert)
        #expect(color(.visualChar) == visual)
        #expect(color(.visualLine) == visual)
    }

    @Test("미설정이면 모든 모드가 nil")
    func unsetColorsFallBackForEveryMode() {
        for mode in [Mode.normal, .insert, .visualChar, .visualLine] {
            #expect(
                ModeIndicatorColor.color(for: mode, normal: nil, insert: nil, visual: nil) == nil)
        }
    }
}

/// 색의 소유·영속 — 토글·스타일과 같은 소유 모델(런타임 SSOT는 프로퍼티, didSet이 저장)이고
/// 같은 단언 함정(`object(forKey:) != nil` 선행)을 지킨다. 패널도 AX도 만들지 않는다.
@MainActor
struct ModeIndicatorColorPersistenceTests {
    /// `#FF8000CC` = (1, 0.5, 0, 0.8) — 0.5·0.8이 각각 0x80·0xCC로 떨어져 반올림까지 고정된다.
    private let orange = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.8)

    /// 기본은 값의 **부재**다 — 설정을 건드리지 않은 사용자는 지금까지와 똑같은 강조색을 본다.
    @Test("미설정 키 → 둘 다 nil")
    func defaultsToUnset() {
        withTemporaryDefaults { defaults in
            let controller = ModeIndicatorController(defaults: defaults)
            #expect(controller.normalColor == nil)
            #expect(controller.insertColor == nil)
            #expect(controller.visualColor == nil)
        }
    }

    @Test("Normal 색 영속: didSet 저장 → 새 컨트롤러 init 로드")
    func normalColorPersistsAcrossControllers() {
        withTemporaryDefaults { defaults in
            let first = ModeIndicatorController(defaults: defaults)
            first.normalColor = orange
            // 존재 확인이 먼저 — 이것 없이는 영속을 통째로 지워도 "미설정"으로 통과한다.
            #expect(
                defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorNormalColor) != nil)
            #expect(
                defaults.string(forKey: PreferenceKeys.onScreenModeIndicatorNormalColor)
                    == "#FF8000CC")

            let second = ModeIndicatorController(defaults: defaults)
            #expect(
                second.normalColor.flatMap(ModeIndicatorColor.hex(from:)) == "#FF8000CC")
        }
    }

    /// Insert에는 상시 표시가 없지만 색은 다른 둘과 같은 규칙으로 산다 — flash가 그 색을 쓴다.
    @Test("Insert 색은 별도 키에 영속된다")
    func insertColorUsesItsOwnKey() {
        withTemporaryDefaults { defaults in
            let first = ModeIndicatorController(defaults: defaults)
            first.insertColor = orange
            // 존재 확인이 먼저 — 이것 없이는 영속을 통째로 지워도 "미설정"으로 통과한다.
            #expect(
                defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorInsertColor) != nil)
            #expect(
                defaults.string(forKey: PreferenceKeys.onScreenModeIndicatorInsertColor)
                    == "#FF8000CC")
            #expect(defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorNormalColor) == nil)

            let second = ModeIndicatorController(defaults: defaults)
            #expect(second.insertColor.flatMap(ModeIndicatorColor.hex(from:)) == "#FF8000CC")
        }
    }

    /// 키가 갈려 있어야 Normal을 고르는 것이 Visual을 덮지 않는다.
    @Test("Visual 색은 별도 키에 영속된다")
    func visualColorUsesItsOwnKey() {
        withTemporaryDefaults { defaults in
            let first = ModeIndicatorController(defaults: defaults)
            first.visualColor = orange
            #expect(
                defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorVisualColor) != nil)
            #expect(defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorNormalColor) == nil)

            let second = ModeIndicatorController(defaults: defaults)
            #expect(second.visualColor.flatMap(ModeIndicatorColor.hex(from:)) == "#FF8000CC")
            #expect(second.normalColor == nil)
        }
    }

    /// "Reset to system accent"의 경로 — 키를 지워야 강조색이 **동적으로** 따라온다. 값을 남긴
    /// 채 무시하면 다음 실행에 되살아난다.
    @Test("nil로 되돌리면 키가 지워진다")
    func resettingRemovesTheKeys() {
        withTemporaryDefaults { defaults in
            let controller = ModeIndicatorController(defaults: defaults)
            controller.normalColor = orange
            controller.insertColor = orange
            controller.visualColor = orange
            controller.normalColor = nil
            controller.insertColor = nil
            controller.visualColor = nil
            #expect(defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorNormalColor) == nil)
            #expect(defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorInsertColor) == nil)
            #expect(defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorVisualColor) == nil)

            let second = ModeIndicatorController(defaults: defaults)
            #expect(second.normalColor == nil)
            #expect(second.insertColor == nil)
            #expect(second.visualColor == nil)
        }
    }

    /// 손으로 쓴 값이 깨져 있어도 인디케이터는 떠야 한다 — 미설정으로 접힌다.
    @Test("못 읽는 저장 값은 미설정으로 접힌다")
    func unreadableStoredValueFallsBackToUnset() {
        withTemporaryDefaults { defaults in
            defaults.set("neon", forKey: PreferenceKeys.onScreenModeIndicatorNormalColor)
            #expect(ModeIndicatorController(defaults: defaults).normalColor == nil)
        }
    }

    /// 토글·스타일과 같은 근거 — 입력이 밀린 적 없으면 화면에도 AX에도 닿지 않는다(패널은 첫
    /// 표시에서야 만들어진다).
    @Test("입력이 밀린 적 없으면 색 변경은 무해하다")
    func changingColorsWithoutInputsIsHarmless() {
        withTemporaryDefaults { defaults in
            let controller = ModeIndicatorController(defaults: defaults)
            controller.normalColor = orange
            controller.visualColor = nil
            #expect(controller.normalColor == orange)
            #expect(controller.visualColor == nil)
        }
    }
}

/// 사용자 색 위의 글씨 — 강조색과 같은 판정을 그대로 탄다. **알파를 보지 않는 것이 계약이다**:
/// 배경을 아무리 투명하게 해도 라벨은 불투명한 흑·백으로 남아야 한다(라벨은 항상 동반된다는
/// PRD 접근성 NFR).
@MainActor
struct ModeIndicatorUserColorTextTests {
    @Test("밝은 사용자 색은 검은 글씨로 뒤집힌다")
    func brightUserColorFlipsToBlackText() {
        #expect(
            ModeIndicatorPanel.textColor(on: NSColor(srgbRed: 1, green: 0.84, blue: 0, alpha: 1))
                == .black)
    }

    @Test("알파는 글씨색 판정을 바꾸지 않는다")
    func alphaDoesNotChangeTheVerdict() {
        for alpha in [CGFloat(0), 0.2, 1] {
            #expect(
                ModeIndicatorPanel.textColor(
                    on: NSColor(srgbRed: 1, green: 0.84, blue: 0, alpha: alpha)) == .black)
            #expect(
                ModeIndicatorPanel.textColor(
                    on: NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: alpha)) == .white)
        }
    }
}

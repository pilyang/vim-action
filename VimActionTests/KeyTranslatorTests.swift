//
//  KeyTranslatorTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine
@testable import VimAction

/// 합성 CGEvent(virtualKey + flags) → 기대 `Key` 픽스처.
///
/// 전제: 실행 머신의 ASCII-capable 키보드 레이아웃이 QWERTY(ABC/US)다.
/// Dvorak 등 다른 ASCII 레이아웃 환경에서는 문자 케이스가 실패할 수 있다.
struct KeyTranslationFixture: Sendable, CustomTestStringConvertible {
    var name: String
    var virtualKey: CGKeyCode
    var flags: CGEventFlags
    var expected: Key?

    init(_ name: String, _ virtualKey: Int, _ flags: CGEventFlags, _ expected: Key?) {
        self.name = name
        self.virtualKey = CGKeyCode(virtualKey)
        self.flags = flags
        self.expected = expected
    }

    var testDescription: String { name }
}

let keyTranslationFixtures: [KeyTranslationFixture] = [
    // 1. 특수키 4종 — keycode 기반, modifiers 없음
    .init("Esc → .escape", kVK_Escape, [], .escape),
    .init("Return → .enter", kVK_Return, [], .enter),
    .init("Tab → .tab", kVK_Tab, [], .tab),
    .init("Space → .space", kVK_Space, [], .space),

    // 2. 특수키 + modifier — escape 옵션 시나리오의 핵심 입력
    .init("Cmd+Space → space+[command]", kVK_Space, [.maskCommand], Key(.space, [.command])),
    .init("Cmd+Esc → escape+[command]", kVK_Escape, [.maskCommand], Key(.escape, [.command])),

    // 3. 단순 문자
    .init("h", kVK_ANSI_H, [], .char("h")),
    .init("j", kVK_ANSI_J, [], .char("j")),
    .init("k", kVK_ANSI_K, [], .char("k")),
    .init("l", kVK_ANSI_L, [], .char("l")),
    .init("w", kVK_ANSI_W, [], .char("w")),
    .init("g", kVK_ANSI_G, [], .char("g")),

    // 4. shift 흡수 — shift는 문자에 반영되고 modifiers에 남지 않는다
    .init("Shift+4 → $", kVK_ANSI_4, [.maskShift], .char("$")),
    .init("Shift+g → G", kVK_ANSI_G, [.maskShift], .char("G")),
    .init("Shift+6 → ^", kVK_ANSI_6, [.maskShift], .char("^")),

    // 5. modifier는 벗기고 base 문자 추출
    .init("Ctrl+D → d+[control]", kVK_ANSI_D, [.maskControl], .char("d", [.control])),
    .init("Opt+A → a+[option]", kVK_ANSI_A, [.maskAlternate], .char("a", [.option])),
    .init(
        "Cmd+Opt+F → f+[command,option]",
        kVK_ANSI_F, [.maskCommand, .maskAlternate], .char("f", [.command, .option])
    ),

    // 6. shift+modifier 동시 — shift만 문자에 반영, 나머지는 modifiers로
    .init(
        "Cmd+Shift+G → G+[command]",
        kVK_ANSI_G, [.maskCommand, .maskShift], .char("G", [.command])
    ),

    // 7. 번역 불가 → nil (호출측 무조건 통과)
    .init("Left arrow → nil", kVK_LeftArrow, [], nil),
    .init("Up arrow → nil", kVK_UpArrow, [], nil),
    .init("F1 → nil", kVK_F1, [], nil),

    // 8. caps lock 무시 — base 문자에는 shift만 반영한다
    .init("CapsLock+j → j", kVK_ANSI_J, [.maskAlphaShift], .char("j")),
]

@MainActor
struct KeyTranslatorTests {
    @Test("CGEvent(keyDown) → Key 번역", arguments: keyTranslationFixtures)
    func translate(_ fixture: KeyTranslationFixture) throws {
        let event = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: fixture.virtualKey, keyDown: true),
            "합성 CGEvent 생성 실패: \(fixture.name)"
        )
        event.flags = fixture.flags

        #expect(KeyTranslator.translate(event) == fixture.expected, "\(fixture.name)")
    }
}

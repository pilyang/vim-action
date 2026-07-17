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

/// 레이아웃과 무관하게 성립하는 케이스 — 특수키는 keycode로 직접 매칭되고,
/// 화살표/펑션 키는 어느 레이아웃에서든 비출력 문자라 nil이다.
let layoutInvariantFixtures: [KeyTranslationFixture] = [
    // 1. 특수키 4종 — keycode 기반, modifiers 없음
    .init("Esc → .escape", kVK_Escape, [], .escape),
    .init("Return → .enter", kVK_Return, [], .enter),
    .init("Tab → .tab", kVK_Tab, [], .tab),
    .init("Space → .space", kVK_Space, [], .space),

    // 2. 특수키 + modifier — escape 옵션 시나리오의 핵심 입력
    .init("Cmd+Space → space+[command]", kVK_Space, [.maskCommand], Key(.space, [.command])),
    .init("Cmd+Esc → escape+[command]", kVK_Escape, [.maskCommand], Key(.escape, [.command])),

    // 3. 번역 불가 → nil (호출측 무조건 통과)
    .init("Left arrow → nil", kVK_LeftArrow, [], nil),
    .init("Up arrow → nil", kVK_UpArrow, [], nil),
    .init("F1 → nil", kVK_F1, [], nil),
]

/// 문자 키는 현재 ASCII-capable 레이아웃으로 번역되므로, keycode↔문자 짝이
/// QWERTY 계열 레이아웃에서만 성립한다 — 비-QWERTY 머신에서는 테스트가 skip된다.
let qwertyCharacterFixtures: [KeyTranslationFixture] = [
    // 1. 단순 문자
    .init("h", kVK_ANSI_H, [], .char("h")),
    .init("j", kVK_ANSI_J, [], .char("j")),
    .init("k", kVK_ANSI_K, [], .char("k")),
    .init("l", kVK_ANSI_L, [], .char("l")),
    .init("w", kVK_ANSI_W, [], .char("w")),
    .init("g", kVK_ANSI_G, [], .char("g")),

    // 2. shift 흡수 — shift는 문자에 반영되고 modifiers에 남지 않는다
    .init("Shift+4 → $", kVK_ANSI_4, [.maskShift], .char("$")),
    .init("Shift+g → G", kVK_ANSI_G, [.maskShift], .char("G")),
    .init("Shift+6 → ^", kVK_ANSI_6, [.maskShift], .char("^")),

    // 3. modifier는 벗기고 base 문자 추출
    .init("Ctrl+D → d+[control]", kVK_ANSI_D, [.maskControl], .char("d", [.control])),
    .init("Opt+A → a+[option]", kVK_ANSI_A, [.maskAlternate], .char("a", [.option])),
    .init(
        "Cmd+Opt+F → f+[command,option]",
        kVK_ANSI_F, [.maskCommand, .maskAlternate], .char("f", [.command, .option])
    ),

    // 4. shift+modifier 동시 — shift만 문자에 반영, 나머지는 modifiers로
    .init(
        "Cmd+Shift+G → G+[command]",
        kVK_ANSI_G, [.maskCommand, .maskShift], .char("G", [.command])
    ),

    // 5. caps lock 무시 — base 문자에는 shift만 반영한다
    .init("CapsLock+j → j", kVK_ANSI_J, [.maskAlphaShift], .char("j")),
]

@MainActor
struct KeyTranslatorTests {
    @Test("CGEvent(keyDown) → Key 번역 — 레이아웃 불변", arguments: layoutInvariantFixtures)
    func translateLayoutInvariant(_ fixture: KeyTranslationFixture) throws {
        try assertTranslation(fixture)
    }

    @Test(
        "CGEvent(keyDown) → Key 번역 — QWERTY 문자",
        .enabled("keycode↔문자 기대값이 QWERTY 계열 레이아웃에서만 성립한다") {
            await isQwertyLayout()
        },
        arguments: qwertyCharacterFixtures
    )
    func translateQwertyCharacter(_ fixture: KeyTranslationFixture) throws {
        try assertTranslation(fixture)
    }

    private func assertTranslation(_ fixture: KeyTranslationFixture) throws {
        let event = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: fixture.virtualKey, keyDown: true),
            "합성 CGEvent 생성 실패: \(fixture.name)"
        )
        event.flags = fixture.flags

        #expect(KeyTranslator.translate(event) == fixture.expected, "\(fixture.name)")
    }

    @Test("문자 번역이 레이아웃 데이터를 캐시하고, 무효화 후 재조회한다")
    func layoutCacheInvalidationRefetches() throws {
        // 물리 J 키는 어느 ASCII-capable 레이아웃에서든 출력 가능한 문자로 번역된다 —
        // 특정 문자를 기대하지 않으므로 QWERTY 조건 없이 성립한다.
        let event = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_J), keyDown: true)
        )
        let before = try #require(KeyTranslator.translate(event))
        #expect(KeyTranslator.cachedLayoutData != nil)

        KeyTranslator.invalidateLayoutCache()
        #expect(KeyTranslator.cachedLayoutData == nil)

        let after = KeyTranslator.translate(event)
        #expect(after == before)
        #expect(KeyTranslator.cachedLayoutData != nil)
    }

    @Test("keyDown 외 타입 → nil (total function 계약)")
    func nonKeyDownReturnsNil() throws {
        // keyUp의 j — 타입 가드가 없다면 keyDown과 동일하게 .char("j")로 번역되는 입력.
        let keyUp = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_J), keyDown: false)
        )
        #expect(KeyTranslator.translate(keyUp) == nil)

        // 실제 flagsChanged가 나르는 modifier keycode 형태 (Shift 단독 누름).
        let flagsChanged = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)
        )
        flagsChanged.type = .flagsChanged
        flagsChanged.flags = [.maskShift]
        #expect(KeyTranslator.translate(flagsChanged) == nil)
    }
}

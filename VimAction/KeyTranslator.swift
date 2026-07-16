//
//  KeyTranslator.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import os
import VimEngine

/// `CGEvent`를 엔진 입력 계약인 `Key`로 정규화하는 번역기.
///
/// 계약: 번역 불가(`nil`)면 호출측은 이벤트를 무조건 통과시킨다.
/// keyDown만 번역 가능하며, 그 외 타입은 번역 불가로 정의한다 —
/// 임의의 `CGEvent`에 대해 답이 정의된 total function이다.
/// TIS API가 메인 스레드를 요구하므로 `@MainActor`에 고정한다 —
/// 탭 콜백은 메인 런루프에서 돌므로 런타임 제약 변화는 없다.
@MainActor
enum KeyTranslator {
    static func translate(_ event: CGEvent) -> Key? {
        // keyDown 외 타입은 keycode 필드 오독(비키보드 이벤트는 0 → "a") 여지가 있다.
        guard event.type == .keyDown else { return nil }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = modifiers(from: event.flags)

        if let special = specialBase(for: keyCode) {
            return Key(special, modifiers)
        }

        // 탭에는 다른 프로세스가 합성한 이벤트도 흘러들어온다 — keycode 필드가
        // UInt16 범위를 벗어나면 크래시 대신 번역 불가(통과)로 처리한다.
        guard let virtualKey = UInt16(exactly: keyCode) else { return nil }
        guard let character = character(
            for: virtualKey,
            shifted: event.flags.contains(.maskShift)
        ) else {
            return nil
        }
        return Key(.char(character), modifiers)
    }

    /// 문자로 표현되지 않는 특수키는 keycode로 먼저 판별한다.
    private static func specialBase(for keyCode: Int64) -> Key.Base? {
        switch Int(keyCode) {
        case kVK_Escape: return .escape
        case kVK_Return: return .enter
        case kVK_Tab: return .tab
        case kVK_Space: return .space
        default: return nil
        }
    }

    /// shift/capsLock/fn은 무시한다 — shift는 문자에 흡수되는 정규화 규칙 참고.
    private static func modifiers(from flags: CGEventFlags) -> Set<Key.Modifier> {
        var result: Set<Key.Modifier> = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    /// 현재 ASCII-capable 레이아웃으로 keycode → 문자 번역.
    ///
    /// base 문자 유도에는 shift만 반영한다 — ctrl/opt/cmd/capsLock를 섞으면
    /// `Ctrl-d` 같은 조합에서 제어 문자가 나와 base를 잃기 때문이다.
    private static func character(for keyCode: UInt16, shifted: Bool) -> Character? {
        guard
            let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue(),
            let layoutDataRef = TISGetInputSourceProperty(
                inputSource, kTISPropertyUnicodeKeyLayoutData
            )
        else {
            logSetupFailureOnce("ASCII-capable 키보드 레이아웃 데이터 획득 실패 — 문자 키 번역 불가")
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRef).takeUnretainedValue() as Data

        let modifierKeyState: UInt32 = shifted ? UInt32((shiftKey >> 8) & 0xFF) : 0
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                0,  // dead key 상태를 실제로 추적한다 (NoDeadKeys 아님)
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        // API 실패는 셋업 문제(1회 기록), dead key 진행·빈 출력은 정상적인 번역 불가.
        guard status == noErr else {
            logSetupFailureOnce("UCKeyTranslate 실패 status=\(status)")
            return nil
        }
        guard deadKeyState == 0, length > 0 else { return nil }

        let string = String(utf16CodeUnits: chars, count: Int(length))
        guard string.count == 1, let character = string.first else { return nil }
        guard isPrintable(character) else { return nil }
        return character
    }

    /// 셋업 실패(레이아웃 데이터 없음, UCKeyTranslate 에러)는 모든 문자 키를 조용히
    /// 통과시키는 실패 모드라 진단이 필요하지만, 키 입력마다 반복되므로 최초 1회만
    /// 기록한다 — 이후 비용은 boolean 체크뿐이다.
    private static var didLogSetupFailure = false
    private static func logSetupFailureOnce(_ message: String) {
        guard !didLogSetupFailure else { return }
        didLogSetupFailure = true
        Logger.eventTap.fault("\(message, privacy: .public)")
    }

    /// 제어 문자·비출력 문자(화살표/펑션 키가 만드는 PUA 포함)는 거부한다.
    private static func isPrintable(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            let value = scalar.value
            if value < 0x20 || value == 0x7F { return false }
            if (0xF700...0xF8FF).contains(value) { return false }
        }
        return true
    }
}

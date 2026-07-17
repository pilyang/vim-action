//
//  KeyTranslator.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
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
        registerLayoutChangeObserverIfNeeded()

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

    /// 현재 ASCII-capable 레이아웃 데이터의 캐시. 키 입력마다 TIS 조회를 반복하지 않기 위한
    /// 것으로, 입력 소스 변경 노티피케이션이 무효화한다(클리어 → 다음 키에서 재조회).
    /// 조회 실패는 캐시하지 않는다 — 다음 키에서 재시도한다. 읽기는 테스트 검증용으로 연다.
    private(set) static var cachedLayoutData: Data?

    /// 입력 소스 변경 노티피케이션의 무효화 경로 — 옵저버 콜백과 테스트가 함께 쓴다.
    static func invalidateLayoutCache() {
        cachedLayoutData = nil
    }

    /// 레이아웃 캐시 무효화 옵저버를 최초 translate 시 1회 등록한다 (`@MainActor`라 경합 없음).
    /// 앱 수명 동안 유지되므로 해제하지 않는다.
    ///
    /// selector 기반 등록 + `.deliverImmediately`가 필수다: block 기반 API는
    /// suspensionBehavior를 지정할 수 없고, 기본(coalesce) 동작은 앱이 비활성인 동안
    /// 배달을 유예한다 — LSUIElement 메뉴바 앱은 사실상 항상 비활성이라 노티가 오지 않아
    /// 캐시가 조용히 낡는다. 선택 소스 변경 외에 enabled 소스 목록 변경도 관찰한다 —
    /// 캐시 대상(ASCII-capable 레이아웃)은 선택 소스가 그대로여도 목록 변경으로 바뀔 수 있다.
    private static var observerRegistered = false
    private static func registerLayoutChangeObserverIfNeeded() {
        guard !observerRegistered else { return }
        observerRegistered = true
        let names = [
            kTISNotifySelectedKeyboardInputSourceChanged as String,
            kTISNotifyEnabledKeyboardInputSourcesChanged as String,
        ]
        for name in names {
            DistributedNotificationCenter.default().addObserver(
                LayoutCacheInvalidator.shared,
                selector: #selector(LayoutCacheInvalidator.inputSourcesChanged(_:)),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
    }

    /// 현재 ASCII-capable 레이아웃 데이터 — 캐시 우선, 없으면 TIS 조회 후 적재.
    private static func currentLayoutData() -> Data? {
        if let cached = cachedLayoutData { return cached }
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
        let data = Unmanaged<CFData>.fromOpaque(layoutDataRef).takeUnretainedValue() as Data
        cachedLayoutData = data
        return data
    }

    /// 현재 ASCII-capable 레이아웃으로 keycode → 문자 번역.
    ///
    /// base 문자 유도에는 shift만 반영한다 — ctrl/opt/cmd/capsLock를 섞으면
    /// `Ctrl-d` 같은 조합에서 제어 문자가 나와 base를 잃기 때문이다.
    private static func character(for keyCode: UInt16, shifted: Bool) -> Character? {
        guard let layoutData = currentLayoutData() else { return nil }

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
            // 캐시된 데이터가 원인일 수 있다 — 유지하면 영구 무번역이 되므로 버려서
            // 다음 키가 새로 조회하게 한다 (캐시 도입 전의 키마다 재조회 자가 치유 복원).
            cachedLayoutData = nil
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

/// 분산 노티 옵저버 셔틀 — suspensionBehavior를 받는 API가 selector 기반뿐이라
/// NSObject가 필요하다 (`KeyTranslator`는 enum). 등록 이유는 등록 지점 주석 참고.
private final class LayoutCacheInvalidator: NSObject {
    static let shared = LayoutCacheInvalidator()

    /// 배달 스레드는 문서상 보장이 없다 — 가정 대신 메인 액터로 홉해 무효화한다.
    /// 홉의 지연은 무해하다: 그 사이 키는 이전 캐시로 번역되고, 이는 노티 기반
    /// 무효화에 원래 내재한 창이다.
    @objc nonisolated func inputSourcesChanged(_: Notification) {
        Task { @MainActor in
            KeyTranslator.invalidateLayoutCache()
        }
    }
}

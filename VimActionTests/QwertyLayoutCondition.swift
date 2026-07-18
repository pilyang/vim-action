//
//  QwertyLayoutCondition.swift
//  VimActionTests
//

import Carbon.HIToolbox

/// 픽스처의 keycode↔문자 짝이 성립하는 QWERTY 계열 레이아웃 ID.
/// Unicode Hex Input은 문자 배열이 US와 동일하다 (hex 입력은 option 조합 전용).
let qwertyLayoutIDs: Set<String> = [
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.US",
    "com.apple.keylayout.UnicodeHexInput",
]

/// 현재 ASCII-capable 레이아웃이 QWERTY 계열인지 — QWERTY 의존 픽스처의 실행 조건.
/// TIS API가 메인 스레드를 요구하므로 `@MainActor`에 고정한다.
@MainActor
func isQwertyLayout() -> Bool {
    guard
        let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
            .takeRetainedValue(),
        let sourceIDRef = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
    else { return false }
    let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDRef).takeUnretainedValue() as String
    return qwertyLayoutIDs.contains(sourceID)
}

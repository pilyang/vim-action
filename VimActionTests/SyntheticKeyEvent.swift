//
//  SyntheticKeyEvent.swift
//  VimActionTests
//

import CoreGraphics
import Testing

/// layout-invariant 특수키만 쓰는 합성 keyDown — QWERTY 의존 없이 탭 경로를 태운다.
/// 생성 방식(이벤트 소스·초기 필드)을 한 자리에 모아 둔다: 파일마다 복제하면 한 곳만
/// 고쳤을 때 테스트끼리 다른 이벤트로 돌아 원인이 어긋난다.
func keyDown(_ virtualKey: Int, _ flags: CGEventFlags = []) throws -> CGEvent {
    let event = try #require(
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: true))
    event.flags = flags
    return event
}

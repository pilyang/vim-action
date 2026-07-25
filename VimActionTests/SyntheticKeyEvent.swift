//
//  SyntheticKeyEvent.swift
//  VimActionTests
//

import CoreGraphics
import Testing

/// layout-invariant 특수키만 쓰는 합성 keyDown — QWERTY 의존 없이 탭 경로를 태운다.
/// 컨트롤러를 태우는 테스트(안전장치·마커·폭주)가 공유한다. `KeyTranslatorTests`·
/// `EventTapDecisionTests`는 픽스처가 `CGKeyCode`·keyUp·flagsChanged를 직접 다뤄
/// 아직 자체 생성을 쓴다 — 그쪽까지 옮기려면 시그니처 확장이 필요하다.
///
/// `flags`를 **항상** 대입하는 것이 핵심이다: `keyboardEventSource: nil`로 만든
/// 이벤트는 기본값이 빈 flags가 아니라 **실행 시점의 실제 modifier 상태를 상속**한다.
/// 그대로 두면 개발자가 Ctrl/Cmd/Opt를 누르고 있는 동안 돌린 테스트에서 엔진이
/// `Esc`가 아닌 `Ctrl-Esc`를 보게 되어(엔진은 modifier 포함 `Key` 전체로 비교한다)
/// 모드 단언이 머신 상태에 따라 깨진다.
func keyDown(_ virtualKey: Int, _ flags: CGEventFlags = []) throws -> CGEvent {
    let event = try #require(
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: true))
    event.flags = flags
    return event
}

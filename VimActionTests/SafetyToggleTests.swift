//
//  SafetyToggleTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
import VimEngine
@testable import VimAction

/// layout-invariant 특수키만 쓰는 합성 keyDown — QWERTY 의존 없는 안전장치 테스트용.
private func keyDown(_ virtualKey: Int, _ flags: CGEventFlags = []) throws -> CGEvent {
    let event = try #require(
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: true))
    event.flags = flags
    return event
}

@MainActor
struct SafetyToggleTests {
    @Test("토글 off: 키 전부 통과 + off 시점 Insert 리셋")
    func interceptionOffPassesThroughAndResets() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))
            #expect(controller.mode == .normal)

            controller.isInterceptionEnabled = false
            #expect(controller.mode == .insert)

            // Normal이었다면 삼켰을 Esc·Space가 전부 통과하고 모드도 불변.
            #expect(controller.handleKeyDown(try keyDown(kVK_Escape)) != nil)
            #expect(controller.handleKeyDown(try keyDown(kVK_Space)) != nil)
            #expect(controller.mode == .insert)
        }
    }

    @Test("토글 off→on: Insert부터 재시작 + 엔진 정상 동작")
    func interceptionBackOnRestartsFromInsert() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입
            controller.isInterceptionEnabled = false
            controller.isInterceptionEnabled = true
            #expect(controller.mode == .insert)

            // 엔진이 살아있다 — Esc 삼킴 + Normal 전이.
            #expect(controller.handleKeyDown(try keyDown(kVK_Escape)) == nil)
            #expect(controller.mode == .normal)
        }
    }

    @Test("탈출 옵션 off(초기 로드): Normal에서 Cmd+Space 삼킴 + Normal 유지")
    func escapeOptionOffLoadedAtInit() throws {
        try withTemporaryDefaults { defaults in
            defaults.set(false, forKey: PreferenceKeys.normalModeEscapeEnabled)
            let controller = EventTapController(defaults: defaults)
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))
            #expect(controller.mode == .normal)

            // 미매핑 modifier 콤보는 탈출 옵션과 무관하게 항상 통과(시스템 단축키 보호) —
            // 옵션은 Insert 전이 여부만 제어한다. off면 통과하되 Normal 유지.
            #expect(controller.handleKeyDown(try keyDown(kVK_Space, [.maskCommand])) != nil)
            #expect(controller.mode == .normal)
        }
    }

    @Test("탈출 옵션 변경: Insert 리셋 + 새 설정 적용 + 영속")
    func escapeOptionChangeResetsAppliesAndPersists() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))
            #expect(controller.mode == .normal)

            controller.isNormalModeEscapeEnabled = false
            #expect(controller.mode == .insert)
            #expect(defaults.bool(forKey: PreferenceKeys.normalModeEscapeEnabled) == false)

            _ = controller.handleKeyDown(try keyDown(kVK_Escape))
            // 탈출 off 주입 적용 확인 — 콤보는 통과하되 Normal 유지 (Insert 전이 없음).
            #expect(controller.handleKeyDown(try keyDown(kVK_Space, [.maskCommand])) != nil)
            #expect(controller.mode == .normal)
        }
    }

    @Test("토글 영속: didSet 저장 → 새 컨트롤러 init 로드")
    func togglePersistsAcrossControllers() throws {
        try withTemporaryDefaults { defaults in
            let first = EventTapController(defaults: defaults)
            #expect(first.isInterceptionEnabled)  // 미설정 키 → 기본 on

            first.isInterceptionEnabled = false
            #expect(defaults.bool(forKey: PreferenceKeys.interceptionEnabled) == false)

            let second = EventTapController(defaults: defaults)
            #expect(second.isInterceptionEnabled == false)
        }
    }
}

/// Settings "Event Tap" 행 파생 — status가 private(set)이라 컨트롤러로는 .running을
/// 만들 수 없으므로, 순수 함수를 직접 호출해 전 분기를 검증한다.
struct EventTapStatusTextTests {
    @Test(".running: 가로채기 on이면 Running, off면 Disabled")
    func runningDerivesFromInterceptionToggle() {
        #expect(eventTapStatusText(status: .running, interceptionEnabled: true) == "Running")
        #expect(eventTapStatusText(status: .running, interceptionEnabled: false) == "Disabled")
    }

    @Test(".running 외 상태는 토글과 무관하게 자기 문구")
    func nonRunningIgnoresToggle() {
        for enabled in [true, false] {
            #expect(
                eventTapStatusText(status: .waitingForPermission, interceptionEnabled: enabled)
                    == "Waiting for Permission")
            #expect(eventTapStatusText(status: .failed, interceptionEnabled: enabled) == "Failed")
            #expect(eventTapStatusText(status: .stopped, interceptionEnabled: enabled) == "Stopped")
        }
    }
}

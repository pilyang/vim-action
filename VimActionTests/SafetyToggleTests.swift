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

/// 임시 UserDefaults suite로 격리 실행. 테스트는 TEST_HOST(앱 프로세스)에서 돌아
/// `.standard`가 실제 앱 도메인이다 — 실기기 사용으로 영속된 값(토글 off 등)이
/// 새어 들면 머신 상태 의존 실패가 된다. 컨트롤러를 만드는 모든 테스트가 쓸 것.
@MainActor
func withTemporaryDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let suiteName = "VimActionTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try body(defaults)
}

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

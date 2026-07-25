//
//  SyntheticEventMarkerTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine
@testable import VimAction

/// layout-invariant 특수키만 쓰는 합성 keyDown — QWERTY 의존 없이 마커 경로만 본다.
private func keyDown(_ virtualKey: Int) throws -> CGEvent {
    let event = try #require(
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: true))
    return event
}

struct ActionExecutorTests {
    @Test("게시되는 모든 이벤트에 마커가 찍힌다")
    func postMarksEveryEvent() throws {
        // 실제 게시는 테스트 머신에 키를 주입하므로 게시 함수를 가로챈다 — 검증 대상은
        // "게시 시점에 마킹돼 있는가"다.
        nonisolated(unsafe) var posted: [CGEvent] = []
        let executor = ActionExecutor { posted.append($0) }

        let events = [try keyDown(kVK_Escape), try keyDown(kVK_Space)]
        #expect(events.allSatisfy { !SyntheticEventMarker.isMarked($0) })  // 사전 조건

        executor.post(events)

        #expect(posted.count == 2)
        #expect(posted.allSatisfy { SyntheticEventMarker.isMarked($0) })
    }

    @Test("마킹하지 않은 이벤트는 마커로 인식되지 않는다")
    func unmarkedEventIsNotDetected() throws {
        let event = try keyDown(kVK_Escape)
        #expect(!SyntheticEventMarker.isMarked(event))
    }
}

/// 탭측 마커 가드 — 마킹된 이벤트는 번역·엔진 재해석 없이 통과해야 한다.
/// 무한 루프를 막는 불변식이라 토글 상태와 무관하게 성립한다.
@MainActor
struct MarkerGuardTests {
    @Test("마킹된 Esc: 통과 + 엔진 미해석(Insert 유지)", arguments: [true, false])
    func markedEventBypassesEngine(interceptionEnabled: Bool) throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            controller.isInterceptionEnabled = interceptionEnabled

            let event = try keyDown(kVK_Escape)
            SyntheticEventMarker.mark(event)

            // 마커가 없었다면 Insert의 Esc는 삼켜지고(nil) Normal로 전이했을 입력이다.
            #expect(controller.handleKeyDown(event) != nil)
            #expect(controller.mode == .insert)
        }
    }

    @Test("대조군 — 같은 Esc가 마커 없이 오면 삼킴 + Normal 전이")
    func unmarkedEventStillReachesEngine() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            let result = controller.handleKeyDown(try keyDown(kVK_Escape))
            #expect(result == nil)
            #expect(controller.mode == .normal)
        }
    }

    @Test("Normal 상태에서 마킹된 이벤트가 들어와도 모드가 흔들리지 않는다")
    func markedEventDoesNotDisturbNormalMode() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입
            #expect(controller.mode == .normal)

            // Normal의 Space는 원래 삼켜진다 — 마커가 있으면 통과하고 모드도 불변.
            let event = try keyDown(kVK_Space)
            SyntheticEventMarker.mark(event)
            #expect(controller.handleKeyDown(event) != nil)
            #expect(controller.mode == .normal)
        }
    }
}

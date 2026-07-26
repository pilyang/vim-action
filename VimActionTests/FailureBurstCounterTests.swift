//
//  FailureBurstCounterTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import Foundation
import Testing
import VimEngine
@testable import VimAction

/// 창 경계 판정 — 시간을 주입받는 순수 타입이라 실제 시계를 기다리지 않는다.
struct FailureBurstCounterTests {
    @Test("임계 미만(4회)은 트립하지 않는다")
    func belowThresholdDoesNotTrip() {
        var counter = FailureBurstCounter()
        for i in 0..<4 {
            #expect(counter.record(at: Double(i) * 0.1) == false)
        }
    }

    @Test("같은 창 안 5회째에 트립한다")
    func thresholdInsideWindowTrips() {
        var counter = FailureBurstCounter()
        for i in 0..<4 {
            #expect(counter.record(at: Double(i) * 0.1) == false)
        }
        let tripped = counter.record(at: 0.4)
        #expect(tripped)
    }

    @Test("창을 벗어난 보고는 누적되지 않는다 — 0.3초 간격 5회는 무발동")
    func reportsSpreadBeyondWindowDoNotAccumulate() {
        var counter = FailureBurstCounter()
        // 창(1초)이 4건을 담을 수 없는 간격 — 매 보고 시점의 창 안 누적은 최대 4건이다.
        for i in 0..<20 {
            #expect(counter.record(at: Double(i) * 0.3) == false)
        }
    }

    @Test("창 경계: 정확히 1초 지난 보고는 창에서 빠진다")
    func windowBoundaryDropsExpiredReports() {
        var counter = FailureBurstCounter()
        for i in 0..<4 {
            #expect(counter.record(at: Double(i) * 0.1) == false)
        }
        // t=0.0의 보고가 창 밖(now - t >= 1)으로 빠져 창 안은 4건 → 트립하지 않는다.
        #expect(counter.record(at: 1.0) == false)
        // 직후 한 건 더면 창 안 5건 → 트립.
        let tripped = counter.record(at: 1.05)
        #expect(tripped)
    }

    @Test("트립 후 창을 비운다 — 같은 이력으로 재트립하지 않는다")
    func tripClearsWindow() {
        var counter = FailureBurstCounter()
        for i in 0..<4 { _ = counter.record(at: Double(i) * 0.1) }
        let tripped = counter.record(at: 0.4)
        #expect(tripped)
        // 트립 직후 같은 창 안의 추가 보고는 1건부터 다시 센다.
        #expect(counter.record(at: 0.5) == false)
    }

    @Test("임계·창은 조정 가능하다")
    func thresholdAndWindowAreConfigurable() {
        var counter = FailureBurstCounter(window: 10, threshold: 2)
        #expect(counter.record(at: 0) == false)
        let tripped = counter.record(at: 5)
        #expect(tripped)
    }
}

/// 트립 → 기존 소프트 off 경로 재사용 확인 (`SafetyToggleTests`의 off 계약과 같은 자리).
@MainActor
struct ExecutionFailureBurstTests {
    @Test("폭주 5회: 가로채기 자동 off + off 부수효과(Insert 리셋·통과) 동반")
    func burstDisablesInterception() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))
            #expect(controller.mode == .normal)

            for i in 0..<4 {
                controller.reportExecutionFailure(at: Double(i) * 0.1)
                #expect(controller.isInterceptionEnabled)
            }
            controller.reportExecutionFailure(at: 0.4)

            #expect(controller.isInterceptionEnabled == false)
            // 새 off 경로가 아니라 didSet 재사용 — 엔진 Insert 리셋과 영속이 따라온다.
            #expect(controller.mode == .insert)
            // 존재 확인이 먼저 — `bool(forKey:)`는 미설정 키에도 false라 이것 없이는
            // 영속을 통째로 지워도 통과한다.
            #expect(defaults.object(forKey: PreferenceKeys.interceptionEnabled) != nil)
            #expect(defaults.bool(forKey: PreferenceKeys.interceptionEnabled) == false)
        }
    }

    @Test("창을 벗어난 실패는 off를 유발하지 않는다")
    func spreadFailuresKeepInterceptionOn() {
        withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            for i in 0..<20 {
                controller.reportExecutionFailure(at: Double(i) * 0.3)
            }
            #expect(controller.isInterceptionEnabled)
        }
    }
}

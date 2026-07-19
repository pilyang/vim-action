//
//  TapWatchdogTests.swift
//  VimActionTests
//

import Testing
@testable import VimAction

/// 워치독의 CI 가능 seam 두 곳을 검증한다: 틱 판정(`watchdogTick` — CGEvent 의존을
/// 클로저 주입으로 대체)과 메인측 status 반영(`applyWatchdogResult`). 타이머 스케줄과
/// 실탭 결합은 TEST_HOST 포트가 항상 nil이라 도달 불가 — 실기기 GREEN에서 확인한다.
@MainActor
struct TapWatchdogTests {

    // MARK: - watchdogTick 판정

    @Test("활성 탭: 재활성화 시도 없이 .live")
    func tickLiveTapSkipsEnable() {
        var enableAttempted = false
        let observation = EventTapController.watchdogTick(
            isEnabled: { true },
            enableAndVerify: {
                enableAttempted = true
                return true
            })
        #expect(observation == .live)
        #expect(!enableAttempted)
    }

    @Test("비활성 탭 재활성화 성공: .recovered")
    func tickDeadTapRecovers() {
        let observation = EventTapController.watchdogTick(
            isEnabled: { false },
            enableAndVerify: { true })
        #expect(observation == .recovered)
    }

    @Test("비활성 탭 재활성화 실패: .dead")
    func tickDeadTapStaysDead() {
        let observation = EventTapController.watchdogTick(
            isEnabled: { false },
            enableAndVerify: { false })
        #expect(observation == .dead)
    }

    // MARK: - applyWatchdogResult 가드

    @Test("토글 off 상태의 늦은 홉: status 불변 + nil 포트에서 크래시 없음")
    func lateHopWhileInterceptionOffIsIgnored() {
        withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            controller.isInterceptionEnabled = false
            let before = controller.status

            // off 가드가 먼저 소비한다 — 관측값과 무관하게 status를 건드리지 않는다.
            controller.applyWatchdogResult(.live)
            controller.applyWatchdogResult(.recovered)
            controller.applyWatchdogResult(.dead)
            #expect(controller.status == before)
        }
    }

    @Test("포트 없는 상태(설치 전)의 늦은 홉: status 불변")
    func lateHopWithoutPortIsIgnored() {
        withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            #expect(controller.status == .waitingForPermission)

            // 토글 on이어도 포트 nil 가드가 막는다 — 설치 전/제거 후 status 오염 방지.
            controller.applyWatchdogResult(.live)
            #expect(controller.status == .waitingForPermission)
            controller.applyWatchdogResult(.dead)
            #expect(controller.status == .waitingForPermission)
        }
    }
}

//
//  TapWatchdogTests.swift
//  VimActionTests
//

import Testing
@testable import VimAction

/// 워치독의 메인측 seam(`applyWatchdogResult`)만 검증한다. 실제 폴링·재활성화와
/// `.running`/`.failed` 전이는 탭 포트가 필요한데 TEST_HOST에선 포트가 항상 nil이라
/// 도달 불가 — 기존 "단위 테스트 불가 지점"에 합류, 실기기 GREEN에서 확인한다.
@MainActor
struct TapWatchdogTests {
    @Test("토글 off 상태의 늦은 홉: status 불변 + nil 포트에서 크래시 없음")
    func lateHopWhileInterceptionOffIsIgnored() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            controller.isInterceptionEnabled = false
            let before = controller.status

            // off 가드가 먼저 소비한다 — live 값과 무관하게 status를 건드리지 않는다.
            controller.applyWatchdogResult(live: true)
            controller.applyWatchdogResult(live: false)
            #expect(controller.status == before)
        }
    }

    @Test("포트 없는 상태(설치 전)의 늦은 홉: status 불변")
    func lateHopWithoutPortIsIgnored() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            #expect(controller.status == .waitingForPermission)

            // 토글 on이어도 포트 nil 가드가 막는다 — 설치 전/제거 후 status 오염 방지.
            controller.applyWatchdogResult(live: true)
            #expect(controller.status == .waitingForPermission)
            controller.applyWatchdogResult(live: false)
            #expect(controller.status == .waitingForPermission)
        }
    }
}

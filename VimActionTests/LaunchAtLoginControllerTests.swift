//
//  LaunchAtLoginControllerTests.swift
//  VimActionTests
//

import ServiceManagement
import Testing

@testable import VimAction

/// `SMAppService`를 통째로 대신한다 — 실물을 부르면 **이 개발 머신의 로그인 항목이 실제로
/// 바뀐다**(TEST_HOST가 앱 프로세스라 등록 대상이 진짜 VimAction이다). status는 테스트가
/// 직접 놓고, register/unregister는 호출 기록 + 그에 따른 상태 전이를 흉내 낸다.
@MainActor
private final class FakeAppService {
    var status: SMAppService.Status
    var registerCount = 0
    var unregisterCount = 0
    /// 던질 에러 — nil이면 성공하고 status가 따라 움직인다.
    var failure: Error?

    init(status: SMAppService.Status) {
        self.status = status
    }

    func makeController() -> LaunchAtLoginController {
        LaunchAtLoginController(
            currentStatus: { [self] in status },
            register: { [self] in
                registerCount += 1
                if let failure { throw failure }
                status = .enabled
            },
            unregister: { [self] in
                unregisterCount += 1
                if let failure { throw failure }
                status = .notRegistered
            })
    }
}

private struct RegistrationFailure: Error {}

@MainActor
struct LaunchAtLoginControllerTests {
    /// 기본은 off이고, 그것은 저장된 기본값이 아니라 "등록 안 됨"이라는 시스템 사실이다.
    @Test("등록 전에는 off")
    func defaultsToDisabled() {
        let service = FakeAppService(status: .notRegistered)
        let controller = service.makeController()

        controller.refresh()

        #expect(!controller.isEnabled)
        #expect(service.registerCount == 0)
    }

    /// `.enabled`만 on이다 — `.requiresApproval`(사용자가 시스템 설정에서 껐다)·`.notFound`는
    /// 어느 쪽이든 로그인 시 실제로 뜨지 않으므로 on으로 보이면 거짓말이 된다.
    @Test(
        "on은 .enabled 하나뿐",
        arguments: [
            (SMAppService.Status.enabled, true),
            (.notRegistered, false),
            (.requiresApproval, false),
            (.notFound, false),
        ])
    func onlyEnabledStatusReadsAsOn(status: SMAppService.Status, expected: Bool) {
        let service = FakeAppService(status: status)
        let controller = service.makeController()

        controller.refresh()

        #expect(controller.isEnabled == expected)
    }

    @Test("켜면 register, 끄면 unregister를 한 번씩 부른다")
    func togglingCallsRegistrationAPIs() {
        let service = FakeAppService(status: .notRegistered)
        let controller = service.makeController()

        controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)

        controller.setEnabled(false)
        #expect(!controller.isEnabled)
        #expect(service.unregisterCount == 1)
        #expect(service.registerCount == 1)
    }

    /// **이 케이스가 미러를 두지 않는 이유다** — 사용자가 시스템 설정 > 로그인 항목에서
    /// 직접 끄면 앱은 아무 통지도 못 받는다. 저장된 값을 믿었다면 토글은 계속 on을 보여준다.
    @Test("시스템 설정에서 꺼진 변경을 창 열 때 따라잡는다")
    func externalDisableIsPickedUpOnRefresh() {
        let service = FakeAppService(status: .notRegistered)
        let controller = service.makeController()

        controller.setEnabled(true)
        #expect(controller.isEnabled)

        // 사용자가 시스템 설정에서 끔 — 앱을 거치지 않은 변경이다.
        service.status = .notRegistered
        controller.refresh()

        #expect(!controller.isEnabled)
    }

    /// 실패하면 요청값이 아니라 재조회한 status가 이긴다 — 토글이 원위치로 돌아가고,
    /// 클릭이 조용한 무동작이 되지 않도록 사유가 남는다.
    @Test("등록 실패는 토글을 되돌리고 사유를 남긴다")
    func registrationFailureRevertsToggleAndReportsReason() {
        let service = FakeAppService(status: .notRegistered)
        service.failure = RegistrationFailure()
        let controller = service.makeController()

        controller.setEnabled(true)

        #expect(service.registerCount == 1)
        #expect(!controller.isEnabled)
        #expect(controller.failureMessage != nil)
    }

    /// 창을 다시 여는 것은 새로 보는 것이다 — 지난 실패 문구가 남아 있으면 안 된다.
    @Test("refresh는 지난 실패 문구를 지운다")
    func refreshClearsStaleFailureMessage() {
        let service = FakeAppService(status: .notRegistered)
        service.failure = RegistrationFailure()
        let controller = service.makeController()

        controller.setEnabled(true)
        #expect(controller.failureMessage != nil)

        controller.refresh()

        #expect(controller.failureMessage == nil)
    }
}

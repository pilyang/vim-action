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
            isKillRequested: { false },
            isEnabled: { true },
            enableAndVerify: {
                enableAttempted = true
                return true
            },
            isSecureInput: { false })
        #expect(observation == .live)
        #expect(!enableAttempted)
    }

    @Test("비활성 탭 재활성화 성공: .recovered")
    func tickDeadTapRecovers() {
        let observation = EventTapController.watchdogTick(
            isKillRequested: { false },
            isEnabled: { false },
            enableAndVerify: { true },
            isSecureInput: { false })
        #expect(observation == .recovered)
    }

    @Test("비활성 탭 재활성화 실패: .dead")
    func tickDeadTapStaysDead() {
        let observation = EventTapController.watchdogTick(
            isKillRequested: { false },
            isEnabled: { false },
            enableAndVerify: { false },
            isSecureInput: { false })
        #expect(observation == .dead)
    }

    /// SEI는 탭 **활성화**를 막지 않는다 — 이벤트 배달만 억제한다 (macOS 26.5 실측).
    /// 그러므로 비활성 탭을 만나면 SEI 여부와 무관하게 항상 되살려야 한다. 이걸
    /// 건너뛰면 SEI가 켜져 있는 동안 *다른 이유로* 죽은 탭의 복구를 거부하게 된다.
    @Test("Secure Input 중이어도 비활성 탭은 되살린다")
    func tickRevivesEvenUnderSecureInput() {
        var enableAttempted = false
        let observation = EventTapController.watchdogTick(
            isKillRequested: { false },
            isEnabled: { false },
            enableAndVerify: {
                enableAttempted = true
                return true
            },
            isSecureInput: { true })
        #expect(observation == .recovered)
        #expect(enableAttempted)
    }

    /// 되살리기가 **실패한 뒤에만** SEI가 의미를 갖는다 — 고장(.dead)과 보호 상태를
    /// 가르는 표시용 구분이지, 재활성화를 보류하는 근거가 아니다.
    @Test("재활성화 실패 + Secure Input: 표시만 .secureInput로 가른다")
    func tickFailedRevivalUnderSecureInputIsLabelled() {
        #expect(
            EventTapController.watchdogTick(
                isKillRequested: { false },
                isEnabled: { false },
                enableAndVerify: { false },
                isSecureInput: { true }) == .secureInput)
        // 같은 실패인데 SEI만 없으면 고장으로 표시된다 — 구분이 SEI에서만 온다는 증거.
        #expect(
            EventTapController.watchdogTick(
                isKillRequested: { false },
                isEnabled: { false },
                enableAndVerify: { false },
                isSecureInput: { false }) == .dead)
    }

    // MARK: - 킬스위치 래치 (틱 진행 중 발동)

    /// 킬 스레드가 틱 **진행 중에** 래치를 세우는 순간을 결정적으로 재현한다 — n번째 읽기부터
    /// true. 실제 스레드 경합은 CI에서 재현 불가라, 래치 읽기 횟수로 창의 위치를 고정한다.
    /// 읽기 순서: ①진입 → (isEnabled) → ②재활성화 직전 → (enableAndVerify/isSecureInput)
    /// → ③관측 후. 탭이 살아 있으면 ②를 건너뛰어 2회, 그 외에는 3회 읽는다.
    private func latch(raisedFromRead n: Int) -> () -> Bool {
        var reads = 0
        return {
            defer { reads += 1 }
            return reads >= n
        }
    }

    /// 가드 ① — 래치가 이미 서 있으면 탭을 **건드리지도** 않는다. 반환 nil만으로는 부족하다:
    /// ①이 없어도 ③이 nil로 만들기 때문에, "isEnabled를 부르지 않았다"가 유일한 증거다.
    @Test("래치가 진입 시점에 서 있음: 탭을 읽지도 않고 관측 없음")
    func latchedAtEntrySkipsTapEntirely() {
        var isEnabledCalled = false
        var enableAttempted = false
        let observation = EventTapController.watchdogTick(
            isKillRequested: latch(raisedFromRead: 0),
            isEnabled: {
                isEnabledCalled = true
                return true
            },
            enableAndVerify: {
                enableAttempted = true
                return true
            },
            isSecureInput: { false })
        #expect(observation == nil)
        #expect(!isEnabledCalled)
        #expect(!enableAttempted)
    }

    /// 가드 ② — 틱 시작 뒤·재활성화 직전에 래치가 서면 되살리면 안 된다. 이것이 febd5ed가
    /// 봉인한 경합의 본체다: 방금 킬스위치가 끈 탭을 in-flight 틱이 되살리는 창.
    @Test("래치가 재활성화 직전에 섬: enableAndVerify 미호출 + 관측 없음")
    func latchRaisedBeforeEnableSkipsRevival() {
        var enableAttempted = false
        let observation = EventTapController.watchdogTick(
            isKillRequested: latch(raisedFromRead: 1),
            isEnabled: { false },
            enableAndVerify: {
                enableAttempted = true
                return true
            },
            isSecureInput: { false })
        #expect(observation == nil)
        #expect(!enableAttempted)
    }

    /// 가드 ③ — 관측을 마친 뒤 래치가 서면 값을 통째로 버린다. 흘리면 메인이 킬스위치
    /// 직후에 거짓 status(.running/.failed/.secureInput)를 찍는다.
    @Test("래치가 관측 후에 섬: 관측값 폐기 (live·recovered·secureInput 전부)")
    func latchRaisedAfterObservationDiscardsIt() {
        // .live: 읽기 ①→③ 2회이므로 ③에서 선다.
        #expect(
            EventTapController.watchdogTick(
                isKillRequested: latch(raisedFromRead: 1),
                isEnabled: { true },
                enableAndVerify: { true },
                isSecureInput: { false }) == nil)
        // .secureInput: 되살리기가 실패해야 도달하므로 ①→②→③ 3회 경로다.
        #expect(
            EventTapController.watchdogTick(
                isKillRequested: latch(raisedFromRead: 2),
                isEnabled: { false },
                enableAndVerify: { false },
                isSecureInput: { true }) == nil)
        // .recovered: 읽기 ①→②→③ 3회. ②까지 통과해 실제로 되살린 뒤 래치가 선 경우.
        #expect(
            EventTapController.watchdogTick(
                isKillRequested: latch(raisedFromRead: 2),
                isEnabled: { false },
                enableAndVerify: { true },
                isSecureInput: { false }) == nil)
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
            controller.applyWatchdogResult(.secureInput)
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

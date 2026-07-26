//
//  KillSwitchTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import VimAction

/// 킬스위치의 CI 가능 seam을 검증한다: 콤보 판정(`isKillCombo` — CGEvent 없이 keycode·flags만),
/// 발동 앞의 방어 가드(`shouldFire`), 그리고 발동이 기존 소프트 off에 위임되는지
/// (`triggerKillSwitch`). 실탭 설치·전용 스레드 결합은 TEST_HOST에서 도달 불가 —
/// 실기기 GREEN에서 확인한다.
struct KillSwitchComboTests {
    /// 발동 조합. 콤보 판정이 이 집합과 "정확히" 같아야 참이다.
    private static let combo: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    @Test("정확히 Ctrl+Opt+Cmd+Esc: 발동")
    func exactComboFires() {
        #expect(KillSwitchTap.isKillCombo(keyCode: Int64(kVK_Escape), flags: Self.combo))
    }

    @Test("modifier 과잉(+Shift, +Fn): 미발동")
    func extraModifiersDoNotFire() {
        #expect(
            !KillSwitchTap.isKillCombo(
                keyCode: Int64(kVK_Escape), flags: Self.combo.union(.maskShift)))
        #expect(
            !KillSwitchTap.isKillCombo(
                keyCode: Int64(kVK_Escape), flags: Self.combo.union(.maskSecondaryFn)))
    }

    @Test("modifier 부족(Ctrl+Cmd, 없음): 미발동")
    func missingModifiersDoNotFire() {
        #expect(
            !KillSwitchTap.isKillCombo(
                keyCode: Int64(kVK_Escape), flags: [.maskControl, .maskCommand]))
        #expect(!KillSwitchTap.isKillCombo(keyCode: Int64(kVK_Escape), flags: []))
    }

    @Test("다른 키에 같은 modifier: 미발동")
    func otherKeysDoNotFire() {
        #expect(!KillSwitchTap.isKillCombo(keyCode: Int64(kVK_Space), flags: Self.combo))
        #expect(!KillSwitchTap.isKillCombo(keyCode: Int64(kVK_ANSI_A), flags: Self.combo))
        #expect(!KillSwitchTap.isKillCombo(keyCode: Int64(kVK_Return), flags: Self.combo))
    }

    /// 상태/부수 비트는 사용자가 의도한 modifier가 아니다 — Caps Lock이 켜져 있다는 이유로
    /// 안전장치가 안 먹으면 안 된다 (미발동의 대가가 오발동보다 크다).
    @Test("Caps Lock·numericPad·nonCoalesced가 섞여도 발동")
    func stateBitsAreIgnored() {
        let noisy = Self.combo.union([.maskAlphaShift, .maskNumericPad, .maskNonCoalesced])
        #expect(KillSwitchTap.isKillCombo(keyCode: Int64(kVK_Escape), flags: noisy))
    }
}

@MainActor
struct KillSwitchGuardTests {
    private static let combo: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    @Test("가드 통과: 콤보 keyDown은 발동 대상")
    func plainComboShouldFire() throws {
        #expect(KillSwitchTap.shouldFire(try keyDown(kVK_Escape, Self.combo)))
    }

    /// 세션 폴백 경로에서는 우리 합성 이벤트가 킬 탭에도 들어온다 — 앱이 자기 출력으로
    /// 자기를 끄는 경로를 열지 않는다 (메인 탭의 마커 최우선 판정과 같은 정신).
    @Test("합성 마커가 찍힌 콤보: 미발동")
    func markedComboDoesNotFire() throws {
        let event = try keyDown(kVK_Escape, Self.combo)
        SyntheticEventMarker.mark(event)
        #expect(!KillSwitchTap.shouldFire(event))
    }

    /// 콤보를 꾹 누르면 fault 로그와 메인 홉이 초당 수십 건 도배된다.
    @Test("오토리핏 콤보: 미발동")
    func autorepeatComboDoesNotFire() throws {
        let event = try keyDown(kVK_Escape, Self.combo)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(!KillSwitchTap.shouldFire(event))
    }

    @Test("콤보가 아닌 keyDown: 미발동")
    func nonComboDoesNotFire() throws {
        #expect(!KillSwitchTap.shouldFire(try keyDown(kVK_Escape)))
        #expect(!KillSwitchTap.shouldFire(try keyDown(kVK_Space, Self.combo)))
    }

    /// 삼킴은 발동보다 넓다 — 오토리핏 콤보는 발동하지 않지만 포커스 앱으로 새서도 안 된다.
    /// (HID 계층이 콤보를 꾹 누르는 동안 초당 10여 건을 계속 올려보낸다.)
    @Test("오토리핏 콤보: 미발동이지만 삼킨다")
    func autorepeatComboIsStillSwallowed() throws {
        let event = try keyDown(kVK_Escape, Self.combo)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(KillSwitchTap.shouldSwallow(event))
        #expect(!KillSwitchTap.shouldFire(event))
    }

    /// 삼킴은 콤보에만 — 무관한 키와 우리 합성 출력은 그대로 통과해야 한다.
    @Test("콤보 아님·합성 마커: 삼키지 않는다")
    func nonComboAndMarkedAreNotSwallowed() throws {
        #expect(!KillSwitchTap.shouldSwallow(try keyDown(kVK_Escape)))
        #expect(!KillSwitchTap.shouldSwallow(try keyDown(kVK_Space, Self.combo)))
        let marked = try keyDown(kVK_Escape, Self.combo)
        SyntheticEventMarker.mark(marked)
        #expect(!KillSwitchTap.shouldSwallow(marked))
    }
}

@MainActor
struct KillSwitchTriggerTests {
    /// 발동의 ②가 기존 소프트 off의 didSet에 위임되는지 — 새 off 경로가 생기면 영속·리셋·
    /// 글리프가 갈라진다. ①(포트 직접 비활성)은 TEST_HOST에서 포트가 항상 nil이라 no-op.
    @Test("triggerKillSwitch: 메인 홉 뒤 가로채기 off + 영속")
    func triggerDelegatesToSoftOff() async {
        let suiteName = "VimActionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = EventTapController(defaults: defaults)
        #expect(controller.isInterceptionEnabled)

        controller.triggerKillSwitch()
        await drainMainQueue()

        #expect(!controller.isInterceptionEnabled)
        // 존재 확인이 먼저 — `bool(forKey:)`는 미설정 키에도 false라 이것 없이는
        // 영속을 통째로 지워도 통과한다.
        #expect(defaults.object(forKey: PreferenceKeys.interceptionEnabled) != nil)
        #expect(defaults.bool(forKey: PreferenceKeys.interceptionEnabled) == false)
    }

    /// 킬스위치가 존재하는 시나리오는 "메인이 굳었다"이다 — 그 상태에서 메인 홉은 영원히
    /// 착지하지 않는다. off의 **영속**이 홉에만 매달려 있으면 강제 종료 후 재실행에서 init이
    /// 다시 on을 읽어 사용자를 같은 상태로 돌려보낸다. 그래서 이 테스트는 홉을 배수하지
    /// 않는다 — @MainActor 테스트 본문에 suspension이 없어 main.async 블록은 실행될 수 없다.
    @Test("triggerKillSwitch: 메인 홉을 기다리지 않고 off를 영속한다")
    func triggerPersistsOffWithoutMainHop() {
        let suiteName = "VimActionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = EventTapController(defaults: defaults)
        #expect(controller.isInterceptionEnabled)

        controller.triggerKillSwitch()

        // `bool(forKey:)`는 **미설정 키에도** false를 준다 — 값이 실제로 쓰였는지는
        // object 존재로만 구분된다 (이게 없으면 아무것도 안 쓴 코드에서도 통과한다).
        #expect(defaults.object(forKey: PreferenceKeys.interceptionEnabled) != nil)
        #expect(defaults.bool(forKey: PreferenceKeys.interceptionEnabled) == false)
    }

    /// 래치는 "래치가 서 있으면 아무도 탭을 되살리지 않는다"를 메인 홉과 무관하게 보장하고,
    /// 해제 지점은 토글 on 복귀 하나뿐이다 — 해제를 빠뜨리면 킬스위치 이후 콜백·워치독
    /// 재활성화가 영구 보류되는 조용한 고장이 된다.
    @Test("킬 요청 래치: 발동 시 세워지고 토글 on 복귀에서만 내려간다")
    func killSwitchLatchSetsAndClears() async {
        let suiteName = "VimActionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = EventTapController(defaults: defaults)
        #expect(!controller.isKillSwitchRequested)

        controller.triggerKillSwitch()
        // 래치는 홉을 기다리지 않는다 — 발동 즉시 서야 그 사이 통지를 막는다.
        #expect(controller.isKillSwitchRequested)
        await drainMainQueue()
        #expect(controller.isKillSwitchRequested)

        controller.isInterceptionEnabled = true
        #expect(!controller.isKillSwitchRequested)
    }

    /// 래치의 **소비처** 계약 — 래치 플래그가 서는 것만으로는 안전하지 않다. 킬 스레드가
    /// 탭을 끄는 즉시 OS가 `tapDisabledBy*`를 보내는데, 그 통지는 발동 ②의 메인 홉보다
    /// 먼저 도착하므로 토글 가드는 아직 on을 보고 있다 — 래치 가드만이 되살림을 막는다.
    ///
    /// 반환값으로 검증하는 이유: TEST_HOST는 포트가 항상 nil이라 가드를 지워도
    /// `enableTapAndVerify`가 no-op이고 status가 그대로다 (관측 불가).
    @Test("킬스위치 래치 중 tapDisabledBy* 통지: 메인 홉 전에도 재활성화 거절")
    func disableNoticeDeclinedWhileLatchedBeforeHop() async {
        let suiteName = "VimActionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = EventTapController(defaults: defaults)
        // 래치 없음 + 토글 on = 정상 재활성화 경로.
        #expect(controller.reenableAfterDisable(type: .tapDisabledByTimeout))

        controller.triggerKillSwitch()
        // 홉 전이라 토글은 아직 on — 이 가드를 통과시키는 건 래치뿐이다.
        #expect(controller.isInterceptionEnabled)
        #expect(!controller.reenableAfterDisable(type: .tapDisabledByTimeout))
        #expect(!controller.reenableAfterDisable(type: .tapDisabledByUserInput))

        // 홉이 착지해 토글이 off가 된 뒤에도 계속 거절.
        await drainMainQueue()
        #expect(!controller.reenableAfterDisable(type: .tapDisabledByTimeout))

        // 토글 on 복귀가 래치를 내리면 다시 정상 경로로 돌아온다.
        controller.isInterceptionEnabled = true
        #expect(controller.reenableAfterDisable(type: .tapDisabledByTimeout))
    }

    /// `main.async`로 게시된 블록이 소진될 때까지 기다린다. 메인 큐는 FIFO라 뒤에 하나 더
    /// 걸어 그것이 실행되면 앞의 것도 끝난 것이다 — 슬립 없는 결정적 대기.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

/// Settings "Kill Switch" 행 파생 — 순수 함수라 전 분기를 직접 검증한다.
struct KillSwitchStatusTextTests {
    @Test("설치된 지점을 구분해 표시")
    func installedStates() {
        #expect(killSwitchStatusText(installation: .hid, isTrusted: true) == "Active (HID)")
        #expect(
            killSwitchStatusText(installation: .session, isTrusted: true)
                == "Active (Session fallback)")
    }

    @Test("미설치: 권한 대기와 실제 실패를 구분")
    func notInstalledDistinguishesPermission() {
        #expect(
            killSwitchStatusText(installation: .notInstalled, isTrusted: false)
                == "Waiting for Permission")
        #expect(killSwitchStatusText(installation: .notInstalled, isTrusted: true) == "Unavailable")
    }

    /// 활성화가 먹지 않은 탭은 "설치됨"으로 보이면 안 된다 — 안전장치가 조용히 부재하는
    /// 것이 최악의 실패 모드라, 권한 대기(`Waiting`)나 생성 실패(`Unavailable`)와도
    /// 구분되는 자기 문구를 갖는다.
    @Test("활성화 실패: 설치됨으로 보이지 않는다")
    func failedIsNotReportedAsActive() {
        let text = killSwitchStatusText(installation: .failed, isTrusted: true)
        #expect(text == "Failed (tap inactive)")
        #expect(!text.contains("Active"))
    }
}

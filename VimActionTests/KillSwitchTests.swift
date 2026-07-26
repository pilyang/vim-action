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
}

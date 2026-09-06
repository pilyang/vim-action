//
//  ModeIndicatorControllerTests.swift
//  VimActionTests
//

import AppKit
import Foundation
import Testing
import VimEngine

@testable import VimAction

/// 온스크린 인디케이터의 **표시 판정**(순수 계층)과 **토글 영속**. 패널도 AX도 만들지
/// 않는다 — 판정은 순수 함수라 값만 오가고, 컨트롤러 테스트는 트리거를 부르지 않는다.
struct ModeIndicatorPresentationTests {
    private func inputs(
        _ mode: Mode, _ indicator: MenuBarIndicator, pid: pid_t? = 42
    ) -> ModeIndicatorController.Inputs {
        .init(mode: mode, indicator: indicator, processID: pid)
    }

    private func presentation(
        _ mode: Mode, _ indicator: MenuBarIndicator, pid: pid_t? = 42, isEnabled: Bool = true
    ) -> ModeIndicatorController.Presentation? {
        ModeIndicatorController.presentation(
            isEnabled: isEnabled, inputs: inputs(mode, indicator, pid: pid))
    }

    @Test("비-Insert 모드는 라벨 + 상시 배지")
    func nonInsertModesShowBadge() {
        for mode in [Mode.normal, .visualChar, .visualLine] {
            let result = presentation(mode, .mode(mode))
            #expect(result?.label == mode.overlayLabel)
            #expect(result?.showsBadge == true)
            #expect(result?.processID == 42)
        }
    }

    /// Insert는 순간 표시만 하고 배지를 남기지 않는다 — 기본 상태에 배지가 있으면 "지금
    /// 위험한 모드다"라는 뜻이 사라진다.
    @Test("Insert는 라벨은 있고 배지는 없다")
    func insertFlashesWithoutBadge() {
        let result = presentation(.insert, .mode(.insert))
        #expect(result?.label == "INSERT")
        #expect(result?.showsBadge == false)
    }

    /// 가로채지 않는 상태에서 모드 라벨을 띄우면 메뉴바에서 없앤 "가로채지 않는데 Normal이라고
    /// 말하는" 거짓말을 화면 한가운데서 되풀이한다.
    @Test("사다리가 .mode가 아니면 아무것도 표시하지 않는다")
    func offLadderShowsNothing() {
        for indicator in [
            MenuBarIndicator.inactive, .interceptionOff, .appDisabled, .secureInput,
        ] {
            #expect(presentation(.normal, indicator) == nil)
        }
    }

    @Test("토글 off면 모드·사다리와 무관하게 아무것도 표시하지 않는다")
    func disabledShowsNothing() {
        for mode in [Mode.insert, .normal, .visualChar, .visualLine] {
            #expect(presentation(mode, .mode(mode), isEnabled: false) == nil)
        }
    }

    /// 붙일 앱이 없으면 앵커도 없다 — 대상 앱이 사라진 경우가 이 경로다.
    @Test("pid가 없으면 아무것도 표시하지 않는다")
    func missingProcessShowsNothing() {
        #expect(presentation(.normal, .mode(.normal), pid: nil) == nil)
    }
}

/// 읽기를 띄울지 말지 — 조율의 핵심 판정이다. 틀려도 증상이 조용하다(모자라면 배지가 낡은
/// 자리에 남고, 넘치면 전환마다 AX 왕복이 곱해진다)는 것이 표로 고정하는 이유다.
struct ModeIndicatorReadCoalescingTests {
    private let normal = ModeIndicatorController.Presentation(
        label: "NORMAL", showsBadge: true, processID: 42)
    private let insert = ModeIndicatorController.Presentation(
        label: "INSERT", showsBadge: false, processID: 42)

    private func needsRead(
        desired: ModeIndicatorController.Presentation,
        current: ModeIndicatorController.Presentation? = nil,
        inFlight: ModeIndicatorController.InFlight? = nil, token: Int = 1,
        pendingFlash: Bool = false, rereadGeometry: Bool = false
    ) -> Bool {
        ModeIndicatorController.needsGeometryRead(
            desired: desired, current: current, inFlight: inFlight, token: token,
            pendingFlash: pendingFlash, rereadGeometry: rereadGeometry)
    }

    /// 모드 전환의 읽기가 아직 도는 중에 사다리 관찰 루프의 재무장이 뒤따라 온다 — 그때
    /// 또 읽으면 토큰이 올라가 방금 띄운 읽기가 폐기되고 flash가 왕복 하나만큼 늦어진다.
    @Test("같은 상태를 같은 토큰으로 읽는 중이면 다시 읽지 않는다")
    func inFlightReadForSameStateIsReused() {
        let inFlight = ModeIndicatorController.InFlight(request: normal, token: 7)
        #expect(
            needsRead(
                desired: normal, current: normal, inFlight: inFlight, token: 7,
                pendingFlash: true) == false)
    }

    /// 진행 중 읽기가 폐기 예약된 상태(사다리를 벗어났다 돌아온 경우)면 그것을 기다려선 안
    /// 된다 — 착지해도 토큰 불일치로 버려져 화면에 아무것도 남지 않는다.
    @Test("진행 중 읽기의 토큰이 낡았으면 다시 읽는다")
    func staleInFlightTokenForcesNewRead() {
        let inFlight = ModeIndicatorController.InFlight(request: normal, token: 7)
        #expect(
            needsRead(
                desired: normal, current: normal, inFlight: inFlight, token: 9,
                pendingFlash: true))
    }

    @Test("기하가 변했으면 같은 상태를 읽는 중이어도 다시 읽는다")
    func geometrySignalForcesNewRead() {
        let inFlight = ModeIndicatorController.InFlight(request: normal, token: 7)
        #expect(
            needsRead(
                desired: normal, current: normal, inFlight: inFlight, token: 7,
                rereadGeometry: true))
    }

    /// Insert는 배지가 없으니 앵커 이벤트(포커스·창 이동·디스플레이 재구성)에 AX 왕복이
    /// 0건이어야 한다 — 창 드래그마다 읽기가 붙으면 이벤트 기반의 이점이 사라진다.
    @Test("Insert의 앵커 이벤트는 읽지 않는다")
    func insertAnchorEventsDoNotRead() {
        #expect(needsRead(desired: insert, current: insert, rereadGeometry: true) == false)
    }

    /// 다만 전환 자체는 Insert여도 flash를 띄워야 하므로 읽는다.
    @Test("밀린 flash는 Insert여도 읽는다")
    func pendingFlashReadsEvenForInsert() {
        #expect(needsRead(desired: insert, current: insert, pendingFlash: true))
    }

    @Test("같은 배지가 이미 떠 있으면 사다리 변화만으로는 읽지 않는다")
    func unchangedBadgeSkipsRead() {
        #expect(needsRead(desired: normal, current: normal) == false)
    }

    @Test("표시할 것이 달라졌으면 읽는다")
    func changedPresentationReads() {
        #expect(needsRead(desired: normal, current: insert))
        #expect(needsRead(desired: normal, current: nil))
    }
}

@MainActor
struct ModeIndicatorToggleTests {
    @Test("미설정 키 → 제품 기본값 on")
    func defaultsToEnabled() throws {
        try withTemporaryDefaults { defaults in
            #expect(ModeIndicatorController(defaults: defaults).isEnabled)
        }
    }

    @Test("저장된 false는 init에서 로드된다")
    func storedFalseLoadsAtInit() throws {
        try withTemporaryDefaults { defaults in
            defaults.set(false, forKey: PreferenceKeys.onScreenModeIndicatorEnabled)
            #expect(ModeIndicatorController(defaults: defaults).isEnabled == false)
        }
    }

    @Test("토글 영속: didSet 저장 → 새 컨트롤러 init 로드")
    func togglePersistsAcrossControllers() throws {
        try withTemporaryDefaults { defaults in
            let first = ModeIndicatorController(defaults: defaults)
            first.isEnabled = false
            // 존재 확인이 먼저 — `bool(forKey:)`는 미설정 키에도 false라 이것 없이는
            // 영속을 통째로 지워도 통과한다.
            #expect(defaults.object(forKey: PreferenceKeys.onScreenModeIndicatorEnabled) != nil)
            #expect(defaults.bool(forKey: PreferenceKeys.onScreenModeIndicatorEnabled) == false)

            let second = ModeIndicatorController(defaults: defaults)
            #expect(second.isEnabled == false)
        }
    }

    /// 배선(`bootstrap`)이 없으면 컨트롤러는 상태를 받은 적이 없다 — 그 상태의 토글 조작은
    /// 화면에도 AX에도 닿지 않아야 한다. 테스트가 실기기 오버레이를 띄우지 않는 근거다.
    @Test("입력이 밀린 적 없으면 토글은 무해하다")
    func togglingWithoutInputsIsHarmless() throws {
        try withTemporaryDefaults { defaults in
            let controller = ModeIndicatorController(defaults: defaults)
            controller.isEnabled = false
            controller.isEnabled = true
            #expect(controller.isEnabled)
        }
    }
}

/// 알약 글씨 색 — 강조색은 사용자가 고르므로 흰 글씨가 늘 읽히지는 않는다.
///
/// **표본이 `NSColor.systemYellow` 같은 동적 시스템 색이 아니라 고정 sRGB 성분인 것이
/// 계약이다.** 동적 색은 외양에 따라 값이 달라져 답이 테스트를 돌린 머신에 묶인다 —
/// 그래파이트가 정확히 그렇다: 라이트 #8E8E93은 흰 글씨 대비 3.26:1(흰 글씨), 다크
/// #98989D는 2.87:1(검은 글씨)이라 3:1 선을 사이에 두고 갈린다.
@MainActor
struct ModeIndicatorPillContrastTests {
    private func accent(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// 흰 글씨 대비 3:1 이상 — 파랑 4.00:1, 보라 4.12, 분홍 3.64, 빨강 3.55.
    @Test("흰 글씨가 읽히는 강조색은 흰 글씨를 유지한다")
    func darkAccentsKeepWhiteText() {
        let accents = [
            accent(0, 0.48, 1), accent(0.69, 0.32, 0.87), accent(1, 0.18, 0.33),
            accent(1, 0.23, 0.19),
        ]
        for color in accents {
            #expect(ModeIndicatorPanel.textColor(on: color) == .white)
        }
    }

    /// 노랑 강조색 + 흰 글씨는 1.41:1이라 사실상 읽히지 않는다 — 이 표가 그 회귀를 막는다.
    /// (주황 2.21, 초록 2.14, 다크 그래파이트 2.84.)
    @Test("밝은 강조색은 검은 글씨로 뒤집힌다")
    func lightAccentsFlipToBlackText() {
        let accents = [
            accent(1, 0.84, 0), accent(1, 0.58, 0), accent(0.16, 0.8, 0.25),
            accent(0.6, 0.6, 0.62),
        ]
        for color in accents {
            #expect(ModeIndicatorPanel.textColor(on: color) == .black)
        }
    }

    /// 흑백 극단 — 순수 함수라 답이 정의돼야 한다.
    @Test("검정 배경은 흰 글씨, 흰 배경은 검은 글씨")
    func extremesResolve() {
        #expect(ModeIndicatorPanel.textColor(on: accent(0, 0, 0)) == .white)
        #expect(ModeIndicatorPanel.textColor(on: accent(1, 1, 1)) == .black)
    }
}

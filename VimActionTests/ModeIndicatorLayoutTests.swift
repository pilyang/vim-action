//
//  ModeIndicatorLayoutTests.swift
//  VimActionTests
//

import CoreGraphics
import Testing

@testable import VimAction

/// 오버레이 배치의 순수 계층. AppKit도 AX도 부르지 않으므로 화면 구성은 전부 fixture다 —
/// 실기기 디스플레이 배치에 묶이면 CI와 개발 머신에서 답이 갈린다.
struct ModeIndicatorLayoutTests {
    /// 주 디스플레이 하나 (AppKit 좌표: 원점 (0,0), 높이 1000).
    private let primary = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    /// 주 화면 **왼쪽**에 붙은 보조 디스플레이 — 이 배치에서 AX x가 음수가 된다.
    private let secondaryOnLeft = CGRect(x: -1200, y: 0, width: 1200, height: 1000)
    private var primaryMaxY: CGFloat { primary.maxY }
    /// 메뉴바가 먹는 띠 — `visibleFrame`이 `frame`보다 이만큼 낮다.
    private let menuBarHeight: CGFloat = 25

    /// 화면 fixture. 고르는 축(`frame`)과 앉히는 축(`visibleFrame`)이 갈린 것을 재현한다.
    private func screen(_ frame: CGRect) -> ModeIndicatorLayout.Screen {
        .init(
            frame: frame,
            visibleFrame: CGRect(
                x: frame.minX, y: frame.minY,
                width: frame.width, height: frame.height - menuBarHeight))
    }

    private var primaryScreen: ModeIndicatorLayout.Screen { screen(primary) }
    private var secondaryScreen: ModeIndicatorLayout.Screen { screen(secondaryOnLeft) }

    private let badge = CGSize(width: 80, height: 22)

    // MARK: - 사다리

    @Test("사다리는 요소 → 창 → 없음 순이다")
    func ladderPrefersElementThenWindow() {
        let element = CGRect(x: 100, y: 200, width: 300, height: 40)
        let window = CGRect(x: 50, y: 100, width: 800, height: 600)

        #expect(
            ModeIndicatorLayout.anchor(.init(element: element, window: window))
                == .element(element))
        #expect(ModeIndicatorLayout.anchor(.init(element: nil, window: window)) == .window(window))
        #expect(ModeIndicatorLayout.anchor(.init(element: nil, window: nil)) == nil)
    }

    /// 요소가 0×0을 보고하는 앱이 있다 — 그 rect에 배지를 붙이면 화면 구석에 떠 있는 것처럼
    /// 보이므로 한 단으로 인정하지 않고 창으로 내려가야 한다.
    @Test("면적 없는 rect는 한 단으로 안 친다")
    func degenerateRectFallsThrough() {
        let window = CGRect(x: 50, y: 100, width: 800, height: 600)
        let empty = CGRect(x: 100, y: 200, width: 0, height: 0)
        let zeroHeight = CGRect(x: 100, y: 200, width: 300, height: 0)

        #expect(ModeIndicatorLayout.anchor(.init(element: empty, window: window)) == .window(window))
        #expect(
            ModeIndicatorLayout.anchor(.init(element: zeroHeight, window: window))
                == .window(window))
        #expect(ModeIndicatorLayout.anchor(.init(element: empty, window: empty)) == nil)
    }

    // MARK: - 배치 (AX 좌표: y는 아래로 증가)

    /// 텍스트 영역 안에 겹치면 사용자가 쓰고 있는 글자를 가린다 — 그래서 요소 **바깥** 위다.
    @Test("요소 단은 요소 바깥 오른쪽 위")
    func elementBadgeSitsOutsideTopRight() {
        let element = CGRect(x: 100, y: 200, width: 300, height: 40)
        let frame = ModeIndicatorLayout.badgeFrameInAXSpace(anchor: .element(element), size: badge)

        #expect(frame.maxX == element.maxX)  // 오른쪽 정렬
        #expect(frame.maxY < element.minY)  // 요소 top 위 (AX에서 minY가 위)
        #expect(frame.size == badge)
    }

    /// 창 밖으로 나가면 어느 창의 상태인지 읽히지 않는다.
    @Test("창 단은 창 안쪽 오른쪽 위")
    func windowBadgeSitsInsideTopRight() {
        let window = CGRect(x: 50, y: 100, width: 800, height: 600)
        let frame = ModeIndicatorLayout.badgeFrameInAXSpace(anchor: .window(window), size: badge)

        #expect(frame.maxX < window.maxX)
        #expect(frame.minX > window.minX)
        #expect(frame.minY > window.minY)
        #expect(frame.maxY < window.maxY)
    }

    // MARK: - 좌표 변환

    @Test("AX → AppKit은 주 화면 높이 하나로 뒤집는다")
    func flipUsesPrimaryScreenHeight() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 40)
        let flipped = ModeIndicatorLayout.flip(rect, primaryScreenMaxY: primaryMaxY)

        #expect(flipped.minX == 100)  // x는 건드리지 않는다
        #expect(flipped.minY == primaryMaxY - rect.maxY)  // 1000 - 240 = 760
        #expect(flipped.size == rect.size)
    }

    /// 주 디스플레이 왼쪽 보조 화면에서는 AX x가 음수다. 디스플레이별 개별 변환 없이 **같은**
    /// 전역 변환으로 픽셀 정렬이 맞음이 실측됐다 — 음수 x가 그대로 보존되어야 한다.
    @Test("보조 디스플레이(AX x 음수)도 같은 전역 변환")
    func flipPreservesNegativeXOnSecondaryDisplay() {
        let rect = CGRect(x: -900, y: 300, width: 300, height: 40)
        let flipped = ModeIndicatorLayout.flip(rect, primaryScreenMaxY: primaryMaxY)

        #expect(flipped.minX == -900)
        #expect(flipped.minY == primaryMaxY - rect.maxY)  // 1000 - 340 = 660
    }

    // MARK: - 클램프

    /// 주 화면이 아니라 **앵커가 있는 화면**이 기준이다 — 주 화면으로 클램프하면 보조
    /// 디스플레이의 배지가 앵커에서 화면 하나만큼 떨어진 곳에 뜬다.
    @Test("클램프는 앵커가 있는 화면 안으로 민다")
    func clampUsesScreenContainingAnchor() {
        let screens = [primaryScreen, secondaryScreen]
        // 보조 화면 오른쪽 끝에 걸친 앵커와, 그 밖으로 삐져나간 배지.
        let anchor = CGRect(x: -200, y: 500, width: 180, height: 40)
        let frame = CGRect(x: -40, y: 500, width: badge.width, height: badge.height)

        let clamped = ModeIndicatorLayout.clamp(frame, nearAnchor: anchor, screens: screens)

        #expect(clamped.maxX == secondaryOnLeft.maxX)
        #expect(clamped.minY == frame.minY)  // 세로는 이미 안쪽이라 그대로
        #expect(clamped.size == frame.size)
    }

    @Test("화면 위쪽으로 나간 배지는 화면 안으로 내려온다")
    func clampPullsBadgeBackFromTopEdge() {
        let anchor = CGRect(x: 100, y: 960, width: 300, height: 40)
        let frame = CGRect(x: 100, y: 990, width: badge.width, height: badge.height)

        let clamped = ModeIndicatorLayout.clamp(frame, nearAnchor: anchor, screens: [primaryScreen])

        // 화면 **위 경계**가 아니라 `visibleFrame`의 위 경계다 — 메뉴바 뒤로 들어간 알약은
        // 보이지 않아 기능이 고장 난 것으로 읽힌다.
        #expect(clamped.maxY == primaryScreen.visibleFrame.maxY)
        #expect(clamped.minX == frame.minX)
    }

    /// 고르는 축과 앉히는 축이 갈린 이유 그 자체 — 메뉴바 띠 안의 앵커는 그 화면의
    /// `visibleFrame`과 교차하지 않으므로, 포함 판정까지 `visibleFrame`으로 하면 앵커가
    /// 자기 디스플레이를 못 찾고 `screens.first`(주 화면)로 떨어져 알약이 화면 하나만큼 튄다.
    @Test("메뉴바 띠 안의 앵커도 자기 디스플레이에 남고 띠 아래로 밀린다")
    func clampKeepsMenuBarBandAnchorOnItsOwnScreen() {
        // 보조 화면의 메뉴바 띠(975~1000) 안에 있는 앵커 — 주 화면과는 겹치지 않는다.
        let anchor = CGRect(x: -600, y: 980, width: 300, height: 18)
        let frame = CGRect(x: -400, y: 985, width: badge.width, height: badge.height)

        let clamped = ModeIndicatorLayout.clamp(
            frame, nearAnchor: anchor, screens: [primaryScreen, secondaryScreen])

        // ⓐ 주 화면(`screens.first`)으로 튀지 않는다.
        #expect(clamped.minX == frame.minX)
        #expect(secondaryOnLeft.contains(clamped))
        // ⓑ 그 화면의 메뉴바 띠 바로 아래에 앉는다.
        #expect(clamped.maxY == secondaryScreen.visibleFrame.maxY)
    }

    // MARK: - 전체 파이프라인

    /// 사다리의 마지막 단 — 붙일 곳이 없으면 오버레이를 띄우지 않는다.
    @Test("앵커가 없으면 패널 frame도 없다")
    func noAnchorMeansNoPanel() {
        #expect(
            ModeIndicatorLayout.panelFrame(
                anchors: .init(), size: badge, screens: [primaryScreen],
                primaryScreenMaxY: primaryMaxY) == nil)
    }

    @Test("요소 앵커의 전체 파이프라인이 화면 안 프레임을 낸다")
    func panelFrameEndToEnd() {
        let element = CGRect(x: 100, y: 200, width: 300, height: 40)
        let frame = ModeIndicatorLayout.panelFrame(
            anchors: .init(element: element), size: badge, screens: [primaryScreen],
            primaryScreenMaxY: primaryMaxY)

        let expected = ModeIndicatorLayout.clamp(
            ModeIndicatorLayout.flip(
                ModeIndicatorLayout.badgeFrameInAXSpace(anchor: .element(element), size: badge),
                primaryScreenMaxY: primaryMaxY),
            nearAnchor: ModeIndicatorLayout.flip(element, primaryScreenMaxY: primaryMaxY),
            screens: [primaryScreen])
        #expect(frame == expected)
        #expect(primaryScreen.visibleFrame.contains(frame!))
    }
}

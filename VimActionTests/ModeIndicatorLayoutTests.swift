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

    /// 실측표의 전형 — 요소 안의 캐럿 (AX 좌표).
    private let element = CGRect(x: 100, y: 200, width: 300, height: 40)
    private let window = CGRect(x: 50, y: 100, width: 800, height: 600)
    private let caret = CGRect(x: 150, y: 210, width: 1, height: 18)

    // MARK: - 사다리

    @Test("flash 사다리는 캐럿 → 요소 → 창 → 없음 순이다")
    func caretFirstLadderPrefersCaretThenElementThenWindow() {
        #expect(
            ModeIndicatorLayout.anchor(
                .init(element: element, window: window, caret: caret), for: .caretFirst)
                == .caret(caret))
        #expect(
            ModeIndicatorLayout.anchor(.init(element: element, window: window), for: .caretFirst)
                == .element(element))
        #expect(
            ModeIndicatorLayout.anchor(.init(window: window), for: .caretFirst) == .window(window))
        #expect(ModeIndicatorLayout.anchor(.init(), for: .caretFirst) == nil)
    }

    /// 배지가 캐럿을 따라다니면 키마다·스크롤마다 다시 읽어야 한다 — 배지는 캐럿을 보지 않는다.
    @Test("배지 사다리는 요소 → 창 → 없음 순이고 캐럿을 보지 않는다")
    func elementFirstLadderIgnoresCaret() {
        #expect(
            ModeIndicatorLayout.anchor(
                .init(element: element, window: window, caret: caret), for: .elementFirst)
                == .element(element))
        #expect(
            ModeIndicatorLayout.anchor(.init(window: window, caret: caret), for: .elementFirst)
                == .window(window))
        #expect(ModeIndicatorLayout.anchor(.init(caret: caret), for: .elementFirst) == nil)
    }

    /// 요소가 0×0을 보고하는 앱이 있다 — 그 rect에 배지를 붙이면 화면 구석에 떠 있는 것처럼
    /// 보이므로 한 단으로 인정하지 않고 창으로 내려가야 한다.
    @Test("면적 없는 rect는 한 단으로 안 친다")
    func degenerateRectFallsThrough() {
        let empty = CGRect(x: 100, y: 200, width: 0, height: 0)
        let zeroHeight = CGRect(x: 100, y: 200, width: 300, height: 0)

        #expect(
            ModeIndicatorLayout.anchor(.init(element: empty, window: window), for: .elementFirst)
                == .window(window))
        #expect(
            ModeIndicatorLayout.anchor(
                .init(element: zeroHeight, window: window), for: .elementFirst)
                == .window(window))
        #expect(
            ModeIndicatorLayout.anchor(.init(element: empty, window: empty), for: .elementFirst)
                == nil)
    }

    // MARK: - 캐럿 유효성

    /// Slack 컴포저는 캐럿을 0×18로 보고하고 그것이 정확한 캐럿이다 — 폭은 보지 않는다.
    @Test("폭 0 캐럿도 쓸 만하다")
    func zeroWidthCaretIsUsable() {
        let slack = CGRect(x: 150, y: 210, width: 0, height: 18)
        #expect(ModeIndicatorLayout.isUsableCaret(slack, element: element))
        #expect(
            ModeIndicatorLayout.anchor(.init(element: element, caret: slack), for: .caretFirst)
                == .caret(slack))
    }

    @Test("높이 0 캐럿은 안 친다")
    func zeroHeightCaretIsRejected() {
        let flat = CGRect(x: 150, y: 210, width: 1, height: 0)
        #expect(ModeIndicatorLayout.isUsableCaret(flat, element: element) == false)
        #expect(
            ModeIndicatorLayout.anchor(.init(element: element, caret: flat), for: .caretFirst)
                == .element(element))
    }

    /// 마커 경로는 선택이 내용 끝에 있으면 캐럿 대신 요소 전체 rect를 돌려준다 — 그 퇴화를
    /// 캐럿으로 쓰면 알약이 입력칸 아래에 뜬다.
    @Test("요소 rect와 같은 캐럿은 안 친다")
    func caretEqualToElementIsRejected() {
        #expect(ModeIndicatorLayout.isUsableCaret(element, element: element) == false)
        #expect(
            ModeIndicatorLayout.anchor(.init(element: element, caret: element), for: .caretFirst)
                == .element(element))
    }

    /// 스크롤로 시야 밖에 나간 캐럿·쓰레기값이 입력칸 밖에 떠 있으면 안 된다.
    @Test("요소 밖 캐럿은 안 친다")
    func caretOutsideElementIsRejected() {
        let scrolledOut = CGRect(x: 150, y: 500, width: 1, height: 18)
        #expect(ModeIndicatorLayout.isUsableCaret(scrolledOut, element: element) == false)
        #expect(
            ModeIndicatorLayout.anchor(
                .init(element: element, caret: scrolledOut), for: .caretFirst)
                == .element(element))
    }

    /// 요소 rect가 없거나 면적이 없으면 "안에 있는가"를 물을 수 없다 — 높이만 본다.
    @Test("요소 rect가 쓸 만하지 않으면 캐럿은 높이만 본다")
    func caretWithUnusableElementNeedsOnlyHeight() {
        let empty = CGRect(x: 100, y: 200, width: 0, height: 0)
        #expect(ModeIndicatorLayout.isUsableCaret(caret, element: nil))
        #expect(ModeIndicatorLayout.isUsableCaret(caret, element: empty))
        #expect(
            ModeIndicatorLayout.anchor(.init(element: empty, caret: caret), for: .caretFirst)
                == .caret(caret))
    }

    // MARK: - 배치 (AX 좌표: y는 아래로 증가)

    /// macOS가 입력 소스 전환 때 캐럿 아래에 띄우는 인디케이터와 같은 자리다.
    @Test("캐럿 단은 캐럿 바로 아래, 왼쪽 정렬")
    func caretPillSitsBelowCaretLeftAligned() {
        let frame = ModeIndicatorLayout.badgeFrameInAXSpace(anchor: .caret(caret), size: badge)

        #expect(frame.minX == caret.minX)
        #expect(frame.minY == caret.maxY + 4)
        #expect(frame.size == badge)
    }

    /// 텍스트 영역 안에 겹치면 사용자가 쓰고 있는 글자를 가린다 — 그래서 요소 **바깥** 위다.
    @Test("요소 단은 요소 바깥 오른쪽 위")
    func elementBadgeSitsOutsideTopRight() {
        let frame = ModeIndicatorLayout.badgeFrameInAXSpace(anchor: .element(element), size: badge)

        #expect(frame.maxX == element.maxX)  // 오른쪽 정렬
        #expect(frame.maxY < element.minY)  // 요소 top 위 (AX에서 minY가 위)
        #expect(frame.size == badge)
    }

    /// 창 밖으로 나가면 어느 창의 상태인지 읽히지 않는다.
    @Test("창 단은 창 안쪽 오른쪽 위")
    func windowBadgeSitsInsideTopRight() {
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
                anchors: .init(), ladder: .caretFirst, size: badge, screens: [primaryScreen],
                primaryScreenMaxY: primaryMaxY) == nil)
    }

    @Test("요소 앵커의 전체 파이프라인이 화면 안 프레임을 낸다")
    func panelFrameEndToEnd() {
        let frame = ModeIndicatorLayout.panelFrame(
            anchors: .init(element: element), ladder: .elementFirst, size: badge,
            screens: [primaryScreen], primaryScreenMaxY: primaryMaxY)

        let expected = ModeIndicatorLayout.clamp(
            ModeIndicatorLayout.flip(
                ModeIndicatorLayout.badgeFrameInAXSpace(anchor: .element(element), size: badge),
                primaryScreenMaxY: primaryMaxY),
            nearAnchor: ModeIndicatorLayout.flip(element, primaryScreenMaxY: primaryMaxY),
            screens: [primaryScreen])
        #expect(frame == expected)
        #expect(primaryScreen.visibleFrame.contains(frame!))
    }

    /// 보조 디스플레이의 폭 0 캐럿(Slack) — 화면 선택이 폭 0 앵커에서도 자기 디스플레이를
    /// 찾아야 알약이 주 화면으로 튀지 않는다 (`CGRect.intersects`의 폭 0 동작에 기댄다).
    @Test("보조 디스플레이의 폭 0 캐럿도 그 화면 안에 앉는다")
    func caretPanelFrameEndToEnd() {
        let element = CGRect(x: -900, y: 300, width: 300, height: 40)
        let caret = CGRect(x: -800, y: 310, width: 0, height: 18)
        let frame = ModeIndicatorLayout.panelFrame(
            anchors: .init(element: element, caret: caret), ladder: .caretFirst, size: badge,
            screens: [primaryScreen, secondaryScreen], primaryScreenMaxY: primaryMaxY)

        let expected = ModeIndicatorLayout.flip(
            ModeIndicatorLayout.badgeFrameInAXSpace(anchor: .caret(caret), size: badge),
            primaryScreenMaxY: primaryMaxY)
        #expect(frame == expected)  // 이미 화면 안이라 클램프가 움직이지 않는다
        #expect(secondaryScreen.visibleFrame.contains(frame!))
    }

    // MARK: - 화면 테두리

    @Test("테두리는 앵커가 있는 화면의 visibleFrame을 두른다")
    func borderCoversVisibleFrameOfAnchorScreen() {
        let layout = ModeIndicatorLayout.borderLayout(
            anchors: .init(element: element), labelSize: badge,
            screens: [primaryScreen, secondaryScreen], primaryScreenMaxY: primaryMaxY)

        // `frame`이 아니라 `visibleFrame` — 위 변이 메뉴바 뒤에 숨으면 세 변짜리로 보인다.
        #expect(layout?.frame == primaryScreen.visibleFrame)
    }

    @Test("모서리 라벨은 테두리 안쪽 오른쪽 위")
    func borderLabelSitsInsideTopRightCorner() {
        let layout = ModeIndicatorLayout.borderLayout(
            anchors: .init(element: element), labelSize: badge,
            screens: [primaryScreen], primaryScreenMaxY: primaryMaxY)!

        #expect(layout.labelFrame.size == badge)
        #expect(layout.frame.contains(layout.labelFrame))
        // 선 굵기보다 안쪽이라 선과 겹치지 않는다.
        #expect(layout.frame.maxX - layout.labelFrame.maxX > ModeIndicatorLayout.borderStrokeWidth)
        #expect(layout.frame.maxY - layout.labelFrame.maxY > ModeIndicatorLayout.borderStrokeWidth)
        // 왼쪽·아래로는 멀리 떨어져 있다 — 오른쪽 위 모서리다.
        #expect(layout.labelFrame.minX > layout.frame.midX)
        #expect(layout.labelFrame.minY > layout.frame.midY)
    }

    /// 요소는 창 안에 있으므로 요소 단이든 창 단이든 같은 디스플레이다 — AX를 더 읽지 않고
    /// 앵커 rect로만 화면을 고른다.
    @Test("테두리는 보조 디스플레이의 앵커를 따라간다")
    func borderFollowsAnchorToSecondaryDisplay() {
        let element = CGRect(x: -900, y: 300, width: 300, height: 40)
        let byElement = ModeIndicatorLayout.borderLayout(
            anchors: .init(element: element), labelSize: badge,
            screens: [primaryScreen, secondaryScreen], primaryScreenMaxY: primaryMaxY)
        let window = CGRect(x: -1100, y: 100, width: 800, height: 600)
        let byWindow = ModeIndicatorLayout.borderLayout(
            anchors: .init(window: window), labelSize: badge,
            screens: [primaryScreen, secondaryScreen], primaryScreenMaxY: primaryMaxY)

        #expect(byElement?.frame == secondaryScreen.visibleFrame)
        #expect(byWindow?.frame == secondaryScreen.visibleFrame)
    }

    /// 앵커가 어느 화면과도 겹치지 않으면(화면 밖) 첫 화면이다 — 순수 함수라 답이 정의돼야 한다.
    @Test("겹치는 화면이 없으면 첫 화면으로 내려간다")
    func borderFallsBackToFirstScreenWhenNoneIntersects() {
        let offScreen = CGRect(x: 5000, y: 5000, width: 300, height: 40)
        let layout = ModeIndicatorLayout.borderLayout(
            anchors: .init(element: offScreen), labelSize: badge,
            screens: [secondaryScreen, primaryScreen], primaryScreenMaxY: primaryMaxY)

        #expect(layout?.frame == secondaryScreen.visibleFrame)
    }

    /// 배지와 같은 사다리(요소 → 창)라 캐럿만으로는 테두리도 없다.
    @Test("앵커가 없으면 테두리도 없다")
    func borderWithoutAnchorIsNil() {
        #expect(
            ModeIndicatorLayout.borderLayout(
                anchors: .init(), labelSize: badge, screens: [primaryScreen],
                primaryScreenMaxY: primaryMaxY) == nil)
        #expect(
            ModeIndicatorLayout.borderLayout(
                anchors: .init(caret: caret), labelSize: badge, screens: [primaryScreen],
                primaryScreenMaxY: primaryMaxY) == nil)
    }
}

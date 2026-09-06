//
//  ModeIndicatorLayout.swift
//  VimAction
//

import CoreGraphics

/// 모드 인디케이터 오버레이의 배치 계산 — **순수 계층**이다. AppKit도 AX도 부르지 않고
/// `CGRect`/`CGSize`만 주고받으며, 화면 구성은 호출자가 frame 배열로 넘긴다.
///
/// 분리한 이유는 테스트 가능성이다: 사다리·배치·클램프·좌표 변환은 실기기 디스플레이
/// 구성과 AX 응답에 의존하지 않는 표 검증 대상인데, `NSScreen`을 직접 읽으면 테스트가
/// 그것을 돌린 머신의 디스플레이 배치에 묶인다 (`MenuBarIndicator.resolve`·
/// `AXTrustVerdict.extentIsVisible`와 같은 부류의 순수 함수).
nonisolated enum ModeIndicatorLayout {
    /// 캐럿 단 알약이 캐럿 아래에 뜰 때의 간격 (스파이크 값).
    private static let caretGap: CGFloat = 4
    /// 요소 단 배지가 요소 위쪽 바깥에 뜰 때의 간격.
    private static let elementGap: CGFloat = 4
    /// 창 단 배지가 창 안쪽 오른쪽 위에 붙을 때의 인셋 (오른쪽, 위).
    private static let windowInset = (horizontal: CGFloat(12), vertical: CGFloat(6))
    /// 화면 테두리의 선 굵기. 패널이 그릴 때도 이 값을 읽는다 — 라벨 인셋이 선 굵기에서
    /// 파생되므로 두 값이 따로 살면 라벨이 선에 겹친다.
    static let borderStrokeWidth: CGFloat = 4
    /// 화면 테두리의 모서리 라벨이 테두리 안쪽 모서리에서 떨어지는 거리 (선 굵기 + 여백).
    private static let borderLabelInset: CGFloat = borderStrokeWidth + 8

    /// 화면 하나 (전부 AppKit 좌표). **고르는 축과 놓는 축이 다르다**: `frame`은 앵커가 어느
    /// 디스플레이에 속하는지 판정하고, `visibleFrame`은 알약을 실제로 놓을 수 있는 범위다.
    ///
    /// 두 축을 가른 이유는 메뉴바 띠다. 텍스트 뷰가 창 전체인 앱(TextEdit)을 최대화하면
    /// "요소 위쪽 바깥" 규칙이 알약을 화면 맨 위, 즉 **메뉴바·노치 뒤**로 보낸다 — 그래서
    /// 앉히는 범위는 `visibleFrame`이어야 한다. 반대로 포함 판정까지 `visibleFrame`으로 하면
    /// 메뉴바 띠 안에 있는 앵커가 자기 디스플레이를 못 찾고 주 화면으로 떨어져 알약이 화면
    /// 하나만큼 튄다. 호출자가 메인에서 `NSScreen`을 읽어 채운다.
    struct Screen: Sendable, Equatable {
        var frame: CGRect
        var visibleFrame: CGRect

        init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// 기하 리더가 읽어 오는 것 — **AX 좌표계**(좌상단 원점, y는 아래로 증가)의 rect들이다.
    /// `caret`은 flash가 있는 요청에서만 읽힌다 — 배지만 다시 놓는 앵커 이벤트는 `nil`로 온다.
    struct Anchors: Sendable, Equatable {
        var element: CGRect?
        var window: CGRect?
        var caret: CGRect?

        init(element: CGRect? = nil, window: CGRect? = nil, caret: CGRect? = nil) {
            self.element = element
            self.window = window
            self.caret = caret
        }
    }

    /// 사다리가 고른 한 단. 배치 규칙이 단마다 다르기 때문에 rect만이 아니라 **어느 단인지**가
    /// 결과에 남아야 한다.
    enum Anchor: Equatable {
        case caret(CGRect)
        case element(CGRect)
        case window(CGRect)

        var rect: CGRect {
            switch self {
            case .caret(let rect), .element(let rect), .window(let rect): rect
            }
        }
    }

    /// 사다리의 첫 단 — **묻는 알약에 따라 다르다.** flash는 `caretFirst`(캐럿 → 요소 → 창),
    /// 상시 배지는 `elementFirst`(요소 → 창)다.
    ///
    /// 배지가 캐럿을 따라다니지 않는 것이 결정이다: 따라다니려면 키마다(그리고 관측되지 않는
    /// 마우스 스크롤마다) AX를 다시 읽어야 하고, 안 읽으면 배지가 엉뚱한 자리에 남는다. 1초 뒤
    /// 사라지는 flash에는 그 드리프트가 없어 캐럿을 쓸 수 있다
    /// (`20260906_mode-indicator-anchor-ladder-event-driven.md` 결정 2). 알약 이름(flash/badge)이
    /// 아니라 첫 단 이름인 것은 `ModeIndicatorStyle`과 케이스 이름이 겹치지 않게 하기 위해서다.
    enum Ladder {
        case caretFirst
        case elementFirst
    }

    /// 앵커 사다리 — 위 단이 실패하면 다음 단으로 내려간다. 마지막은 "없음"이다.
    ///
    /// **면적이 있는 rect만 한 단으로 인정한다**: 요소가 0×0(또는 음수)을 보고하는 앱이 있고,
    /// 그런 rect에 배지를 붙이면 화면 구석에 떠 있는 것처럼 보인다. 이 판정을 리더가 아니라
    /// 여기 두는 것이 계약이다 — 리더는 AX가 답한 것을 그대로 옮기고, 무엇이 쓸 만한
    /// 앵커인지는 순수 계층이 정해야 표로 검증된다. 캐럿 단의 유효성(`isUsableCaret`)도 같다.
    static func anchor(_ anchors: Anchors, for ladder: Ladder) -> Anchor? {
        if case .caretFirst = ladder, let caret = anchors.caret,
            isUsableCaret(caret, element: anchors.element)
        {
            return .caret(caret)
        }
        if let element = anchors.element, isUsable(element) { return .element(element) }
        if let window = anchors.window, isUsable(window) { return .window(window) }
        return nil
    }

    /// 배지를 붙일 만한 rect인가. **이 규칙의 유일한 소유자다** — 기하 리더도 이것으로
    /// "요소가 답했으니 창은 안 읽어도 된다"를 판정하므로, 두 벌이 되면 리더가 건너뛴 읽기를
    /// 사다리가 필요로 하는 어긋남이 생긴다.
    static func isUsable(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0
    }

    /// 캐럿 rect를 한 단으로 인정하는가. `isUsable`과 같은 계약이다 — 리더가 캐럿 변형
    /// 셋(`(loc,1)` → `(loc-1,1)` → 텍스트 마커)을 차례로 시도하며 다음 변형으로 넘어갈지를
    /// 이것으로 판정하므로, 규칙은 여기 한 벌이다.
    ///
    /// - **높이만 있으면 된다** — Slack 컴포저는 캐럿을 0×18로 보고하고 그것이 정확한 캐럿이다.
    /// - **요소 rect와 같으면 아니다** — 마커 경로는 선택이 내용 끝에 있으면 캐럿 대신 요소
    ///   전체 rect로 퇴화한다 (Chromium 실측).
    /// - **요소 rect가 쓸 만하면 그 안에 걸쳐야 한다** — 스크롤로 시야 밖에 나간 캐럿이나
    ///   쓰레기값이 입력칸 밖에 떠 있으면 안 된다. `CGRect.intersects`는 폭 0 rect에도
    ///   참을 돌려준다 (이 플랫폼에서 확인).
    static func isUsableCaret(_ caret: CGRect, element: CGRect?) -> Bool {
        guard caret.height > 0, caret != element else { return false }
        guard let element, isUsable(element) else { return true }
        return caret.intersects(element)
    }

    /// 단별 배지 배치 (AX 좌표계).
    ///
    /// - 캐럿 단: 캐럿 **바로 아래**, 왼쪽 정렬 — macOS가 입력 소스 전환 때 캐럿 아래에 띄우는
    ///   인디케이터와 같은 자리다. 줄 첫머리에서는 `(loc-1,1)`이 개행 문자라 rect가 이전 줄
    ///   끝에 있어 알약도 거기 뜬다 — 실측에서 수용한 quirk이고 특별 취급하지 않는다.
    /// - 요소 단: 요소 **바깥 오른쪽 위** — 오른쪽 모서리에 맞추고 요소 top 위로 띄운다.
    ///   텍스트 영역 안에 겹치면 사용자가 쓰고 있는 글자를 가린다.
    /// - 창 단: 창 **안쪽 오른쪽 위** — 창 밖으로 나가면 어느 창의 상태인지 읽히지 않는다.
    static func badgeFrameInAXSpace(anchor: Anchor, size: CGSize) -> CGRect {
        switch anchor {
        case .caret(let caret):
            return CGRect(
                x: caret.minX, y: caret.maxY + caretGap,
                width: size.width, height: size.height)
        case .element(let element):
            return CGRect(
                x: element.maxX - size.width,
                y: element.minY - size.height - elementGap,
                width: size.width, height: size.height)
        case .window(let window):
            return CGRect(
                x: window.maxX - size.width - windowInset.horizontal,
                y: window.minY + windowInset.vertical,
                width: size.width, height: size.height)
        }
    }

    /// AX(좌상단 원점) → AppKit(좌하단 원점). **주 화면 높이 하나로 뒤집는 전역 변환**이며,
    /// 주 디스플레이 왼쪽에 붙은 보조 디스플레이(AX x 음수)에서도 픽셀 정렬이 맞음이
    /// 실측됐다 — 디스플레이별 개별 변환은 필요 없다
    /// (`20260906_mode-indicator-anchor-ladder-event-driven.md` 결정 6).
    static func flip(_ rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX, y: primaryScreenMaxY - rect.maxY,
            width: rect.width, height: rect.height)
    }

    /// 앵커가 속한 화면 — 판정 축은 `frame`이다 (`Screen` 주석의 메뉴바 띠 사유). 클램프와
    /// 화면 테두리가 같은 규칙으로 화면을 고르도록 한 자리에 둔다.
    private static func screen(near anchor: CGRect, in screens: [Screen]) -> Screen? {
        screens.first { $0.frame.intersects(anchor) }
    }

    /// 알약을 **앵커가 있는 화면의 `visibleFrame`** 안으로 민다 (전부 AppKit 좌표).
    ///
    /// 주 화면 기준이 아닌 것이 요점이다: 보조 디스플레이의 창 모서리에 있는 앵커를 주 화면으로
    /// 클램프하면 알약이 앵커에서 화면 하나만큼 떨어진 곳에 뜬다. 앵커와 겹치는 화면이 없으면
    /// (앵커가 화면 밖) 알약과 겹치는 화면, 그것도 없으면 주 화면으로 내려간다.
    ///
    /// **화면 선택은 세 단 전부 `frame` 축이고, 미는 범위만 `visibleFrame`이다** —
    /// `Screen` 주석의 메뉴바 띠 사유 참고.
    static func clamp(_ frame: CGRect, nearAnchor anchor: CGRect, screens: [Screen]) -> CGRect {
        guard
            let screen = screen(near: anchor, in: screens)
                ?? screens.first(where: { $0.frame.intersects(frame) }) ?? screens.first
        else {
            // 화면 목록이 비는 것은 실기기에서 일어나지 않지만, 순수 함수라 답이 정의돼야 한다.
            return frame
        }
        let bounds = screen.visibleFrame
        return CGRect(
            x: min(max(frame.minX, bounds.minX), max(bounds.maxX - frame.width, bounds.minX)),
            y: min(max(frame.minY, bounds.minY), max(bounds.maxY - frame.height, bounds.minY)),
            width: frame.width, height: frame.height)
    }

    /// 컨트롤러가 부르는 알약 배치의 단일 진입점 — 사다리 → 배치 → 좌표 변환 → 클램프.
    /// 앵커가 없으면 `nil`이고, 그때 오버레이는 표시하지 않는다 (사다리의 마지막 단 "없음").
    ///
    /// `screens`·`primaryScreenMaxY`는 호출자가 메인에서 `NSScreen`을 읽어 넘긴다.
    /// `primaryScreenMaxY`는 **`frame`의 maxY**다 — 좌표계를 뒤집는 기준이지 배치 범위가
    /// 아니라서, 여기에 `visibleFrame`을 넣으면 전 좌표가 메뉴바 높이만큼 밀린다.
    static func panelFrame(
        anchors: Anchors, ladder: Ladder, size: CGSize, screens: [Screen],
        primaryScreenMaxY: CGFloat
    ) -> CGRect? {
        guard let anchor = anchor(anchors, for: ladder) else { return nil }
        let badge = flip(
            badgeFrameInAXSpace(anchor: anchor, size: size),
            primaryScreenMaxY: primaryScreenMaxY)
        return clamp(
            badge, nearAnchor: flip(anchor.rect, primaryScreenMaxY: primaryScreenMaxY),
            screens: screens)
    }

    /// 화면 테두리 스타일의 배치 (전부 AppKit 화면 좌표). `frame`이 테두리 패널이 덮는 범위이고
    /// `labelFrame`이 그 안 오른쪽 위 모서리의 라벨 알약이다.
    struct BorderLayout: Equatable {
        var frame: CGRect
        var labelFrame: CGRect
    }

    /// 화면 테두리 배치 — 상시 배지의 사다리(요소 → 창)로 앵커를 고르고, **그 앵커가 속한
    /// 디스플레이의 `visibleFrame`**을 두른다. 앵커가 없으면 배지와 마찬가지로 아무것도 없다.
    ///
    /// 화면은 앵커 rect로만 고른다 — AX를 더 읽지 않는다. 요소는 창 안에 있으므로 요소 단이든
    /// 창 단이든 같은 디스플레이다. 겹치는 화면이 없으면 첫 화면으로 내려간다(클램프의 가운데
    /// 단 "알약과 겹치는 화면"은 여기서 뜻이 없다 — 테두리 프레임이 곧 화면이다).
    ///
    /// `frame`이 아니라 `visibleFrame`인 이유: `frame`을 두르면 위 변이 메뉴바 뒤에, 아래 변이
    /// Dock 뒤에 숨어 테두리가 세 변짜리로 보인다. 라벨은 인셋만큼 안쪽이라 메뉴바와 겹치지 않는다.
    static func borderLayout(
        anchors: Anchors, labelSize: CGSize, screens: [Screen], primaryScreenMaxY: CGFloat
    ) -> BorderLayout? {
        guard let anchor = anchor(anchors, for: .elementFirst) else { return nil }
        let anchorFrame = flip(anchor.rect, primaryScreenMaxY: primaryScreenMaxY)
        guard let screen = screen(near: anchorFrame, in: screens) ?? screens.first else {
            return nil
        }
        let frame = screen.visibleFrame
        let label = CGRect(
            x: frame.maxX - borderLabelInset - labelSize.width,
            y: frame.maxY - borderLabelInset - labelSize.height,
            width: labelSize.width, height: labelSize.height)
        return BorderLayout(frame: frame, labelFrame: label)
    }
}

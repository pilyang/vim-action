//
//  ModeIndicatorBorderPanel.swift
//  VimAction
//

import AppKit

/// 화면 테두리 스타일의 상시 표시 — 포커스 창이 있는 디스플레이의 `visibleFrame`을 덮는 패널
/// **하나**에 강조색 테두리와 모서리 라벨 알약을 함께 그린다.
///
/// 라벨이 같은 패널의 서브뷰인 것이 요점이다: `hide()` 한 번에 테두리와 라벨이 같이 사라져,
/// 스타일을 배지로 되돌린 직후 라벨만 화면 구석에 남는 일이 없다. 색만으로 구분하지 않는다는
/// PRD 접근성 NFR 때문에 라벨은 항상 동반된다 — 테두리만으로는 어느 모드인지 말하지 못한다.
///
/// 비활성화 패널 설정은 `ModeIndicatorPanel.makeOverlayPanel`에서 받는다 — 그 설정이 섬세한
/// 부분이라 두 벌로 만들지 않는다. 층은 배지와 같다(`statusBar - 1`): flash가 그 위에 그려진다.
/// 화면을 덮는 패널이라 `ignoresMouseEvents`가 특히 중요하다 — 클릭을 한 번이라도 먹으면
/// 사용자가 앱 대신 우리를 누른 것이 된다.
@MainActor
final class ModeIndicatorBorderPanel {
    private let panel: NSPanel
    private let pill: ModeIndicatorPillView

    init() {
        let border = ModeIndicatorBorderView(frame: .zero)
        pill = ModeIndicatorPillView(style: .badge)
        border.addSubview(pill)
        panel = ModeIndicatorPanel.makeOverlayPanel(level: ModeIndicatorStyle.badge.windowLevel)
        panel.contentView = border
    }

    /// 테두리를 `frame`에, 라벨을 `labelFrame`에 띄우고 **그대로 둔다** — 배지의 `show`와 같은
    /// 계약이다(애니메이션도 타이머도 없고 멱등). 둘 다 화면 좌표이고, 라벨은 패널 안 좌표로
    /// 옮겨 앉힌다.
    func show(_ label: String, at frame: NSRect, labelFrame: NSRect) {
        pill.label = label
        pill.frame = labelFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// 즉시 감춘다 — 배지의 `hide`와 같은 사유·같은 계약이다.
    func hide() {
        panel.orderOut(nil)
    }
}

/// 강조색 테두리. 색은 알약과 같은 이유로 그리는 시점의 외양에서 해석한다.
private final class ModeIndicatorBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // 선은 bounds 안쪽에 온전히 들어와야 한다 — 절반이 패널 밖으로 잘리면 굵기가 반이 된다.
        let width = ModeIndicatorLayout.borderStrokeWidth
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
            xRadius: width * 2, yRadius: width * 2)
        path.lineWidth = width
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

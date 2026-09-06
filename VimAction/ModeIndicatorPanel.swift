//
//  ModeIndicatorPanel.swift
//  VimAction
//

import AppKit

/// 모드 라벨을 그리는 알약. 색만으로 구분하지 않는다는 PRD 접근성 NFR 때문에 **항상 텍스트가
/// 동반**되며, 그래서 배경은 라벨 폭에 맞춰 늘어난다 (`size(for:)`가 그 폭의 소유자다).
private final class ModeIndicatorPillView: NSView {
    static let font = NSFont.boldSystemFont(ofSize: 12)
    /// 라벨 주위 여백 (가로, 세로).
    private static let padding = (horizontal: CGFloat(10), vertical: CGFloat(5))
    private static let cornerRadius: CGFloat = 6

    var label = "" {
        didSet {
            guard label != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 라벨을 담는 패널 크기 — **컨트롤러가 순수 레이아웃에 넘기는 값**이다. 배지 크기를
    /// 레이아웃이 아니라 뷰가 정하는 이유는 폰트 메트릭이 여기 있기 때문이고, 순수 계층은
    /// 크기를 받아 쓰기만 한다.
    static func size(for label: String) -> CGSize {
        let text = (label as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: ceil(text.width) + padding.horizontal * 2,
            height: ceil(text.height) + padding.vertical * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        ).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: NSColor.white,
        ]
        let text = label as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes)
    }
}

/// 모드 라벨을 띄우는 비활성화 오버레이 패널.
///
/// **최전면 앱을 절대 빼앗지 않는 것이 이 타입의 존재 이유다** — `.nonactivatingPanel` +
/// `orderFrontRegardless()`만 쓰고 `makeKey…`·`NSApp.activate` 계열은 부르지 않는다.
/// VimAction이 활성화되면 `FrontmostAppGate`의 최전면 캐시가 자기 자신으로 덮여 앱별
/// disable 판정과 메뉴 편의 기능이 흔들린다. 설정 조합은 스파이크에서 앱 7종을 200ms 주기로
/// 순환시켜 검증한 것 그대로다 (플랜 `20260906_onscreen-mode-indicator.md`).
@MainActor
final class ModeIndicatorPanel {
    /// 페이드인 → 홀드 → 페이드아웃. 합이 대략 1초다.
    private static let fadeIn: TimeInterval = 0.15
    private static let hold: TimeInterval = 0.7
    private static let fadeOut: TimeInterval = 0.3

    private let panel: NSPanel
    private let pill = ModeIndicatorPillView()
    /// 예약된 페이드아웃. 표시 중 새 전환이 오면 취소하고 다시 건다.
    private var fadeOutWork: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // 메뉴바와 같은 층 — 전체화면 앱 위에서도 보여야 한다.
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        // 우리가 활성화되지 않으므로 `hidesOnDeactivate`가 켜져 있으면 뜨자마자 사라진다.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.contentView = pill
    }

    static func size(for label: String) -> CGSize { ModeIndicatorPillView.size(for: label) }

    /// 라벨을 `frame`에 띄우고 ~1초 뒤 페이드아웃한다. 표시 중 다시 부르면 **라벨·위치를 갈아
    /// 끼우고 타이머를 재시작**한다 — 연속 전환에서 앞 라벨이 사라지는 도중에 뒤 라벨이 겹쳐
    /// 뜨면 어느 쪽이 현재인지 읽히지 않는다.
    func flash(_ label: String, at frame: NSRect) {
        fadeOutWork?.cancel()
        pill.label = label
        panel.setFrame(frame, display: true)
        // 이미 떠 있으면 알파를 0으로 되돌리지 않는다 — 연속 전환마다 깜빡인다. 페이드아웃
        // 도중이면 현재 알파에서 1로 되올라가 끊김 없이 이어진다.
        if !panel.isVisible { panel.alphaValue = 0 }
        // 활성화 없이 띄우는 유일한 경로다.
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            panel.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeOut
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                // 애니메이션 도중 새 flash가 왔으면 그쪽이 알파를 되올렸다 — 여기서 감추면
                // 방금 띄운 라벨이 사라진다.
                guard let self, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        }
        fadeOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeIn + Self.hold, execute: work)
    }

    /// 즉시 감춘다 — 사다리가 `.mode`를 벗어났거나 앵커가 사라진 경우다. 페이드는 없다:
    /// "지금 이 라벨은 더 이상 사실이 아니다"라서 감추는 것이라 남아 있는 동안 거짓말을 한다.
    func hide() {
        fadeOutWork?.cancel()
        fadeOutWork = nil
        panel.orderOut(nil)
    }
}

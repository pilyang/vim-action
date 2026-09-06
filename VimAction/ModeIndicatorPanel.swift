//
//  ModeIndicatorPanel.swift
//  VimAction
//

import AppKit

/// 알약 두 겹의 외양 차이. 크기·모서리·창 층만 다르고 나머지(비활성화 패널 설정, 표시 경로)는
/// 같아서 값 하나로 갈라 둔다.
///
/// **배지가 한 층 아래인 것이 "flash가 배지 위에 그려진다"의 유일한 보장이다.** 같은 층이면
/// 마지막 `orderFrontRegardless()` 순서에 의존하는데, 창이 움직여 배지가 나중에 재배치되면
/// 뒤집힌다. 두 알약은 요소 오른쪽 위 모서리에 오른쪽·아래 정렬로 붙고 flash가 양방향으로 더
/// 커서 배지를 완전히 덮는다 — 전환 직후 1초간 flash만 보이고 페이드아웃하며 배지가 드러난다.
enum ModeIndicatorStyle {
    /// 모드 전환 순간 표시. 한 단계 크고 진하다.
    case flash
    /// 비-Insert 동안 상시. 한 단계 작고 옅다 — 계속 떠 있는 것이라 소음이 되면 안 된다.
    case badge

    var font: NSFont {
        switch self {
        case .flash: .boldSystemFont(ofSize: 12)
        case .badge: .systemFont(ofSize: 10, weight: .semibold)
        }
    }

    /// 라벨 주위 여백 (가로, 세로).
    var padding: (horizontal: CGFloat, vertical: CGFloat) {
        switch self {
        case .flash: (10, 5)
        case .badge: (7, 3)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .flash: 6
        case .badge: 5
        }
    }

    /// 메뉴바와 같은 층 — 전체화면 앱 위에서도 보여야 한다. 배지만 한 단 아래다.
    var windowLevel: NSWindow.Level {
        switch self {
        case .flash: .statusBar
        case .badge: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        }
    }
}

/// 모드 라벨을 그리는 알약. 색만으로 구분하지 않는다는 PRD 접근성 NFR 때문에 **항상 텍스트가
/// 동반**되며, 그래서 배경은 라벨 폭에 맞춰 늘어난다 (`size(for:style:)`가 그 폭의 소유자다).
/// 같은 이유로 글씨 색은 고정이 아니라 강조색에서 파생된다 (`textColor(on:)`).
private final class ModeIndicatorPillView: NSView {
    private let style: ModeIndicatorStyle

    var label = "" {
        didSet {
            guard label != oldValue else { return }
            needsDisplay = true
        }
    }

    init(style: ModeIndicatorStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used — 코드로만 만든다") }

    /// 라벨을 담는 패널 크기 — **컨트롤러가 순수 레이아웃에 넘기는 값**이다. 배지 크기를
    /// 레이아웃이 아니라 뷰가 정하는 이유는 폰트 메트릭이 여기 있기 때문이고, 순수 계층은
    /// 크기를 받아 쓰기만 한다.
    static func size(for label: String, style: ModeIndicatorStyle) -> CGSize {
        let text = (label as NSString).size(withAttributes: [.font: style.font])
        let padding = style.padding
        return CGSize(
            width: ceil(text.width) + padding.horizontal * 2,
            height: ceil(text.height) + padding.vertical * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 강조색은 동적 색이라 **그리는 시점의 외양에서** 해석돼야 한다 — 그래서 배경색과
        // 글씨색 결정이 둘 다 여기 있다.
        let background = NSColor.controlAccentColor
        background.setFill()
        NSBezierPath(
            roundedRect: bounds, xRadius: style.cornerRadius, yRadius: style.cornerRadius
        ).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.font, .foregroundColor: ModeIndicatorPanel.textColor(on: background),
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
///
/// 인스턴스는 둘이다 — 순간 표시용과 상시 배지용. 스타일만 다르고 나머지는 같아서 타입을
/// 나누지 않는다: 위 패널 설정이 이 타입의 섬세한 부분이라 두 벌이 되면 한쪽만 고쳐도
/// 컴파일이 통과한다.
@MainActor
final class ModeIndicatorPanel {
    /// 페이드인 → 홀드 → 페이드아웃. 합이 대략 1초다 (`flash`만 쓴다).
    private static let fadeIn: TimeInterval = 0.15
    private static let hold: TimeInterval = 0.7
    private static let fadeOut: TimeInterval = 0.3

    private let panel: NSPanel
    private let pill: ModeIndicatorPillView
    /// 예약된 페이드아웃. 표시 중 새 flash가 오면 취소하고 다시 건다.
    private var fadeOutWork: DispatchWorkItem?

    init(style: ModeIndicatorStyle) {
        pill = ModeIndicatorPillView(style: style)
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = style.windowLevel
        panel.ignoresMouseEvents = true
        // 우리가 활성화되지 않으므로 `hidesOnDeactivate`가 켜져 있으면 뜨자마자 사라진다.
        panel.hidesOnDeactivate = false
        // 배지도 flash와 같은 조합이다 — Space를 옮기면 앱 활성화 알림이 재앵커를 걸어 새
        // Space의 요소로 즉시 옮겨 붙으므로, 검증된 조합을 배지 때문에 갈라 놓지 않는다.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.contentView = pill
    }

    static func size(for label: String, style: ModeIndicatorStyle) -> CGSize {
        ModeIndicatorPillView.size(for: label, style: style)
    }

    /// 알약 글씨 색 — 강조색 위에서 읽히는 쪽을 고른다. **순수 함수라 표로 검증한다.**
    ///
    /// 흰 글씨가 기본인 것은 macOS가 강조색 컨트롤에 쓰는 색이라서다. 다만 강조색은 사용자가
    /// 고르고, 밝은 강조색에서 흰 글씨는 사실상 읽히지 않는다 — **다크 외양에서 잰** 흰 글씨
    /// 대비가 노랑 1.41:1, 초록 2.02, 주황 2.23, 그래파이트 2.87이다(파랑 3.23·빨강 3.43·
    /// 분홍 3.52·보라 3.63). 그래서 흰 글씨가 큰 글씨 최소 대비 3:1 아래로 떨어지는
    /// 강조색에서만 검은 글씨로 바꾼다: 파랑·보라·분홍·빨강은 그대로라 기존 외양과 macOS
    /// 관례가 유지되고, 나머지 넷만 검은 글씨로 뒤집힌다.
    ///
    /// **그래파이트는 3:1 선 위에 앉아 외양에 따라 갈린다** — 라이트에서 #8E8E93(3.26:1 →
    /// 흰 글씨), 다크에서 #98989D(2.87:1 → 검은 글씨). 강조색은 동적 색이라 그리는 시점에
    /// 해석되고 이 판정도 그 값으로 내려가므로 그것이 맞는 동작이다. 다만 **테스트는 동적
    /// 시스템 색을 쓰면 안 된다** — 답이 테스트를 돌린 머신의 외양에 묶인다.
    ///
    /// 뷰가 아니라 여기 있는 것은 뷰가 `private`이라 테스트가 닿지 않아서다.
    static func textColor(on background: NSColor) -> NSColor {
        guard let srgb = background.usingColorSpace(.sRGB) else { return .white }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance =
            0.2126 * linear(srgb.redComponent) + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
        // WCAG 대비비 (1.05 / (L + 0.05))가 3 이상인가 — 나누기 없이 같은 판정이다.
        return luminance <= 1.05 / 3 - 0.05 ? .white : .black
    }

    /// 라벨을 `frame`에 띄우고 ~1초 뒤 페이드아웃한다. 표시 중 다시 부르면 **라벨·위치를 갈아
    /// 끼우고 타이머를 재시작**한다 — 연속 전환에서 앞 라벨이 사라지는 도중에 뒤 라벨이 겹쳐
    /// 뜨면 어느 쪽이 현재인지 읽히지 않는다.
    func flash(_ label: String, at frame: NSRect) {
        fadeOutWork?.cancel()
        place(label, at: frame)
        // 이미 떠 있으면 알파를 0으로 되돌리지 않는다 — 연속 전환마다 깜빡인다. 페이드아웃
        // 도중이면 현재 알파에서 1로 되올라가 끊김 없이 이어진다.
        if !panel.isVisible { panel.alphaValue = 0 }
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

    /// 라벨을 `frame`에 띄우고 **그대로 둔다** — 상시 배지의 표시 경로다.
    ///
    /// 애니메이션도 타이머도 없는 것이 요점이다: 배지는 포커스·창 이벤트마다 다시 놓이는데
    /// 그때마다 페이드가 걸리면 창을 옮길 때 배지가 출렁이고, 페이드아웃이 예약되면 가만히
    /// 있는 동안 배지가 사라진다. 멱등이라 같은 위치로 다시 불러도 안전하다.
    func show(_ label: String, at frame: NSRect) {
        fadeOutWork?.cancel()
        fadeOutWork = nil
        place(label, at: frame)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// 즉시 감춘다 — 사다리가 `.mode`를 벗어났거나 앵커가 사라진 경우다. 페이드는 없다:
    /// "지금 이 라벨은 더 이상 사실이 아니다"라서 감추는 것이라 남아 있는 동안 거짓말을 한다.
    func hide() {
        fadeOutWork?.cancel()
        fadeOutWork = nil
        panel.orderOut(nil)
    }

    private func place(_ label: String, at frame: NSRect) {
        pill.label = label
        panel.setFrame(frame, display: true)
    }
}

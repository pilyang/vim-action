//
//  ModeIndicatorGeometryReader.swift
//  VimAction
//

import ApplicationServices
import CoreGraphics

/// 모드 인디케이터가 붙을 앵커의 AX 읽기. **컨트롤러의 전용 기하 큐 위에서만 불린다** —
/// 메인·탭 콜백에서 AX를 부르지 않는다는 불변식은 이 경로에도 예외가 없다.
///
/// `pid`만 받는 것이 규칙이다: `AXUIElement`를 큐 경계로 넘기지 않으므로 비-`Sendable` 값이
/// 격리를 건너는 일이 애초에 없고, 요소는 이 큐 위에서 만들어져 여기서만 쓰인다
/// (`FocusedElementResolver.readFamily`와 같은 계약). 돌려주는 것은 rect뿐이다.
///
/// 타임아웃은 새로 정하지 않는다 — 요소·앱 요소 양쪽을 `AXRead`에서 받으므로 50ms 단일
/// 상수가 그대로 상속된다.
nonisolated enum ModeIndicatorGeometryReader {
    /// 포커스 요소 rect와 포커스 창 rect를 한 번에 읽는다 (AX 좌표계).
    ///
    /// 어느 단이 실패하든 그 단만 `nil`이 되고 나머지는 그대로 살아 있다 — 사다리가 아래
    /// 단으로 내려가는 것은 순수 계층(`ModeIndicatorLayout.anchor`)의 몫이라, 여기서는
    /// "읽힌 것만 담는다".
    static func read(processID: pid_t) -> ModeIndicatorLayout.Anchors {
        let element = AXRead.focusedElement(ofProcess: processID).flatMap(rect(of:))
        // 요소가 답했으면 창은 읽지 않는다 — 사다리가 어차피 요소를 고르므로 결과는 같고,
        // 콜드 앱에서 AX 왕복 셋(창 조회·position·size)이 통째로 빠진다. 그래서 `window`가
        // `nil`인 것은 "읽기 실패"가 아니라 "필요 없었다"일 수도 있다.
        if let element, ModeIndicatorLayout.isUsable(element) {
            return ModeIndicatorLayout.Anchors(element: element)
        }
        return ModeIndicatorLayout.Anchors(
            element: element, window: focusedWindowRect(processID: processID))
    }

    private static func focusedWindowRect(processID: pid_t) -> CGRect? {
        let application = AXRead.applicationElement(ofProcess: processID)
        guard let value = AXRead.copyValue(application, kAXFocusedWindowAttribute as String),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return rect(of: value as! AXUIElement)
    }

    /// `AXPosition` + `AXSize` → rect. 둘 중 하나라도 없으면 rect가 없다.
    private static func rect(of element: AXUIElement) -> CGRect? {
        guard let origin = copyPoint(element, kAXPositionAttribute as String),
            let size = copySize(element, kAXSizeAttribute as String)
        else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    /// `AXValue` 언랩 — 레포의 기존 세 곳(`AXTrustProber`의 `.cgSize`,
    /// `FocusedTextReader`·`ViewportReader`의 `.cfRange`)과 같은 형태다. 실패는 전부 `nil`
    /// 하나로 접는다: 소비자의 폴백이 "이 단을 건너뛴다" 하나뿐이라 에러코드로 갈라 봐야 쓸
    /// 데가 없다 (`AXRead.copyValue`와 같은 규칙). 제네릭으로 묶지 않은 것은 `AXValueGetValue`가
    /// 임의 `T`의 포인터를 받으면 경고가 나서다 — 두 벌이지만 각각 세 줄이다.
    private static func copyPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func copySize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = AXRead.copyValue(element, attribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        return (value as! AXValue)
    }
}

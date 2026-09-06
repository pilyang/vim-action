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
///
/// **비용**: 요소 rect(포커스 요소 조회·position·size)에, 요소가 쓸 만하지 않을 때만 창(창
/// 조회·position·size)이 더해진다. 캐럿은 `includesCaret`일 때만 읽고 최대 다섯 번(선택 범위·
/// bounds 두 변형·마커 범위·마커 bounds)이라, 콜드 앱의 flash 한 번이 AX 왕복 최대 열한 번이다.
nonisolated enum ModeIndicatorGeometryReader {
    /// 포커스 요소 rect·(필요하면) 포커스 창 rect·(flash면) 캐럿 rect를 한 번에 읽는다 (AX 좌표계).
    ///
    /// 어느 단이 실패하든 그 단만 `nil`이 되고 나머지는 그대로 살아 있다 — 사다리가 아래
    /// 단으로 내려가는 것은 순수 계층(`ModeIndicatorLayout.anchor`)의 몫이라, 여기서는
    /// "읽힌 것만 담는다".
    ///
    /// `includesCaret`은 **요청에 flash가 있을 때만** 참이다 — 캐럿은 flash만 쓰고(상시 배지는
    /// 캐럿을 따라다니지 않는다), 앵커·사다리 이벤트의 배지 재배치는 캐럿 왕복 없이 오늘의
    /// 비용에 머문다. 컨트롤러가 명시적으로 넘긴다 — 전역 상태로 두면 어느 읽기가 캐럿을
    /// 물었는지 코드에서 보이지 않는다.
    static func read(processID: pid_t, includesCaret: Bool) -> ModeIndicatorLayout.Anchors {
        let focused = AXRead.focusedElement(ofProcess: processID)
        let element = focused.flatMap(rect(of:))
        // 요소 rect 다음이어야 한다 — 캐럿 유효성 판정이 요소 rect를 본다. 그리고 아래 조기
        // 반환 **앞**이어야 한다: 요소가 쓸 만한 것이 실측표의 모든 앱에서 정상 경로다.
        let caret = includesCaret ? focused.flatMap { caretRect(of: $0, within: element) } : nil
        // 요소가 답했으면 창은 읽지 않는다 — 사다리가 어차피 요소를 고르므로 결과는 같고,
        // 콜드 앱에서 AX 왕복 셋(창 조회·position·size)이 통째로 빠진다. 그래서 `window`가
        // `nil`인 것은 "읽기 실패"가 아니라 "필요 없었다"일 수도 있다.
        if let element, ModeIndicatorLayout.isUsable(element) {
            return ModeIndicatorLayout.Anchors(element: element, caret: caret)
        }
        return ModeIndicatorLayout.Anchors(
            element: element, window: focusedWindowRect(processID: processID), caret: caret)
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

    /// 캐럿 rect — 결정 5의 순서대로 시도하고 **첫 쓸 만한 것**에서 멈춘다
    /// (`20260906_mode-indicator-anchor-ladder-event-driven.md`). 쓸 만한지는 순수 계층의
    /// `isUsableCaret`이 정한다 — 사다리와 같은 규칙이라야 리더가 넘긴 것을 사다리가 버리는
    /// 어긋남이 없다.
    ///
    /// 1. `AXSelectedTextRange`의 위치 `loc`에 `AXBoundsForRange (loc, 1)`.
    /// 2. 안 되면 `(loc-1, 1)` — 문서 끝이다. **길이 0 범위는 쓰지 않는다**: AppKit이 한 줄 위
    ///    rect를 돌려준다.
    /// 3. 텍스트 마커 경로 — Electron contenteditable(Slack 컴포저)의 유일한 답이라 마지막이다.
    ///
    /// 문서 끝인지 미리 묻지 않는다(`AXNumberOfCharacters`) — "해 보고 물러나는" 편이 왕복
    /// 하나가 적다. Chromium 브라우저(Chrome·Arc)는 셋 다 빈 값이라 조용히 `nil`이고, 사다리가
    /// 요소 단으로 내려간다 (`20260906_no-forced-chromium-screen-reader-mode.md`).
    private static func caretRect(of element: AXUIElement, within elementRect: CGRect?) -> CGRect? {
        func usable(_ rect: CGRect?) -> CGRect? {
            guard let rect, ModeIndicatorLayout.isUsableCaret(rect, element: elementRect) else {
                return nil
            }
            return rect
        }
        if let selection = copyRange(element, kAXSelectedTextRangeAttribute as String) {
            if let rect = usable(boundsForRange(element, location: selection.location, length: 1)) {
                return rect
            }
            if selection.location > 0,
                let rect = usable(
                    boundsForRange(element, location: selection.location - 1, length: 1))
            {
                return rect
            }
        }
        return usable(boundsForTextMarkerRange(element))
    }

    /// `AXBoundsForRange`는 **파라미터화 속성**이다 (`FocusedTextReader`의 `AXStringForRange`와
    /// 같은 형태).
    private static func boundsForRange(_ element: AXUIElement, location: Int, length: Int)
        -> CGRect?
    {
        var range = CFRange(location: location, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        return copyRect(
            parameterizedValue(
                element, kAXBoundsForRangeParameterizedAttribute as String, parameter))
    }

    /// 텍스트 마커 경로. 마커 범위는 **불투명 CFType**이라 형 검사도 변환도 없이 그대로
    /// 파라미터로 넘긴다 — 우리가 아는 것은 "이 앱이 준 값을 이 앱에 되돌려 준다"뿐이다.
    private static func boundsForTextMarkerRange(_ element: AXUIElement) -> CGRect? {
        guard let marker = AXRead.copyValue(element, "AXSelectedTextMarkerRange") else {
            return nil
        }
        return copyRect(parameterizedValue(element, "AXBoundsForTextMarkerRange", marker))
    }

    private static func parameterizedValue(
        _ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef
    ) -> AXValue? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, attribute as CFString, parameter, &value) == .success
        else {
            return nil
        }
        return axValue(value)
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
    /// 임의 `T`의 포인터를 받으면 경고가 나서다 — 네 벌이지만 각각 세 줄이다.
    private static func copyPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(AXRead.copyValue(element, attribute)) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func copySize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(AXRead.copyValue(element, attribute)) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func copyRange(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = axValue(AXRead.copyValue(element, attribute)) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private static func copyRect(_ value: AXValue?) -> CGRect? {
        guard let value else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    /// 속성 값이든 파라미터화 속성 값이든 `AXValue`인지 확인하고 캐스팅한다 — 형 검사 없이
    /// 강제 캐스팅하면 엉뚱한 타입을 돌려주는 앱에서 크래시다.
    private static func axValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}

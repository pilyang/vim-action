//
//  AXRead.swift
//  VimAction
//

import ApplicationServices

/// AX 읽기 두 경로(`FocusedElementResolver`의 전용 큐, 디스패치 경로의 게시 큐)가 공유하는
/// 진입점. 타입이 하나인 것 자체가 계약이다 — 타임아웃이 경로마다 갈리면 "50ms 단일 상수"가
/// 코드에서 지켜지는지 감사할 수 없다.
nonisolated enum AXRead {
    /// AX 메시징 타임아웃 — **경로 불문 단일 상수**다.
    ///
    /// 탭 생존을 지키는 것은 이 값이 아니라 **배치**다: AX 호출은 콜백·메인 스레드에 들어오지
    /// 않으므로(리졸버는 전용 큐, 디스패치 읽기는 게시 큐) 캡은 병적 정지가 큐를 잡아두는 것을
    /// 자르는 차단기일 뿐이다. 값의 근거는 실측이다 — 콜드 성공 19~35ms, 웜 정상 최대 16ms
    /// (Notion `selectedRange`)이고, 실패 반환은 캡+2ms로 바운드된다. 앞선 3ms 하드 캡은
    /// 웜 정상 읽기까지 죽여 supersede됐다 (`20260802_ax-read-timeout-50ms-supersedes-3ms.md`).
    static let messagingTimeout: Float = 0.05

    /// 앱의 현재 포커스 요소. 타임아웃은 앱·요소 양쪽에 건다.
    ///
    /// **pid만 받는 것이 규칙이다**: `AXUIElement`를 큐 경계로 넘기지 않으므로 비-`Sendable`
    /// 값이 격리를 건너는 일이 애초에 없다 (`ActionExecutor`의 CGEvent 계약과 같은 규칙).
    /// 요소는 호출한 큐 위에서 만들어져 그 큐 안에서만 쓰인다.
    ///
    /// **쓰기 경로(`AXWriter`)도 요소는 반드시 여기서 받는다** — 그래서 위 타임아웃이
    /// 읽기·쓰기 양쪽에 같은 상수로 상속되고, 요소를 만드는 자리가 이 함수 하나로 남는다.
    static func focusedElement(ofProcess processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let element = (value as! AXUIElement)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    /// 속성 값 조회 — 실패는 전부 `nil` 하나다. 호출자가 에러코드로 갈라야 할 이유가
    /// 없어서다: 두 경로 다 폴백이 하나뿐이다(리졸버는 `.textArea`, 디스패치 읽기는 무상태 시퀀스).
    static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else {
            return nil
        }
        return value
    }
}

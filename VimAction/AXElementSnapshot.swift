//
//  AXElementSnapshot.swift
//  VimAction
//

import ApplicationServices
import Foundation

/// AX 쓰기 대상 요소의 **액션별 lazy·1회 memo** — `FocusedTextSnapshot`·`ViewportSnapshot`과
/// 같은 형태다.
///
/// 요소를 스냅샷으로 두는 이유는 두 가지다. ① 한 액션 안에서 오프셋 계산용 읽기와 쓰기가
/// **같은 요소 핸들**을 써야 그 사이 포커스가 옮겨간 경우 엉뚱한 요소에 범위를 쓰는 창이
/// 닫힌다(`AXWriter.write`의 요소 계약 나머지 절반). ② **실패도 memo한다** — 그러지 않으면
/// 포커스 요소를 노출하지 않는 앱에서 한 액션이 물음 수만큼 50ms 캡을 문다.
///
/// 수명이 액션당 1회인 것은 `FocusedTextSnapshot`과 맞춘 것이다: 요소 자체는 버스트 중
/// 대체로 불변이지만, 실패 memo와 캡이 닫히는 단위가 캐럿 읽기와 어긋나면 "요소는 살아
/// 있다고 기억하는데 읽기는 매번 실패"하는 상태가 생긴다.
///
/// 획득 seam을 주입받는 이유는 리더·라이터와 같다 — 기본값이 실구현이고, 테스트는 실제 AX
/// 없이(그리고 TCC 없이) 요소를 만들어 낸다. `AXUIElementCreateApplication`은 IPC가 없어
/// 헤드리스에서 안전한 fake 재료다.
nonisolated final class AXElementSnapshot {
    private let processID: pid_t?
    private let acquire: @Sendable (pid_t) -> AXUIElement?

    /// 이중 옵셔널 — 바깥 `nil`은 "아직 안 물었다", 안쪽 `nil`은 "물었고 실패했다"다
    /// (`FocusedTextSnapshot.cached`와 같은 규칙).
    private var cached: AXUIElement??

    init(
        processID: pid_t?,
        acquire: @escaping @Sendable (pid_t) -> AXUIElement? = AXRead.focusedElement(ofProcess:)
    ) {
        self.processID = processID
        self.acquire = acquire
    }

    /// 처음 물을 때만 AX를 부른다. pid가 없으면 아예 부르지 않는다.
    func value() -> AXUIElement? {
        if let cached { return cached }
        guard let processID else {
            cached = .some(nil)
            return nil
        }
        let element = acquire(processID)
        cached = .some(element)
        return element
    }
}

/// AX 쓰기 경로의 **액션별 캐럿 주변 창** — `FocusedTextSnapshot`과 수명·memo 규칙이 같고
/// 둘만 다르다: ① 요소를 `AXElementSnapshot`에서 받아 **쓰기와 같은 핸들**을 쓴다
/// ② 창 반경이 `FocusedTextReader.axWindowRadius`(4096)다.
///
/// pid가 아니라 요소를 받는 것이 핵심 계약이다 (`FocusedTextReader.read(_:radius:)` doc):
/// pid로 다시 획득하면 오프셋을 계산한 요소와 쓰는 요소가 갈릴 수 있다. 덤으로 액션당
/// `focusedElement` 왕복이 1회로 유지된다.
///
/// **키보드 경로의 `FocusedTextSnapshot`(256)과 소비자가 겹치지 않는 것도 계약이다** — 한
/// 액션이 둘 다 물으면 왕복이 두 배가 된다. 실행 계획이 정해 준 쪽만 묻는다.
nonisolated final class AXWindowSnapshot {
    private let element: AXElementSnapshot
    private let read: @Sendable (AXUIElement) -> FocusedText?

    /// `FocusedTextSnapshot.cached`와 같은 이중 옵셔널 — 실패도 memo한다.
    private var cached: FocusedText??

    init(
        element: AXElementSnapshot,
        read: @escaping @Sendable (AXUIElement) -> FocusedText? = {
            FocusedTextReader.read($0, radius: FocusedTextReader.axWindowRadius)
        }
    ) {
        self.element = element
        self.read = read
    }

    func value() -> FocusedText? {
        if let cached { return cached }
        let value = element.value().flatMap { read($0) }
        cached = .some(value)
        return value
    }
}

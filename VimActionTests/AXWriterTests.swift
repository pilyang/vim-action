//
//  AXWriterTests.swift
//  VimActionTests
//

import ApplicationServices
import Foundation
import Testing

@testable import VimAction

/// 쓰기 seam이 받은 인자 한 벌. `AXUIElement`·`CFTypeRef`가 비-`Sendable`이라 값 타입으로
/// 모아 두고 `nonisolated(unsafe)`로 관측한다 (테스트는 단일 스레드 동기 호출이다).
private struct WriteCall {
    let element: AXUIElement
    let attribute: String
    let value: CFTypeRef
}

/// 실기기 AX 없이 쓰기 seam을 관측하는 가짜 — `ViewportReaderTests`의 `recordingReader`와
/// 같은 형태다. **여기서는 seam 대체가 안전장치이기도 하다**: 진짜 구현이 붙으면 테스트가
/// 개발자의 실제 문서에 선택 범위를 써 넣는다.
private func recordingWriter(
    returning error: AXError = .success,
    onWrite: @escaping @Sendable (WriteCall) -> Void
) -> AXWriter {
    AXWriter { element, attribute, value in
        onWrite(WriteCall(element: element, attribute: attribute, value: value))
        return error
    }
}

/// 테스트용 요소. `AXUIElementCreateApplication`은 **메시징이 아니라 순수 로컬 생성**이라
/// TCC 없이 만들어지고, 뒤따르는 메시징은 seam이 가로채므로 실 AX 트리에 닿지 않는다
/// (존재하지 않는 pid를 쓰는 `ExecutionWiringTests`의 관례와 같은 편).
private func testElement(pid: pid_t = 99_999) -> AXUIElement {
    AXUIElementCreateApplication(pid)
}

/// `AXValue`에서 `CFRange`를 되꺼낸다 — 편의 메서드가 만든 값의 **타입과 내용**을 함께 본다.
/// 타입 확인이 빠지면 다른 `AXValue`(`.cgPoint` 등)를 만들어도 단언이 통과한다.
private func cfRange(from value: CFTypeRef) -> CFRange? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return range
}

/// AX 속성 쓰기 통로의 계약 — **인자를 가공 없이 전달하고 `AXError`를 가공 없이 돌려준다**.
/// 분류·삼킴이 통로 안에서 일어나지 않는다는 것이 여기서 고정되고, 그것이 어댑터 쪽
/// 분류 순수 함수의 전제가 된다.
struct AXWriterTests {
    @Test("만들기만 해서는 쓰지 않는다")
    func constructionDoesNotWrite() {
        nonisolated(unsafe) var writes = 0
        let writer = recordingWriter { _ in writes += 1 }

        withExtendedLifetime(writer) {}

        #expect(writes == 0)
    }

    /// 수신 요소가 **같은 핸들**인 것이 계약의 핵심이다 — 읽기와 쓰기가 같은 요소를 써야
    /// 그 사이 포커스가 옮겨간 경우 엉뚱한 요소에 범위를 써 넣는 창이 닫힌다.
    @Test("요소·속성 이름·값을 가공 없이 그대로 넘긴다")
    func writePassesArgumentsThrough() {
        nonisolated(unsafe) var calls: [WriteCall] = []
        let writer = recordingWriter { calls.append($0) }
        let element = testElement()
        let value = 42 as CFNumber

        _ = writer.write(element, kAXValueAttribute, value)

        #expect(calls.count == 1)
        #expect(calls.first.map { CFEqual($0.element, element) } == true)
        #expect(calls.first?.attribute == kAXValueAttribute)
        #expect(calls.first.map { CFEqual($0.value, value) } == true)
    }

    @Test("편의 메서드는 AXSelectedTextRange에 cfRange 타입 AXValue를 쓴다")
    func selectedTextRangeConvenienceWritesCFRange() {
        nonisolated(unsafe) var calls: [WriteCall] = []
        let writer = recordingWriter { calls.append($0) }
        let element = testElement()

        _ = writer.writeSelectedTextRange(element, NSRange(location: 17, length: 5))

        #expect(calls.count == 1)
        #expect(calls.first.map { CFEqual($0.element, element) } == true)
        #expect(calls.first?.attribute == kAXSelectedTextRangeAttribute)
        let range = calls.first.flatMap { cfRange(from: $0.value) }
        #expect(range?.location == 17)
        #expect(range?.length == 5)
    }

    /// 길이 0은 선택이 아니라 **캐럿**이다 — AX 어댑터의 모션이 전부 이 형태라 빈 범위가
    /// 통로에서 걸러지지 않는 것이 계약이다.
    @Test("길이 0 범위(캐럿)도 그대로 나간다")
    func caretRangeIsWrittenAsIs() {
        nonisolated(unsafe) var calls: [WriteCall] = []
        let writer = recordingWriter { calls.append($0) }

        _ = writer.writeSelectedTextRange(testElement(), NSRange(location: 0, length: 0))

        #expect(calls.count == 1)
        let range = calls.first.flatMap { cfRange(from: $0.value) }
        #expect(range?.location == 0)
        #expect(range?.length == 0)
    }

    /// **분류는 이 타입의 책임이 아니다.** 어느 코드도 통로에서 접히거나 삼켜지지 않음을
    /// 스윕으로 고정한다 — 화이트리스트 분류(미지원 스킵 / 경합 스킵 / 실보고 / 관측 전용)가
    /// 갈라야 할 코드들이 어댑터까지 온전히 도착한다는 뜻이다.
    @Test("주입한 AXError가 가공 없이 그대로 반환된다")
    func injectedErrorIsReturnedVerbatim() {
        let codes: [AXError] = [
            .success, .failure, .illegalArgument, .invalidUIElement, .cannotComplete,
            .attributeUnsupported, .actionUnsupported, .notImplemented, .apiDisabled,
        ]

        for code in codes {
            let writer = AXWriter { _, _, _ in code }
            #expect(writer.write(testElement(), kAXValueAttribute, 0 as CFNumber) == code)
            #expect(
                writer.writeSelectedTextRange(testElement(), NSRange(location: 0, length: 1))
                    == code,
                "편의 메서드도 코드를 접지 않는다")
        }
    }

    /// 쓰기는 게시 직렬 큐 위에서만 일어난다 — 읽기 seam 2종과 같은 계약이고, 같은 이유로
    /// 홉이 없어야 한다(홉이 생기면 "읽기·계산·쓰기가 같은 큐에서 동기"라는 전제가 깨져
    /// keyboard 경로의 낡은 읽기 문제가 AX 경로에도 생긴다).
    @Test("쓰기는 부른 큐 위에서 동기로 실행된다 — 홉 없음")
    func writeRunsSynchronouslyOnTheCallingQueue() {
        let key = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: "dev.pilyang.VimActionTests.axWritePosting")
        queue.setSpecific(key: key, value: "posting")

        nonisolated(unsafe) var observedQueue: String?
        nonisolated(unsafe) var observedMainThread = true
        let writer = AXWriter { _, _, _ in
            observedQueue = DispatchQueue.getSpecific(key: key)
            observedMainThread = Thread.isMainThread
            return .success
        }

        let finished = DispatchSemaphore(value: 0)
        queue.async {
            _ = writer.writeSelectedTextRange(testElement(), NSRange(location: 3, length: 0))
            finished.signal()
        }
        #expect(finished.wait(timeout: .now() + 5) == .success)

        #expect(observedQueue == "posting", "쓰기가 부른 큐를 벗어났다")
        #expect(observedMainThread == false, "AX는 메인 스레드에 들어오지 않는다")
    }
}

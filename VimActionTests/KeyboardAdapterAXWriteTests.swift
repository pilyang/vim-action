//
//  KeyboardAdapterAXWriteTests.swift
//  VimActionTests
//

import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
import VimActionConfig
import VimEngine

@testable import VimAction

/// AX 쓰기 1건의 관측 — 요소는 무시하고 범위만 본다(요소 계약은 `AXWriterTests` 몫).
private struct AXCall {
    let range: NSRange
}

private func range(from value: CFTypeRef) -> NSRange? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var cfRange = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &cfRange) else { return nil }
    return NSRange(location: cfRange.location, length: cfRange.length)
}

/// AX 실행 경로를 켠 어댑터 — **네 seam을 전부 주입한다.**
///
/// 요소는 `AXUIElementCreateApplication`(순수 로컬 생성, IPC·TCC 없음)이고 뒤따르는 메시징은
/// 읽기·쓰기 seam이 전부 가로채므로 실기기 AX 트리에 닿지 않는다. 진짜 writer가 붙으면
/// 테스트가 **개발자의 실제 문서에 선택 범위를 써 넣는다** (`AXWriterTests`의 같은 주석).
private func makeAXAdapter(
    axText: FocusedText?,
    element: AXUIElement? = AXUIElementCreateApplication(99_999),
    writeError: @escaping @Sendable () -> AXError = { .success },
    reportFailure: @escaping @Sendable (TimeInterval) -> Void = { _ in },
    onWrite: @escaping @Sendable (AXCall) -> Void = { _ in },
    collecting posted: @escaping @Sendable (CGEvent) -> Void = { _ in }
) -> KeyboardAdapter {
    KeyboardAdapter(
        executor: ActionExecutor(postEvent: posted),
        pasteWise: PasteWiseResolver(readClipboard: { .charwise }, readChangeCount: { 0 }),
        reader: FocusedTextReader { _ in nil },
        viewportReader: ViewportReader { _ in nil },
        axWindow: { _ in axText },
        writer: AXWriter { _, _, value in
            onWrite(AXCall(range: range(from: value) ?? NSRange(location: -1, length: -1)))
            return writeError()
        },
        axElement: { _ in element },
        reportExecutionFailure: reportFailure,
        now: { 0 })
}

/// `strategy: accessibility` 프로파일. 다른 필드는 기본값이라 이 축만 변한다.
private let axProfile = ResolvedProfile(AppProfile(strategy: .accessibility))

/// `"foo.bar  baz"` — 오프셋: f0 o1 o2 .3 b4 a5 r6 ␣7 ␣8 b9 a10 z11, 문서 끝 12.
private let axText = focusedText("foo.bar  baz", caret: 0)

/// 존재하는 pid여야 스냅샷이 seam을 부른다 (`processID`가 `nil`이면 읽기 자체가 생략된다).
private let anyPID: pid_t = 99_999

struct KeyboardAdapterAXWriteTests {
    /// 증명된 모션은 **AX 캐럿 쓰기 1건**이고 합성 이벤트는 하나도 나가지 않는다.
    @Test("strategy: accessibility에서 증명된 모션은 AX 캐럿 쓰기다")
    func provenMotionWritesCaret() {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: axText, onWrite: { calls.append($0) }, collecting: { posted.append($0) })

        adapter.execute(
            [.move(.wordForward)], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 3, length: 0)])
        #expect(posted.isEmpty, "AX 경로는 합성 이벤트를 내지 않는다")
    }

    /// **기본 전략은 keyboard** — 미지정 프로파일은 동작 diff 0이다.
    @Test("strategy 미지정이면 쓰기 seam은 불리지 않는다")
    func defaultStrategyDelegates() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: axText, onWrite: { _ in writes += 1 }, collecting: { posted.append($0) })

        adapter.execute([.move(.wordForward)], processID: anyPID)

        #expect(writes == 0, "쓰기 seam 무호출이 위임의 증거다 — 내용 비교가 아니다")
        #expect(!posted.isEmpty)
    }

    /// 비텍스트·미상 계열은 **전 액션 keyboard 강등**이다 — AX 대입은 텍스트 요소 전제다.
    @Test("nonText·unresolved 계열은 AX로 가지 않는다", arguments: [ElementFamily.nonText, .unresolved])
    func nonTextFamilyDelegates(_ family: ElementFamily) {
        nonisolated(unsafe) var writes = 0
        let adapter = makeAXAdapter(axText: axText, onWrite: { _ in writes += 1 })

        adapter.execute(
            [.move(.wordForward)], family: family, profile: axProfile, processID: anyPID)

        #expect(writes == 0)
    }

    /// `j`/`k`는 위임 유지 — 오프셋 대입이 희망 열을 잃는다.
    @Test("j·k는 AX로 가지 않는다", arguments: [Motion.lineUp, .lineDown])
    func verticalMotionsDelegate(_ motion: Motion) {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: axText, onWrite: { _ in writes += 1 }, collecting: { posted.append($0) })

        adapter.execute([.move(motion)], profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(!posted.isEmpty, "위임이지 스킵이 아니다")
    }

    /// 프로파일이 그 모션을 재정의했으면 AX가 덮어쓰지 않는다 — 사용자 지시가 우선이다.
    @Test("모션 재정의가 있으면 AX가 아니라 그 시퀀스가 나간다")
    func motionOverrideWins() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let profile = ResolvedProfile(
            AppProfile(
                strategy: .accessibility,
                motions: [.wordForward: .strokes([ConfigKeyStroke(.end)])]))
        let adapter = makeAXAdapter(
            axText: axText, onWrite: { _ in writes += 1 }, collecting: { posted.append($0) })

        adapter.execute([.move(.wordForward)], profile: profile, processID: anyPID)

        #expect(writes == 0)
        #expect(
            posted.map { $0.getIntegerValueField(.keyboardEventKeycode) }
                == [Int64(kVK_End), Int64(kVK_End)])
    }

    /// 증명 실패(`unproven`)는 **위임**이다 — 쓰기 시도 전이라 이중 실행이 불가능하다.
    @Test("오프셋 증명 실패는 keyboard 위임이다")
    func unprovenDelegates() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        // 창이 문서 일부라 줄 시작을 증명할 수 없다.
        let truncated = FocusedText(
            selection: NSRange(location: 102, length: 0), characterCount: 999,
            window: "cdef", windowRange: NSRange(location: 100, length: 4))
        let adapter = makeAXAdapter(
            axText: truncated, onWrite: { _ in writes += 1 }, collecting: { posted.append($0) })

        adapter.execute([.move(.lineStart)], profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(!posted.isEmpty, "증명 실패는 스킵이 아니라 위임이다")
    }

    /// Vim 무효(`invalid`)는 **정직한 스킵**이다 — 위임하면 실제로 캐럿이 움직인다.
    @Test("Vim 무효는 쓰기도 게시도 없는 스킵이다")
    func invalidIsHonestSkip() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText("foo.bar  baz", caret: 0), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        // 문서 시작에서 `h`는 Vim no-op이다.
        adapter.execute([.move(.charLeft)], profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty, "위임하면 `←`가 나가 이전 줄로 넘어간다")
    }

    /// 포커스 요소를 안 여는 앱(Slack류)에서는 **그 execute 잔여까지 접는다** — 접지 않으면
    /// `100j`가 100×50ms로 게시 큐를 잡는다.
    @Test("요소·읽기가 없으면 execute 잔여를 통째로 스킵한다")
    func missingElementEndsExecute() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: nil, element: nil, onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.move(.wordForward), .move(.wordForward)], profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty, "위임도 아니다 — 읽기 단계 실패는 스킵이다")
    }

    /// **첫 비-`.success`에서 execute 잔여를 통째로 스킵한다** — "보고는 키 입력 1건당 최대
    /// 1회"가 구조로 보장되는 지점이다.
    @Test("첫 실패 뒤의 액션은 실행되지 않는다")
    func firstFailureEndsExecute() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var reports = 0
        let adapter = makeAXAdapter(
            axText: axText, writeError: { .failure }, reportFailure: { _ in reports += 1 },
            onWrite: { _ in writes += 1 })

        adapter.execute(
            [.move(.wordForward), .move(.wordForward), .move(.wordForward)], profile: axProfile,
            processID: anyPID)

        #expect(writes == 1, "첫 쓰기에서 끊긴다")
        #expect(reports == 1, "보고도 1회다")
    }

    /// 미지원 스킵(`.attributeUnsupported`)도 같은 규칙이지만 **보고는 아니다**.
    @Test("미지원 응답은 잔여를 끊되 보고하지 않는다")
    func unsupportedEndsExecuteWithoutReport() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var reports = 0
        let adapter = makeAXAdapter(
            axText: axText, writeError: { .attributeUnsupported },
            reportFailure: { _ in reports += 1 }, onWrite: { _ in writes += 1 })

        adapter.execute(
            [.move(.wordForward), .move(.wordForward)], profile: axProfile, processID: anyPID)

        #expect(writes == 1)
        #expect(reports == 0, "미지원은 앱의 정적 성질이지 우리 실행의 고장이 아니다")
    }

    /// 중단 래치는 **파괴적 쓰기 직전**에도 선다 — AX 경로에는 청크가 없어 여기가 유일한
    /// 질의 지점이다.
    @Test("중단된 실행은 AX 쓰기를 내지 않는다")
    func abortedExecuteDoesNotWrite() {
        nonisolated(unsafe) var writes = 0
        let adapter = makeAXAdapter(axText: axText, onWrite: { _ in writes += 1 })

        adapter.execute(
            [.move(.wordForward)], profile: axProfile, processID: anyPID, isCurrent: { false })

        #expect(writes == 0)
    }

    /// **순서 봉인** — 앞선 위임 액션의 미게시 이벤트가 동기 AX 쓰기보다 먼저 나가야 한다.
    /// 게시는 배달만 걸고 돌아오고 AX 쓰기는 대상 앱 런루프까지 동기로 들어가므로, 미게시분을
    /// 두고 쓰면 화면 순서가 액션 순서와 그대로 뒤집힌다.
    @Test("위임 액션의 이벤트가 AX 쓰기보다 먼저 게시된다")
    func pendingKeyboardEventsFlushBeforeWrite() {
        nonisolated(unsafe) var trace: [String] = []
        let adapter = makeAXAdapter(
            axText: axText, onWrite: { _ in trace.append("ax") },
            collecting: { _ in trace.append("post") })

        // `j`는 위임(희망 열), `w`는 AX — 한 execute 안에서 둘이 섞이는 유일한 모양이다.
        adapter.execute(
            [.move(.lineDown), .move(.wordForward)], profile: axProfile, processID: anyPID)

        #expect(trace.first == "post")
        #expect(trace.last == "ax")
    }
}

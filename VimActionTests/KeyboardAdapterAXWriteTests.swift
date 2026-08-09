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

/// 마지막으로 쓴 범위 — 기본 되읽기가 **즉시 착지한 앱**(TextEdit 실측)을 흉내내는 재료다.
private final class LandedRange: @unchecked Sendable {
    var value: NSRange?
}

/// AX 실행 경로를 켠 어댑터 — **다섯 seam을 전부 주입한다.**
///
/// 요소는 `AXUIElementCreateApplication`(순수 로컬 생성, IPC·TCC 없음)이고 뒤따르는 메시징은
/// 읽기·쓰기 seam이 전부 가로채므로 실기기 AX 트리에 닿지 않는다. 진짜 writer가 붙으면
/// 테스트가 **개발자의 실제 문서에 선택 범위를 써 넣는다** (`AXWriterTests`의 같은 주석).
///
/// `readback` 기본값이 "쓴 값 그대로"라 되읽어 검증이 관심사가 아닌 테스트는 폴링에 걸리지
/// 않는다 — 검증 시나리오만 자기 재읽기와 `now`를 주입한다.
private func makeAXAdapter(
    axText: FocusedText?,
    element: AXUIElement? = AXUIElementCreateApplication(99_999),
    clipboard: PasteWise? = .charwise,
    writeError: @escaping @Sendable () -> AXError = { .success },
    readback: (@Sendable () -> NSRange?)? = nil,
    now: @escaping @Sendable () -> TimeInterval = { 0 },
    reportFailure: @escaping @Sendable (TimeInterval) -> Void = { _ in },
    onWrite: @escaping @Sendable (AXCall) -> Void = { _ in },
    collecting posted: @escaping @Sendable (CGEvent) -> Void = { _ in }
) -> KeyboardAdapter {
    let landed = LandedRange()
    return KeyboardAdapter(
        executor: ActionExecutor(postEvent: posted),
        pasteWise: PasteWiseResolver(readClipboard: { clipboard }, readChangeCount: { 0 }),
        reader: FocusedTextReader { _ in nil },
        viewportReader: ViewportReader { _ in nil },
        axWindow: { _ in axText },
        axSelection: { _ in readback?() ?? landed.value },
        writer: AXWriter { _, _, value in
            let written = range(from: value) ?? NSRange(location: -1, length: -1)
            landed.value = written
            onWrite(AXCall(range: written))
            return writeError()
        },
        axElement: { _ in element },
        reportExecutionFailure: reportFailure,
        now: now)
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

// MARK: - 편집 하이브리드 (PR-D1b 세션 2)

/// `"l1\nl2\nl3"` — 오프셋: l0 1:1 \n2 l3 1:4 \n5 l6 3:7, 문서 끝 8.
/// `FocusedTextOffsetsTests`의 `threeLines`와 같은 문서라 두 표가 같은 모델을 딛는다.
private let axLines = "l1\nl2\nl3"

/// keyDown만 남긴 (키코드, 플래그) — 스트로크는 다운·업 쌍이라 짝수 인덱스가 다운이다.
private func downStrokes(_ events: [CGEvent]) -> [(code: Int64, flags: CGEventFlags)] {
    stride(from: 0, to: events.count, by: 2).map {
        (events[$0].getIntegerValueField(.keyboardEventKeycode), events[$0].flags)
    }
}

private let cutStroke = (code: Int64(kVK_ANSI_X), flags: CGEventFlags.maskCommand)
private let copyStroke = (code: Int64(kVK_ANSI_C), flags: CGEventFlags.maskCommand)

struct KeyboardAdapterHybridEditTests {
    /// 하이브리드의 접두 쓰기 범위 — 세션 1의 순수 함수 표와 **같은 답**이어야 한다.
    /// 답이 갈리면 판정(스킵 여부)과 실행(쓰는 범위)이 서로 다른 표를 보게 된다.
    @Test(
        "AX 편집은 계산된 범위를 쓴다",
        arguments: [
            (caret: 0, action: VimAction.edit(.delete, .motion(.charRight, count: 1)),
                written: NSRange(location: 0, length: 1)),  // x
            (caret: 0, action: .edit(.delete, .motion(.wordForward, count: 1)),
                written: NSRange(location: 0, length: 2)),  // dw — 개행을 넘지 않는다
            (caret: 0, action: .edit(.change, .motion(.wordForward, count: 1)),
                written: NSRange(location: 0, length: 2)),  // cw → ce 리타깃
            (caret: 0, action: .edit(.delete, .textObject(.word(.inner))),
                written: NSRange(location: 0, length: 2)),  // diw
            (caret: 3, action: .edit(.delete, .line(count: 1)),
                written: NSRange(location: 3, length: 3)),  // dd — 종결자 포함
            (caret: 6, action: .edit(.delete, .line(count: 1)),
                written: NSRange(location: 5, length: 3)),  // 마지막 줄 dd — 앞 개행 흡수
            (caret: 3, action: .edit(.change, .line(count: 1)),
                written: NSRange(location: 3, length: 2)),  // cc — 줄 유지
        ])
    func hybridWritesComputedSpan(_ fixture: (caret: Int, action: VimAction, written: NSRange)) {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: fixture.caret), onWrite: { calls.append($0) },
            collecting: { posted.append($0) })

        adapter.execute([fixture.action], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [fixture.written])
        // 파괴 단계는 **위임 그대로** — 우리가 텍스트를 쓰는 것이 아니다.
        #expect(downStrokes(posted).map(\.code) == [cutStroke.code])
        #expect(downStrokes(posted).allSatisfy { $0.flags == cutStroke.flags })
    }

    /// yank는 오퍼레이터 뒤에 **게시 `←`** 가 붙는다 — AX 캐럿 쓰기는 게시를 상시 이겨
    /// 빈 복사가 되는 것이 실측됐다 (`20260808_ax-collapse-posted-arrow-not-caret-write.md`).
    /// 한 그룹이라 사이가 끊기지 않는다.
    @Test("yank collapse는 같은 게시 스트림의 ←다")
    func yankCollapseStaysPosted() {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3), onWrite: { calls.append($0) },
            collecting: { posted.append($0) })

        adapter.execute([.edit(.yank, .line(count: 1))], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 3, length: 3)])
        #expect(downStrokes(posted).map(\.code) == [copyStroke.code, Int64(kVK_LeftArrow)])
    }

    /// **기본 전략은 keyboard** — 미지정 프로파일의 편집은 동작 diff 0이다.
    /// 쓰기 seam 무호출이 위임의 증거다(내용 비교가 아니다 — 같은 바이트 회귀는 안 잡힌다).
    @Test("strategy 미지정이면 편집도 쓰기 seam을 부르지 않는다")
    func defaultStrategyDelegatesEdit() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute([.edit(.delete, .line(count: 1))], processID: anyPID)

        #expect(writes == 0)
        #expect(!posted.isEmpty)
    }

    /// 비텍스트·미상 계열은 편집이 걸러내기 게이트에서 막힌다 — AX도 위임도 아니다.
    @Test("nonText·unresolved 계열의 편집은 AX로 가지 않는다", arguments: [ElementFamily.nonText, .unresolved])
    func nonTextFamilyDoesNotWriteEdits(_ family: ElementFamily) {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.edit(.delete, .line(count: 1))], family: family, profile: axProfile,
            processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty, "걸러내기 게이트가 먼저다")
    }

    /// **범위가 이름한 모션**의 재정의는 AX를 이긴다 — 사용자 지시가 우선이다.
    @Test("dw의 word_forward 재정의는 위임으로 낙하한다")
    func namedMotionOverrideDelegatesEdit() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let profile = ResolvedProfile(
            AppProfile(
                strategy: .accessibility,
                motions: [.wordForward: .strokes([ConfigKeyStroke(.end)])]))
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.edit(.delete, .motion(.wordForward, count: 1))], profile: profile, processID: anyPID)

        #expect(writes == 0)
        #expect(downStrokes(posted).map(\.code) == [Int64(kVK_End), cutStroke.code])
    }

    /// **이름하지 않은 모션**의 재정의는 AX를 막지 않는다 — `dd`가 내부적으로 쓰는
    /// `line_start`는 "이 앱에서 `dd`를 하는 방법"이라는 지시가 아니다.
    @Test("dd는 line_start 재정의가 있어도 AX로 간다")
    func unnamedMotionOverrideStillUsesAX() {
        nonisolated(unsafe) var calls: [AXCall] = []
        let profile = ResolvedProfile(
            AppProfile(
                strategy: .accessibility,
                motions: [.lineStart: .strokes([ConfigKeyStroke(.home)])]))
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3), onWrite: { calls.append($0) })

        adapter.execute([.edit(.delete, .line(count: 1))], profile: profile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 3, length: 3)])
    }

    /// Vim 무효는 **정직한 스킵**이다 — 위임하면 실제로 다른 줄이 지워진다.
    @Test(
        "범위가 Vim 무효면 쓰기도 게시도 없다",
        arguments: [
            (caret: 0, range: VimAction.TextRange.linewiseMotion(.lineUp, count: 1)),  // 첫 줄 dk
            (caret: 6, range: .linewiseMotion(.lineDown, count: 1)),  // 마지막 줄 dj
        ])
    func invalidSpanIsHonestSkip(_ fixture: (caret: Int, range: VimAction.TextRange)) {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: fixture.caret), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute([.edit(.delete, fixture.range)], profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty)
    }

    /// 증명 실패(`.selection`·`aw`)는 **위임**이고, 그 시퀀스가 keyboard 경로와 바이트 동일해야
    /// 한다 — 실제 keyboard 어댑터의 출력과 대조한다(상수 하드코딩이 아니다).
    @Test(
        "unproven 낙하는 현행 keyboard 시퀀스와 바이트 동일하다",
        arguments: [
            VimAction.edit(.delete, .selection), .edit(.yank, .selection),
            .edit(.delete, .textObject(.word(.around))),
        ])
    func unprovenDelegationMatchesKeyboard(_ action: VimAction) {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var hybrid: [CGEvent] = []
        nonisolated(unsafe) var keyboard: [CGEvent] = []
        let text = focusedText(axLines, caret: 3)
        let axAdapter = makeAXAdapter(
            axText: text, onWrite: { _ in writes += 1 }, collecting: { hybrid.append($0) })
        // 같은 읽기를 keyboard 경로에 먹인 어댑터 — 전략만 다르다.
        let keyboardAdapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { keyboard.append($0) }),
            pasteWise: PasteWiseResolver(readClipboard: { .charwise }, readChangeCount: { 0 }),
            reader: FocusedTextReader { _ in text },
            viewportReader: ViewportReader { _ in nil })

        axAdapter.execute([action], profile: axProfile, processID: anyPID)
        keyboardAdapter.execute([action], processID: anyPID)

        #expect(writes == 0, "쓰기 시도 전이라 이중 실행이 불가능하다")
        #expect(downStrokes(hybrid).map(\.code) == downStrokes(keyboard).map(\.code))
        #expect(downStrokes(hybrid).map(\.flags) == downStrokes(keyboard).map(\.flags))
    }

    /// 요소·읽기 실패는 `unproven`과 **다른 축**이다 — 위임이 아니라 스킵이고 잔여도 접는다.
    @Test("요소가 없으면 편집도 execute 잔여를 접는다")
    func missingElementEndsEditExecute() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: nil, element: nil, onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.edit(.delete, .line(count: 1)), .edit(.delete, .line(count: 1))], profile: axProfile,
            processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty)
    }

    // MARK: 되읽어 검증

    /// 쓰기 `.success`가 적용 완료가 아닌 앱(Notion ~10ms 비동기 실측)에서 **수렴하면**
    /// 파괴 단계가 나간다 — 즉시 1회 읽기 설계였다면 여기서 상시 헛스킵이었다.
    @Test("낡은 값이 두 번 와도 수렴하면 게시된다")
    func readbackConverges() {
        nonisolated(unsafe) var reads = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3),
            readback: {
                reads += 1
                // 처음 둘은 쓰기 **전** 선택(캐럿)이다.
                return reads <= 2
                    ? NSRange(location: 3, length: 0) : NSRange(location: 3, length: 3)
            },
            collecting: { posted.append($0) })

        adapter.execute([.edit(.delete, .line(count: 1))], profile: axProfile, processID: anyPID)

        #expect(reads == 3)
        #expect(downStrokes(posted).map(\.code) == [cutStroke.code])
    }

    /// 상한(40ms) 도달 = 검증 실패 → **무동작 + execute 잔여 중단**이다. 보고는 아니다
    /// (쓰기는 `.success`였고 파괴는 시도 전).
    @Test("상한까지 어긋나면 파괴 단계가 나가지 않고 잔여도 접힌다")
    func readbackTimeoutSkipsAndEndsExecute() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var reports = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var clock: TimeInterval = 0
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3),
            // 영영 착지하지 않는 앱 — 오프셋 공간 불일치의 모양이다.
            readback: { NSRange(location: 0, length: 0) },
            now: {
                clock += 0.01
                return clock
            },
            reportFailure: { _ in reports += 1 },
            onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.edit(.delete, .line(count: 1)), .edit(.delete, .line(count: 1))], profile: axProfile,
            processID: anyPID)

        #expect(writes == 1, "첫 액션에서 끊긴다 — 잔여는 실행되지 않는다")
        #expect(posted.isEmpty, "파괴 단계는 나가지 않는다")
        #expect(reports == 0, "검증 실패는 실행 실패 보고가 아니다")
    }

    // MARK: 원자성 · 치환

    /// 중단 래치는 **접두 쓰기 직전**까지만이다.
    @Test("쓰기 직전에 밀려나면 접두도 쓰지 않는다")
    func abortBeforePrefixSkipsWrite() {
        nonisolated(unsafe) var writes = 0
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3), onWrite: { _ in writes += 1 })

        adapter.execute(
            [.edit(.delete, .line(count: 1))], profile: axProfile, processID: anyPID,
            isCurrent: { false })

        #expect(writes == 0)
    }

    /// **원자 그룹 ④** — 접두 쓰기(및 검증)와 첫 게시 그룹 사이에는 질의가 없다. 사이에서
    /// 끊기면 AX 선택이 화면에 잔류하고 다음 Normal `x`가 그것을 통째로 잘라낸다.
    @Test("쓰기 도중 밀려나도 첫 그룹은 게시된다")
    func prefixAndFirstGroupAreAtomic() {
        nonisolated(unsafe) var wrote = false
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 3),
            writeError: {
                wrote = true  // 쓰기와 동시에 새 입력이 들어온 모양이다.
                return .success
            },
            collecting: { posted.append($0) })

        adapter.execute(
            [.edit(.delete, .line(count: 1))], profile: axProfile, processID: anyPID,
            isCurrent: { !wrote })

        #expect(downStrokes(posted).map(\.code) == [cutStroke.code])
    }

    /// 비-QWERTY 치환은 `.groups`뿐 아니라 **하이브리드 그룹에도** 걸린다 — 빠지면 AZERTY에서
    /// `Cmd-X`가 엉뚱한 명령으로 나간다.
    @Test("하이브리드 오퍼레이터도 역조회 키코드로 치환된다")
    func hybridGroupIsSubstituted() {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let landed = LandedRange()
        let adapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { posted.append($0) }),
            pasteWise: PasteWiseResolver(readClipboard: { .charwise }, readChangeCount: { 0 }),
            hasQwertyCommandKeys: { false },
            commandKeyCodes: { ["z": 44, "x": 11, "c": 34, "v": 47] },  // Dvorak 실측 표
            reader: FocusedTextReader { _ in nil },
            viewportReader: ViewportReader { _ in nil },
            axWindow: { _ in focusedText(axLines, caret: 3) },
            axSelection: { _ in landed.value },
            writer: AXWriter { _, _, value in
                let written = range(from: value) ?? NSRange(location: -1, length: -1)
                landed.value = written
                calls.append(AXCall(range: written))
                return .success
            },
            axElement: { _ in AXUIElementCreateApplication(99_999) })

        adapter.execute([.edit(.delete, .line(count: 1))], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 3, length: 3)])
        #expect(downStrokes(posted).map(\.code) == [11], "x의 Dvorak 키코드")
        #expect(downStrokes(posted).allSatisfy { $0.flags.contains(.maskCommand) })
    }

    /// 붙여넣기 단위 기억은 **게시 확정 시**라는 현행 규칙이 하이브리드에도 그대로 적용된다 —
    /// 클립보드를 채우는 주체가 여전히 앱이라 `PasteWiseResolver` 계약은 무변경이다.
    @Test("하이브리드 dd도 linewise를 기억한다")
    func hybridRecordsPasteWise() {
        nonisolated(unsafe) var changeCount = 0
        let landed = LandedRange()
        let pasteWise = PasteWiseResolver(
            readClipboard: { .charwise }, readChangeCount: { changeCount })
        let adapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { _ in }),
            pasteWise: pasteWise,
            reader: FocusedTextReader { _ in nil },
            viewportReader: ViewportReader { _ in nil },
            axWindow: { _ in focusedText(axLines, caret: 3) },
            axSelection: { _ in landed.value },
            writer: AXWriter { _, _, value in
                landed.value = range(from: value)
                return .success
            },
            axElement: { _ in AXUIElementCreateApplication(99_999) })

        adapter.execute([.edit(.delete, .line(count: 1))], profile: axProfile, processID: anyPID)
        changeCount += 1  // 앱이 잘라내기를 비동기로 처리했다.

        #expect(pasteWise.resolve() == .linewise, "휴리스틱은 charwise를 낸다 — 기억이 이겨야 한다")
    }

    /// **검증 실패로 나가지 않은 편집도 기억을 남기지 않는다.** 하이브리드는 매핑 확정과 게시
    /// 사이에 설계된 실패 단계(접두 쓰기·되읽어 검증)가 있어, 매핑 시점에 기억하면 나가지도
    /// 않은 편집의 wise가 남는다 — 그 뒤 외부 복사 1회가 델타를 정확히 1로 만들면 `p`가
    /// 그 기억으로 오판된다(델타-1 규칙이 그때는 자가 치유하지 못한다).
    @Test("검증 불일치로 접힌 편집은 wise를 기억하지 않는다")
    func unverifiedEditRecordsNothing() {
        nonisolated(unsafe) var changeCount = 0
        nonisolated(unsafe) var clock: TimeInterval = 0
        let pasteWise = PasteWiseResolver(
            readClipboard: { .charwise }, readChangeCount: { changeCount })
        let adapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { _ in }),
            pasteWise: pasteWise,
            reader: FocusedTextReader { _ in nil },
            viewportReader: ViewportReader { _ in nil },
            axWindow: { _ in focusedText(axLines, caret: 3) },
            axSelection: { _ in NSRange(location: 0, length: 0) },  // 영영 착지하지 않는다
            writer: AXWriter { _, _, _ in .success },
            axElement: { _ in AXUIElementCreateApplication(99_999) },
            now: {
                clock += 0.01
                return clock
            })

        adapter.execute([.edit(.delete, .line(count: 1))], profile: axProfile, processID: anyPID)
        // 사용자가 브라우저에서 charwise로 복사했다 — 델타가 정확히 1이 되는 자리다.
        changeCount += 1

        #expect(pasteWise.resolve() == .charwise, "나가지 않은 편집의 wise가 남으면 안 된다")
    }

    /// 스킵된 편집은 기억도 남기지 않는다 — 무효로 접힌 `dk` 뒤의 `p`가 오염되면 안 된다.
    @Test("Vim 무효로 스킵된 편집은 wise를 기억하지 않는다")
    func skippedEditRecordsNothing() {
        nonisolated(unsafe) var changeCount = 0
        let pasteWise = PasteWiseResolver(
            readClipboard: { .charwise }, readChangeCount: { changeCount })
        let adapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { _ in }),
            pasteWise: pasteWise,
            reader: FocusedTextReader { _ in nil },
            viewportReader: ViewportReader { _ in nil },
            axWindow: { _ in focusedText(axLines, caret: 0) },
            axSelection: { _ in nil },
            writer: AXWriter { _, _, _ in .success },
            axElement: { _ in AXUIElementCreateApplication(99_999) })

        adapter.execute(
            [.edit(.delete, .linewiseMotion(.lineUp, count: 1))], profile: axProfile,
            processID: anyPID)
        changeCount += 1

        #expect(pasteWise.resolve() == .charwise, "기억이 없어 휴리스틱으로 간다")
    }
}

// MARK: - 삽입 하이브리드 (PR-D1b 세션 3)

private let returnCode = Int64(kVK_Return)
private let pasteCode = Int64(kVK_ANSI_V)
private let upCode = Int64(kVK_UpArrow)

struct KeyboardAdapterHybridInsertionTests {
    /// `o`/`O`의 접두는 **논리** 줄 끝/줄 시작이고, 위임분은 `Return`(+`O`의 복귀)뿐이다.
    /// `Cmd-→`/`Cmd-←`가 시각 줄이라 소프트 랩 문단에서 서지 못하던 자리가 여기서 풀린다.
    @Test(
        "openLine은 논리 줄 끝·줄 시작에 캐럿을 쓰고 Return만 위임한다",
        arguments: [
            (caret: 0, above: false, written: 2, delegated: [returnCode]),  // 첫 줄 o
            (caret: 3, above: false, written: 5, delegated: [returnCode]),  // 가운데 줄 o
            (caret: 6, above: false, written: 8, delegated: [returnCode]),  // 마지막 줄 o (문서 끝)
            (caret: 0, above: true, written: 0, delegated: [returnCode, upCode]),  // 첫 줄 O
            (caret: 4, above: true, written: 3, delegated: [returnCode, upCode]),
        ])
    func openLineWritesCaret(
        _ fixture: (caret: Int, above: Bool, written: Int, delegated: [Int64])
    ) {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: fixture.caret), onWrite: { calls.append($0) },
            collecting: { posted.append($0) })

        adapter.execute([.openLine(above: fixture.above)], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: fixture.written, length: 0)])
        #expect(downStrokes(posted).map(\.code) == fixture.delegated)
    }

    /// 계열 게이트는 하이브리드가 우회하지 못한다 — 단일행 필드에서 `Return`은 submit이다.
    @Test("textField의 openLine은 AX로도 나가지 않는다")
    func openLineTextFieldStaysBlocked() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.openLine(above: false)], family: .textField, profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty)
    }

    /// `new_line` 재정의는 위임분에 남아 있어야 한다 — 접두만 AX로 갈아끼운다.
    @Test("openLine 하이브리드도 new_line 재정의를 탄다")
    func openLineHonorsNewLineOverride() {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let profile = ResolvedProfile(
            AppProfile(
                strategy: .accessibility,
                actions: [.openLine: .strokes([ConfigKeyStroke(.return, [.shift])])]))
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), onWrite: { calls.append($0) },
            collecting: { posted.append($0) })

        adapter.execute([.openLine(above: false)], profile: profile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 2, length: 0)])
        #expect(downStrokes(posted).map(\.code) == [returnCode])
        #expect(downStrokes(posted).allSatisfy { $0.flags.contains(.maskShift) })
    }

    /// 붙여넣기 삽입점 — 세션 1의 순수 함수 표와 같은 답이어야 한다. 접두가 캐럿 쓰기라
    /// **화살표 우회 장치가 전부 사라진다**: 줄 끝 `→` 포화도, linewise의 꼬리 `Cmd-←`도 없다.
    @Test(
        "paste는 계산된 삽입점에 캐럿을 쓰고 Cmd-V만 위임한다",
        arguments: [
            (caret: 0, before: false, wise: PasteWise.charwise, written: 1),  // p — 한 칸 오른쪽
            (caret: 1, before: false, wise: .charwise, written: 2),
            (caret: 2, before: false, wise: .charwise, written: 2),  // 줄 끝 xp — 접두 없음
            (caret: 8, before: false, wise: .charwise, written: 8),  // 문서 끝
            (caret: 1, before: true, wise: .charwise, written: 1),  // P — 캐럿 그대로
            (caret: 4, before: true, wise: .linewise, written: 3),  // 줄 시작
            (caret: 0, before: false, wise: .linewise, written: 3),  // 다음 줄 시작
            (caret: 4, before: false, wise: .linewise, written: 6),
        ])
    func pasteWritesInsertion(
        _ fixture: (caret: Int, before: Bool, wise: PasteWise, written: Int)
    ) {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: fixture.caret), clipboard: fixture.wise,
            onWrite: { calls.append($0) }, collecting: { posted.append($0) })

        adapter.execute(
            [.paste(before: fixture.before, count: 1)], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: fixture.written, length: 0)])
        #expect(downStrokes(posted).map(\.code) == [pasteCode], "접두 화살표가 하나도 없다")
        #expect(downStrokes(posted).allSatisfy { $0.flags == .maskCommand })
    }

    /// **이 세션의 수용 기준.** 마지막 줄(뒤 개행 없음)의 linewise `p`는 문서 끝 캐럿 +
    /// `[Return, Cmd-V]`다 — `ddp`의 `P` 퇴행이 여기서 실해소된다. naive 문서 끝 캐럿은
    /// 병합 훼손이 실측됐고, 캐럿 쓰기만으로는 구분 개행을 만들 수 없다.
    @Test("마지막 줄 linewise p는 문서 끝 캐럿 + [Return, Cmd-V]다")
    func lastLineLinewisePasteSynthesizesReturn() {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 6), clipboard: .linewise,
            onWrite: { calls.append($0) }, collecting: { posted.append($0) })

        adapter.execute([.paste(before: false, count: 1)], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 8, length: 0)])
        #expect(downStrokes(posted).map(\.code) == [returnCode, pasteCode])
    }

    /// **끝 개행이 있는 문서의 빈 마지막 줄에서는 개행을 합성하지 않는다.** 구분 개행이 이미
    /// 있어 그 자리가 곧 삽입점이고, `Return`을 내면 빈 줄이 하나 더 생겨 현행 keyboard보다
    /// 나빠진다 — `"l1\nl2\n"`의 마지막 줄 `dd` 뒤 `p`가 정확히 이 자리다.
    @Test("끝 개행 뒤 빈 줄의 linewise p는 Return 없이 붙인다")
    func trailingNewlineLastLinePasteDoesNotSynthesize() {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText("l1\nl2\n", caret: 6), clipboard: .linewise,
            onWrite: { calls.append($0) }, collecting: { posted.append($0) })

        adapter.execute([.paste(before: false, count: 1)], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 6, length: 0)])
        #expect(downStrokes(posted).map(\.code) == [pasteCode])
    }

    /// `open_line: disabled`는 `.paste`의 개행 합성도 막는다 — `.paste` 액션이라 어댑터의
    /// `actions:` 게이트를 지나지 않으므로, 매퍼가 fail-open 하면 `Return`이 전송인 앱에서
    /// `p` 한 번이 메시지를 보낸다. 강등 결과는 현행 위임(`P` 퇴행)이다.
    @Test("open_line disable이면 마지막 줄 p도 위임으로 강등한다")
    func openLineDisableDemotesAppendingLine() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let profile = ResolvedProfile(
            AppProfile(strategy: .accessibility, actions: [.openLine: .disabled]))
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 6), clipboard: .linewise,
            onWrite: { _ in writes += 1 }, collecting: { posted.append($0) })

        adapter.execute([.paste(before: false, count: 1)], profile: profile, processID: anyPID)

        #expect(writes == 0)
        #expect(
            !downStrokes(posted).map(\.code).contains(returnCode), "개행 합성이 나가면 안 된다")
        #expect(!posted.isEmpty, "강등이지 스킵이 아니다")
    }

    /// `.appendingLine`의 개행도 `new_line` 훅을 탄다 — 줄을 만드는 키라는 점이 `o`와 같다.
    @Test("appendingLine의 개행도 new_line 재정의를 탄다")
    func appendingLineHonorsNewLineOverride() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let profile = ResolvedProfile(
            AppProfile(
                strategy: .accessibility,
                actions: [.openLine: .strokes([ConfigKeyStroke(.return, [.shift])])]))
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 6), clipboard: .linewise,
            collecting: { posted.append($0) })

        adapter.execute([.paste(before: false, count: 1)], profile: profile, processID: anyPID)

        #expect(downStrokes(posted).map(\.code) == [returnCode, pasteCode])
        #expect(downStrokes(posted).first?.flags.contains(.maskShift) == true)
    }

    /// 단일행 필드는 **항상** "종결자 없는 마지막 줄"이라 linewise `p`가 상시 이 경로로
    /// 떨어진다 — 거기서 `Return`은 대개 submit이므로 위임(현행 `P` 퇴행)으로 강등한다.
    @Test("textField의 마지막 줄 linewise p는 위임으로 강등한다")
    func appendingLineInTextFieldDelegates() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var hybrid: [CGEvent] = []
        nonisolated(unsafe) var keyboard: [CGEvent] = []
        let text = focusedText(axLines, caret: 6)
        let axAdapter = makeAXAdapter(
            axText: text, clipboard: .linewise, onWrite: { _ in writes += 1 },
            collecting: { hybrid.append($0) })
        let keyboardAdapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { keyboard.append($0) }),
            pasteWise: PasteWiseResolver(readClipboard: { .linewise }, readChangeCount: { 0 }),
            reader: FocusedTextReader { _ in text },
            viewportReader: ViewportReader { _ in nil })

        axAdapter.execute(
            [.paste(before: false, count: 1)], family: .textField, profile: axProfile,
            processID: anyPID)
        keyboardAdapter.execute(
            [.paste(before: false, count: 1)], family: .textField, processID: anyPID)

        #expect(writes == 0)
        #expect(downStrokes(hybrid).map(\.code) == downStrokes(keyboard).map(\.code))
        #expect(!hybrid.isEmpty, "강등이지 스킵이 아니다")
    }

    /// 카운트는 **접두 1회 + `Cmd-V`×count**다. 첫 그룹만 원자이고 나머지는 일반 청크 경로라
    /// 게시 순서·개수가 keyboard와 같은 모양을 유지한다.
    @Test("3p는 쓰기 1건 + Cmd-V 3타다")
    func countedPasteWritesOnce() {
        nonisolated(unsafe) var calls: [AXCall] = []
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), clipboard: .charwise,
            onWrite: { calls.append($0) }, collecting: { posted.append($0) })

        adapter.execute([.paste(before: false, count: 3)], profile: axProfile, processID: anyPID)

        #expect(calls.map(\.range) == [NSRange(location: 1, length: 0)])
        #expect(downStrokes(posted).map(\.code) == [pasteCode, pasteCode, pasteCode])
    }

    /// 마지막 줄 `3p`도 `Return`은 **첫 그룹에만** 붙는다 — 뒤의 `Cmd-V`는 붙여넣은 내용
    /// 끝(개행 뒤)에서 이어지므로 개행을 다시 만들 이유가 없다.
    @Test("마지막 줄 3p의 Return은 첫 그룹에만 붙는다")
    func countedAppendingLinePasteSynthesizesOneReturn() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 6), clipboard: .linewise,
            collecting: { posted.append($0) })

        adapter.execute([.paste(before: false, count: 3)], profile: axProfile, processID: anyPID)

        #expect(
            downStrokes(posted).map(\.code) == [returnCode, pasteCode, pasteCode, pasteCode])
    }

    /// 증명 실패는 **위임**이고 그 시퀀스가 keyboard 경로와 바이트 동일해야 한다 —
    /// 살아 있는 선택 위에서는 출발점을 증명할 수 없다(정확화 표의 공통 조건).
    @Test(
        "unproven 낙하는 현행 keyboard 시퀀스와 바이트 동일하다",
        arguments: [
            VimAction.paste(before: false, count: 1), .paste(before: true, count: 1),
            .openLine(above: false), .openLine(above: true),
        ])
    func unprovenInsertionDelegatesLikeKeyboard(_ action: VimAction) {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var hybrid: [CGEvent] = []
        nonisolated(unsafe) var keyboard: [CGEvent] = []
        // 살아 있는 선택 — 삽입 산출도 캐럿(길이 0)만 증명한다.
        let text = focusedText(axLines, caret: 3, length: 2)
        let axAdapter = makeAXAdapter(
            axText: text, onWrite: { _ in writes += 1 }, collecting: { hybrid.append($0) })
        let keyboardAdapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { keyboard.append($0) }),
            pasteWise: PasteWiseResolver(readClipboard: { .charwise }, readChangeCount: { 0 }),
            reader: FocusedTextReader { _ in text },
            viewportReader: ViewportReader { _ in nil })

        axAdapter.execute([action], profile: axProfile, processID: anyPID)
        keyboardAdapter.execute([action], processID: anyPID)

        #expect(writes == 0, "쓰기 시도 전이라 이중 실행이 불가능하다")
        #expect(downStrokes(hybrid).map(\.code) == downStrokes(keyboard).map(\.code))
        #expect(downStrokes(hybrid).map(\.flags) == downStrokes(keyboard).map(\.flags))
    }

    /// 요소·읽기 실패는 `unproven`과 **다른 축**이다 — 위임이 아니라 스킵이고 잔여도 접는다.
    @Test("요소가 없으면 삽입도 execute 잔여를 접는다")
    func missingElementEndsInsertionExecute() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: nil, element: nil, onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.paste(before: false, count: 1), .openLine(above: false)], profile: axProfile,
            processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty)
    }

    /// **되읽어 검증은 삽입 하이브리드에도 걸린다** — 접두가 캐럿 이동뿐이라 파괴 등급은
    /// 낮지만, 검증을 빼면 낡은 캐럿 위에서 `Cmd-V`·`Return`이 터진다(`.appendingLine`에서는
    /// 줄 분리). 상한 도달 = 무동작 + execute 잔여 중단이다.
    @Test("접두가 착지하지 않으면 붙여넣기도 나가지 않는다")
    func insertionReadbackTimeoutSkips() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var reports = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var clock: TimeInterval = 0
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0),
            readback: { NSRange(location: 99, length: 0) },  // 영영 착지하지 않는다
            now: {
                clock += 0.01
                return clock
            },
            reportFailure: { _ in reports += 1 },
            onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.paste(before: false, count: 1), .paste(before: false, count: 1)], profile: axProfile,
            processID: anyPID)

        #expect(writes == 1, "첫 액션에서 끊긴다")
        #expect(posted.isEmpty)
        #expect(reports == 0, "검증 실패는 실행 실패 보고가 아니다")
    }

    /// 중단 래치는 접두 쓰기 직전까지만이다 — 삽입도 같은 규칙이다.
    @Test("쓰기 직전에 밀려나면 삽입 접두도 쓰지 않는다")
    func abortBeforeInsertionPrefixSkipsWrite() {
        nonisolated(unsafe) var writes = 0
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), onWrite: { _ in writes += 1 })

        adapter.execute(
            [.paste(before: false, count: 1)], profile: axProfile, processID: anyPID,
            isCurrent: { false })

        #expect(writes == 0)
    }

    /// 비-QWERTY 치환은 하이브리드 `Cmd-V`에도 걸린다 — 빠지면 AZERTY에서 엉뚱한 명령이 나간다.
    @Test("하이브리드 Cmd-V도 역조회 키코드로 치환된다")
    func hybridPasteIsSubstituted() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let landed = LandedRange()
        let adapter = KeyboardAdapter(
            executor: ActionExecutor(postEvent: { posted.append($0) }),
            pasteWise: PasteWiseResolver(readClipboard: { .charwise }, readChangeCount: { 0 }),
            hasQwertyCommandKeys: { false },
            commandKeyCodes: { ["z": 44, "x": 11, "c": 34, "v": 47] },  // Dvorak 실측 표
            reader: FocusedTextReader { _ in nil },
            viewportReader: ViewportReader { _ in nil },
            axWindow: { _ in focusedText(axLines, caret: 0) },
            axSelection: { _ in landed.value },
            writer: AXWriter { _, _, value in
                landed.value = range(from: value)
                return .success
            },
            axElement: { _ in AXUIElementCreateApplication(99_999) })

        adapter.execute([.paste(before: false, count: 1)], profile: axProfile, processID: anyPID)

        #expect(downStrokes(posted).map(\.code) == [47], "v의 Dvorak 키코드")
    }

    /// `actions:` disable은 모든 게이트·부수효과보다 앞이다 — AX 왕복도 0건이어야 한다.
    @Test("프로파일이 끈 paste·openLine은 AX로도 나가지 않는다")
    func disabledActionsSkipAX() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let profile = ResolvedProfile(
            AppProfile(strategy: .accessibility, actions: [.paste: .disabled, .openLine: .disabled])
        )
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.paste(before: false, count: 1), .openLine(above: false)], profile: profile,
            processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty)
    }

    /// 비텍스트·미상 계열은 걸러내기 게이트가 먼저다 — AX도 위임도 아니다.
    @Test(
        "nonText·unresolved 계열의 삽입은 AX로 가지 않는다",
        arguments: [ElementFamily.nonText, .unresolved])
    func nonTextFamilyDoesNotWriteInsertions(_ family: ElementFamily) {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.paste(before: false, count: 1), .openLine(above: false)], family: family,
            profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty)
    }

    /// **기본 전략은 keyboard** — 미지정 프로파일의 삽입은 동작 diff 0이다.
    @Test("strategy 미지정이면 삽입도 쓰기 seam을 부르지 않는다")
    func defaultStrategyDelegatesInsertion() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), onWrite: { _ in writes += 1 },
            collecting: { posted.append($0) })

        adapter.execute(
            [.paste(before: false, count: 1), .openLine(above: false)], processID: anyPID)

        #expect(writes == 0)
        #expect(!posted.isEmpty)
    }

    /// 텍스트 없는 클립보드는 AX 경로에서도 정직한 스킵이다 — 접두만 쓰면 "붙여넣기 없이
    /// 캐럿만 움직이는" 조용한 오동작이 된다.
    @Test("빈 클립보드는 AX 경로에서도 스킵이다")
    func emptyClipboardSkipsBeforeWrite() {
        nonisolated(unsafe) var writes = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAXAdapter(
            axText: focusedText(axLines, caret: 0), clipboard: nil,
            onWrite: { _ in writes += 1 }, collecting: { posted.append($0) })

        adapter.execute([.paste(before: false, count: 1)], profile: axProfile, processID: anyPID)

        #expect(writes == 0)
        #expect(posted.isEmpty)
    }
}

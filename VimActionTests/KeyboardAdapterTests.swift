//
//  KeyboardAdapterTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine
@testable import VimAction

/// 게시 함수를 가로챈 어댑터 — 실제 키를 테스트 머신에 주입하지 않는다.
/// CGEvent **생성**은 TCC 권한이 필요 없어 headless로 돈다.
private func makeAdapter(collecting posted: @escaping @Sendable (CGEvent) -> Void) -> KeyboardAdapter {
    KeyboardAdapter(executor: ActionExecutor(postEvent: posted))
}

private func keyCodes(of events: [CGEvent]) -> [Int64] {
    events.map { $0.getIntegerValueField(.keyboardEventKeycode) }
}

struct KeyboardAdapterTests {
    @Test("모션 1개 → keyDown+keyUp 쌍 (순서·키코드·플래그)")
    func moveProducesDownUpPair() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.move(.wordBackward)])

        #expect(posted.map(\.type) == [.keyDown, .keyUp])
        #expect(keyCodes(of: posted) == [Int64(kVK_LeftArrow), Int64(kVK_LeftArrow)])
        // 플래그는 keyUp에도 실린다 — 앱이 보는 modifier 상태가 쌍 사이에서 흔들리지 않게.
        #expect(posted.allSatisfy { $0.flags.contains(.maskAlternate) })
        #expect(posted.allSatisfy { !$0.flags.contains(.maskCommand) })
    }

    @Test("모디파이어 없는 모션은 수정키를 싣지 않는다")
    func plainMotionCarriesNoModifiers() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.move(.charLeft)])

        #expect(keyCodes(of: posted) == [Int64(kVK_LeftArrow), Int64(kVK_LeftArrow)])
        #expect(posted.allSatisfy { $0.flags.isDisjoint(with: [.maskAlternate, .maskCommand, .maskControl, .maskShift]) })
    }

    /// 카운트는 엔진이 반복 액션으로 펼쳐서 준다 — 어댑터는 순서대로 그만큼 낸다.
    @Test("반복 모션은 순서대로 전부 게시된다")
    func repeatedMotionsPostInOrder() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.move(.lineDown), .move(.lineDown), .move(.lineEnd)])

        #expect(posted.count == 6)
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_DownArrow), Int64(kVK_DownArrow),
                Int64(kVK_DownArrow), Int64(kVK_DownArrow),
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
            ])
        #expect(posted.suffix(2).allSatisfy { $0.flags.contains(.maskCommand) })
    }

    /// 미지원 액션은 **실패가 아니다** — 조용히 스킵한다. 실패로 보고하면 정상 사용의
    /// `dd` 연타가 폭주 자동 off를 트립하는 오탐이 된다.
    @Test("미지원 액션은 게시 없이 스킵된다")
    func unsupportedActionsAreSkipped() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([
            .edit(.delete, .line(count: 1)),
            .paste(before: false, count: 1),
            .beginSelection(linewise: false),
            .extendSelection(.charRight),
            .openLine(above: false),
            .undo,
            .redo,
            .scroll(.halfPage, forward: true),
            .clearSelection,
            .switchSelectionWise(linewise: true),
        ])

        #expect(posted.isEmpty)
    }

    @Test("미지원이 섞여 있어도 모션은 실행된다")
    func supportedMotionsRunAlongsideUnsupported() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([
            .edit(.delete, .line(count: 1)),
            .move(.charRight),
            .undo,
        ])

        #expect(keyCodes(of: posted) == [Int64(kVK_RightArrow), Int64(kVK_RightArrow)])
    }

    @Test("빈 액션 시퀀스는 아무것도 게시하지 않는다")
    func emptyActionsPostNothing() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([])

        #expect(posted.isEmpty)
    }

    /// 멀티 스트로크 모션 — 스트로크마다 keyDown+keyUp 쌍이 매핑 순서 그대로 나온다.
    /// 쌍이 어긋나거나 순서가 섞이면 조합의 착지점이 달라진다.
    @Test("멀티 스트로크 모션은 스트로크별 쌍이 순서대로 게시된다")
    func multiStrokeMotionPostsPairsInOrder() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.move(.wordForward)])

        #expect(posted.map(\.type) == [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp])
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
            ])
        #expect(posted.allSatisfy { $0.flags.contains(.maskAlternate) })
    }

    /// 마커 불변식 — 어댑터가 내는 이벤트는 전부 `ActionExecutor`를 거치므로 마킹돼 있다.
    /// 마킹되지 않은 합성 이벤트는 탭이 재해석해 무한 루프가 된다.
    @Test("게시된 모든 이벤트에 합성 마커가 찍혀 있다")
    func everyPostedEventIsMarked() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.move(.documentEnd), .move(.charLeft)])

        #expect(posted.count == 4)
        #expect(posted.allSatisfy { SyntheticEventMarker.isMarked($0) })
    }
}

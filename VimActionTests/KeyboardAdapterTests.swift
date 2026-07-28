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
            // 지원하는 `.edit`이라도 이 계열에서 미지원인 범위는 같은 스킵 경로다.
            .edit(.change, .textObject(.quote(.double, .inner))),
            .paste(before: false, count: 1),
            .openLine(above: false),
            .undo,
            .redo,
            .scroll(.halfPage, forward: true),
            // `V`→`v`는 줄 반올림에 역연산이 없어 미지원이다 — 무게시가 아니라 정직한 스킵.
            .switchSelectionWise(linewise: false),
        ])

        #expect(posted.isEmpty)
    }

    @Test("미지원이 섞여 있어도 모션은 실행된다")
    func supportedMotionsRunAlongsideUnsupported() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([
            .paste(before: false, count: 1),
            .move(.charRight),
            .undo,
        ])

        #expect(keyCodes(of: posted) == [Int64(kVK_RightArrow), Int64(kVK_RightArrow)])
    }

    /// 편집 배선 — 매퍼가 낸 시퀀스가 순서 그대로 쌍이 되어 나간다. `dd`는 줄 시작으로
    /// 이동 → 아래로 선택 확장 → 잘라내기 3타다.
    @Test("편집 액션은 매퍼 시퀀스대로 게시된다")
    func editProducesMappedSequence() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.edit(.delete, .line(count: 1))])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_DownArrow), Int64(kVK_DownArrow),
                Int64(kVK_ANSI_X), Int64(kVK_ANSI_X),
            ])
        #expect(posted.map(\.type) == [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp])
        // 선택 확장 구간에만 Shift가 실린다 — 접두와 오퍼레이터 키에 새면 범위가 어긋난다.
        #expect(posted.prefix(2).allSatisfy { !$0.flags.contains(.maskShift) })
        #expect(posted.dropFirst(2).prefix(2).allSatisfy { $0.flags.contains(.maskShift) })
        #expect(posted.suffix(2).allSatisfy { $0.flags == .maskCommand })
    }

    /// 지원하는 `.edit`이라도 범위가 미지원이면 게시가 아예 없어야 한다 — 절반만 나가면
    /// 선택만 해 놓고 멈춘 상태가 된다.
    @Test("미지원 범위의 편집은 게시 0건이다")
    func unsupportedEditRangePostsNothing() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.edit(.delete, .textObject(.pair(.paren, .around)))])

        #expect(posted.isEmpty)
    }

    @Test("편집이 낸 이벤트에도 합성 마커가 찍혀 있다")
    func editedEventsAreMarked() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.edit(.yank, .motion(.wordForward, count: 1))])

        #expect(!posted.isEmpty)
        #expect(posted.allSatisfy { SyntheticEventMarker.isMarked($0) })
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

    /// Visual `y` 회귀 방어 — 엔진은 `.edit(.yank, .selection)`과 `clearSelection`을 **두 액션**으로
    /// 낸다. collapse는 `clearSelection`이 전담하므로 `←`는 **정확히 한 번**만 나가야 한다.
    /// 양쪽이 다 내면 캐럿이 범위 시작에서 한 칸 더 밀린다.
    @Test("Visual y는 Cmd-C 뒤에 ←를 한 번만 낸다")
    func visualYankThenClearPostsCopyThenSingleLeft() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.edit(.yank, .selection), .clearSelection])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_ANSI_C), Int64(kVK_ANSI_C),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
            ])
        #expect(posted.prefix(2).allSatisfy { $0.flags == .maskCommand })
        // collapse의 `←`는 맨 키다 — 수식자가 실리면 범위 시작이 아닌 곳으로 간다.
        #expect(posted.suffix(2).allSatisfy { $0.flags.isDisjoint(with: .maskCommand) })
    }

    /// `v` 진입은 무게시가 아니다 — Vim의 charwise Visual은 inclusive라 커서 문자가 이미
    /// 잡혀 있어야 하고, 그래야 이탈 시 `←`가 접을 선택을 찾아 캐럿이 제자리에 남는다.
    @Test("v 진입은 Shift-→ 1타로 커서 문자를 선택한다")
    func charwiseEntrySelectsOneCharacter() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.beginSelection(linewise: false)])

        #expect(keyCodes(of: posted) == [Int64(kVK_RightArrow), Int64(kVK_RightArrow)])
        #expect(posted.allSatisfy { $0.flags.contains(.maskShift) })
    }

    /// Visual 세션 배선 — `V` 진입 후 `j` 확장이 매퍼 시퀀스대로 이어 나간다.
    @Test("Visual 세션은 매퍼 시퀀스대로 게시된다")
    func visualSessionProducesMappedSequence() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.beginSelection(linewise: true), .extendSelection(.lineDown)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_DownArrow), Int64(kVK_DownArrow),
                Int64(kVK_DownArrow), Int64(kVK_DownArrow),
            ])
        // 진입의 `Cmd-←`만 선택이 아니다 — 나머지는 전부 선택 확장이라 Shift가 실린다.
        #expect(posted.prefix(2).allSatisfy { $0.flags == .maskCommand })
        #expect(posted.dropFirst(2).allSatisfy { $0.flags.contains(.maskShift) })
        #expect(posted.allSatisfy { SyntheticEventMarker.isMarked($0) })
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

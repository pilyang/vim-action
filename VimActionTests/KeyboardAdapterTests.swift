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
///
/// 클립보드도 **항상 주입한다** — 프로덕션 기본값으로 흘러가면 `.paste` 테스트가 개발자의
/// 실제 클립보드를 읽어 비결정적이 된다(`defaults` 주입과 같은 이유).
/// `changeCount`도 주입한다 — 기본값은 **변하지 않는** 카운터라 "우리 편집 기억"이 발동하지
/// 않고 클립보드 휴리스틱만 쓰인다. 기억 경로는 그것을 검증하는 테스트가 직접 올린다.
private func makeAdapter(
    clipboard wise: PasteWise? = .charwise,
    changeCount: @escaping @Sendable () -> Int = { 0 },
    collecting posted: @escaping @Sendable (CGEvent) -> Void
) -> KeyboardAdapter {
    KeyboardAdapter(
        executor: ActionExecutor(postEvent: posted),
        pasteWise: PasteWiseResolver(readClipboard: { wise }, readChangeCount: changeCount))
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
            // `V`→`v`는 줄 반올림에 역연산이 없어 미지원이다 — 무게시가 아니라 정직한 스킵.
            .switchSelectionWise(linewise: false),
        ])

        #expect(posted.isEmpty)
    }

    /// 클립보드에 텍스트가 없으면 `p`는 **미지원이 아니라** "붙여넣을 것이 없음"이다 —
    /// 어느 쪽이든 게시는 0건이지만, 접두만 나가면 붙여넣기 없이 캐럿이 움직이는 오동작이 된다.
    @Test("텍스트 없는 클립보드의 paste는 게시 0건이다")
    func pasteWithoutClipboardTextPostsNothing() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(clipboard: nil) { posted.append($0) }

        adapter.execute([.paste(before: false, count: 1), .paste(before: true, count: 3)])

        #expect(posted.isEmpty)
    }

    @Test("미지원이 섞여 있어도 모션은 실행된다")
    func supportedMotionsRunAlongsideUnsupported() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([
            .edit(.delete, .textObject(.pair(.paren, .around))),
            .move(.charRight),
            .switchSelectionWise(linewise: false),
        ])

        #expect(keyCodes(of: posted) == [Int64(kVK_RightArrow), Int64(kVK_RightArrow)])
    }

    /// `o` 배선 — 줄 끝으로 간 뒤 개행. 엔진이 이미 Insert로 전이했으므로 뒤에 붙일 키가 없다.
    @Test("o는 Cmd-→ 뒤 Return을 낸다")
    func openLineBelowPostsLineEndThenReturn() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.openLine(above: false)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_Return), Int64(kVK_Return),
            ])
        #expect(posted.prefix(2).allSatisfy { $0.flags == .maskCommand })
        // `Return`은 맨 키다 — Cmd가 실리면 앱별 전용 단축키로 나간다.
        #expect(posted.suffix(2).allSatisfy { $0.flags.isDisjoint(with: [.maskCommand, .maskShift]) })
    }

    /// `O`는 **명령 키로 끝나지 않는다** — 개행이 현재 줄을 아래로 밀고, 새로 생긴 빈 줄로
    /// `↑`가 올라가야 한다. 이 3타 순서가 첫 줄에서도 맞는 것이 설계의 요점이다.
    @Test("O는 Cmd-←, Return, ↑ 3타를 순서대로 낸다")
    func openLineAbovePostsThreeStrokesEndingWithUp() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.openLine(above: true)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_Return), Int64(kVK_Return),
                Int64(kVK_UpArrow), Int64(kVK_UpArrow),
            ])
        #expect(posted.suffix(2).allSatisfy { $0.flags.isDisjoint(with: [.maskCommand, .maskShift]) })
    }

    @Test("u는 Cmd-Z, Ctrl-r은 Shift-Cmd-Z다")
    func undoRedoPostCommandZ() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.undo, .redo])

        #expect(keyCodes(of: posted).allSatisfy { $0 == Int64(kVK_ANSI_Z) })
        #expect(posted.prefix(2).allSatisfy { $0.flags == .maskCommand })
        #expect(posted.suffix(2).allSatisfy { $0.flags == [.maskShift, .maskCommand] })
    }

    /// 스크롤은 화살표 반복이다 — 페이지 키가 뷰만 옮기고 다음 모션에 되돌아오기 때문이다.
    /// **modifier가 하나도 없어야** 한다: Shift가 새면 스크롤이 선택이 되고, Cmd가 새면
    /// 문서 끝으로 튄다.
    @Test("스크롤은 화살표 반복이고 full은 half의 2배다")
    func scrollPostsArrowRepetition() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.scroll(.halfPage, forward: true)])
        let half = keyCodes(of: posted)
        posted = []
        adapter.execute([.scroll(.fullPage, forward: false)])
        let full = keyCodes(of: posted)

        // keyDown/keyUp 쌍이라 이벤트 수는 스트로크의 2배다.
        #expect(half == Array(repeating: Int64(kVK_DownArrow), count: 15 * 2))
        #expect(full == Array(repeating: Int64(kVK_UpArrow), count: 30 * 2))
        #expect(posted.allSatisfy { $0.flags.isDisjoint(with: [.maskCommand, .maskShift]) })
    }

    /// 우리가 낸 `dd`가 클립보드를 쓰면 뒤따르는 `p`는 **끝 개행 휴리스틱을 쓰지 않는다** —
    /// Notion처럼 끝 개행을 안 붙이는 앱에서 linewise 내용이 charwise로 오판되던 것을 막는다.
    @Test("직전 dd 뒤의 p는 클립보드가 charwise로 보여도 linewise로 붙여넣는다")
    func lineEditIsRememberedAsLinewise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        // 클립보드는 charwise로 보인다(Notion이 끝 개행을 안 붙인 상황).
        let adapter = makeAdapter(clipboard: .charwise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.edit(.delete, .line(count: 1))])
        posted = []
        count += 1  // 대상 앱이 잘라내기를 처리해 클립보드를 썼다.
        adapter.execute([.paste(before: false, count: 1)])

        // linewise `p` 접두 = `Cmd-→, →, Cmd-←` 뒤에 `Cmd-V`.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// 기억이 내용을 설명하지 못하면 휴리스틱으로 돌아간다 — 우리 편집 뒤에 **다른 무언가가**
    /// 클립보드를 덮었으면(2회 이상 증가) 그 내용은 더 이상 우리 것이 아니다.
    @Test("우리 편집 뒤 외부 복사가 끼면 휴리스틱으로 폴백한다")
    func externalCopyAfterOurEditFallsBackToHeuristic() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .charwise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.edit(.delete, .line(count: 1))])
        posted = []
        count += 2  // 우리 잘라내기 + 외부 복사.
        adapter.execute([.paste(before: false, count: 1)])

        // charwise `p` = `→` 뒤에 `Cmd-V`.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// `cc`는 줄 끝까지만 선택해 개행을 남기지 않는다 — 내용이 실제로 charwise이므로
    /// 줄 단위로 기억하면 안 된다.
    @Test("change는 줄 범위여도 linewise로 기억하지 않는다")
    func changeIsNotRememberedAsLinewise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .charwise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.edit(.change, .line(count: 1))])
        posted = []
        count += 1
        adapter.execute([.paste(before: false, count: 1)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// charwise `3p` — 위치 접두는 **1회만**이고 `Cmd-V`만 반복한다. 접두가 반복되면
    /// 두 번째 붙여넣기가 한 칸씩 밀린 곳으로 간다.
    @Test("charwise 3p는 → 1타 뒤 Cmd-V 3연타다")
    func charwisePasteRepeatsOnlyTheCommandKey() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(clipboard: .charwise) { posted.append($0) }

        adapter.execute([.paste(before: false, count: 3)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
        // 접두 `→`에 Shift가 새면 선택이 되고 뒤이은 `Cmd-V`가 그 선택을 덮어쓴다.
        #expect(posted.prefix(2).allSatisfy { $0.flags.isEmpty })
        #expect(posted.dropFirst(2).allSatisfy { $0.flags == .maskCommand })
    }

    /// linewise `p` — 다음 줄 시작으로 3타 이동 후 붙여넣기. 꼬리 `Cmd-←`가 마지막 줄의
    /// `→` 포화를 보정하는 멱등 보정자다.
    @Test("linewise p는 Cmd-→, →, Cmd-← 뒤 Cmd-V다")
    func linewisePasteNormalizesToNextLineStart() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(clipboard: .linewise) { posted.append($0) }

        adapter.execute([.paste(before: false, count: 1)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
        #expect(posted.prefix(2).allSatisfy { $0.flags == .maskCommand })
        #expect(posted.dropFirst(2).prefix(2).allSatisfy { $0.flags.isEmpty })
        #expect(posted.suffix(4).allSatisfy { $0.flags == .maskCommand })
    }

    /// linewise `P`는 줄 시작에서 바로 붙여넣는다 — 클립보드가 개행으로 끝나 현재 줄이 밀린다.
    @Test("linewise P는 Cmd-← 뒤 Cmd-V다")
    func linewisePasteBeforePostsLineStartThenPaste() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(clipboard: .linewise) { posted.append($0) }

        adapter.execute([.paste(before: true, count: 1)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
        #expect(posted.allSatisfy { $0.flags == .maskCommand })
        #expect(posted.allSatisfy { SyntheticEventMarker.isMarked($0) })
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

/// 실행 중단 래치가 어댑터에서 실제로 게시를 끊는가.
///
/// 수집기 seam(`ActionExecutor(postEvent:)`)이 두 역할을 겸한다 — 무엇이 나갔는지 세면서
/// **동시에 중단 신호를 세운다**. 그래야 "게시가 시작된 뒤 중단됐다"는 실제 상황을 headless로
/// 재현할 수 있다 (실기기에서는 킬스위치·새 키가 그 자리를 맡는다).
struct KeyboardAdapterAbortTests {
    /// dispatch와 실행 사이에 다음 키가 들어온 경우 — 한 이벤트도 나가면 안 된다.
    @Test("이미 밀려난 실행은 아무것도 게시하지 않는다")
    func supersededRunPostsNothing() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute(Array(repeating: .move(.charLeft), count: 20), isCurrent: { false })

        #expect(posted.isEmpty)
    }

    /// 폭주의 핵심 계약 — 중단 신호가 서면 **잔여는 게시되지 않는다**. 첫 청크는 이미
    /// 나갔으므로 0건은 아니고, 전량(50 스트로크 = 100 이벤트)에는 한참 못 미쳐야 한다.
    @Test("중단되면 잔여 청크가 게시되지 않는다")
    func abortDiscardsRemainingChunks() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        // 한 이벤트라도 나가면 곧바로 밀려난 것으로 본다.
        adapter.execute(
            Array(repeating: .move(.charLeft), count: 50), isCurrent: { posted.isEmpty })

        #expect(!posted.isEmpty, "첫 청크는 지연 없이 나간다")
        #expect(posted.count < 100, "잔여가 폐기됐다")
    }

    /// 원자 그룹 제약 A — Visual `y`가 내는 `[.edit(.yank, .selection), .clearSelection]`
    /// 사이에서는 절대 끊지 않는다. 끊기면 **살아 있는 선택이 Normal로 넘어오고**, 그 상태의
    /// `x`(`Shift-→, Cmd-X`)가 선택을 통째로 잘라낸다.
    ///
    /// 청크 경계가 정확히 쌍 한가운데 오도록 모션으로 패딩한 뒤, 첫 이벤트에서 중단시킨다.
    @Test("yank(selection)과 clearSelection 사이는 중단되지 않는다")
    func selectionYankAndClearAreNeverSplit() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        let actions: [VimAction] =
            Array(repeating: .move(.charLeft), count: 7)
            + [.edit(.yank, .selection), .clearSelection]

        adapter.execute(actions, isCurrent: { posted.isEmpty })

        // 9 스트로크 전부 = 18 이벤트. 쌍이 갈렸다면 `Cmd-C`에서 끊겨 16건이 됐을 것이다.
        #expect(posted.count == 18)
        #expect(keyCodes(of: posted).suffix(2) == [Int64(kVK_LeftArrow), Int64(kVK_LeftArrow)])
        #expect(posted.suffix(2).allSatisfy { $0.flags.isDisjoint(with: .maskCommand) })
    }

    /// 위 테스트의 대조군 — 잠금이 없는 배치에서는 같은 지점에서 실제로 끊긴다.
    /// (없으면 "쌍이 안 갈렸다"가 "애초에 끊길 일이 없었다"와 구분되지 않는다.)
    @Test("잠금이 없는 액션 사이에서는 같은 지점에서 끊긴다")
    func unlockedBoundaryDoesSplit() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute(
            Array(repeating: .move(.charLeft), count: 9), isCurrent: { posted.isEmpty })

        #expect(posted.count < 18)
    }

    /// 원자 그룹 제약 B — `.paste`는 액션 **1개** 안에서 카운트가 곱해지므로 액션 내부가
    /// 갈라져야 끊긴다. 단, `접두 + 첫 Cmd-V`만은 한 몸이다: 접두만 나가고 끊기면 붙여넣기
    /// 없이 캐럿만 움직이는 조용한 오동작이 된다.
    @Test("paste는 내부에서 끊기되 접두와 첫 Cmd-V는 함께 나간다")
    func pasteSplitsInsideButKeepsPrefixWithFirstPaste() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([.paste(before: false, count: 20)], isCurrent: { posted.isEmpty })

        let codes = keyCodes(of: posted)
        #expect(codes.prefix(4) == [
            Int64(kVK_RightArrow), Int64(kVK_RightArrow),  // charwise 접두
            Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),  // 첫 붙여넣기 — 같은 청크
        ])
        let pastes = codes.filter { $0 == Int64(kVK_ANSI_V) }.count / 2
        #expect(pastes >= 1, "붙여넣기 없이 접두만 나가지 않는다")
        #expect(pastes < 20, "잔여 Cmd-V가 폐기됐다")
    }

    /// 중단은 게시 **여부**만 가르고 내용은 바꾸지 않는다 — 중단이 없으면 청크 분할 전과
    /// 똑같은 시퀀스가 나온다 (청크가 순서를 흔들거나 이벤트를 빠뜨리지 않는다).
    @Test("중단이 없으면 청크 분할과 무관하게 전량이 순서대로 나간다")
    func uninterruptedRunPostsEverythingInOrder() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute(Array(repeating: .move(.charLeft), count: 20))

        #expect(posted.count == 40)
        #expect(keyCodes(of: posted).allSatisfy { $0 == Int64(kVK_LeftArrow) })
        #expect(posted.allSatisfy { SyntheticEventMarker.isMarked($0) })
    }

    /// 재확인 위치의 계약 — **게시 직전**(페이싱 뒤)이다. 체크가 sleep보다 앞이면 무효화
    /// 뒤에도 청크 하나가 더 나가고, 실기기에서 그 화살표들이 새 사용자 키와 인터리브되는
    /// 1청크 폭 순서 역전으로 실증됐다. 진입 체크만 통과시키고 첫 flush의 재확인에서
    /// 밀려나게 하면, 옛 배치는 16건을 게시하고 지금 배치는 0건이어야 한다.
    @Test("게시 직전에 밀려나면 그 청크도 나가지 않는다")
    func chunkInvalidatedRightBeforePostIsDiscarded() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        nonisolated(unsafe) var checks = 0
        adapter.execute(
            Array(repeating: .move(.charLeft), count: 20),
            isCurrent: {
                checks += 1
                return checks == 1
            })

        #expect(posted.isEmpty)
    }
}

/// 요소 계열 게이트 — 리졸버가 보고한 계열에 따라 어댑터가 무엇을 걸러내는가.
///
/// 걸러내기는 시퀀스 다변화가 아니다: `.textField`는 `o`/`O`만, `.nonText`는 편집·Visual·명령
/// 위임만 막고 **모션과 스크롤은 그대로 게시한다**. 전부 막으면 엔진이 이미 키를 삼킨 뒤라
/// 스킵이 네이티브 동작으로의 복귀가 아니라 완전 무동작이 되어, Finder 리스트 이동과 Chrome
/// 페이지 스크롤이 죽는다 (`20260801_non-text-filter-keeps-motion-and-scroll.md`).
struct KeyboardAdapterElementFamilyTests {
    /// 비텍스트에서 살아남는 두 액션. 화살표는 텍스트가 아닌 곳에서도 무해하게 흘러간다.
    @Test(
        "비텍스트에서도 모션·스크롤은 게시된다",
        arguments: [VimAction.move(.lineDown), .scroll(.halfPage, forward: true)] as [VimAction])
    func nonTextStillPostsArrowOnlyActions(_ action: VimAction) {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([action], family: .nonText)

        #expect(!posted.isEmpty, "\(action)")
        #expect(posted.allSatisfy { $0.flags.isEmpty }, "화살표뿐이라 수정키가 실리지 않는다")
    }

    /// Finder에서 `p`는 파일을 붙여넣고 `u`는 파일 조작을 되돌린다 — 걸러내기의 동기다.
    /// `.edit`은 살아 있는 선택에 `Cmd-X`(= 파일 이동)를 내므로 같은 등급이다.
    @Test(
        "비텍스트에서 편집·Visual·명령 위임은 한 이벤트도 나가지 않는다",
        arguments: [
            VimAction.edit(.delete, .line(count: 1)),
            .edit(.yank, .selection),
            .beginSelection(linewise: false),
            .extendSelection(.wordForward),
            .clearSelection,
            .openLine(above: false),
            .paste(before: false, count: 1),
            .undo,
            .redo,
        ] as [VimAction])
    func nonTextFiltersEditingAndCommands(_ action: VimAction) {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([action], family: .nonText)

        #expect(posted.isEmpty, "\(action)")
    }

    /// TextField에서 걸러내는 것은 `o`/`O` 하나뿐이다 — `Return`이 대개 submit이라 되돌릴 수 없다.
    @Test(
        "TextField에서 o·O만 걸러진다",
        arguments: [VimAction.openLine(above: false), .openLine(above: true)] as [VimAction])
    func textFieldFiltersOpenLine(_ action: VimAction) {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([action], family: .textField)

        #expect(posted.isEmpty, "\(action)")
    }

    /// **의도된 수렴** — TextField 전용 편집 시퀀스를 만들지 않기로 한 결정을 어댑터 층에서도
    /// 고정한다 (`20260801_textfield-edit-sequences-scrapped.md`). 매퍼 층 고정은
    /// `EditKeyMapperTests`에 있다.
    @Test(
        "TextField의 나머지 어휘는 TextArea와 같은 이벤트를 낸다",
        arguments: [
            VimAction.edit(.delete, .line(count: 1)),
            .edit(.change, .motion(.wordForward, count: 1)),
            .beginSelection(linewise: true),
            .paste(before: false, count: 1),
            .undo,
        ] as [VimAction])
    func textFieldMatchesTextAreaElsewhere(_ action: VimAction) {
        nonisolated(unsafe) var fromTextArea: [CGEvent] = []
        nonisolated(unsafe) var fromTextField: [CGEvent] = []
        makeAdapter { fromTextArea.append($0) }.execute([action], family: .textArea)
        makeAdapter { fromTextField.append($0) }.execute([action], family: .textField)

        #expect(!fromTextArea.isEmpty, "\(action)")
        #expect(keyCodes(of: fromTextField) == keyCodes(of: fromTextArea), "\(action)")
    }

    /// 앱 전환 직후의 **미확정 창**은 `.nonText`와 같은 편이다 — 요소를 아직 모르는 동안
    /// 위험 어휘를 내보내면 실측된 방향으로 틀린다(TextEdit→Finder 직후의 `u`가 `Cmd-Z`로
    /// Finder에 도달했다, `20260801_unresolved-window-after-app-switch.md`).
    @Test(
        "미확정 창에서 편집·Visual·명령 위임은 한 이벤트도 나가지 않는다",
        arguments: [
            VimAction.edit(.delete, .line(count: 1)),
            .edit(.yank, .selection),
            .beginSelection(linewise: false),
            .extendSelection(.wordForward),
            .clearSelection,
            .openLine(above: false),
            .paste(before: false, count: 1),
            .undo,
            .redo,
        ] as [VimAction])
    func unresolvedFiltersEditingAndCommands(_ action: VimAction) {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute([action], family: .unresolved)

        #expect(posted.isEmpty, "\(action)")
    }

    /// 미확정 창이 **모션·스크롤까지 막지는 않는다**. 창은 앱 전환 직후 ~20ms마다 열리므로,
    /// 여기서 화살표를 막으면 앱을 옮길 때마다 첫 이동이 사라져 체감 고장이 된다.
    @Test(
        "미확정 창에서도 모션·스크롤은 게시된다",
        arguments: [VimAction.move(.lineDown), .scroll(.halfPage, forward: true)] as [VimAction])
    func unresolvedStillPostsArrowOnlyActions(_ action: VimAction) {
        nonisolated(unsafe) var fromUnresolved: [CGEvent] = []
        nonisolated(unsafe) var fromTextArea: [CGEvent] = []
        makeAdapter { fromUnresolved.append($0) }.execute([action], family: .unresolved)
        makeAdapter { fromTextArea.append($0) }.execute([action], family: .textArea)

        #expect(!fromUnresolved.isEmpty, "\(action)")
        #expect(keyCodes(of: fromUnresolved) == keyCodes(of: fromTextArea), "\(action)")
    }

    /// **게이트가 부수효과보다 앞이라는 계약.** `.edit`의 `recordLinewiseEdit()`은 매퍼 호출
    /// 전에 불리므로, 게이트가 뒤에 있으면 게시하지도 않은 편집이 기억돼 다음 `p`의 wise가
    /// 오염된다. `recordLinewiseEdit()`이 주입된 `changeCount`를 읽는다는 사실로 관측한다.
    @Test("비텍스트 편집은 붙여넣기 단위 기억을 남기지 않는다")
    func nonTextEditDoesNotRecordPasteWise() {
        nonisolated(unsafe) var changeCountReads = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(
            changeCount: {
                changeCountReads += 1
                return 0
            }, collecting: { posted.append($0) })

        adapter.execute([.edit(.delete, .line(count: 1))], family: .nonText)
        #expect(changeCountReads == 0, "게이트가 기억보다 앞이다")

        // 대조군: 같은 액션이 TextArea에서는 실제로 기억을 남긴다 (관측 수단이 유효하다는 확인).
        adapter.execute([.edit(.delete, .line(count: 1))], family: .textArea)
        #expect(changeCountReads == 1)
    }
}

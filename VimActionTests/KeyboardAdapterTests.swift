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

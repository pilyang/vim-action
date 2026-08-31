//
//  KeyboardAdapterTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimActionConfig
import VimEngine
@testable import VimAction

/// 게시 함수를 가로챈 어댑터 — 실제 키를 테스트 머신에 주입하지 않는다.
/// CGEvent **생성**은 TCC 권한이 필요 없어 headless로 돈다.
///
/// 클립보드도 **항상 주입한다** — 프로덕션 기본값으로 흘러가면 `.paste` 테스트가 개발자의
/// 실제 클립보드를 읽어 비결정적이 된다(`defaults` 주입과 같은 이유).
/// `changeCount`도 주입한다 — 기본값은 **변하지 않는** 카운터라 "우리 편집 기억"이 발동하지
/// 않고 클립보드 휴리스틱만 쓰인다. 기억 경로는 그것을 검증하는 테스트가 직접 올린다.
/// 캐럿 주변 리더도 같은 이유로 항상 주입한다 — 프로덕션 기본값은 실제 AX를 읽는다.
private func makeAdapter(
    clipboard wise: PasteWise? = .charwise,
    changeCount: @escaping @Sendable () -> Int = { 0 },
    qwertyCommandKeys: @escaping @Sendable () -> Bool = { true },
    // 기본값이 **빈 표**인 것이 요점이다 — 실값(`KeyTranslator.commandKeyCodes`)을 읽으면
    // 테스트가 개발자 머신의 레이아웃에 갈리고, 빈 표는 "역조회 전부 실패"라 비-QWERTY
    // 통째 보류 테스트가 치환 도입 전과 같은 의미로 성립한다.
    commandKeyCodes: @escaping @Sendable () -> [Character: CGKeyCode] = { [:] },
    reader: FocusedTextReader = FocusedTextReader { _ in nil },
    visualAnchor: VisualAnchorTracker = VisualAnchorTracker(),
    viewport: ViewportReader = ViewportReader { _ in nil },
    collecting posted: @escaping @Sendable (CGEvent) -> Void
) -> KeyboardAdapter {
    KeyboardAdapter(
        executor: ActionExecutor(postEvent: posted),
        pasteWise: PasteWiseResolver(readClipboard: { wise }, readChangeCount: changeCount),
        hasQwertyCommandKeys: qwertyCommandKeys, commandKeyCodes: commandKeyCodes,
        reader: reader, visualAnchor: visualAnchor, viewportReader: viewport)
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

    /// charwise 편집도 기억한다 — 줄 끝 `x`가 개행을 잘라내면 내용이 개행으로 끝나
    /// 휴리스틱은 linewise로 오판하고, `p`가 엉뚱하게 줄 단위로 붙여넣는다.
    @Test("직전 dw 뒤의 p는 클립보드가 linewise로 보여도 charwise로 붙여넣는다")
    func charwiseEditIsRememberedAsCharwise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        // 클립보드는 linewise로 보인다(잘라낸 내용이 개행으로 끝난 상황).
        let adapter = makeAdapter(clipboard: .linewise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.edit(.delete, .motion(.wordForward, count: 1))])
        posted = []
        count += 1  // 대상 앱이 잘라내기를 처리해 클립보드를 썼다.
        adapter.execute([.paste(before: false, count: 1)])

        // charwise `p` = `→` 뒤에 `Cmd-V`.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// `cc`의 내용은 실제로 charwise다(줄 유지·개행 없음) — 휴리스틱에 맡기지 않고 그
    /// 사실을 직접 기억한다. 위의 "linewise로 기억하지 않는다"에서 한 발 더 나간 것이다.
    @Test("직전 cc 뒤의 p는 클립보드가 linewise로 보여도 charwise로 붙여넣는다")
    func changeIsRememberedAsCharwise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .linewise, changeCount: { count }) {
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

    /// Visual linewise 세션의 `d`는 줄 단위 내용을 남긴다 — Notion은 끝 개행을 안 붙여
    /// 휴리스틱이 charwise로 오판한다 (`ddp`와 같은 오판 클래스).
    @Test("V 세션의 d 뒤 p는 클립보드가 charwise로 보여도 linewise로 붙여넣는다")
    func linewiseSelectionEditIsRememberedAsLinewise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .charwise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.beginSelection(linewise: true)])
        adapter.execute([.edit(.delete, .selection)])
        posted = []
        count += 1
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

    /// Visual charwise 세션 — 선택이 개행을 물고 끝나면 휴리스틱이 linewise로 오판한다.
    @Test("v 세션의 y 뒤 p는 클립보드가 linewise로 보여도 charwise로 붙여넣는다")
    func charwiseSelectionEditIsRememberedAsCharwise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .linewise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.beginSelection(linewise: false)])
        adapter.execute([.edit(.yank, .selection), .clearSelection])
        posted = []
        count += 1
        adapter.execute([.paste(before: false, count: 1)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// 세션 wise는 게시가 확정된 전환을 따라간다 — `v`→`V` 폴백 시퀀스는 게시되므로
    /// 이후 `.selection` 편집의 내용은 줄 단위다.
    @Test("v→V 전환 뒤의 selection 편집은 linewise로 기억된다")
    func postedWiseSwitchUpdatesRememberedWise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .charwise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.beginSelection(linewise: false)])
        adapter.execute([.switchSelectionWise(linewise: true)])
        adapter.execute([.edit(.delete, .selection)])
        posted = []
        count += 1
        adapter.execute([.paste(before: false, count: 1)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// `V`→`v` 폴백은 매퍼 `nil`(정직한 스킵)이라 화면 선택이 그대로 줄 단위다 —
    /// 게시되지 않은 전환은 wise도 바꾸지 않아야 기억이 내용과 일치한다.
    @Test("스킵된 V→v 전환은 기억되는 wise를 바꾸지 않는다")
    func skippedWiseSwitchKeepsRememberedWise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .charwise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.beginSelection(linewise: true)])
        adapter.execute([.switchSelectionWise(linewise: false)])  // 무상태 폴백 = 스킵
        adapter.execute([.edit(.delete, .selection)])
        posted = []
        count += 1
        adapter.execute([.paste(before: false, count: 1)])

        // 화면 선택은 여전히 줄 단위였으므로 linewise가 내용 진실이다.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// 걸러진 begin(`.nonText`·`.unresolved`)은 note를 못 남기지만 **옛 세션의 wise만은
    /// 반드시 잊어야 한다** — 남으면 뒤의 `.selection` 편집이 이전 세션의 wise로 기록돼,
    /// 휴리스틱이었다면 맞았을 자리를 틀리게 만든다 (앱 전환 콜드 창의 `v` 시나리오).
    @Test("걸러진 begin은 이전 세션 wise를 잊는다 — selection 편집은 휴리스틱으로 남는다")
    func filteredBeginForgetsPreviousSessionWise() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .charwise, changeCount: { count }) {
            posted.append($0)
        }

        // 이전 세션: V 세션의 d가 linewise를 note한다.
        adapter.execute([.beginSelection(linewise: true)])
        adapter.execute([.edit(.delete, .selection)])
        count += 1
        // 새 세션: 앱 전환 콜드 창(.unresolved)의 v — 게이트에 걸러져 note가 없다.
        adapter.execute([.beginSelection(linewise: false)], family: .unresolved)
        // 화면의 charwise 선택을 d가 자른다 — 낡은 linewise가 기록되면 안 되는 자리다.
        adapter.execute([.edit(.delete, .selection)])
        posted = []
        count += 1
        adapter.execute([.paste(before: false, count: 1)])

        // 기억이 없으므로 휴리스틱(끝 개행 없음 = charwise)을 따른다.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// 세션 wise를 모르는 `.selection` 편집은 기억을 남기지 않는다 — begin 없이 온 편집은
    /// 휴리스틱으로 남는 것이 보수 방향이다 (기록할 근거가 없다).
    @Test("begin 없이 온 selection 편집은 기억을 남기지 않는다")
    func selectionEditWithoutSessionWiseLeavesNoMemory() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var count = 7
        let adapter = makeAdapter(clipboard: .linewise, changeCount: { count }) {
            posted.append($0)
        }

        adapter.execute([.edit(.delete, .selection)])
        posted = []
        count += 1
        adapter.execute([.paste(before: false, count: 1)])

        // 기억이 없으므로 휴리스틱(클립보드 끝 개행 = linewise)을 따른다.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_ANSI_V), Int64(kVK_ANSI_V),
            ])
    }

    /// 줄 끝의 Vim 커서는 마지막 글자 **위**라 "커서 뒤"가 곧 지금 캐럿 자리다 — `→`를
    /// 내면 다음 줄 시작으로 포화해 붙여넣기가 줄을 넘는다 (도그푸딩 실측: 줄 끝 `xp`가
    /// 글자를 다음 줄로 보냈다). 편집 정확화(엣지 1)와 같은 줄 끝 커서 모델이다.
    @Test("줄 끝이 증명된 charwise p는 → 접두 없이 Cmd-V만 낸다")
    func charwisePasteAtProvenLineEndDropsPrefix() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        // 문서 "ab\ncd", 캐럿 2 = 첫 줄 끝 (b 뒤, 개행 앞).
        let adapter = makeAdapter(
            clipboard: .charwise,
            reader: FocusedTextReader { _ in focusedText("ab\ncd", caret: 2) }
        ) { posted.append($0) }

        adapter.execute([.paste(before: false, count: 1)], processID: 1)

        #expect(keyCodes(of: posted) == [Int64(kVK_ANSI_V), Int64(kVK_ANSI_V)])
    }

    /// 줄 중간에서는 증명이 서도 현행 그대로다 — 정확화는 줄 끝 분기 하나뿐이다.
    @Test("줄 중간의 charwise p는 → 접두를 유지한다")
    func charwisePasteMidLineKeepsPrefix() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(
            clipboard: .charwise,
            reader: FocusedTextReader { _ in focusedText("ab\ncd", caret: 1) }
        ) { posted.append($0) }

        adapter.execute([.paste(before: false, count: 1)], processID: 1)

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

/// 편집 그룹 페이싱 — **단일 청크(≤8타) 편집 그룹만** 스트로크 사이 간격을 두고 게시한다.
///
/// 오퍼레이터(`Cmd-X`/`Cmd-C`)의 의미가 직전 선택 스트로크의 착지에 의존하는데, Notion은
/// 0간격 버스트에서 선택이 착지하기 전에 오퍼레이터를 처리해 "선택 없는 `Cmd-C` = 블록
/// 전체 복사"가 됐다 (`y$` 도그푸딩 실측 — `20260831_edit-group-stroke-pacing.md`).
struct KeyboardAdapterEditPacingTests {
    /// 경계는 청크 폭(8) 재사용이다 — 카운트 버스트(`500x` = 501타 단일 그룹)는 "카운트
    /// 버스트 타이밍 현행 유지" 제약대로 페이싱 밖에 남는다.
    @Test(
        "편집 그룹 페이싱 경계는 청크 폭이다",
        arguments: [(2, true), (3, true), (8, true), (9, false), (501, false)])
    func editGroupPacedBoundary(_ strokeCount: Int, _ paced: Bool) {
        #expect(KeyboardAdapter.editGroupPaced(strokeCount: strokeCount) == paced)
    }

    /// 배선 검증 — 판정만 참이고 게시가 일반 경로면 죽은 코드다. 페이싱의 스트로크 간
    /// sleep은 **보장 하한**이라 경과 시간의 하한 단언은 흔들리지 않는다 (느린 머신은 더
    /// 오래 걸릴 뿐이다). `y$` = `[Shift-Cmd-→, Cmd-C, ←]` 3타 → 간격 2회 ≥ 10ms.
    @Test("y$ 편집 그룹은 페이싱 게시된다")
    func lineEndYankPostsPaced() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        let elapsed = ContinuousClock().measure {
            adapter.execute([.edit(.yank, .motion(.lineEnd, count: 1))])
        }

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_ANSI_C), Int64(kVK_ANSI_C),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
            ])
        #expect(elapsed >= .milliseconds(9))
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

    /// **게이트가 부수효과보다 앞이라는 계약.** 게이트가 뒤에 있으면 게시하지도 않은
    /// 편집이 `recordEdit`으로 기억돼 다음 `p`의 wise가 오염된다.
    /// `recordEdit`이 주입된 `changeCount`를 읽는다는 사실로 관측한다.
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

/// force-text 계열 — `keyboard_family: force_text` 프로파일은 keyboard 실행의 실효 계열을
/// `.textArea`로 치환한다(요소 감지 우회 — "이 앱의 role 보고를 믿지 말라"는 사용자 지시,
/// `20260813_force-text-keyboard-family-substitution.md`). 걸러내기 게이트·매퍼 호출·
/// 하이브리드 위임분이 같은 치환값을 본다는 계약의 keyboard 단독 축이다 — AX 쪽
/// (`usesAXWrite`는 원본 계열)은 `KeyboardAdapterForceTextAXTests`가 고정한다.
struct KeyboardAdapterForceTextTests {
    private let forceText = ResolvedProfile(AppProfile(keyboardFamily: .forceText))

    /// 걸러내기 게이트가 치환값을 본다 — 비텍스트·미확정 보고에서도 편집이 TextArea
    /// 시퀀스 그대로 나간다 (`.unresolved` 창도 사용자 지시가 뚫는다 — 문언 그대로).
    @Test(
        "force-text: 비텍스트·미확정 계열에서도 편집이 게시된다",
        arguments: [ElementFamily.nonText, .unresolved])
    func forceTextPostsEditsOnNonText(_ family: ElementFamily) {
        nonisolated(unsafe) var fromForceText: [CGEvent] = []
        nonisolated(unsafe) var fromTextArea: [CGEvent] = []
        makeAdapter { fromForceText.append($0) }
            .execute([.edit(.delete, .line(count: 1))], family: family, profile: forceText)
        makeAdapter { fromTextArea.append($0) }
            .execute([.edit(.delete, .line(count: 1))], family: .textArea)

        #expect(!fromForceText.isEmpty)
        #expect(keyCodes(of: fromForceText) == keyCodes(of: fromTextArea), "항상 TextArea 시퀀스")
    }

    /// `.textField`의 openLine 걸러내기(`Return` = submit)도 치환이 우회한다 — force-text는
    /// 그 role 보고 자체를 믿지 않는다.
    @Test("force-text: TextField 보고에서도 o가 게시된다")
    func forceTextPostsOpenLineOnTextField() {
        nonisolated(unsafe) var fromForceText: [CGEvent] = []
        nonisolated(unsafe) var fromTextArea: [CGEvent] = []
        makeAdapter { fromForceText.append($0) }
            .execute([.openLine(above: false)], family: .textField, profile: forceText)
        makeAdapter { fromTextArea.append($0) }
            .execute([.openLine(above: false)], family: .textArea)

        #expect(!fromForceText.isEmpty)
        #expect(keyCodes(of: fromForceText) == keyCodes(of: fromTextArea))
    }

    /// 명시 `key_mapping`(기본값과 동일)은 현행 그대로다 — 치환은 `force_text`에만 발동한다.
    @Test("기본 key_mapping은 비텍스트 걸러내기를 유지한다")
    func keyMappingKeepsFilterGate() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let profile = ResolvedProfile(AppProfile(keyboardFamily: .keyMapping))
        makeAdapter { posted.append($0) }
            .execute([.edit(.delete, .line(count: 1))], family: .nonText, profile: profile)

        #expect(posted.isEmpty)
    }
}

/// 비-QWERTY 레이아웃 게이트 — ANSI 문자 키코드를 합성하는 액션(`Cmd-Z/X/C/V`)은 보류하고,
/// 화살표·Return만 쓰는 액션은 통과한다 (`20260801` 레이아웃 가드 결정).
struct KeyboardAdapterLayoutGateTests {
    @Test("비-QWERTY: 편집·paste·undo·redo는 게시되지 않는다")
    func nonQwertyBlocksLetterCommandActions() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(qwertyCommandKeys: { false }, collecting: { posted.append($0) })

        adapter.execute([
            .edit(.delete, .line(count: 1)),
            .edit(.yank, .selection),
            .paste(before: false, count: 1),
            .undo,
            .redo,
        ])

        #expect(posted.isEmpty)
    }

    @Test("비-QWERTY: 모션·스크롤·openLine·선택은 그대로 게시된다")
    func nonQwertyKeepsLayoutIndependentActions() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(qwertyCommandKeys: { false }, collecting: { posted.append($0) })

        adapter.execute([
            .move(.lineDown),
            .scroll(.halfPage, forward: true),
            .openLine(above: false),
            .beginSelection(linewise: false),
            .clearSelection,
        ])

        #expect(!posted.isEmpty)
        // 화살표·Return·Cmd-화살표만 — ANSI 문자 키코드는 하나도 나가지 않는다.
        let letterCodes: Set<Int64> = [
            Int64(kVK_ANSI_Z), Int64(kVK_ANSI_X), Int64(kVK_ANSI_C), Int64(kVK_ANSI_V),
        ]
        #expect(keyCodes(of: posted).allSatisfy { !letterCodes.contains($0) })
    }

    /// 게이트는 부수효과보다 앞이다 — 걸러내기 게이트의 `nonTextEditDoesNotRecordPasteWise`와
    /// 같은 계약을 레이아웃 축에서도 고정한다.
    @Test("비-QWERTY 편집은 붙여넣기 단위 기억을 남기지 않는다")
    func nonQwertyEditDoesNotRecordPasteWise() {
        nonisolated(unsafe) var changeCountReads = 0
        let adapter = makeAdapter(
            changeCount: {
                changeCountReads += 1
                return 0
            },
            qwertyCommandKeys: { false },
            collecting: { _ in })

        adapter.execute([.edit(.delete, .line(count: 1))])

        #expect(changeCountReads == 0, "게이트가 기억보다 앞이다")
    }

    @Test("QWERTY 복귀 시 같은 액션이 다시 게시된다 (액션마다 재판정)")
    func layoutIsReconsultedPerExecution() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var qwerty = false
        let adapter = makeAdapter(
            qwertyCommandKeys: { qwerty }, collecting: { posted.append($0) })

        adapter.execute([.undo])
        #expect(posted.isEmpty)

        qwerty = true
        adapter.execute([.undo])
        #expect(keyCodes(of: posted) == [Int64(kVK_ANSI_Z), Int64(kVK_ANSI_Z)])
    }

    // MARK: 역조회 치환 (`20260806_non-qwerty-command-key-reverse-lookup.md`)

    /// AZERTY 실측 표 — z만 W 자리(13)로 옮겨가고 x/c/v는 QWERTY와 같다.
    private static let azertyCodes: [Character: CGKeyCode] = [
        "z": 13, "x": 7, "c": 8, "v": 9,
    ]

    /// Dvorak 실측 표 — 4키 전부 재배열이다.
    private static let dvorakCodes: [Character: CGKeyCode] = [
        "z": 44, "x": 11, "c": 34, "v": 47,
    ]

    @Test("비-QWERTY + 역조회 성공: undo·redo가 치환된 키코드로 게시된다 (플래그 보존)")
    func reverseLookupRewritesUndoRedo() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(
            qwertyCommandKeys: { false }, commandKeyCodes: { Self.azertyCodes },
            collecting: { posted.append($0) })

        adapter.execute([.undo])
        #expect(keyCodes(of: posted) == [13, 13])
        #expect(posted.allSatisfy { $0.flags.contains(.maskCommand) })
        #expect(posted.allSatisfy { !$0.flags.contains(.maskShift) })

        // redo는 같은 z 키코드에 Shift가 얹힌다 — shifted 역조회가 따로 없는 이유다.
        posted.removeAll()
        adapter.execute([.redo])
        #expect(keyCodes(of: posted) == [13, 13])
        #expect(posted.allSatisfy { $0.flags.contains(.maskCommand) })
        #expect(posted.allSatisfy { $0.flags.contains(.maskShift) })
    }

    @Test("비-QWERTY + 역조회 성공: 편집·paste의 명령 키만 치환되고 화살표는 그대로다")
    func reverseLookupRewritesEditAndPasteCommandKeysOnly() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(
            qwertyCommandKeys: { false }, commandKeyCodes: { Self.dvorakCodes },
            collecting: { posted.append($0) })

        // delete = `Shift-→, Cmd-X` — 화살표(124)는 손대지 않고 X(7)만 11로 바뀐다.
        adapter.execute([.edit(.delete, .motion(.charRight, count: 1))])
        #expect(keyCodes(of: posted) == [Int64(kVK_RightArrow), Int64(kVK_RightArrow), 11, 11])

        // yank(.selection) = `Cmd-C` 1타 — C(8)가 34로 바뀐다.
        posted.removeAll()
        adapter.execute([.edit(.yank, .selection)])
        #expect(keyCodes(of: posted) == [34, 34])

        // charwise p = `→` 접두 + `Cmd-V` — V(9)가 47로 바뀐다.
        posted.removeAll()
        adapter.execute([.paste(before: false, count: 1)])
        #expect(keyCodes(of: posted) == [Int64(kVK_RightArrow), Int64(kVK_RightArrow), 47, 47])
    }

    @Test("부분 역조회: 못 찾은 문자가 필요한 액션만 보류된다 (액션별 판정)")
    func partialLookupBlocksOnlyActionsNeedingMissingCharacter() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        // z만 찾은 표 — undo/redo는 살고, x가 필요한 delete는 보류된다.
        let adapter = makeAdapter(
            qwertyCommandKeys: { false }, commandKeyCodes: { ["z": 13] },
            collecting: { posted.append($0) })

        adapter.execute([.edit(.delete, .line(count: 1))])
        #expect(posted.isEmpty)

        adapter.execute([.undo])
        #expect(keyCodes(of: posted) == [13, 13])
    }

    @Test("부분 역조회로 보류된 편집은 붙여넣기 단위 기억을 남기지 않는다")
    func partialLookupBlockedEditDoesNotRecordPasteWise() {
        nonisolated(unsafe) var changeCountReads = 0
        let adapter = makeAdapter(
            changeCount: {
                changeCountReads += 1
                return 0
            },
            qwertyCommandKeys: { false }, commandKeyCodes: { ["z": 13] },
            collecting: { _ in })

        adapter.execute([.edit(.delete, .line(count: 1))])

        #expect(changeCountReads == 0, "게이트가 기억보다 앞이다")
    }

    @Test("QWERTY에서는 치환이 통째로 생략된다 (표가 달라도 현행 바이트 동일)")
    func qwertySkipsRewriteEntirely() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        // 표가 Dvorak 값이어도 QWERTY면 읽히지 않는다 — 생략이 곧 현행 바이트 동일의 증명.
        let adapter = makeAdapter(
            qwertyCommandKeys: { true }, commandKeyCodes: { Self.dvorakCodes },
            collecting: { posted.append($0) })

        adapter.execute([.undo, .edit(.yank, .selection)])

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_ANSI_Z), Int64(kVK_ANSI_Z), Int64(kVK_ANSI_C), Int64(kVK_ANSI_C),
            ])
    }
}

/// 게시 직전 치환의 안전 전제 고정 — 논리 ANSI 명령 키코드(6/7/8/9 = Z/X/C/V)는 문자 명령
/// 키를 합성하는 액션(`.edit`·`.paste`·`.undo`·`.redo`)의 명령 스트로크에만 등장한다.
/// 여기서는 그 밖의 전 매퍼 출력(모션 전 어휘·Visual 세션·openLine·스크롤)에 이 키코드가
/// 없음을 스윕한다 — 깨지면 치환이 명령 키가 아닌 스트로크를 바꾸게 되므로, 새 어휘가
/// 문자 키를 합성하려면 이 테스트와 게이트(`requiredCommandCharacters`)를 함께 확장해야
/// 한다. 프로파일 스트로크 어휘(`ConfigKey`)는 타입 차원에서 문자 키가 없다.
struct LogicalCommandKeyCodeExclusivityTests {
    private static let commandKeyCodes: Set<CGKeyCode> = [
        CGKeyCode(kVK_ANSI_Z), CGKeyCode(kVK_ANSI_X),
        CGKeyCode(kVK_ANSI_C), CGKeyCode(kVK_ANSI_V),
    ]

    @Test("모션 매퍼 전 어휘에 명령 키코드가 없다")
    func motionSequencesCarryNoCommandKeyCodes() {
        for motion in Motion.allCases {
            let strokes = MotionKeyMapper.keyStrokes(for: motion) ?? []
            #expect(
                strokes.allSatisfy { !Self.commandKeyCodes.contains($0.keyCode) },
                "\(motion)")
        }
    }

    @Test("Visual 세션 매퍼 전 어휘에 명령 키코드가 없다")
    func visualSequencesCarryNoCommandKeyCodes() {
        var actions: [VimAction] = [
            .beginSelection(linewise: false), .beginSelection(linewise: true),
            .switchSelectionWise(linewise: false), .switchSelectionWise(linewise: true),
            .clearSelection,
        ]
        actions += Motion.allCases.map { .extendSelection($0) }
        for action in actions {
            let strokes = VisualKeyMapper.keyStrokes(for: action, family: .textArea) ?? []
            #expect(
                strokes.allSatisfy { !Self.commandKeyCodes.contains($0.keyCode) },
                "\(action)")
        }
    }

    @Test("openLine·스크롤 시퀀스에 명령 키코드가 없다")
    func delegationSequencesCarryNoCommandKeyCodes() {
        let actions: [VimAction] = [
            .openLine(above: false), .openLine(above: true),
            .scroll(.halfPage, forward: true), .scroll(.halfPage, forward: false),
            .scroll(.fullPage, forward: true), .scroll(.fullPage, forward: false),
        ]
        for action in actions {
            let strokes = CommandKeyMapper.keyStrokes(for: action, family: .textArea) ?? []
            #expect(
                strokes.allSatisfy { !Self.commandKeyCodes.contains($0.keyCode) },
                "\(action)")
        }
    }
}

/// 캐럿 주변 리더 seam — 소비자는 `mapping`의 `.edit` 분기(**범위 술어** — 표에 적힌 범위만
/// 묻는다)·Visual 세션 분기(**세션 술어** — 수립·자가 검증이 묻는다)·`.paste` 분기(charwise
/// `p`의 줄 끝 증명) 세 곳이다. 스크롤은 여기 없다 — 별개 프리미티브(`ViewportReader`,
/// `KeyboardAdapterViewportTests`)를 읽는다.
/// 여기서 고정하는 것은 세 가지다: 누가 읽는가(그리고 몇 번), 읽기가 실패해도
/// 실행은 하는가(폴백 계약), 그리고 읽기가 0폭 포화를 증명하면 게시를 멈추는가.
///
/// 읽기 횟수를 고정하는 이유는 비용이다 — Notion에서 읽기 1회가 7ms이고 액션 수만큼 곱해진다.
/// 정확화 이득 없는 자리에서 조용히 AX를 부르기 시작하면 그만큼이 그대로 지연이 된다.
struct KeyboardAdapterFocusedTextTests {
    /// 대표 어휘를 훑는다 — 걸러내기·레이아웃 게이트·부수효과 경로가 서로 다른 액션들이라
    /// 어느 하나에 소비가 붙어도 걸린다.
    ///
    /// **`.motion` 범위 편집이 반드시 있어야 한다** — 그것 없이는 아래 폴백 계약 테스트가
    /// 새 소비 경로를 하나도 지나지 않아 공허하게 통과한다.
    private static let vocabulary: [VimAction] = [
        .move(.wordForward),
        .edit(.delete, .motion(.charRight, count: 1)),
        .edit(.delete, .line(count: 1)),
        .edit(.delete, .linewiseMotion(.lineUp, count: 1)),
        .edit(.delete, .linewiseMotion(.documentStart, count: 1)),
        .edit(.delete, .textObject(.word(.inner))),
        .beginSelection(linewise: false),
        .edit(.yank, .selection),
        .clearSelection,
        .openLine(above: false),
        .paste(before: false, count: 1),
        .undo,
        .scroll(.halfPage, forward: true),
    ]

    /// 문서 `"ab\ncd"`의 끝(오프셋 5)에 캐럿이 있는 읽기 — 줄 끝이므로 `x`가 개행을 집는 자리다.
    private static let atDocumentEnd = FocusedText(
        selection: NSRange(location: 5, length: 0), characterCount: 5,
        window: "ab\ncd", windowRange: NSRange(location: 0, length: 5))

    /// 같은 문서의 첫 줄(오프셋 1) — `dk`가 위로 갈 줄이 없는 자리다.
    private static let onFirstLine = FocusedText(
        selection: NSRange(location: 1, length: 0), characterCount: 5,
        window: "ab\ncd", windowRange: NSRange(location: 0, length: 5))

    /// 정확화 없는 `x`의 무상태 시퀀스 — `Shift-→` 뒤 `Cmd-X` (스트로크당 keyDown+keyUp 2건).
    private static let charDeleteKeyCodes = [
        Int64(kVK_RightArrow), Int64(kVK_RightArrow), Int64(kVK_ANSI_X), Int64(kVK_ANSI_X),
    ]

    @Test("표에 적힌 범위와 Visual 세션만 읽는다 — 나머지 어휘는 왕복 0건")
    func onlyTabulatedRangeEditsConsultTheReader() {
        nonisolated(unsafe) var reads = 0
        let reader = FocusedTextReader { _ in
            reads += 1
            return nil
        }

        makeAdapter(reader: reader, collecting: { _ in }).execute(Self.vocabulary, processID: 42)

        #expect(
            reads == 6,
            """
            편집은 `x`·`dk`·`dgg`·`diw` 넷(범위 술어), Visual은 `v` 진입 하나(세션 술어 — \
            수립 읽기는 실패해도 왕복이다), 붙여넣기는 charwise `p` 하나(줄 끝 증명)다. \
            `dd`·`dj`는 묻지 않고, `clearSelection`은 폐기만이라 읽지 않으며, 상태 없는 \
            세션이라 확장도 있었다면 읽지 않았을 것이다. 스크롤은 이 리더가 아니라 \
            뷰포트 리더를 읽는다 — 여기 6에 들어오지 않는다.
            """)
    }

    /// 스냅샷은 **액션마다 새로** 만든다 — 같은 버스트의 앞 액션이 캐럿을 옮기므로 앞 액션의
    /// 읽기를 물려받으면 낡은 오프셋으로 판정한다. (한 액션 **안**의 memo는
    /// `FocusedTextSnapshotTests`가 고정한다.)
    @Test("읽기는 액션마다 새로 한다 — 앞 액션의 값을 물려받지 않는다")
    func theSnapshotIsRebuiltPerAction() {
        nonisolated(unsafe) var reads = 0
        let reader = FocusedTextReader { _ in
            reads += 1
            return nil
        }

        makeAdapter(reader: reader, collecting: { _ in })
            .execute(
                [
                    .edit(.delete, .motion(.charRight, count: 1)),
                    .edit(.delete, .motion(.charRight, count: 1)),
                ], processID: 42)

        #expect(reads == 2)
    }

    /// 읽을 앱이 없으면(pid `nil`) 리더는 아예 불리지 않는다 — 실패와 같은 폴백으로 간다.
    @Test("pid가 없으면 리더를 부르지 않는다")
    func missingProcessIDSkipsTheRead() {
        nonisolated(unsafe) var reads = 0
        let reader = FocusedTextReader { _ in
            reads += 1
            return nil
        }

        makeAdapter(reader: reader, collecting: { _ in }).execute(Self.vocabulary)

        #expect(reads == 0)
    }

    /// **무효 정확화의 본체** — Vim에서 no-op인 조합을 읽기가 증명하면 액션 통째로 스킵한다.
    /// 첫 줄 `dk`가 그 자리다: 현행 시퀀스는 `↑`가 문서 시작에서 포화한 채 아래로 확장해
    /// **아래 줄을 지운다**(수용 엣지 2 — 가장 버그처럼 보이던 것).
    @Test("첫 줄 `dk`는 게시하지 않는다 — Vim처럼 무효")
    func suppressesTheEditWhenTheReadProvesItInvalid() {
        nonisolated(unsafe) var suppressed: [CGEvent] = []
        nonisolated(unsafe) var changeCountReads = 0
        makeAdapter(
            changeCount: {
                changeCountReads += 1
                return 0
            },
            reader: FocusedTextReader { _ in Self.onFirstLine },
            collecting: { suppressed.append($0) }
        ).execute([.edit(.delete, .linewiseMotion(.lineUp, count: 1))], processID: 42)

        #expect(suppressed.isEmpty, "선택 스트로크도 나가지 않는다 — 액션 통째로 스킵이다")
        // 게시하지 않은 줄 단위 편집은 붙여넣기 단위 기억도 남기지 않는다 — 남기면 다음 `p`가
        // linewise로 오판된다 (프로파일 disable 스킵과 같은 규칙).
        #expect(changeCountReads == 0)

        // 같은 액션이라도 읽기가 없으면 오늘의 무상태 시퀀스 그대로다 — 그리고 기억은 남는다.
        nonisolated(unsafe) var fallback: [CGEvent] = []
        makeAdapter(
            changeCount: {
                changeCountReads += 1
                return 0
            }, reader: FocusedTextReader { _ in nil }, collecting: { fallback.append($0) }
        ).execute([.edit(.delete, .linewiseMotion(.lineUp, count: 1))], processID: 42)

        #expect(!fallback.isEmpty)
        #expect(changeCountReads == 1)
    }

    /// **재조립의 본체** — 줄 끝 `x`는 개행을 집는 대신 Vim처럼 마지막 글자를 지운다
    /// (수용 엣지 1). 문서 끝도 줄 끝의 특수 경우라 같은 자리다 — 세션 1의 "문서 끝 `x`는
    /// 무동작" 억제를 이 재조립이 덮어쓴다.
    @Test("줄 끝 `x`는 왼쪽 한 글자를 지운다 — 방향 재조립")
    func reassemblesTheSelectionAtTheLineEnd() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        makeAdapter(
            reader: FocusedTextReader { _ in Self.atDocumentEnd }, collecting: { posted.append($0) }
        ).execute([.edit(.delete, .motion(.charRight, count: 1))], processID: 42)

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow), Int64(kVK_ANSI_X), Int64(kVK_ANSI_X),
            ])
        // 방향만 바뀌는 것이 아니라 **선택**이어야 한다 — Shift가 빠지면 캐럿만 움직이고
        // 뒤이은 `Cmd-X`가 빈 선택에 나간다(정확화가 오히려 엣지 5를 만든다).
        #expect(posted.prefix(2).allSatisfy { $0.flags.contains(.maskShift) })

        // 읽기가 없으면 오늘의 무상태 시퀀스 그대로다 (`Shift-→`, `Cmd-X`).
        nonisolated(unsafe) var fallback: [CGEvent] = []
        makeAdapter(reader: FocusedTextReader { _ in nil }, collecting: { fallback.append($0) })
            .execute([.edit(.delete, .motion(.charRight, count: 1))], processID: 42)

        #expect(keyCodes(of: fallback) == Self.charDeleteKeyCodes)
    }

    /// 마지막 줄 `dgg`는 선행 `↓`가 줄 끝으로 포화해 마지막 줄을 빠뜨린다 (수용 엣지 4).
    /// 정확화는 `cgg`가 이미 쓰는 "줄 끝에서 위로"로 접두만 바꾼다.
    @Test("마지막 줄 `dgg`는 줄 끝에서 위로 선택한다")
    func reassemblesTheDocumentStartPrefixOnTheLastLine() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        makeAdapter(
            reader: FocusedTextReader { _ in Self.atDocumentEnd }, collecting: { posted.append($0) }
        ).execute([.edit(.delete, .linewiseMotion(.documentStart, count: 1))], processID: 42)

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),  // Cmd-→ (줄 끝)
                Int64(kVK_UpArrow), Int64(kVK_UpArrow),  // Shift-Cmd-↑ (문서 시작까지 선택)
                Int64(kVK_ANSI_X), Int64(kVK_ANSI_X),
            ])
        #expect(posted.prefix(2).allSatisfy { !$0.flags.contains(.maskShift) }, "접두는 이동이다")
        #expect(posted.dropFirst(2).prefix(2).allSatisfy { $0.flags.contains(.maskShift) })
    }

    /// 문서 한가운데라면 억제하지 않는다 — 억제는 증명된 자리에서만 일어난다.
    @Test("문서 한가운데 `x`는 그대로 나간다")
    func doesNotSuppressAwayFromTheBoundary() {
        let midDocument = FocusedText(
            selection: NSRange(location: 1, length: 0), characterCount: 5,
            window: "ab\ncd", windowRange: NSRange(location: 0, length: 5))

        nonisolated(unsafe) var posted: [CGEvent] = []
        makeAdapter(
            reader: FocusedTextReader { _ in midDocument }, collecting: { posted.append($0) }
        ).execute([.edit(.delete, .motion(.charRight, count: 1))], processID: 42)

        #expect(keyCodes(of: posted) == Self.charDeleteKeyCodes)
    }

    /// **폴백 계약**: 읽기가 실패하든 성공하든 정확화만 갈릴 뿐 실행은 한다 — 실패 경로에서
    /// 시퀀스가 달라지면 "읽기 실패 = 무동작"이라는 최악의 회귀가 된다 (Slack·VS Code는
    /// 포커스 요소를 노출하지 않아 그 경로가 상시다).
    ///
    /// 샘플은 **문서 한가운데**이므로 어느 어휘도 정확화되지 않는다. 동시에 트립와이어이기도
    /// 하다: 창(19자)이 `characterCount`(40)에 못 미쳐서, "오른쪽에 개행이 없으면 줄 끝"류의
    /// 부실한 판정은 여기서 `d$`도 아닌 `x`를 삼키며 빨개진다. 창 안에 개행을 하나 두어
    /// `dk`의 "위 줄 수"가 실제로 세어지게 한 것도 같은 이유다 — 세지 못하면 이 어휘가
    /// 정확화 경로를 지나지 않아 검증이 공허해진다.
    @Test("읽기가 실패해도 성공해도 같은 무상태 시퀀스가 나간다")
    func sequencesAreIdenticalRegardlessOfReadOutcome() {
        let sample = FocusedText(
            selection: NSRange(location: 6, length: 0), characterCount: 40,
            window: "the\nquick brown fox", windowRange: NSRange(location: 0, length: 19))

        nonisolated(unsafe) var succeeded: [CGEvent] = []
        makeAdapter(reader: FocusedTextReader { _ in sample }, collecting: { succeeded.append($0) })
            .execute(Self.vocabulary, processID: 42)

        nonisolated(unsafe) var failed: [CGEvent] = []
        makeAdapter(reader: FocusedTextReader { _ in nil }, collecting: { failed.append($0) })
            .execute(Self.vocabulary, processID: 42)

        // 읽을 앱 자체가 없는 경우(pid nil)도 같은 편이다 — 실패와 구분되지 않는다.
        nonisolated(unsafe) var noProcess: [CGEvent] = []
        makeAdapter(reader: FocusedTextReader { _ in sample }, collecting: { noProcess.append($0) })
            .execute(Self.vocabulary)

        #expect(!succeeded.isEmpty)
        #expect(keyCodes(of: succeeded) == keyCodes(of: failed))
        #expect(keyCodes(of: succeeded) == keyCodes(of: noProcess))
        #expect(succeeded.map(\.flags) == failed.map(\.flags))
    }
}

/// 뷰포트 리더 seam (M5 PR-C2 ②) — 소비자는 `mapping`의 `.scroll` 분기 **한 곳**이다.
/// 여기서 고정하는 것도 셋이다: 누가 읽는가(스크롤만 — 그 extent의 프로파일 명시값이 없을
/// 때만), 몇 번 읽는가(**execute당 1회** — 뷰포트 높이는 버스트 중 불변이라
/// `FocusedTextSnapshot`의 액션당 계약과 수명이 다르다), 실패 폴백(15/30 바이트 동일 —
/// 정확화만 포기하고 게시는 한다).
struct KeyboardAdapterViewportTests {
    private static func profile(half: Int? = nil, full: Int? = nil) -> ResolvedProfile {
        ResolvedProfile(AppProfile(halfPageLines: half, fullPageLines: full))
    }

    @Test("viewport 40의 Ctrl-d — ↓ 20타, 수정키 없음")
    func halfPageUsesViewportLines() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        makeAdapter(viewport: ViewportReader { _ in 40 }, collecting: { posted.append($0) })
            .execute([.scroll(.halfPage, forward: true)], processID: 42)

        #expect(posted.count == 20 * 2, "20스트로크 × keyDown+keyUp")
        #expect(keyCodes(of: posted).allSatisfy { $0 == Int64(kVK_DownArrow) })
        #expect(
            posted.allSatisfy {
                $0.flags.isDisjoint(with: [.maskAlternate, .maskCommand, .maskControl, .maskShift])
            })
    }

    /// 우선순위 사다리의 첫 칸 — 프로파일 명시값은 AX를 **이기는** 것이 아니라 읽기 자체를
    /// 생략시킨다(`scrollConsultsViewport` 술어). extent별 독립: half만 명시면 full은 읽는다.
    @Test("프로파일 명시 extent는 뷰포트를 읽지 않는다 — extent별 독립")
    func explicitProfileExtentSkipsTheRead() {
        nonisolated(unsafe) var reads = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(
            viewport: ViewportReader { _ in
                reads += 1
                return 40
            }, collecting: { posted.append($0) })

        adapter.execute(
            [.scroll(.halfPage, forward: true)], profile: Self.profile(half: 5), processID: 42)
        #expect(reads == 0, "half 명시 — 읽기 생략")
        #expect(posted.count == 5 * 2, "명시값 5가 이긴다")

        posted.removeAll()
        adapter.execute(
            [.scroll(.fullPage, forward: true)], profile: Self.profile(half: 5), processID: 42)
        #expect(reads == 1, "full은 미명시 — 읽는다")
        #expect(posted.count == 38 * 2, "full = 뷰포트 40 − 2")
    }

    @Test("pid가 없으면 리더를 부르지 않고 상수 폴백으로 게시한다")
    func missingProcessIDSkipsTheRead() {
        nonisolated(unsafe) var reads = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        makeAdapter(
            viewport: ViewportReader { _ in
                reads += 1
                return 40
            }, collecting: { posted.append($0) }
        ).execute([.scroll(.halfPage, forward: true)])

        #expect(reads == 0)
        #expect(posted.count == 15 * 2, "폴백 = 코드 상수 15")
    }

    /// 무상태 폴백의 바이트 동일 계약 — 읽기 실패가 스크롤을 죽이면 안 된다.
    @Test("읽기 실패는 15/30 상수와 바이트 동일하게 게시한다")
    func failedReadFallsBackToConstants() {
        nonisolated(unsafe) var failed: [CGEvent] = []
        makeAdapter(viewport: ViewportReader { _ in nil }, collecting: { failed.append($0) })
            .execute(
                [.scroll(.halfPage, forward: true), .scroll(.fullPage, forward: false)],
                processID: 42)

        nonisolated(unsafe) var noRead: [CGEvent] = []
        makeAdapter(collecting: { noRead.append($0) })
            .execute([.scroll(.halfPage, forward: true), .scroll(.fullPage, forward: false)])

        #expect(failed.count == (15 + 30) * 2)
        #expect(keyCodes(of: failed) == keyCodes(of: noRead))
        #expect(failed.map(\.flags) == noRead.map(\.flags))
    }

    /// `3Ctrl-f`는 엔진이 액션 3건으로 복제한다 — 액션마다 읽으면 정확도 이득 0에 비용만
    /// 곱해지므로(타임아웃 앱 최악 33×50ms) 뷰포트 스냅샷은 execute당 1회다.
    @Test("뷰포트 읽기는 execute당 1회다 — 액션 수만큼 곱해지지 않는다")
    func viewportIsReadOncePerExecute() {
        nonisolated(unsafe) var reads = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        makeAdapter(
            viewport: ViewportReader { _ in
                reads += 1
                return 40
            }, collecting: { posted.append($0) }
        ).execute(
            [.scroll(.halfPage, forward: true), .scroll(.halfPage, forward: true)], processID: 42)

        #expect(reads == 1)
        #expect(posted.count == 20 * 2 * 2, "두 액션 모두 같은 읽기로 정확화된다")
    }

    /// 별개 프리미티브 계약 — 스크롤이 캐럿 주변 리더(`FocusedTextReader`)를 건드리기
    /// 시작하면 `reads == 6` 왕복 고정이 조용히 무너진다.
    @Test("스크롤은 캐럿 주변 리더를 부르지 않는다")
    func scrollDoesNotTouchTheFocusedTextReader() {
        nonisolated(unsafe) var focusedReads = 0
        nonisolated(unsafe) var viewportReads = 0
        makeAdapter(
            reader: FocusedTextReader { _ in
                focusedReads += 1
                return nil
            },
            viewport: ViewportReader { _ in
                viewportReads += 1
                return 40
            }, collecting: { _ in }
        ).execute([.scroll(.fullPage, forward: true)], processID: 42)

        #expect(focusedReads == 0)
        #expect(viewportReads == 1)
    }
}

/// Visual 앵커 상태의 end-to-end 배선 (M5 PR-C1) — 수립·자가 검증·`vh` 재앵커·폐기가
/// `execute` 경로에서 실제로 맞물리는지를 고정한다. 순수 로직 골든은
/// `VisualAnchorMappingTests`가, 여기서는 세션 술어(누가 언제 읽는가)와 상태 수명이 주다.
struct KeyboardAdapterVisualAnchorTests {
    /// 문서 `"ab\ncde"`의 오프셋 4(`d` 앞 — **열 1**이라 `h`가 유효하다) 캐럿 —
    /// `v` 진입 직전의 읽기. 열 0 앵커의 재앵커 봉쇄는 매퍼 골든이 전담한다.
    private static let caretAtFour = FocusedText(
        selection: NSRange(location: 4, length: 0), characterCount: 6,
        window: "ab\ncde", windowRange: NSRange(location: 0, length: 6))

    /// `v` 진입 `Shift-→`가 만든 진입형 선택 `[4, 5)` — 세션 중 액션의 읽기.
    private static let entrySelection = FocusedText(
        selection: NSRange(location: 4, length: 1), characterCount: 6,
        window: "ab\ncde", windowRange: NSRange(location: 0, length: 6))

    /// 호출 순서대로 준비된 값을 내주는 리더 — 준비가 소진되면 마지막 값을 반복한다.
    /// (`execute` 사이의 연쇄를 한 리더로 표현하기 위한 것으로, 몇 번째 읽기인지가 곧 단언이다.)
    private static func sequencedReader(
        _ responses: [FocusedText?], reads: @escaping @Sendable () -> Void = {}
    ) -> FocusedTextReader {
        nonisolated(unsafe) var call = 0
        return FocusedTextReader { _ in
            reads()
            defer { call += 1 }
            return call < responses.count ? responses[call] : responses.last ?? nil
        }
    }

    @Test("vh — 진입 수립 후 재앵커 시퀀스가 게시된다")
    func entryThenCharLeftReanchors() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let tracker = VisualAnchorTracker()
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, Self.entrySelection]),
            visualAnchor: tracker, collecting: { posted.append($0) }
        ).execute(
            [.beginSelection(linewise: false), .extendSelection(.charLeft)], processID: 42)

        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),  // Shift-→ (진입)
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),  // → (오른쪽 끝 A+1로 collapse)
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),  // Shift-←
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),  // Shift-←
            ])
        #expect(posted.prefix(2).allSatisfy { $0.flags.contains(.maskShift) })
        // 재앵커 접두 `→`는 **collapse**다 — Shift가 실리면 접기가 아니라 확장이 된다.
        #expect(
            posted.dropFirst(2).prefix(2).allSatisfy { !$0.flags.contains(.maskShift) },
            "접두 →는 Shift 없음")
        #expect(posted.suffix(4).allSatisfy { $0.flags.contains(.maskShift) }, "재확장은 선택")
        // 상태는 side가 반전된 채 남는다 — 다음 후진의 무보정 1타가 여기 딛는다.
        #expect(tracker.current?.side == .right)
        #expect(tracker.current?.pinnedEnd == 5)
    }

    /// 카운트는 반복 액션이다 — 첫 `h`만 재앵커(3타)하고 이후는 후진형이라 1타씩이다.
    /// 리더가 계속 진입형 `[3, 4)`를 내줘도(낡은 읽기) 같다: 재앵커 뒤의 판정은 앵커 쪽
    /// 끝(오른쪽 4)만 보므로 포커스 쪽이 낡아도 어긋나지 않는다.
    @Test("3h — 재앵커 1회 후 무보정 1타씩, 낡은 읽기에도 동일")
    func repeatedCharLeftReanchorsOnce() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, Self.entrySelection]),
            collecting: { posted.append($0) }
        ).execute(
            [
                .beginSelection(linewise: false),
                .extendSelection(.charLeft), .extendSelection(.charLeft),
                .extendSelection(.charLeft),
            ], processID: 42)

        // 진입 1타 + 재앵커 3타 + 후진 1타 + 후진 1타 = 6스트로크(이벤트 12건).
        #expect(posted.count == 12)
        #expect(
            keyCodes(of: posted.suffix(4)) == [
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
            ])
        #expect(posted.suffix(4).allSatisfy { $0.flags.contains(.maskShift) })
    }

    /// 앵커 쪽 끝이 어긋난 읽기 = 화면이 상태와 다르다(마우스·앱 지연) — 그 액션부터
    /// 무상태 폴백이고 상태는 폐기된다. **폐기 뒤의 액션은 읽기 자체가 없다** — 상태가
    /// 없으면 검증할 것도 없다는 세션 술어의 확인이다.
    @Test("검증 실패 — 폴백 강등 + 폐기, 이후 읽기 0회")
    func validationFailureFallsBackAndDiscards() {
        let drifted = FocusedText(
            selection: NSRange(location: 1, length: 2), characterCount: 6,
            window: "ab\ncde", windowRange: NSRange(location: 0, length: 6))

        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var reads = 0
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, drifted], reads: { reads += 1 }),
            collecting: { posted.append($0) }
        ).execute(
            [
                .beginSelection(linewise: false),
                .extendSelection(.charLeft), .extendSelection(.charLeft),
            ], processID: 42)

        // 진입 Shift-→ 1타 + 폴백 Shift-← 1타 + (상태 없음) 폴백 Shift-← 1타.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
            ])
        #expect(posted.allSatisfy { $0.flags.contains(.maskShift) })
        #expect(reads == 2, "진입 수립 1회 + 첫 확장의 검증 1회 — 폐기 뒤에는 읽지 않는다")
    }

    @Test("pid 불일치 — 폴백 강등 + 폐기")
    func processIDMismatchFallsBackAndDiscards() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let tracker = VisualAnchorTracker()
        let adapter = makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, Self.entrySelection]),
            visualAnchor: tracker, collecting: { posted.append($0) })

        adapter.execute([.beginSelection(linewise: false)], processID: 42)
        #expect(tracker.current != nil)

        // 같은 세션 상태로 다른 앱의 읽기가 오면 — 앱을 다녀온 경우다 — 폐기 + 폴백.
        adapter.execute([.extendSelection(.charLeft)], processID: 43)

        #expect(keyCodes(of: posted.suffix(2)) == [Int64(kVK_LeftArrow), Int64(kVK_LeftArrow)])
        #expect(posted.suffix(2).allSatisfy { $0.flags.contains(.maskShift) })
        #expect(tracker.current == nil)
    }

    @Test("clearSelection — 상태 폐기, 이후 확장은 읽기 없이 폴백")
    func clearSelectionDiscardsState() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var reads = 0
        let tracker = VisualAnchorTracker()
        let adapter = makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour], reads: { reads += 1 }),
            visualAnchor: tracker, collecting: { posted.append($0) })

        adapter.execute([.beginSelection(linewise: false), .clearSelection], processID: 42)
        #expect(tracker.current == nil, "이탈이 세션 상태를 남기면 다음 세션이 낡은 앵커를 딛는다")
        #expect(reads == 1, "clearSelection은 읽지 않는다 — 폐기는 증거가 필요 없다")

        adapter.execute([.extendSelection(.charLeft)], processID: 42)
        #expect(keyCodes(of: posted.suffix(2)) == [Int64(kVK_LeftArrow), Int64(kVK_LeftArrow)])
        #expect(reads == 1, "상태가 없으면 확장도 읽지 않는다")
    }

    /// `v`→`V` 폴백은 포커스만 반올림해 상태와 화면이 어긋난다 — 앱 앵커는 그대로라 자가
    /// 검증이 잡지 못하므로, 게시 시점에 폐기하는 것이 계약이다. 읽기 실패로 정확화(⑥)가
    /// 서지 못한 전환이 이 폴백 경로다.
    @Test("v→V 폴백 — 게시는 현행, 상태는 폐기")
    func switchWiseFallbackDiscardsState() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let tracker = VisualAnchorTracker()
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, nil]),
            visualAnchor: tracker, collecting: { posted.append($0) }
        ).execute(
            [.beginSelection(linewise: false), .switchSelectionWise(linewise: true)],
            processID: 42)

        // 진입 Shift-→ 뒤 폴백 전환 `Shift-↓, Shift-Cmd-←` 그대로.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_DownArrow), Int64(kVK_DownArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
            ])
        #expect(tracker.current == nil)
    }

    @Test("pid가 없으면 Visual도 읽지 않는다 — 시퀀스는 무상태 그대로")
    func missingProcessIDStaysStateless() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var reads = 0
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour], reads: { reads += 1 }),
            collecting: { posted.append($0) }
        ).execute([.beginSelection(linewise: false), .extendSelection(.charLeft)])

        #expect(reads == 0)
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
            ])
    }

    /// 상태 갱신은 게시 **전**(매핑 확정 시점)에 일어나므로, 중단으로 이벤트가 버려지면
    /// 재앵커된 상태가 재앵커되지 않은 화면 위에 남는다 — 진입형 선택 `[A, A+1)`이 새
    /// `pinnedEnd`(A+1)와 우연히 일치해 자가 검증이 거짓 통과하는 유일한 자리라, 드롭
    /// 경로는 상태를 폐기해야 한다.
    @Test("중단으로 이벤트가 버려지면 상태도 함께 버린다")
    func abortedExecutionDiscardsState() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        nonisolated(unsafe) var calls = 0
        let tracker = VisualAnchorTracker()
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, Self.entrySelection]),
            visualAnchor: tracker, collecting: { posted.append($0) }
        ).execute(
            [.beginSelection(linewise: false), .extendSelection(.charLeft)], processID: 42,
            isCurrent: {
                // 첫 확인(진입 가드)만 통과시키고 게시 직전 확인에서 끊는다 — 매핑과 상태
                // 갱신은 끝났지만 이벤트는 한 건도 나가지 않은 상태를 만든다.
                calls += 1
                return calls == 1
            })

        #expect(posted.isEmpty)
        #expect(tracker.current == nil, "게시되지 않은 재앵커가 상태로 남으면 다음 h가 선택을 지운다")
    }

    /// ⑤ end-to-end — `V` 세션의 charwise 모션은 무게시 `.skipped`다: 이벤트가 한 건도
    /// 나가지 않되, 상태는 그대로 남는다 (화면 불변 = 거리 포함 전부 유효 유지).
    @Test("V 세션의 h는 무게시 스킵 — 상태는 유지된다")
    func linewiseSessionCharwiseMotionSkipsWithoutPublishing() {
        // `V` 진입 직전 캐럿 4 → 앵커 줄 시작 3. 진입 후 선택 [3, 6).
        let linewiseSelection = FocusedText(
            selection: NSRange(location: 3, length: 3), characterCount: 6,
            window: "ab\ncde", windowRange: NSRange(location: 0, length: 6))

        nonisolated(unsafe) var posted: [CGEvent] = []
        let tracker = VisualAnchorTracker()
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, linewiseSelection]),
            visualAnchor: tracker, collecting: { posted.append($0) }
        ).execute(
            [.beginSelection(linewise: true), .extendSelection(.charLeft)], processID: 42)

        // 진입 `Cmd-←, Shift-↓` 2타뿐 — `h`는 Vim에서 범위 무변화라 무게시가 정확 동작이다.
        #expect(posted.count == 4)
        #expect(tracker.current?.wise == .linewise)
        #expect(tracker.current?.focusLineDistance == 0, "무게시는 상태도 건드리지 않는다")
    }

    /// ⑥ end-to-end — `v`→`V` 정확화가 재앵커를 게시하고 상태를 linewise로 재수립한다.
    /// 폴백의 `.discard`(위 테스트)와 달리 세션이 이어진다.
    @Test("v→V 정확화 — 재앵커 게시 + 상태 재수립")
    func switchWiseRefinementReanchorsAndReestablishes() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let tracker = VisualAnchorTracker()
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, Self.entrySelection]),
            visualAnchor: tracker, collecting: { posted.append($0) }
        ).execute(
            [.beginSelection(linewise: false), .switchSelectionWise(linewise: true)],
            processID: 42)

        // 진입 Shift-→ 뒤 재앵커 `←, Cmd-←, Shift-↓` — 앵커 줄도 통째로 잡는다.
        #expect(
            keyCodes(of: posted) == [
                Int64(kVK_RightArrow), Int64(kVK_RightArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_LeftArrow), Int64(kVK_LeftArrow),
                Int64(kVK_DownArrow), Int64(kVK_DownArrow),
            ])
        #expect(tracker.current?.wise == .linewise)
        #expect(tracker.current?.pinnedEnd == 3)
        // 원래 캐럿은 미보관 — ⑦의 열 근사는 `V` 진입 세션에서만 성립하므로, 전환 세션의
        // `V`→`v`는 정직한 스킵으로 남는다.
        #expect(tracker.current?.originalCaret == nil)
    }

    /// 읽기 실패는 폐기가 아니다 — 하지만 무상태 확장은 게시되어 포커스를 옮기므로,
    /// linewise의 포커스 줄 거리만은 미상으로 좁혀야 한다. 알던 값이 남으면 `V`→`v`
    /// 조건부 지원(다음 세션)이 낡은 거리로 잘못 재선택한다.
    @Test("읽기 실패 중의 linewise 확장은 줄 거리를 미상으로 좁힌다")
    func readFailureDuringLinewiseExtendUnknowsDistance() {
        let tracker = VisualAnchorTracker()
        makeAdapter(
            reader: Self.sequencedReader([Self.caretAtFour, nil]),
            visualAnchor: tracker, collecting: { _ in }
        ).execute(
            [.beginSelection(linewise: true), .extendSelection(.lineDown)], processID: 42)

        #expect(tracker.current != nil, "읽기 실패는 폐기 트리거가 아니다")
        #expect(tracker.current?.focusLineDistance == nil)
        #expect(tracker.current?.anchor == 3, "앵커(줄 시작)는 그대로다 — 좁힌 것은 거리뿐")
    }
}

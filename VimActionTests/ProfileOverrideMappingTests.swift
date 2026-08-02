//
//  ProfileOverrideMappingTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimActionConfig
import VimEngine
@testable import VimAction

/// 프로파일 재정의·disable이 실행 경로 전체에 전파되는가 — `MotionKeyMapper` 조회
/// **단일 지점**에 얹은 재정의가 편집(dG)·Visual(vG)·명령 접두(paste·o/O)·scroll까지
/// 자동으로 따라오는 것이 이 설계의 핵심 계약이다.
///
/// `.empty` 기본 파라미터가 배선 누락을 가릴 수 있으므로(컴파일은 통과), 전파는
/// 여기서 소비처별로 명시 검증한다.

/// `ResolvedProfile`은 `AppProfile` 변환으로만 만들어진다 — 테스트도 같은 경로를 써서
/// 변환까지 함께 지난다.
private func makeProfile(
    motions: [Motion: ConfigOverride] = [:],
    actions: [ConfigAction: ConfigOverride] = [:],
    half: Int? = nil, full: Int? = nil
) -> ResolvedProfile {
    ResolvedProfile(
        AppProfile(
            halfPageLines: half, fullPageLines: full, motions: motions,
            actions: actions))
}

/// 내장 매핑(Cmd-↓)과 확실히 구분되는 재정의 — End 단일 키.
private let endOverride: [Motion: ConfigOverride] = [
    .documentEnd: .strokes([ConfigKeyStroke(.end)])
]
private let endKey = KeyStroke(kVK_End)
/// Slack의 줄바꿈 키 — 내장 `Return`과 확실히 구분되는 액션 키 재정의.
private let shiftReturnConfig = ConfigKeyStroke(.return, [.shift])
private let shiftReturn = KeyStroke(kVK_Return, [.maskShift])
private let cut = KeyStroke(kVK_ANSI_X, [.maskCommand])

struct ProfileOverrideMappingTests {
    // MARK: 모션·선택 — 조회 단일 지점

    @Test("모션 재정의가 내장 매핑을 대체한다")
    func overrideReplacesBuiltInMapping() {
        #expect(
            MotionKeyMapper.keyStrokes(for: .documentEnd, profile: makeProfile(motions: endOverride))
                == [endKey])
        #expect(
            MotionKeyMapper.keyStrokes(for: .documentEnd)
                == [KeyStroke(kVK_DownArrow, [.maskCommand])], "프로파일 없으면 내장 그대로")
    }

    @Test("선택 확장은 재정의 시퀀스에도 Shift를 얹는다")
    func selectionAddsShiftToOverride() {
        #expect(
            MotionKeyMapper.selectionStrokes(
                for: .documentEnd, profile: makeProfile(motions: endOverride))
                == [KeyStroke(kVK_End, [.maskShift])])
    }

    @Test("disabled 모션은 조회가 nil이다 — 정직한 스킵 경로")
    func disabledMotionReturnsNil() {
        let profile = makeProfile(motions: [.documentEnd: .disabled])
        #expect(MotionKeyMapper.keyStrokes(for: .documentEnd, profile: profile) == nil)
        #expect(MotionKeyMapper.selectionStrokes(for: .documentEnd, profile: profile) == nil)
    }

    // MARK: 편집·Visual — 자동 전파

    @Test("편집 복합(dG)이 재정의를 따라온다")
    func editCompositeFollowsOverride() {
        let strokes = EditKeyMapper.keyStrokes(
            for: .delete, range: .linewiseMotion(.documentEnd, count: 1), family: .textArea,
            profile: makeProfile(motions: endOverride))
        // dG = 줄 시작 + 재정의된 documentEnd 선택 + Cmd-X
        #expect(
            strokes == [
                KeyStroke(kVK_LeftArrow, [.maskCommand]), KeyStroke(kVK_End, [.maskShift]), cut,
            ])
    }

    @Test("disabled 모션을 쓰는 편집은 통째로 nil이다 — 부분 시퀀스 금지")
    func editWithDisabledMotionSkipsEntirely() {
        let profile = makeProfile(motions: [.documentEnd: .disabled])
        #expect(
            EditKeyMapper.keyStrokes(
                for: .delete, range: .linewiseMotion(.documentEnd, count: 1), family: .textArea,
                profile: profile) == nil)
    }

    /// yank의 collapse(`←`)도 모션이다 — `char_left` disable이 yank 전체를 접는다.
    @Test("char_left disable이 yank의 collapse까지 접는다")
    func disabledCharLeftFoldsYank() {
        let profile = makeProfile(motions: [.charLeft: .disabled])
        #expect(
            EditKeyMapper.keyStrokes(
                for: .yank, range: .motion(.wordForward, count: 1), family: .textArea,
                profile: profile) == nil)
    }

    @Test("Visual 확장(vG)이 재정의를 따라온다")
    func visualExtendFollowsOverride() {
        #expect(
            VisualKeyMapper.keyStrokes(
                for: .extendSelection(.documentEnd), family: .textArea,
                profile: makeProfile(motions: endOverride))
                == [KeyStroke(kVK_End, [.maskShift])])
        #expect(
            VisualKeyMapper.keyStrokes(
                for: .extendSelection(.documentEnd), family: .textArea,
                profile: makeProfile(motions: [.documentEnd: .disabled])) == nil)
    }

    // MARK: 명령 계열 — 접두 전파 + scroll 줄 수

    @Test("scroll 줄 수 재정의 — 기본 15/30은 코드 상수로 남는다")
    func scrollLineCountOverride() {
        let overridden = CommandKeyMapper.keyStrokes(
            for: .scroll(.halfPage, forward: true), family: .textArea,
            profile: makeProfile(half: 5))
        #expect(overridden?.count == 5)
        #expect(overridden?.allSatisfy { $0 == KeyStroke(kVK_DownArrow) } == true)

        let defaultHalf = CommandKeyMapper.keyStrokes(
            for: .scroll(.halfPage, forward: true), family: .textArea)
        #expect(defaultHalf?.count == 15, "재정의 없으면 코드 상수 15")

        let fullOverridden = CommandKeyMapper.keyStrokes(
            for: .scroll(.fullPage, forward: false), family: .textArea,
            profile: makeProfile(full: 7))
        #expect(fullOverridden?.count == 7)
    }

    @Test("scroll의 반복 모션도 재정의·disable을 따라온다")
    func scrollFollowsMotionOverride() {
        let profile = makeProfile(motions: [.lineDown: .disabled])
        #expect(
            CommandKeyMapper.keyStrokes(
                for: .scroll(.halfPage, forward: true), family: .textArea, profile: profile)
                == nil)
    }

    @Test("openLine(o)의 위치 접두가 재정의를 따라온다")
    func openLineFollowsOverride() {
        let strokes = CommandKeyMapper.keyStrokes(
            for: .openLine(above: false), family: .textArea,
            profile: makeProfile(motions: [.lineEnd: .strokes([ConfigKeyStroke(.end)])]))
        #expect(strokes == [endKey, KeyStroke(kVK_Return)])

        #expect(
            CommandKeyMapper.keyStrokes(
                for: .openLine(above: false), family: .textArea,
                profile: makeProfile(motions: [.lineEnd: .disabled])) == nil)
    }

    // MARK: 액션 자신의 키 재정의 — 모션 접두는 그대로

    @Test("openLine의 줄바꿈 키만 갈아끼운다 — o/O의 접두는 모션이 그대로 소유")
    func openLineNewLineKeyOverride() {
        let profile = makeProfile(actions: [.openLine: .strokes([shiftReturnConfig])])

        #expect(
            CommandKeyMapper.keyStrokes(
                for: .openLine(above: false), family: .textArea, profile: profile)
                == [KeyStroke(kVK_RightArrow, [.maskCommand]), shiftReturn])
        // `O`가 `o`로 붕괴하지 않는 것이 자기 키만 교체하는 이유다.
        #expect(
            CommandKeyMapper.keyStrokes(
                for: .openLine(above: true), family: .textArea, profile: profile)
                == [
                    KeyStroke(kVK_LeftArrow, [.maskCommand]), shiftReturn,
                    KeyStroke(kVK_UpArrow),
                ])
    }

    @Test("액션 키 재정의는 모션 재정의와 함께 걸린다")
    func actionKeyAndMotionOverrideCompose() {
        let profile = makeProfile(
            motions: [.lineEnd: .strokes([ConfigKeyStroke(.end)])],
            actions: [.openLine: .strokes([shiftReturnConfig])])

        #expect(
            CommandKeyMapper.keyStrokes(
                for: .openLine(above: false), family: .textArea, profile: profile)
                == [endKey, shiftReturn])
    }

    @Test("undo·redo·paste도 자기 키를 재정의한다")
    func commandKeyOverrides() {
        let undo = makeProfile(actions: [.undo: .strokes([ConfigKeyStroke(.home)])])
        #expect(
            CommandKeyMapper.keyStrokes(for: .undo, family: .textArea, profile: undo)
                == [KeyStroke(kVK_Home)])

        let redo = makeProfile(actions: [.redo: .strokes([ConfigKeyStroke(.end)])])
        #expect(
            CommandKeyMapper.keyStrokes(for: .redo, family: .textArea, profile: redo)
                == [endKey])

        // 붙여넣기는 카운트만큼 반복되는 그룹이라 재정의도 그룹마다 실린다.
        let paste = makeProfile(actions: [.paste: .strokes([shiftReturnConfig])])
        #expect(
            CommandKeyMapper.pasteStrokeGroups(
                before: true, count: 2, wise: .charwise, family: .textArea, profile: paste)
                == [[shiftReturn], [shiftReturn]])
    }

    @Test("paste 접두 모션이 disable되면 붙여넣기 전체가 접힌다")
    func pastePrefixDisableFoldsPaste() {
        let profile = makeProfile(motions: [.charRight: .disabled])
        #expect(
            CommandKeyMapper.pasteStrokeGroups(
                before: false, count: 2, wise: .charwise, family: .textArea, profile: profile)
                == nil)
        #expect(
            CommandKeyMapper.pasteStrokeGroups(
                before: false, count: 2, wise: .charwise, family: .textArea) != nil,
            "프로파일 없으면 그대로 동작")
    }
}

/// 어댑터 레벨 — disable이 게시 0건의 **정직한 스킵**으로 끝나는가 (부분 게시 금지 계약).
struct ProfileDisableAdapterTests {
    private func makeAdapter(
        changeCount: @escaping @Sendable () -> Int = { 0 },
        collecting posted: @escaping @Sendable (CGEvent) -> Void
    ) -> KeyboardAdapter {
        KeyboardAdapter(
            executor: ActionExecutor(postEvent: posted),
            pasteWise: PasteWiseResolver(readClipboard: { .charwise }, readChangeCount: changeCount),
            hasQwertyCommandKeys: { true })
    }

    @Test("actions disable(scroll)은 한 이벤트도 게시하지 않는다")
    func disabledActionPostsNothing() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute(
            [.scroll(.halfPage, forward: true)],
            profile: makeProfile(actions: [.scroll: .disabled]))
        #expect(posted.isEmpty)

        adapter.execute([.scroll(.halfPage, forward: true)])
        #expect(posted.count == 15 * 2, "프로파일 없으면 그대로 실행된다 (keyDown+keyUp 쌍)")
    }

    @Test("disabled 모션을 쓰는 편집은 한 이벤트도 게시하지 않는다 — 부분 시퀀스 금지")
    func disabledMotionInEditPostsNothing() {
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter { posted.append($0) }

        adapter.execute(
            [.edit(.delete, .linewiseMotion(.documentEnd, count: 1))],
            profile: makeProfile(motions: [.documentEnd: .disabled]))

        #expect(posted.isEmpty)
    }

    /// 게이트 2종(`nonTextEditDoesNotRecordPasteWise`·비-QWERTY)과 같은 계약을 프로파일
    /// 축에서 고정한다 — 스킵된 편집이 기억을 남기면 다음 외부 복사 한 번 뒤의 `p`가
    /// linewise로 오판돼 다음 줄 시작에 붙는다.
    @Test("프로파일 disable로 스킵된 줄 단위 편집은 붙여넣기 단위 기억을 남기지 않는다")
    func disabledEditDoesNotRecordPasteWise() {
        nonisolated(unsafe) var changeCountReads = 0
        nonisolated(unsafe) var posted: [CGEvent] = []
        let adapter = makeAdapter(
            changeCount: {
                changeCountReads += 1
                return 0
            }, collecting: { posted.append($0) })

        adapter.execute(
            [.edit(.delete, .line(count: 1))],
            profile: makeProfile(motions: [.lineStart: .disabled]))
        #expect(posted.isEmpty)
        #expect(changeCountReads == 0, "스킵이 확정된 편집은 기억을 남기지 않는다")

        // 대조군: 같은 액션이 프로파일 없이는 실제로 기억을 남긴다 (관측 수단이 유효하다는 확인).
        adapter.execute([.edit(.delete, .line(count: 1))])
        #expect(changeCountReads == 1)
    }
}

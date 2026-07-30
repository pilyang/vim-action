//
//  KeyboardAdapter.swift
//  VimAction
//

import CoreGraphics
import os
import VimEngine

/// Keyboard 전략의 실행 어댑터 — 엔진이 낸 `VimAction`을 합성 `CGEvent`로 바꿔
/// `ActionExecutor`로 내보낸다.
///
/// **호출은 게시 직렬 큐 위에서** 한다: `CGEvent`는 비-`Sendable`이라 만든 컨텍스트에서
/// 게시까지 끝내야 하고(격리를 건너는 값이 애초에 없게), 탭 콜백은 경량 불변식에 묶여 있다.
/// 그래서 타입 단위 `nonisolated`다 — 메인 격리를 가정하지 않는다.
///
/// 실행 범위는 v1 어휘 전체다 — 이동(`.move`), 편집(`.edit`), Visual 선택 세션, 그리고
/// 네이티브 명령 위임(`.openLine`·`.paste`·`.undo`·`.redo`·`.scroll`). 아직 구현하지 않은
/// 액션은 **실패가 아니다** — 조용히 스킵하고 DEBUG 로그만 남긴다
/// (`20260726_unsupported-action-not-failure.md`).
nonisolated struct KeyboardAdapter: Sendable {
    private let executor: ActionExecutor

    /// 붙여넣기 단위 판정에 필요한 클립보드 읽기. 클로저인 이유는 `ActionExecutor.postEvent`와
    /// 같다 — 테스트가 결정적인 값을 주입한다. 실제 패스트보드를 읽으면 테스트가 **개발자의
    /// 클립보드**에 따라 결과가 갈려 비결정적이 된다.
    private let readPasteWise: @Sendable () -> PasteWise?

    init(
        executor: ActionExecutor = ActionExecutor(),
        readPasteWise: @escaping @Sendable () -> PasteWise? = { Clipboard.pasteWise() }
    ) {
        self.executor = executor
        self.readPasteWise = readPasteWise
    }

    /// 키 입력 1건이 만든 액션 시퀀스를 실행한다.
    func execute(_ actions: [VimAction]) {
        var events: [CGEvent] = []
        #if DEBUG
        var skippedCount = 0
        var firstSkipped: VimAction?
        #endif

        for action in actions {
            let strokes: [KeyStroke]
            switch mapping(for: action) {
            case .strokes(let mapped):
                strokes = mapped
            case .unsupported:
                #if DEBUG
                skippedCount += 1
                if firstSkipped == nil { firstSkipped = action }
                #endif
                continue
            case .skipped:
                continue
            }
            // 액션 단위 all-or-nothing — 스트로크 하나라도 CGEvent 생성에 실패하면 그 액션
            // 전체를 버린다. 부분 시퀀스는 편집에서 "선택은 어긋난 채 Cmd-X만 나가는"
            // 파괴적 실행이 된다 (이동만 실행하던 시절의 스킵-계속은 한 타 누락으로 무해했다).
            var actionEvents: [CGEvent] = []
            var creationFailed = false
            for stroke in strokes {
                guard
                    let down = CGEvent(
                        keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: true),
                    let up = CGEvent(
                        keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: false)
                else {
                    creationFailed = true
                    break
                }
                // 소스가 nil인 이벤트는 flags 기본값이 **실행 시점의 실제 modifier 상태**라,
                // 대입은 선택이 아니라 필수다 — 사용자가 누르고 있던 키가 새어 들어간다.
                down.flags = stroke.flags
                up.flags = stroke.flags
                actionEvents.append(down)
                actionEvents.append(up)
            }
            guard !creationFailed else {
                // 미지원 스킵(DEBUG)과 달리 실제 이상 상황이라 항상 남긴다.
                Logger.eventTap.error(
                    "CGEvent 생성 실패 — 액션 폐기: \(String(describing: action), privacy: .public)")
                continue
            }
            events.append(contentsOf: actionEvents)
        }

        #if DEBUG
        // 카운트 반복(`9999u`, Visual `9999j` 등)으로 액션이 수천 개일 수 있어 요약 1건으로
        // 접는다. 요약에 쓰는 건 개수와 첫 1개뿐이라 액션 자체를 쌓아 두지 않는다.
        if let first = firstSkipped {
            Logger.eventTap.debug(
                "미지원 액션 스킵 ×\(skippedCount, privacy: .public): \(String(describing: first), privacy: .public)"
            )
        }
        #endif

        executor.post(events)
    }

    /// 액션 1건의 매핑 결과. 스킵을 **두 종류로 가르는 것이 요점**이다 — 단계 4의 릴리스
    /// 게이트 판정이 "미지원 스킵 로그 전수 확인"이라, 지원하는데 이번 입력에는 할 일이 없는
    /// 경우가 미지원으로 집계되면 심사자가 그 어휘를 미구현으로 읽는다.
    private enum Mapping {
        case strokes([KeyStroke])
        /// 매퍼가 `nil` — 이 어휘가 아직 구현되지 않았다. 요약 로그에 집계된다.
        case unsupported
        /// 지원하지만 이번엔 게시할 것이 없다. 사유를 아는 자리에서 **자체 로그를 이미 남겼다**.
        case skipped
    }

    /// 액션 → 합성할 키스트로크.
    ///
    /// `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다 — 엔진에 케이스가 늘어도
    /// `default:`가 흡수해 어댑터가 컴파일 에러로 무너지지 않는다.
    ///
    /// `static`이 아닌 이유는 `.paste`가 주입된 클립보드 읽기를 쓰기 때문이다.
    private func mapping(for action: VimAction) -> Mapping {
        // 요소 계열은 단계 3의 focusedRole 리졸버가 채운다 — 그때까지 TextArea 고정.
        switch action {
        case .move(let motion):
            return .strokes(MotionKeyMapper.keyStrokes(for: motion))

        case .edit(let op, let range):
            return Self.mapping(EditKeyMapper.keyStrokes(for: op, range: range, family: .textArea))

        case .beginSelection, .extendSelection, .switchSelectionWise, .clearSelection:
            return Self.mapping(VisualKeyMapper.keyStrokes(for: action, family: .textArea))

        case .openLine, .undo, .redo, .scroll:
            return Self.mapping(CommandKeyMapper.keyStrokes(for: action, family: .textArea))

        case .paste(let before, let count):
            // 텍스트가 없는 클립보드(이미지만 있는 등)는 미지원이 아니라 "붙여넣을 것이 없음"이다.
            // 접두만 게시하면 붙여넣기 없이 캐럿만 움직이는 조용한 오동작이 된다.
            guard let wise = readPasteWise() else {
                Logger.eventTap.debug("paste 스킵 — 클립보드에 텍스트가 없다")
                return .skipped
            }
            return Self.mapping(
                CommandKeyMapper.pasteStrokes(
                    before: before, count: count, wise: wise, family: .textArea))

        default:
            return .unsupported
        }
    }

    /// 매퍼의 `[KeyStroke]?` 계약을 `Mapping`으로 옮긴다 — `nil`은 미지원이다.
    private static func mapping(_ strokes: [KeyStroke]?) -> Mapping {
        strokes.map(Mapping.strokes) ?? .unsupported
    }
}

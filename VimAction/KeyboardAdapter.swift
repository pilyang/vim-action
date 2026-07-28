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
/// 실행 범위는 이동(`.move`), 편집(`.edit`), Visual 선택 세션이다. 아직 구현하지 않은 액션은
/// **실패가 아니다** — 조용히 스킵하고 DEBUG 로그만 남긴다
/// (`20260726_unsupported-action-not-failure.md`).
nonisolated struct KeyboardAdapter: Sendable {
    private let executor: ActionExecutor

    init(executor: ActionExecutor = ActionExecutor()) {
        self.executor = executor
    }

    /// 키 입력 1건이 만든 액션 시퀀스를 실행한다.
    func execute(_ actions: [VimAction]) {
        var events: [CGEvent] = []
        #if DEBUG
        var skippedCount = 0
        var firstSkipped: VimAction?
        #endif

        for action in actions {
            guard let strokes = Self.keyStrokes(for: action) else {
                #if DEBUG
                skippedCount += 1
                if firstSkipped == nil { firstSkipped = action }
                #endif
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

    /// 액션 → 합성할 키스트로크. `nil`은 **미지원**(스킵+로그) — 실패와 구분된다.
    ///
    /// `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다 — 엔진에 케이스가 늘어도
    /// `default:`가 흡수해 어댑터가 컴파일 에러로 무너지지 않는다.
    private static func keyStrokes(for action: VimAction) -> [KeyStroke]? {
        switch action {
        case .move(let motion):
            return MotionKeyMapper.keyStrokes(for: motion)
        case .edit(let op, let range):
            // 요소 계열은 단계 3의 focusedRole 리졸버가 채운다 — 그때까지 TextArea 고정.
            return EditKeyMapper.keyStrokes(for: op, range: range, family: .textArea)
        case .beginSelection, .extendSelection, .switchSelectionWise, .clearSelection:
            return VisualKeyMapper.keyStrokes(for: action, family: .textArea)
        default:
            return nil
        }
    }
}

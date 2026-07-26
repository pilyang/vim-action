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
/// M2 시점의 실행 범위는 `.move`뿐이다. 아직 구현하지 않은 액션은 **실패가 아니다** —
/// 조용히 스킵하고 DEBUG 로그만 남긴다 (`20260726_unsupported-action-not-failure.md`).
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
            guard case .move(let motion) = action else {
                #if DEBUG
                skippedCount += 1
                if firstSkipped == nil { firstSkipped = action }
                #endif
                continue
            }
            for stroke in MotionKeyMapper.keyStrokes(for: motion) {
                guard
                    let down = CGEvent(
                        keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: true),
                    let up = CGEvent(
                        keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: false)
                else { continue }
                // 소스가 nil인 이벤트는 flags 기본값이 **실행 시점의 실제 modifier 상태**라,
                // 대입은 선택이 아니라 필수다 — 사용자가 누르고 있던 키가 새어 들어간다.
                down.flags = stroke.flags
                up.flags = stroke.flags
                events.append(down)
                events.append(up)
            }
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
}

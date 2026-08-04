//
//  VisualAnchorTests.swift
//  VimActionTests
//

import Foundation
import Testing

@testable import VimAction

/// 검증 대상 상태의 기본형 — 문서 "ab\ncd"에서 `v`로 오프셋 3(c)에 진입한 charwise 세션.
private func charwiseState(
    side: VisualAnchorState.Side = .left, anchor: Int = 3, pinnedEnd: Int = 3,
    processID: pid_t = 42
) -> VisualAnchorState {
    VisualAnchorState(
        anchor: anchor, wise: .charwise, side: side, pinnedEnd: pinnedEnd,
        processID: processID, originalCaret: nil, focusLineDistance: nil)
}

struct VisualAnchorTests {
    // MARK: - 자가 검증 (`agrees`)

    /// `.left`(전진형 `[A, F+1)`)는 읽은 선택의 **왼쪽 끝**이 앱 앵커여야 한다.
    @Test("전진형은 왼쪽 끝이 pinnedEnd와 일치하면 통과한다")
    func leftSideAgreesOnLeftEnd() {
        let state = charwiseState(side: .left, pinnedEnd: 3)
        let read = focusedText("ab\ncd", caret: 3, length: 2)  // [3, 5) — 전진 확장 뒤

        #expect(state.agrees(with: read, processID: 42))
    }

    /// `.right`(후진형 `[F, A+1)`)는 읽은 선택의 **오른쪽 끝**이 앱 앵커여야 한다.
    @Test("후진형은 오른쪽 끝이 pinnedEnd와 일치하면 통과한다")
    func rightSideAgreesOnRightEnd() {
        let state = charwiseState(side: .right, pinnedEnd: 4)
        let read = focusedText("ab\ncd", caret: 1, length: 3)  // [1, 4) — 후진 확장 뒤

        #expect(state.agrees(with: read, processID: 42))
    }

    /// 앵커 쪽 끝이 어긋났다 = 마우스·앱 지연 등으로 화면이 상태와 다르다 — 원인 불문 폐기다.
    @Test("앵커 쪽 끝 불일치는 검증 실패다")
    func mismatchedAnchorEndFailsValidation() {
        let state = charwiseState(side: .left, pinnedEnd: 3)
        let read = focusedText("ab\ncd", caret: 1, length: 2)  // 왼쪽 끝 1 ≠ 3

        #expect(!state.agrees(with: read, processID: 42))
    }

    /// 포커스 쪽 끝은 **검증하지 않는다** — 모션 착지는 앱만 알아 예측 불가이고, 예측 가능한
    /// 쪽만 검증해야 헛실패가 최소다. 같은 왼쪽 끝에 길이가 달라도 전진형은 통과한다.
    @Test("포커스 쪽 끝은 검증 대상이 아니다")
    func focusEndIsNotValidated() {
        let state = charwiseState(side: .left, pinnedEnd: 3)

        #expect(state.agrees(with: focusedText("ab\ncd", caret: 3, length: 1), processID: 42))
        #expect(state.agrees(with: focusedText("ab\ncd", caret: 3, length: 2), processID: 42))
    }

    @Test("pid 불일치는 검증 실패다 — nil pid 포함")
    func mismatchedProcessIDFailsValidation() {
        let state = charwiseState(pinnedEnd: 3)
        let read = focusedText("ab\ncd", caret: 3, length: 1)

        #expect(!state.agrees(with: read, processID: 43))
        #expect(!state.agrees(with: read, processID: nil))
    }

    /// Visual 세션이 살아 있으면 선택은 비어 있을 수 없다(진입이 이미 1자를 잡는다) —
    /// 빈 선택은 세션이 화면에서 죽었다는 증거다. 캐럿이 pinnedEnd 위여도 폐기가 맞다.
    @Test("빈 선택(캐럿)은 검증 실패다")
    func emptySelectionFailsValidation() {
        let state = charwiseState(side: .left, pinnedEnd: 3)
        let read = focusedText("ab\ncd", caret: 3)  // length 0 — 왼쪽 끝은 일치

        #expect(!state.agrees(with: read, processID: 42))
    }

    // MARK: - 트래커 수명 (`validated` / `apply`)

    @Test("검증 통과는 상태를 유지하고 그대로 돌려준다")
    func validationSuccessKeepsState() {
        let state = charwiseState(side: .left, pinnedEnd: 3)
        let tracker = VisualAnchorTracker(state: state)

        let validated = tracker.validated(
            against: focusedText("ab\ncd", caret: 3, length: 2), processID: 42)

        #expect(validated == state)
        #expect(tracker.current == state)
    }

    /// 검증 실패 = **즉시 폐기 + nil** — 그 액션부터 무상태 폴백이고, 다음 액션은 상태가
    /// 없으므로 읽기 자체를 생략한다(hasState가 그 값싼 확인이다).
    @Test("검증 실패는 상태를 즉시 폐기한다")
    func validationFailureDiscardsState() {
        let tracker = VisualAnchorTracker(state: charwiseState(side: .left, pinnedEnd: 3))

        let validated = tracker.validated(
            against: focusedText("ab\ncd", caret: 1, length: 2), processID: 42)

        #expect(validated == nil)
        #expect(tracker.current == nil)
        #expect(!tracker.hasState)
    }

    @Test("apply — unchanged는 유지, set은 교체, discard는 삭제")
    func applyLifecycle() {
        let initial = charwiseState(side: .left, pinnedEnd: 3)
        let reanchored = charwiseState(side: .right, pinnedEnd: 4)
        let tracker = VisualAnchorTracker(state: initial)

        tracker.apply(.unchanged)
        #expect(tracker.current == initial)

        tracker.apply(.set(reanchored))
        #expect(tracker.current == reanchored)

        tracker.apply(.discard)
        #expect(tracker.current == nil)
    }

    @Test("상태 없는 트래커 — hasState false, 검증은 nil")
    func emptyTrackerHasNoState() {
        let tracker = VisualAnchorTracker()

        #expect(!tracker.hasState)
        #expect(
            tracker.validated(against: focusedText("ab", caret: 0, length: 1), processID: 42)
                == nil)
    }
}

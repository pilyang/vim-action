//
//  ExecutionAbortLatchTests.swift
//  VimActionTests
//

import Testing
@testable import VimAction

/// 실행 중단 래치의 계약 — "실행 1건은 자기가 최신인 동안에만 유효하다".
///
/// 세대 카운터를 쓰는 이유가 여기 드러난다: 무효화 주체(킬스위치·토글 off·새 입력)가
/// 해제 시점을 몰라도 되고, 해제 API가 없으므로 **해제를 빠뜨려 영구 보류되는** 킬 요청
/// 래치식 고장이 원리적으로 없다.
struct ExecutionAbortLatchTests {
    @Test("시작한 실행은 곧바로 최신이다")
    func newRunIsCurrent() {
        let latch = ExecutionAbortLatch()

        let run = latch.beginRun()

        #expect(latch.isCurrent(run))
    }

    /// 새 실행이 이전 실행을 밀어낸다 — 사용자가 버스트 도중 다음 키를 누른 경우다.
    @Test("새 실행이 시작되면 이전 실행은 무효가 된다")
    func laterRunSupersedesEarlier() {
        let latch = ExecutionAbortLatch()

        let first = latch.beginRun()
        let second = latch.beginRun()

        #expect(!latch.isCurrent(first))
        #expect(latch.isCurrent(second))
    }

    /// 킬스위치·토글 off·결정을 만들지 않는 사용자 키(passthrough/swallow)의 경로다 —
    /// 새 실행을 시작하지 않고 진행 중인 것만 끊는다.
    @Test("invalidate는 새 실행 없이 진행 중인 실행을 끊는다")
    func invalidateStopsRunningWork() {
        let latch = ExecutionAbortLatch()
        let run = latch.beginRun()

        latch.invalidate()

        #expect(!latch.isCurrent(run))
    }

    /// 무효화는 **누적되지 않는다** — 한 번 밀려난 실행은 몇 번을 더 무효화해도 그대로
    /// 무효이고, 그 뒤에 시작한 실행은 정상적으로 최신이다 (해제 API가 없는데도 래치가
    /// "영구 잠김"이 되지 않는 이유).
    @Test("여러 번 무효화해도 다음 실행은 정상적으로 시작된다")
    func invalidationDoesNotLatchPermanently() {
        let latch = ExecutionAbortLatch()
        let stale = latch.beginRun()

        latch.invalidate()
        latch.invalidate()
        let fresh = latch.beginRun()

        #expect(!latch.isCurrent(stale))
        #expect(latch.isCurrent(fresh))
    }
}

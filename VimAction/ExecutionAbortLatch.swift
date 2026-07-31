//
//  ExecutionAbortLatch.swift
//  VimAction
//

import os

/// 실행 중단 래치 — 게시 중인 합성 이벤트 버스트를 도중에 끊는 신호.
///
/// 단계 0 실측이 남긴 문제를 푼다: 카운트 버스트(당시 `9999j`)는 수 초짜리 중단 불가 폭주이고, 그 사이 킬스위치는
/// "새 키 가로채기"만 막을 뿐 이미 게시된 이벤트는 끝까지 소진되며, 사용자가 끼워 넣은 타이핑은
/// 버스트 사이에 흩어져 문서를 오염시킨다 (`20260726_count-burst-abort-latch-promotion.md`).
///
/// **형태는 Bool 플래그가 아니라 세대 카운터다.** 실행 1건은 `beginRun()`으로 자기 세대를 받고,
/// 청크 사이마다 "내 세대가 아직 최신인가"를 묻는다. 새 실행이 시작되거나 누가 `invalidate()`를
/// 부르면 세대가 올라가 이전 실행들이 **전부** 한 번에 무효가 된다. 이 형태의 요점은
/// **해제(clear) API가 아예 없다**는 것이다 — 킬 요청 래치(`killSwitchRequested`)가 안고 있는
/// "해제를 빠뜨리면 영구 보류되는 조용한 고장"이라는 실패 모드가 구조적으로 존재하지 않는다.
/// Bool 플래그였다면 해제 규칙이 둘(다음 실행 시작 / 토글 on) 필요하고, 큰 버스트 뒤에 큰
/// 버스트가 큐잉된 경우 앞 버스트가 안 끊긴다.
///
/// 잠금이 필요한 이유는 `TapPortBox`와 같다 — 세우는 쪽에 킬 탭의 **전용 스레드**가 있어
/// 어떤 격리도 가정할 수 없다.
nonisolated final class ExecutionAbortLatch: Sendable {
    private let generation = OSAllocatedUnfairLock(initialState: UInt64(0))

    /// 실행 1건을 시작하고 그 세대를 받는다 — 이 시점에 이전 실행은 전부 무효가 된다.
    ///
    /// **게시 큐에 넣기 전(= 탭 콜백 스레드)에 불러야 한다.** 큐 안에서 부르면 이미 도는
    /// 버스트가 끝난 뒤에야 세대가 올라가 아무것도 끊지 못한다.
    func beginRun() -> UInt64 {
        generation.withLock { current in
            current += 1
            return current
        }
    }

    /// 진행 중인 실행을 전부 무효화한다 — 킬스위치·마스터 토글 off·새 사용자 입력.
    func invalidate() {
        generation.withLock { $0 += 1 }
    }

    /// 이 실행이 아직 최신인가. 어댑터가 청크 사이마다 묻는다.
    func isCurrent(_ run: UInt64) -> Bool {
        generation.withLock { $0 == run }
    }
}

//
//  FailureBurstCounter.swift
//  VimAction
//

import Foundation

/// 실행 실패 폭주 감지기 — 슬라이딩 창 안의 보고 수가 임계에 닿으면 트립한다.
/// 트립은 가로채기 자동 off로 이어진다 (버그가 사용자를 키보드에서 차단하는 최악의
/// 실패 모드를 시간 제한한다).
///
/// 시간은 주입받는 순수 타입이다 — `watchdogTick`과 같은 이유로, 판정만 분리해야 실제
/// 시계를 기다리지 않고 창 경계를 단위 테스트할 수 있다. 상태를 가지므로 단일 격리
/// (컨트롤러의 MainActor) 안에서만 쓴다.
struct FailureBurstCounter {
    /// 창 길이(초)와 임계 횟수 — "1초 안에 5회"가 기본값이다. 실사용 데이터에 따라
    /// 조정할 여지를 남겨 상수로 둔다.
    static let defaultWindow: TimeInterval = 1
    static let defaultThreshold = 5

    private let window: TimeInterval
    private let threshold: Int
    /// 창 안에 남은 보고 시각들 — 오름차순(보고가 단조 증가하는 시각으로 들어온다).
    private var reports: [TimeInterval] = []

    init(window: TimeInterval = defaultWindow, threshold: Int = defaultThreshold) {
        self.window = window
        self.threshold = threshold
    }

    /// 실패 1건 보고. 창 안 누적이 임계에 닿으면 `true`(트립)를 돌려주고 창을 비운다 —
    /// 비우지 않으면 트립 후 들어오는 보고마다 같은 이력으로 재트립한다.
    mutating func record(at now: TimeInterval) -> Bool {
        reports.removeAll { now - $0 >= window }
        reports.append(now)
        guard reports.count >= threshold else { return false }
        reports.removeAll()
        return true
    }
}

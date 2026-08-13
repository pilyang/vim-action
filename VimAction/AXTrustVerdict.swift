//
//  AXTrustVerdict.swift
//  VimAction
//

import VimActionConfig

/// `strategy: auto` 앱을 AX로 라우팅해도 되는가 — 프로브의 판정값.
///
/// **default-deny다**: 판정 계층을 전부 통과한 앱만 `.trusted`가 되고, 아직 프로브가 돌지
/// 않았거나(`.pending`) 어느 계층에서든 탈락하면(`.untrusted`) keyboard로 돈다. 둘 다 완전
/// 기능이라 auto는 "점진 강화"이지 "실패하면 무동작"이 아니다.
///
/// 판정을 만들고 캐시하는 협력자(pid 키·프로브 큐·런타임 강등)는 **PR-D2 세션 2·3 몫**이라
/// 아직 없다 — 지금은 모든 앱이 `.pending`이고, 그래서 이 세션의 auto는 예외 없이 keyboard로
/// 접힌다. 판정 계층·수명·강등 규칙의 SSOT는 architecture `strategy-dispatch.md`의
/// auto 프로브 섹션이다 (`20260813_auto-probe-async-cached-verdict-pid-lifetime.md`).
nonisolated enum AXTrustVerdict: Hashable, Sendable, CaseIterable {
    /// 아직 프로브가 판정하지 않았다 — 캐시 부재.
    case pending
    /// 판정 계층을 전부 통과했다.
    case trusted
    /// 어느 계층에서 탈락했거나 런타임 증거로 강등됐다.
    case untrusted
}

/// 선언된 전략과 판정을 **실효 전략**으로 접는다 — 실행 계층이 보는 유일한 전략값이다.
///
/// `.auto`를 실행 계층까지 흘리지 않는 것이 요점이다: 흘리면 전략을 보는 모든 자리가 판정
/// 조회를 다시 해야 하고, 조회 시점이 갈리면 한 버스트 안에서 라우팅이 바뀔 수 있다. 접기는
/// 콜백 스냅샷 1회이고 결과는 `DispatchContext`가 나른다.
///
/// **명시 전략은 판정을 보지 않는다** — `accessibility`는 사용자가 "이 앱은 AX로 하라"고 쓴
/// 것이라 프로브가 뒤집을 대상이 아니고(거부 목록도 auto 판정에만 적용된다), `keyboard`도
/// 마찬가지다. 판정이 값을 바꾸는 유일한 입력은 `auto`다.
nonisolated func effectiveStrategy(
    _ declared: ProfileStrategy, verdict: AXTrustVerdict
) -> ProfileStrategy {
    switch declared {
    case .accessibility, .keyboard:
        return declared
    case .auto:
        switch verdict {
        case .trusted: return .accessibility
        case .pending, .untrusted: return .keyboard
        }
    }
}

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

/// auto 신뢰 **거부 목록** — 프로브의 계층 1. 코드 상수이며 YAML에 노출하지 않는다.
///
/// 등재 기준은 "프로브 신호(요소·읽기·settable 실증)가 잡지 못함이 **실측된** 거짓말 앱"이다 —
/// Notion은 읽기·쓰기 프리미티브가 전부 정상(왕복 15/15)인데 거짓말이 신호 사각(블록 넘는
/// 선택 미보고·visible 오보)에 있어, 목록이 프로브와 중복이 아니라 빈틈을 메운다. 목록 앱은
/// AX 접촉 없이 즉시 untrusted·재시도 없음이고, **auto 판정에만 적용된다** — 명시
/// `strategy: accessibility`는 목록과 무관하게 이긴다 (`20260813_ax-trust-deny-list-code-constant.md`).
nonisolated let axTrustDenyList: Set<String> = ["notion.id"]

/// 프로브 판정의 **탈락 계층** — 판정 전이 로그에 실려 거부 목록 성장·기본값 전환 게이트의
/// 판정 데이터가 된다 (`20260813_auto-trusted-runtime-demotion-and-observability.md`).
nonisolated enum AXTrustProbeLayer: Hashable, Sendable, CaseIterable {
    /// 계층 1 — 거부 목록. AX 접촉 없이 갈리므로 `classifyAXTrustProbe`의 입력이 아니라
    /// 트리거 판정(`AXTrustProber.probeDecision`)이 낸다.
    case denyList
    /// 계층 2 — 요소 실증 (포커스 요소 존재 + `AXSelectedTextRange` 노출).
    case element
    /// 계층 3 — 읽기·쓰기 가능성 실증 (3프리미티브 읽기 + settable).
    case readWrite
}

/// 프로브가 한 번의 수집에서 모은 신호 — **Bool만 싣는다.**
///
/// 창 읽기(`AXStringForRange`)의 본문을 여기 싣지 않는 것이 계약이다: 판정 전이 로그는
/// 릴리스에서 생존하는 `.info`인데, 신호가 Bool뿐이면 창 본문이 로그로 새는 경로가
/// 타입 수준에서 막힌다.
///
/// 계층 2의 신호를 **리졸버 family 값에서 가져오지 않는 것도 계약이다** — family의 실패
/// 폴백은 `.textArea`(허용 방향)라 재사용하면 요소 미노출 앱이 통과한다. 같은 검사를
/// default-deny 방향으로 다시 한다 (`20260813_ax-lie-detection-read-attestation-settable.md`).
nonisolated struct AXTrustProbeSignals: Hashable, Sendable {
    /// `AXRead.focusedElement`가 요소를 돌려줬는가.
    var focusedElementFound = false
    /// 속성 **이름 목록**에 `AXSelectedTextRange`가 있는가 (값 조회는 판별자가 못 된다 —
    /// Finder도 `.success`를 돌려준다. 리졸버 분류와 같은 실측 근거).
    var exposesSelectedTextRange = false
    /// 실행 경로가 실제로 소비할 읽기(`selectedRange` 값 + `characterCount` +
    /// `StringForRange` 창)가 **한 번의 왕복으로** 전부 성공했는가.
    var readsSucceeded = false
    /// `AXUIElementIsAttributeSettable(AXSelectedTextRange)` — 값을 바꾸지 않는 쓰기 축.
    /// 읽기 전용이지만 선택 가능한 뷰(Mail 본문·PDF·콘솔류)를 무돌연변이로 가른다.
    var selectedTextRangeSettable = false

    /// 계층 2 탈락인가 — Electron 트리 기상(`AXManualAccessibility`)의 발동 조건이다
    /// (`20260813_electron-tree-wake-on-probe-failure.md`).
    var failsElementAttestation: Bool {
        !focusedElementFound || !exposesSelectedTextRange
    }

    /// 콜드 형태 실패인가 — 유계 재시도(~200ms×2)의 대상이다. 요소 없음·미노출·읽기 실패는
    /// 잠든 트리·콜드 웜업에서 일시적일 수 있지만(PR-A 실측: 재시도 2~3회), **settable=false
    /// 단독은 확정 답변**이라 재시도하지 않는다.
    var isColdFormFailure: Bool {
        failsElementAttestation || !readsSucceeded
    }
}

/// 수집된 신호 → 판정 — **default-deny 순수 함수**다. 전부 통과해야 trusted이고,
/// 탈락 계층은 판정 전이 로그의 재료다.
///
/// 값을 바꾸는 쓰기 왕복은 신호에 없다 — 진짜 적용 검증은 값 변경이 필요해 캐럿 이동·활성
/// 선택 파괴·IME 개입·타이핑 레이스가 전부 프로브 위험이 된다. settable=true가 적용까지
/// 보장하지 않는 잔여 축은 런타임(되읽어 검증 + 세션 3의 강등)이 담당한다
/// (`20260813_ax-lie-detection-read-attestation-settable.md`).
nonisolated func classifyAXTrustProbe(
    _ signals: AXTrustProbeSignals
) -> (verdict: AXTrustVerdict, failedLayer: AXTrustProbeLayer?) {
    if signals.failsElementAttestation { return (.untrusted, .element) }
    if !signals.readsSucceeded || !signals.selectedTextRangeSettable {
        return (.untrusted, .readWrite)
    }
    return (.trusted, nil)
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

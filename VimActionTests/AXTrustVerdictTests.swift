import Testing
import VimActionConfig

@testable import VimAction

/// 실효 전략 접기 — `(선언된 전략, 판정) → 실행이 타는 전략`.
///
/// 표를 전수로 도는 것이 계약이다: 어휘가 늘면(전략이든 판정이든) 여기서 "어느 편인가"를
/// 반드시 결정하게 된다.
@Suite("실효 전략 접기")
struct EffectiveStrategyTests {
    /// 전략 × 판정 전수 표. 기대값이 곧 결정 문언이다.
    static let table: [(ProfileStrategy, AXTrustVerdict, ProfileStrategy)] = [
        // 명시 전략은 판정을 보지 않는다 — 프로브가 사용자 지시를 뒤집지 않는다.
        (.accessibility, .pending, .accessibility),
        (.accessibility, .trusted, .accessibility),
        (.accessibility, .untrusted, .accessibility),
        (.keyboard, .pending, .keyboard),
        (.keyboard, .trusted, .keyboard),
        (.keyboard, .untrusted, .keyboard),
        // auto만 판정이 값을 바꾼다. default-deny — trusted만 AX다.
        (.auto, .trusted, .accessibility),
        (.auto, .pending, .keyboard),
        (.auto, .untrusted, .keyboard),
    ]

    @Test("접기 표", arguments: table)
    func folds(declared: ProfileStrategy, verdict: AXTrustVerdict, expected: ProfileStrategy) {
        #expect(effectiveStrategy(declared, verdict: verdict) == expected)
    }

    /// 실행 계층은 `.auto`를 모른다 — 접기가 그 값을 소비하는 유일한 지점이라는 계약.
    @Test("접힌 전략에 auto는 없다")
    func neverReturnsAuto() {
        for declared in ProfileStrategy.allCases {
            for verdict in AXTrustVerdict.allCases {
                #expect(effectiveStrategy(declared, verdict: verdict) != .auto)
            }
        }
    }

    /// 표가 실제로 전수인지 — 케이스가 늘면 이 단언이 먼저 깨진다.
    @Test("표는 전략 × 판정 전수다")
    func tableIsExhaustive() {
        #expect(Self.table.count == ProfileStrategy.allCases.count * AXTrustVerdict.allCases.count)
    }
}

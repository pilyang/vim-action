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

/// 프로브 신호 → 판정 — default-deny 계층의 순수 함수 표.
///
/// 신호 4비트 **전수 16행**이다 (`AXWriteOutcome` 전수 스윕과 같은 규칙): 요소 실증
/// (found·exposes)이 먼저 갈리고, 그다음 읽기·쓰기 실증(reads·settable), 전부 참일 때만
/// trusted다. 계층 1(거부 목록)은 AX 접촉 전에 갈리므로 이 함수의 입력이 아니다.
@Suite("프로브 판정 계층")
struct AXTrustProbeClassificationTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var signals: AXTrustProbeSignals
        var verdict: AXTrustVerdict
        var layer: AXTrustProbeLayer?

        init(
            _ found: Bool, _ exposes: Bool, _ reads: Bool, _ settable: Bool,
            _ verdict: AXTrustVerdict, _ layer: AXTrustProbeLayer?
        ) {
            signals = AXTrustProbeSignals(
                focusedElementFound: found, exposesSelectedTextRange: exposes,
                readsSucceeded: reads, selectedTextRangeSettable: settable)
            self.verdict = verdict
            self.layer = layer
        }

        var testDescription: String {
            let bits = [
                signals.focusedElementFound, signals.exposesSelectedTextRange,
                signals.readsSucceeded, signals.selectedTextRangeSettable,
            ].map { $0 ? "T" : "F" }.joined()
            return "\(bits) → \(verdict)"
        }
    }

    static let table: [Row] = [
        // 요소 없음 — 나머지 신호와 무관하게 계층 2 탈락.
        Row(false, false, false, false, .untrusted, .element),
        Row(false, false, false, true, .untrusted, .element),
        Row(false, false, true, false, .untrusted, .element),
        Row(false, false, true, true, .untrusted, .element),
        Row(false, true, false, false, .untrusted, .element),
        Row(false, true, false, true, .untrusted, .element),
        Row(false, true, true, false, .untrusted, .element),
        Row(false, true, true, true, .untrusted, .element),
        // 요소는 있는데 `AXSelectedTextRange` 미노출 — 계층 2 탈락.
        Row(true, false, false, false, .untrusted, .element),
        Row(true, false, false, true, .untrusted, .element),
        Row(true, false, true, false, .untrusted, .element),
        Row(true, false, true, true, .untrusted, .element),
        // 요소 실증 통과, 읽기·쓰기 실증 탈락 — 계층 3.
        Row(true, true, false, false, .untrusted, .readWrite),
        Row(true, true, false, true, .untrusted, .readWrite),
        Row(true, true, true, false, .untrusted, .readWrite),
        // 전부 통과 — 유일한 trusted.
        Row(true, true, true, true, .trusted, nil),
    ]

    @Test("판정 표", arguments: table)
    func classifies(row: Row) {
        let result = classifyAXTrustProbe(row.signals)
        #expect(result.verdict == row.verdict)
        #expect(result.failedLayer == row.layer)
    }

    @Test("표는 신호 4비트 전수다")
    func tableIsExhaustive() {
        #expect(Self.table.count == 16)
        #expect(Set(Self.table.map(\.signals)).count == 16)
    }

    /// 유계 재시도의 대상 판정 — **settable=false 단독은 확정 답변이라 재시도하지 않는다.**
    /// 요소 없음·미노출·읽기 실패는 잠든 트리·콜드 웜업의 일시 상태일 수 있어 재시도 대상이다.
    @Test("콜드 형태 실패 술어")
    func coldFormFailure() {
        #expect(
            AXTrustProbeSignals(
                focusedElementFound: false, exposesSelectedTextRange: false,
                readsSucceeded: false, selectedTextRangeSettable: false
            ).isColdFormFailure, "요소 없음은 콜드 형태다")
        #expect(
            AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: false,
                readsSucceeded: false, selectedTextRangeSettable: false
            ).isColdFormFailure, "속성 미노출도 콜드 형태다")
        #expect(
            AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: true,
                readsSucceeded: false, selectedTextRangeSettable: true
            ).isColdFormFailure, "읽기 실패도 콜드 형태다")
        #expect(
            !AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: true,
                readsSucceeded: true, selectedTextRangeSettable: false
            ).isColdFormFailure, "settable=false 단독은 확정 답변 — 재시도 없음")
        #expect(
            !AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: true,
                readsSucceeded: true, selectedTextRangeSettable: true
            ).isColdFormFailure, "전부 통과는 실패가 아니다")
    }
}

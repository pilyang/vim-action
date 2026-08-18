import CoreGraphics
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

/// 메뉴 "Strategy:" 줄 — `(선언된 전략, 판정) → 표시 문구`. 접기(`effectiveStrategy`)와
/// 입력 공간이 같지만 출력이 셋으로 갈린다: 접기는 pending과 untrusted를 둘 다 keyboard로
/// 접어 "판정 중"을 표현할 수 없다 — 이 함수가 접기 재사용이 아닌 이유가 곧 표의 존재
/// 이유다 (`20260813_auto-trusted-runtime-demotion-and-observability.md` 메뉴바 표시).
@Suite("메뉴 전략 표시 문구")
struct StrategyStatusTextTests {
    /// 전략 × 판정 전수 표 — `EffectiveStrategyTests`와 같은 규칙.
    static let table: [(ProfileStrategy, AXTrustVerdict, String)] = [
        // 명시 전략은 판정을 보지 않는다 — 접기와 같은 규칙.
        (.accessibility, .pending, "Strategy: AX"),
        (.accessibility, .trusted, "Strategy: AX"),
        (.accessibility, .untrusted, "Strategy: AX"),
        (.keyboard, .pending, "Strategy: Keyboard"),
        (.keyboard, .trusted, "Strategy: Keyboard"),
        (.keyboard, .untrusted, "Strategy: Keyboard"),
        // auto만 셋으로 갈린다 — pending이 "판정 중"이다.
        (.auto, .pending, "Strategy: probing…"),
        (.auto, .trusted, "Strategy: AX"),
        (.auto, .untrusted, "Strategy: Keyboard"),
    ]

    @Test("표시 표", arguments: table)
    func renders(declared: ProfileStrategy, verdict: AXTrustVerdict, expected: String) {
        #expect(strategyStatusText(declared: declared, verdict: verdict) == expected)
    }

    @Test("표는 전략 × 판정 전수다")
    func tableIsExhaustive() {
        #expect(Self.table.count == ProfileStrategy.allCases.count * AXTrustVerdict.allCases.count)
    }
}

/// 프로브 신호 → 판정 — default-deny 계층의 순수 함수 표.
///
/// 신호 5비트 **전수 32행**이다 (`AXWriteOutcome` 전수 스윕과 같은 규칙): 요소 실증
/// (found·exposes)이 먼저 갈리고, 그다음 요소 기하(extent), 그다음 읽기·쓰기 실증
/// (reads·settable), 전부 참일 때만 trusted다. 계층 1(거부 목록·브라우저 클래스)은 AX 접촉
/// 전에 갈리므로 이 함수의 입력이 아니다.
@Suite("프로브 판정 계층")
struct AXTrustProbeClassificationTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var signals: AXTrustProbeSignals
        var verdict: AXTrustVerdict
        var layer: AXTrustProbeLayer?

        init(
            _ found: Bool, _ exposes: Bool, _ extent: Bool, _ reads: Bool, _ settable: Bool,
            _ verdict: AXTrustVerdict, _ layer: AXTrustProbeLayer?
        ) {
            signals = AXTrustProbeSignals(
                focusedElementFound: found, exposesSelectedTextRange: exposes,
                hasVisibleExtent: extent, readsSucceeded: reads,
                selectedTextRangeSettable: settable)
            self.verdict = verdict
            self.layer = layer
        }

        var testDescription: String {
            let bits = [
                signals.focusedElementFound, signals.exposesSelectedTextRange,
                signals.hasVisibleExtent, signals.readsSucceeded,
                signals.selectedTextRangeSettable,
            ].map { $0 ? "T" : "F" }.joined()
            return "\(bits) → \(verdict)"
        }
    }

    /// 계층 순서를 코드로 편 표 — 32행을 손으로 쓰지 않고 **같은 규칙을 다른 모양으로**
    /// 두 번 적어(여기는 계층별 열거, 판정 함수는 순차 guard) 서로를 검증한다.
    static let table: [Row] = {
        var rows: [Row] = []
        for found in [false, true] {
            for exposes in [false, true] {
                for extent in [false, true] {
                    for reads in [false, true] {
                        for settable in [false, true] {
                            let expected: (AXTrustVerdict, AXTrustProbeLayer?)
                            if !found || !exposes {
                                // 요소 없음·`AXSelectedTextRange` 미노출 — 나머지 신호와 무관하게 계층 2.
                                expected = (.untrusted, .element)
                            } else if !extent {
                                // 요소는 실증됐지만 숨은 입력(짧은 변 < 임계) — 계층 3.
                                expected = (.untrusted, .geometry)
                            } else if !reads || !settable {
                                // 읽기·쓰기 실증 탈락 — 계층 4.
                                expected = (.untrusted, .readWrite)
                            } else {
                                // 전부 통과 — 유일한 trusted.
                                expected = (.trusted, nil)
                            }
                            rows.append(
                                Row(found, exposes, extent, reads, settable, expected.0, expected.1))
                        }
                    }
                }
            }
        }
        return rows
    }()

    @Test("판정 표", arguments: table)
    func classifies(row: Row) {
        let result = classifyAXTrustProbe(row.signals)
        #expect(result.verdict == row.verdict)
        #expect(result.failedLayer == row.layer)
    }

    @Test("표는 신호 5비트 전수다")
    func tableIsExhaustive() {
        #expect(Self.table.count == 32)
        #expect(Set(Self.table.map(\.signals)).count == 32)
        #expect(Self.table.filter { $0.verdict == .trusted }.count == 1, "trusted는 한 모양뿐")
    }

    /// 실측 두 점이 임계 양쪽에 있다: Docs 숨은 contenteditable 625×1(거짓말), VS Code Monaco
    /// 800×23(정직). 임계는 짧은 변 기준이라 폭이 넓어도 높이 1pt면 걸린다.
    @Test(
        "기하 판별 — 짧은 변 임계",
        arguments: [
            (CGSize(width: 625, height: 1), false),
            (CGSize(width: 800, height: 23), true),
            (CGSize(width: 0, height: 0), false),
            (CGSize(width: 1, height: 1), false),
            (CGSize(width: 3.9, height: 300), false),
            (CGSize(width: 4, height: 4), true),
            (CGSize(width: 300, height: 16), true),
        ])
    func extentThreshold(size: CGSize, visible: Bool) {
        #expect(AXTrustProbeSignals.extentIsVisible(size) == visible)
    }

    /// 유계 재시도의 대상 판정 — **settable=false 단독은 확정 답변이라 재시도하지 않는다.**
    /// 요소 없음·미노출·읽기 실패는 잠든 트리·콜드 웜업의 일시 상태일 수 있어 재시도 대상이다.
    @Test("콜드 형태 실패 술어")
    func coldFormFailure() {
        #expect(
            AXTrustProbeSignals(
                focusedElementFound: false, exposesSelectedTextRange: false,
                hasVisibleExtent: false, readsSucceeded: false, selectedTextRangeSettable: false
            ).isColdFormFailure, "요소 없음은 콜드 형태다")
        #expect(
            AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: false,
                hasVisibleExtent: true, readsSucceeded: false, selectedTextRangeSettable: false
            ).isColdFormFailure, "속성 미노출도 콜드 형태다")
        #expect(
            AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: true,
                hasVisibleExtent: true, readsSucceeded: false, selectedTextRangeSettable: true
            ).isColdFormFailure, "읽기 실패도 콜드 형태다")
        #expect(
            !AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: true,
                hasVisibleExtent: true, readsSucceeded: true, selectedTextRangeSettable: false
            ).isColdFormFailure, "settable=false 단독은 확정 답변 — 재시도 없음")
        #expect(
            !AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: true,
                hasVisibleExtent: false, readsSucceeded: true, selectedTextRangeSettable: true
            ).isColdFormFailure, "숨은 입력(기하 탈락) 단독도 확정 답변 — 잠든 트리는 1pt로 나타나지 않는다")
        #expect(
            !AXTrustProbeSignals(
                focusedElementFound: true, exposesSelectedTextRange: true,
                hasVisibleExtent: true, readsSucceeded: true, selectedTextRangeSettable: true
            ).isColdFormFailure, "전부 통과는 실패가 아니다")
    }
}

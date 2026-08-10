//
//  AXWriteEffectsTests.swift
//  VimActionTests
//

import Foundation
import Testing
import VimEngine

@testable import VimAction

/// 요약 로그의 대상이 되는 아무 액션 — 효과 지점은 액션을 **첫 1개만** 요약에 싣고 판정에는
/// 쓰지 않으므로, 어떤 액션인지는 이 파일의 단언과 무관하다.
private let anyAction = VimAction.move(.charLeft)

/// `AXWriteOutcome`이 값으로 낸 소비자 행동이 실제 효과가 되는 지점의 계약.
///
/// **보고 seam 호출 여부/횟수로 단언한다** — 내용 비교가 아니다. 요약 로그(os.Logger)는
/// 단언할 수 없으므로 버킷 분리는 `count(of:)`로 본다.
struct AXWriteEffectsTests {
    @Test("`.failure` 1건 → 보고 seam 1회")
    func failureReportsOnce() {
        nonisolated(unsafe) var reports: [TimeInterval] = []
        var effects = AXWriteEffects(
            bundleID: "com.apple.TextEdit", report: { reports.append($0) }, now: { 3 })

        effects.apply(.failure, action: anyAction)
        effects.logSummary()

        #expect(reports.count == 1)
        #expect(effects.count(of: .failure) == 1)
    }

    /// 보고에 실리는 시각이 **게시 큐에서 캡처된 값**이라는 것 — 메인 홉이 뒤늦게 착지해도
    /// 그 착지 시각으로 세면 안 된다(뭉침 착지가 1초 창에 몰려 거짓 트립한다). 시계를 apply
    /// 뒤에 전진시켜, 실린 값이 캡처 시점 값임을 고정한다.
    @Test("보고 시각은 apply(= 게시 큐) 시점 캡처값 — 뒤에 시계가 전진해도 그대로")
    func reportCarriesCaptureTime() {
        nonisolated(unsafe) var clock: TimeInterval = 5
        nonisolated(unsafe) var reports: [TimeInterval] = []
        var effects = AXWriteEffects(
            bundleID: nil, report: { reports.append($0) }, now: { clock })

        effects.apply(.failure, action: anyAction)
        clock = 99  // 메인 홉이 한참 뒤에 착지하는 상황의 등가.
        effects.logSummary()

        #expect(reports == [5])
    }

    /// **보고 케이스는 `.failure` 하나뿐**이라는 default-deny의 실행 측 절반. `CaseIterable`
    /// 스윕이라 클래스가 늘면 자동으로 여기 들어온다 — 새 케이스가 조용히 보고로 흘러들 수 없다.
    @Test(
        "비보고 클래스 전수: 보고 seam 무호출",
        arguments: AXWriteOutcome.allCases.filter { $0 != .failure })
    func nonFailureOutcomesNeverReport(outcome: AXWriteOutcome) {
        nonisolated(unsafe) var reports = 0
        var effects = AXWriteEffects(
            bundleID: "com.apple.TextEdit", report: { _ in reports += 1 }, now: { 0 })

        effects.apply(outcome, action: anyAction)
        effects.logSummary()

        #expect(reports == 0)
        #expect(effects.count(of: outcome) == 1)
    }

    /// "보고는 원인 키 입력 1건당 최대 1회"(`20260726`)를 **구조로** 고정한다 — 인스턴스 수명이
    /// 곧 execute 1회이므로, 같은 execute의 실패가 여럿이어도 카운터에는 1건만 들어간다.
    @Test("한 execute의 실패 3건은 보고 1회로 접힌다 (집계는 3)")
    func repeatedFailuresFoldIntoOneReport() {
        nonisolated(unsafe) var reports: [TimeInterval] = []
        var effects = AXWriteEffects(
            bundleID: nil, report: { reports.append($0) }, now: { 1 })

        for _ in 0..<3 { effects.apply(.failure, action: anyAction) }
        effects.logSummary()

        #expect(reports.count == 1)
        #expect(effects.count(of: .failure) == 3)
    }

    /// 새 execute = 새 인스턴스 = 새 보고. 접기의 단위가 execute라는 것의 반대편 증거다.
    @Test("인스턴스가 갈리면(= 키 입력이 갈리면) 보고도 갈린다")
    func separateExecutesReportSeparately() {
        nonisolated(unsafe) var reports: [TimeInterval] = []
        let report: @Sendable (TimeInterval) -> Void = { reports.append($0) }

        var first = AXWriteEffects(bundleID: nil, report: report, now: { 1 })
        first.apply(.failure, action: anyAction)
        var second = AXWriteEffects(bundleID: nil, report: report, now: { 2 })
        second.apply(.failure, action: anyAction)

        #expect(reports == [1, 2])
    }

    /// 미지원 스킵과 경합 스킵이 **서로도, 다른 클래스와도** 섞이지 않는다 — 섞이면 앱의 정적
    /// 성질(강등 신호)과 일시적 경합을 심사자가 구분하지 못한다.
    @Test("스킵 2종은 전용 버킷으로 갈려 집계된다")
    func skipBucketsStaySeparate() {
        var effects = AXWriteEffects(bundleID: "com.apple.TextEdit", report: { _ in }, now: { 0 })

        effects.apply(.unsupportedSkip, action: anyAction)
        effects.apply(.unsupportedSkip, action: anyAction)
        effects.apply(.contentionSkip, action: anyAction)
        effects.apply(.illegalArgument, action: anyAction)
        effects.logSummary()

        #expect(effects.count(of: .unsupportedSkip) == 2)
        #expect(effects.count(of: .contentionSkip) == 1)
        #expect(effects.count(of: .illegalArgument) == 1)
        #expect(effects.count(of: .success) == 0)
        #expect(effects.count(of: .failure) == 0)
    }

    /// 되읽어 검증 불일치는 **`AXWriteOutcome` 밖의 전용 버킷**이다 — 그 enum은 `AXError`
    /// 분류표 그 자체이고 검증 불일치는 `AXError`가 아니다(쓰기는 `.success`였다). 보고로도
    /// 새지 않는다: 파괴 단계는 시도 전이다.
    @Test("검증 불일치 버킷은 분류표와도 보고와도 섞이지 않는다")
    func verifyMismatchStaysOutOfOutcomeTable() {
        nonisolated(unsafe) var reports = 0
        var effects = AXWriteEffects(
            bundleID: "com.apple.TextEdit", report: { _ in reports += 1 }, now: { 0 })

        effects.apply(.success, action: anyAction)
        effects.noteVerifyMismatch(action: anyAction)
        effects.noteVerifyMismatch(action: anyAction)
        effects.logSummary()

        #expect(effects.verifyMismatchCount == 2)
        #expect(reports == 0, "쓰기는 `.success`였고 파괴는 시도 전이다")
        #expect(AXWriteOutcome.allCases.allSatisfy { effects.count(of: $0) == ($0 == .success ? 1 : 0) })
    }

    /// 어댑터가 실제로 seam을 들고 효과 지점을 만든다는 유일한 증거 — 세션 2의 드라이버는
    /// 이 팩토리로 인스턴스를 얻는다.
    @Test("어댑터의 팩토리가 만든 효과 지점은 주입된 보고 seam·시계를 쓴다")
    func adapterFactoryCarriesInjectedSeams() {
        nonisolated(unsafe) var reports: [TimeInterval] = []
        let adapter = KeyboardAdapter(
            reportExecutionFailure: { reports.append($0) }, now: { 7 })

        var effects = adapter.axWriteEffects(bundleID: "com.apple.TextEdit")
        effects.apply(.failure, action: anyAction)
        effects.logSummary()

        #expect(reports == [7])
    }
}

/// 효과 지점 → `EventTapController.reportExecutionFailure(at:)` → `FailureBurstCounter` 결합.
/// M2가 만들어 두고 실호출자가 없던 자동 차단 기계에 **첫 실호출자가 붙었다**는 것이 여기서
/// 고정된다 (`ExecutionFailureBurstTests`가 컨트롤러 쪽에서 보던 계약의 어댑터 쪽 절반).
@MainActor
struct AXWriteFailureReportWiringTests {
    /// 효과 지점의 보고를 컨트롤러에 직결한다 — 프로덕션에서는 `keyboardActionSink`가 같은
    /// 모양의 클로저를 꽂고 그 안에서 메인 홉만 한 겹 더 얹는다(시각은 이미 캡처돼 있다).
    private static func effects(
        controller: EventTapController, at capturedTime: TimeInterval
    ) -> AXWriteEffects {
        AXWriteEffects(
            bundleID: "com.apple.TextEdit",
            report: { failedAt in
                MainActor.assumeIsolated { controller.reportExecutionFailure(at: failedAt) }
            },
            now: { capturedTime })
    }

    @Test("게시 큐 캡처 시각 기준 1초 5회 → 가로채기 자동 off (기존 소프트 off 경로 재사용)")
    func fiveCapturedFailuresWithinWindowTrip() throws {
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)

            // 인스턴스 1개 = 키 입력 1건 — 접기 단위가 execute라 5건은 인스턴스 5개다.
            for i in 0..<5 {
                var effects = Self.effects(controller: controller, at: Double(i) * 0.1)
                effects.apply(.failure, action: anyAction)
                effects.logSummary()
            }

            #expect(controller.isInterceptionEnabled == false)
            // 존재 확인이 먼저 — `bool(forKey:)`는 미설정 키에도 false다.
            #expect(defaults.object(forKey: PreferenceKeys.interceptionEnabled) != nil)
            #expect(defaults.bool(forKey: PreferenceKeys.interceptionEnabled) == false)
        }
    }

    @Test("창 밖으로 흩어진 실패는 트립하지 않는다 — 0.3초 간격 20건")
    func spreadCapturedFailuresDoNotTrip() {
        withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)

            for i in 0..<20 {
                var effects = Self.effects(controller: controller, at: Double(i) * 0.3)
                effects.apply(.failure, action: anyAction)
            }

            #expect(controller.isInterceptionEnabled)
        }
    }

    /// 접기가 카운터까지 이어진다 — 한 키 입력의 실패 여러 건이 창을 혼자 채우지 못한다.
    /// (`100j`가 액션 100건으로 전개되는 구조에서 임계를 즉시 넘기던 축.)
    @Test("한 execute의 실패 10건은 카운터에 1건으로만 들어간다")
    func foldedReportsCountOnceInCounter() {
        withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)

            var effects = Self.effects(controller: controller, at: 0)
            for _ in 0..<10 { effects.apply(.failure, action: anyAction) }

            #expect(controller.isInterceptionEnabled)
        }
    }
}

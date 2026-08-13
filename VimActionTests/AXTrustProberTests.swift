//
//  AXTrustProberTests.swift
//  VimActionTests
//

import Foundation
import Testing
import VimActionConfig

@testable import VimAction

/// 격리된 `NotificationCenter` + no-op seam을 주입해 라이브 `NSWorkspace` 구독과 AX 접촉을
/// 둘 다 피한다 (`FocusedElementResolverTests`와 같은 규칙). `schedule` 기본값이 **드롭**인
/// 것이 요점이다 — 트리거 부기만 보는 테스트가 실수로 프로브 본체를 돌리지 않는다.
@MainActor
private func makeProber(
    collect: @escaping @Sendable (pid_t) -> AXTrustProbeSignals = { _ in AXTrustProbeSignals() },
    wake: @escaping @Sendable (pid_t) -> Void = { _ in },
    schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { _ in }
) -> AXTrustProber {
    AXTrustProber(
        notificationCenter: NotificationCenter(), collectSignals: collect, wakeTree: wake,
        coldRetryPause: {}, schedule: schedule)
}

/// 전 계층 통과 신호 — trusted의 유일한 모양.
private let trustedSignals = AXTrustProbeSignals(
    focusedElementFound: true, exposesSelectedTextRange: true, readsSucceeded: true,
    selectedTextRangeSettable: true)

/// 요소 실증(계층 2) 탈락 신호 — 기상·재시도가 걸리는 모양.
private let elementFailureSignals = AXTrustProbeSignals()

/// 트리거 판정 — 순수 함수 표 (게이트 `isDisabled`와 같은 부류, 캐시와 무관하게 검증한다).
@Suite("auto 프로브 트리거 판정")
struct ProbeDecisionTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var declared: ProfileStrategy
        var denyListed = false
        var verdict: AXTrustVerdict = .pending
        var reArmed = false
        var reProbeCount = 0
        var inFlight = false
        var overrideLogged = false
        var expected: AXTrustProber.ProbeDecision

        var testDescription: String { name }
    }

    static let table: [Row] = [
        // 명시 전략은 프로브 대상이 아니다 — 판정도 안 보고(접기), 프로브도 없다.
        Row(name: "명시 keyboard", declared: .keyboard, expected: .none),
        Row(name: "명시 keyboard + 거부 목록", declared: .keyboard, denyListed: true, expected: .none),
        Row(name: "명시 accessibility", declared: .accessibility, expected: .none),
        // 명시 accessibility + 거부 목록 — 사용자 지시가 이기고, 관측만 1회 남긴다.
        Row(
            name: "명시 accessibility + 거부 목록 → override 관측",
            declared: .accessibility, denyListed: true, expected: .logDenyListOverride),
        Row(
            name: "override 관측은 1회뿐",
            declared: .accessibility, denyListed: true, overrideLogged: true, expected: .none),
        // 거부 목록 auto — AX 접촉 없이 즉시 untrusted, 반복 apply 없음.
        Row(
            name: "거부 목록 auto는 즉시 untrusted",
            declared: .auto, denyListed: true, expected: .applyDenyListVerdict),
        Row(
            name: "거부 목록 판정은 반복하지 않는다",
            declared: .auto, denyListed: true, verdict: .untrusted, expected: .none),
        // auto의 프로브 수명.
        Row(name: "pending 첫 디스패치는 프로브", declared: .auto, expected: .probe),
        Row(name: "in-flight 중 중복 없음", declared: .auto, inFlight: true, expected: .none),
        Row(name: "trusted는 sticky — 재확인 왕복 없음", declared: .auto, verdict: .trusted, expected: .none),
        Row(
            name: "untrusted는 재장전 없이 재프로브 없음",
            declared: .auto, verdict: .untrusted, expected: .none),
        Row(
            name: "재장전된 untrusted는 재프로브",
            declared: .auto, verdict: .untrusted, reArmed: true, expected: .probe),
        Row(
            name: "재장전돼도 상한 도달이면 중단",
            declared: .auto, verdict: .untrusted, reArmed: true,
            reProbeCount: AXTrustProber.reProbeAttemptCap, expected: .none),
        Row(
            name: "재장전돼도 in-flight면 중복 없음",
            declared: .auto, verdict: .untrusted, reArmed: true, inFlight: true, expected: .none),
    ]

    @Test("판정 표", arguments: table)
    func decides(row: Row) {
        let decision = AXTrustProber.probeDecision(
            declaredStrategy: row.declared, isDenyListed: row.denyListed, verdict: row.verdict,
            reArmed: row.reArmed, reProbeCount: row.reProbeCount, inFlight: row.inFlight,
            overrideLogged: row.overrideLogged)
        #expect(decision == row.expected)
    }
}

/// 프로브 1회의 동기 오케스트레이션 — 수집·기상·유계 재시도의 순서와 횟수.
@Suite("프로브 오케스트레이션")
struct RunProbeTests {
    @Test("첫 수집 성공이면 재시도도 기상도 없다")
    func succeedsFirstTry() {
        var collects = 0
        var wakes = 0
        let run = AXTrustProber.runProbe(
            processID: 1, alreadyWokeTree: false,
            collect: { _ in
                collects += 1
                return trustedSignals
            },
            wake: { _ in wakes += 1 }, retryPause: {})
        #expect(collects == 1)
        #expect(wakes == 0)
        #expect(run.wokeTree == false)
        #expect(classifyAXTrustProbe(run.signals).verdict == .trusted)
    }

    @Test("요소 실증 실패는 기상 1회 + 유계 재시도")
    func elementFailureWakesOnceAndRetries() {
        var collects = 0
        var wakes = 0
        let run = AXTrustProber.runProbe(
            processID: 1, alreadyWokeTree: false,
            collect: { _ in
                collects += 1
                return elementFailureSignals
            },
            wake: { _ in wakes += 1 }, retryPause: {})
        #expect(collects == 1 + AXTrustProber.coldRetryCount, "수집은 1 + 재시도 상한")
        #expect(wakes == 1, "기상은 재시도가 몇 번이든 1회다")
        #expect(run.wokeTree, "기상 사실이 결과에 실려 pid당 1회 부기가 된다")
        #expect(classifyAXTrustProbe(run.signals).failedLayer == .element)
    }

    @Test("재시도 중 성공하면 거기서 멈춘다 — 기상이 트리를 깨운 경로")
    func retrySucceedsAfterWake() {
        nonisolated(unsafe) var script = [elementFailureSignals, trustedSignals]
        var wakes = 0
        let run = AXTrustProber.runProbe(
            processID: 1, alreadyWokeTree: false,
            collect: { _ in script.removeFirst() },
            wake: { _ in wakes += 1 }, retryPause: {})
        #expect(script.isEmpty, "수집 2회 — 성공한 재시도에서 멈춘다")
        #expect(wakes == 1)
        #expect(classifyAXTrustProbe(run.signals).verdict == .trusted)
    }

    @Test("읽기 실패(요소는 실증됨)는 재시도하되 기상은 없다")
    func readFailureRetriesWithoutWake() {
        var collects = 0
        var wakes = 0
        let coldReads = AXTrustProbeSignals(
            focusedElementFound: true, exposesSelectedTextRange: true, readsSucceeded: false,
            selectedTextRangeSettable: true)
        _ = AXTrustProber.runProbe(
            processID: 1, alreadyWokeTree: false,
            collect: { _ in
                collects += 1
                return coldReads
            },
            wake: { _ in wakes += 1 }, retryPause: {})
        #expect(collects == 1 + AXTrustProber.coldRetryCount, "콜드 웜업 재시도는 산다")
        #expect(wakes == 0, "기상은 요소 실증 실패에만 걸린다")
    }

    @Test("settable=false 단독은 확정 답변 — 재시도 없음")
    func settableFalseDoesNotRetry() {
        var collects = 0
        let readOnly = AXTrustProbeSignals(
            focusedElementFound: true, exposesSelectedTextRange: true, readsSucceeded: true,
            selectedTextRangeSettable: false)
        let run = AXTrustProber.runProbe(
            processID: 1, alreadyWokeTree: false,
            collect: { _ in
                collects += 1
                return readOnly
            },
            wake: { _ in }, retryPause: {})
        #expect(collects == 1)
        #expect(classifyAXTrustProbe(run.signals).failedLayer == .readWrite)
    }

    @Test("이미 깨운 앱은 다시 깨우지 않는다 — pid당 1회의 나머지 절반")
    func alreadyWokenAppIsNotWokenAgain() {
        var wakes = 0
        let run = AXTrustProber.runProbe(
            processID: 1, alreadyWokeTree: true,
            collect: { _ in elementFailureSignals },
            wake: { _ in wakes += 1 }, retryPause: {})
        #expect(wakes == 0)
        #expect(run.wokeTree == false, "이번 실행이 깨운 것이 아니다")
    }
}

/// 판정 캐시 — 조회·트리거 부기·단조성·수명. 큐·알림 배선은 실기기 몫이고 여기서는
/// 갱신 진입점(`update`·`completeProbe`·`noteActivation`)을 직접 부른다
/// (`FocusedElementResolver.update`와 같은 분리).
@MainActor
@Suite("auto 판정 캐시")
struct AXTrustProberCacheTests {
    @Test("미지 pid·nil pid는 pending")
    func absentIsPending() {
        let prober = makeProber()
        #expect(prober.verdict(for: nil) == .pending)
        #expect(prober.verdict(for: 42) == .pending)
    }

    @Test("pending 첫 디스패치가 프로브를 1회만 큐에 얹는다")
    func firstDispatchEnqueuesOnce() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 1, "in-flight 중 연타 디스패치는 중복 enqueue가 없다")
        #expect(prober.verdict(for: 7) == .pending, "판정은 완료가 실어 온다")
    }

    @Test("pid·bundle id를 모르면 아무것도 하지 않는다")
    func missingIdentityDoesNothing() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(processID: nil, bundleID: "com.example", declaredStrategy: .auto)
        prober.noteReplaceDispatch(processID: 7, bundleID: nil, declaredStrategy: .auto)
        #expect(enqueued == 0)
    }

    @Test("명시 전략 앱은 프로브가 없다")
    func explicitStrategiesAreNotProbed() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(
            processID: 7, bundleID: "com.example", declaredStrategy: .keyboard)
        prober.noteReplaceDispatch(
            processID: 7, bundleID: "com.example", declaredStrategy: .accessibility)
        #expect(enqueued == 0)
        #expect(prober.verdict(for: 7) == .pending)
    }

    @Test("거부 목록 auto는 AX 접촉 없이 즉시 untrusted — 재장전 대상도 아니다")
    func denyListedAppIsImmediatelyUntrusted() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(processID: 7, bundleID: "notion.id", declaredStrategy: .auto)
        #expect(enqueued == 0, "프로브 없음 — 목록 판정은 AX 무접촉이다")
        #expect(prober.verdict(for: 7) == .untrusted)

        // 활성화 재장전은 목록 탈락에 안 걸린다 — 목록은 정적이라 재시도가 무의미하다.
        prober.noteActivation(processID: 7)
        prober.noteReplaceDispatch(processID: 7, bundleID: "notion.id", declaredStrategy: .auto)
        #expect(enqueued == 0)
    }

    @Test("명시 accessibility는 거부 목록보다 이긴다 — 프로브도 판정도 없다")
    func explicitAccessibilityBeatsDenyList() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(
            processID: 7, bundleID: "notion.id", declaredStrategy: .accessibility)
        prober.noteReplaceDispatch(
            processID: 7, bundleID: "notion.id", declaredStrategy: .accessibility)
        #expect(enqueued == 0)
        #expect(prober.verdict(for: 7) == .pending, "판정 캐시는 무접촉 — override는 관측만 남긴다")
    }

    @Test("완료가 판정을 싣고 in-flight를 푼다 — trusted는 sticky")
    func completionLandsVerdictAndTrustedSticks() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        prober.completeProbe(
            processID: 7, bundleID: "com.example", wokeTree: false, verdict: .trusted,
            failedLayer: nil, generation: prober.probeGeneration)
        #expect(prober.verdict(for: 7) == .trusted)

        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        prober.noteActivation(processID: 7)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 1, "trusted는 재확인 왕복이 없다 — 반증은 세션 3의 런타임 강등뿐")
    }

    @Test("untrusted는 활성화 재장전 후에만 재프로브하고, 상한이 총량을 자른다")
    func untrustedReProbesOnlyAfterActivationUpToCap() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        let fail = {
            prober.completeProbe(
                processID: 7, bundleID: "com.example", wokeTree: false, verdict: .untrusted,
                failedLayer: .element, generation: prober.probeGeneration)
        }
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        fail()
        #expect(enqueued == 1)

        // 재장전 없는 디스패치는 재프로브하지 않는다.
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 1)

        // 활성화 재장전 → 다음 디스패치가 재프로브. 상한까지만.
        for attempt in 1...AXTrustProber.reProbeAttemptCap {
            prober.noteActivation(processID: 7)
            prober.noteReplaceDispatch(
                processID: 7, bundleID: "com.example", declaredStrategy: .auto)
            #expect(enqueued == 1 + attempt)
            fail()
        }
        prober.noteActivation(processID: 7)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 1 + AXTrustProber.reProbeAttemptCap, "상한 도달 — 더는 재프로브 없음")
    }

    @Test("재장전은 소비된다 — 활성화 1회가 재프로브 1회다")
    func reArmIsConsumed() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        prober.completeProbe(
            processID: 7, bundleID: "com.example", wokeTree: false, verdict: .untrusted,
            failedLayer: .element, generation: prober.probeGeneration)
        prober.noteActivation(processID: 7)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        prober.completeProbe(
            processID: 7, bundleID: "com.example", wokeTree: false, verdict: .untrusted,
            failedLayer: .element, generation: prober.probeGeneration)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 2, "같은 활성화로 두 번 재프로브하지 않는다")
    }

    /// 단조성 — 프로브 결과는 trusted를 끌어내리지 못한다 (플립플롭 금지 문언 그대로).
    /// 강등 간선은 런타임 증거 전용의 별도 진입점 `noteAutoAXUnavailable`이다 — 바로 아래
    /// 테스트가 그 대조다("프로브는 못 내리고 런타임 증거는 내린다").
    @Test("프로브 결과는 trusted를 끌어내리지 못한다")
    func probeResultNeverDemotesTrusted() {
        let prober = makeProber()
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        prober.update(verdict: .untrusted, failedLayer: .element, for: 7, bundleID: "com.example")
        #expect(prober.verdict(for: 7) == .trusted)
    }

    /// 위 단조성의 대조 — 런타임 증거(auto발 `.axUnavailable` 창 안 임계)는 trusted를
    /// 내린다. 강등이 곧 다음 키의 keyboard 접기다 (`effectiveStrategy`).
    @Test("런타임 증거는 trusted를 끌어내린다 — 창 안 임계 도달")
    func runtimeEvidenceDemotesTrusted() {
        let prober = makeProber()
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        for tick in 0..<AXTrustProber.demotionThreshold {
            #expect(prober.verdict(for: 7) == .trusted, "임계 전에는 판정이 서 있다")
            prober.noteAutoAXUnavailable(
                processID: 7, bundleID: "com.example", at: TimeInterval(tick))
        }
        #expect(prober.verdict(for: 7) == .untrusted)
        #expect(
            effectiveStrategy(.auto, verdict: prober.verdict(for: 7)) == .keyboard,
            "강등 뒤 접기는 keyboard다")
    }

    @Test("창 밖으로 흩어진 신호는 강등하지 못한다 — 슬라이딩 창 만료")
    func demotionSignalsExpireOutsideWindow() {
        let prober = makeProber()
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        // 2건 뒤 창 길이만큼 지나 3번째 — 앞 2건이 만료돼 임계에 닿지 않는다.
        prober.noteAutoAXUnavailable(processID: 7, bundleID: "com.example", at: 0)
        prober.noteAutoAXUnavailable(processID: 7, bundleID: "com.example", at: 1)
        prober.noteAutoAXUnavailable(
            processID: 7, bundleID: "com.example", at: AXTrustProber.demotionWindow + 1)
        #expect(prober.verdict(for: 7) == .trusted, "지속 실패가 아니라 산발 실패다 — 강등 없음")
    }

    /// 엔트리 부재 = 종료 회수·클리어의 증거 — 신호가 엔트리를 만들면 안 된다
    /// (`completeProbe`의 부재 드롭과 같은 방어).
    @Test("엔트리 없는 강등 신호는 버려진다 — 엔트리를 만들지 않는다")
    func demotionSignalWithoutEntryIsDropped() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteAutoAXUnavailable(processID: 7, bundleID: "com.example", at: 0)
        #expect(prober.verdict(for: 7) == .pending)

        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 1, "다음 디스패치는 백지의 첫 프로브다 — 신호가 부기를 남기지 않았다")
    }

    /// pending·untrusted로 도는 중의 신호는 낡은 홉이다 — 판정도 탈락 계층도 건드리지 않는다.
    @Test("trusted가 아닌 엔트리의 강등 신호는 무시된다")
    func demotionSignalOnNonTrustedIsIgnored() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        // 프로브 탈락 untrusted(.element) — 강등 신호가 와도 재장전 자격이 살아 있어야 한다.
        prober.update(verdict: .untrusted, failedLayer: .element, for: 7, bundleID: "com.example")
        for tick in 0..<AXTrustProber.demotionThreshold {
            prober.noteAutoAXUnavailable(
                processID: 7, bundleID: "com.example", at: TimeInterval(tick))
        }
        #expect(prober.verdict(for: 7) == .untrusted)
        prober.noteActivation(processID: 7)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 1, "신호가 탈락 계층을 .runtime으로 바꿨다면 재장전이 막혔을 것이다")
    }

    /// "재승격은 앱 재실행 = 재프로브뿐" — 강등은 활성화 재장전 대상이 아니다
    /// (거부 목록과 같은 pid 수명 종단).
    @Test("강등된 앱은 활성화로 재장전되지 않는다")
    func demotedAppIsNotReArmedByActivation() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        for tick in 0..<AXTrustProber.demotionThreshold {
            prober.noteAutoAXUnavailable(
                processID: 7, bundleID: "com.example", at: TimeInterval(tick))
        }
        #expect(prober.verdict(for: 7) == .untrusted)

        prober.noteActivation(processID: 7)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 0, "강등은 pid 수명 sticky — 재프로브 경로가 없다")
    }

    /// 강등의 종단성 — 강등보다 먼저 enqueue돼 있던(어긋난 짝의) 프로브가 나중에 착지해도
    /// 상향 간선으로 강등을 덮지 못한다 (거부 목록 종단과 같은 축).
    @Test("강등 판정은 종단 — 늦게 착지한 프로브 결과가 덮지 못한다")
    func runtimeDemotionIsTerminal() {
        let prober = makeProber()
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        for tick in 0..<AXTrustProber.demotionThreshold {
            prober.noteAutoAXUnavailable(
                processID: 7, bundleID: "com.example", at: TimeInterval(tick))
        }
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        #expect(prober.verdict(for: 7) == .untrusted, "재승격은 앱 재실행(백지 엔트리)뿐이다")
    }

    /// 강등 카운터도 엔트리 수명이다 — 종료 회수 뒤 같은 pid의 새 앱은 카운터까지 백지다.
    @Test("종료 회수는 강등 카운터도 백지로 만든다")
    func terminationResetsDemotionCounter() {
        let prober = makeProber()
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        prober.noteAutoAXUnavailable(processID: 7, bundleID: "com.example", at: 0)
        prober.noteAutoAXUnavailable(processID: 7, bundleID: "com.example", at: 1)
        prober.noteTermination(processID: 7)

        // 같은 pid를 물려받은 새 앱 — trusted 재수립 뒤 신호 1건으로는 강등되지 않아야 한다.
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.other")
        prober.noteAutoAXUnavailable(processID: 7, bundleID: "com.other", at: 2)
        #expect(prober.verdict(for: 7) == .trusted, "이전 프로세스의 신호 2건이 승계되면 안 된다")
    }

    @Test("untrusted → trusted는 허용 — 기상·재프로브가 성공한 경로")
    func untrustedCanBecomeTrusted() {
        let prober = makeProber()
        prober.update(verdict: .untrusted, failedLayer: .element, for: 7, bundleID: "com.example")
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        #expect(prober.verdict(for: 7) == .trusted)
    }

    @Test("update에 pending은 없다 — 프로브는 판정을 비우지 못한다")
    func updateIgnoresPending() {
        let prober = makeProber()
        prober.update(verdict: .untrusted, failedLayer: .element, for: 7, bundleID: "com.example")
        prober.update(verdict: .pending, failedLayer: nil, for: 7, bundleID: "com.example")
        #expect(prober.verdict(for: 7) == .untrusted)
    }

    @Test("설정 리로드 클리어 — pending 복귀, 재프로브 부기도 초기화")
    func clearResetsVerdictsAndBookkeeping() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        prober.completeProbe(
            processID: 7, bundleID: "com.example", wokeTree: false, verdict: .trusted,
            failedLayer: nil, generation: prober.probeGeneration)
        prober.clearVerdicts()
        #expect(prober.verdict(for: 7) == .pending)

        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 2, "클리어 뒤 첫 디스패치는 새 프로브다")
    }

    /// "수명 = 앱 실행 1회"의 나머지 절반 — 회수가 없으면 실제 수명이 "pid 값"이 되어,
    /// pid 되감기가 낡은 판정(특히 회복 간선 없는 trusted)을 무관한 새 앱에 승계시킨다.
    @Test("앱 종료가 엔트리를 회수한다 — 같은 pid의 다음 프로세스는 백지다")
    func terminationReclaimsEntry() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "com.example")
        prober.noteTermination(processID: 7)
        #expect(prober.verdict(for: 7) == .pending)

        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        #expect(enqueued == 1, "재사용된 pid의 첫 디스패치는 새 프로브다")
    }

    @Test("종료 뒤 착지한 완료는 버려진다 — 죽은 pid의 판정을 되살리지 않는다")
    func completionAfterTerminationIsDropped() {
        let prober = makeProber(schedule: { _ in })
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        prober.noteTermination(processID: 7)
        prober.completeProbe(
            processID: 7, bundleID: "com.example", wokeTree: false, verdict: .trusted,
            failedLayer: nil, generation: prober.probeGeneration)
        #expect(prober.verdict(for: 7) == .pending, "엔트리 부재 = 회수의 증거 — 결과를 버린다")
    }

    /// "즉시 untrusted·재시도 없음"의 종단성 — 판정보다 먼저 enqueue돼 있던(앱 전환 순간
    /// 어긋난 짝의) 프로브가 나중에 착지해도 상향 간선으로 목록 판정을 덮지 못한다.
    @Test("거부 목록 판정은 종단 — 늦게 착지한 프로브 결과가 덮지 못한다")
    func denyListVerdictIsTerminal() {
        let prober = makeProber()
        prober.update(verdict: .untrusted, failedLayer: .denyList, for: 7, bundleID: "notion.id")
        prober.update(verdict: .trusted, failedLayer: nil, for: 7, bundleID: "notion.id")
        #expect(prober.verdict(for: 7) == .untrusted)
    }

    @Test("클리어 이전 세대의 완료는 버려진다")
    func staleCompletionIsDropped() {
        nonisolated(unsafe) var enqueued = 0
        let prober = makeProber(schedule: { _ in enqueued += 1 })
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        let stale = prober.probeGeneration
        prober.clearVerdicts()
        prober.completeProbe(
            processID: 7, bundleID: "com.example", wokeTree: false, verdict: .trusted,
            failedLayer: nil, generation: stale)
        #expect(prober.verdict(for: 7) == .pending, "낡은 판정이 새 캐시를 오염시키지 않는다")
    }

    /// 기상 1회 부기가 재프로브에 승계된다 — 첫 프로브가 깨운 앱을 재프로브가 또 깨우지 않는다.
    @Test("기상은 pid당 1회 — 재프로브에 승계")
    func wakeHappensOncePerProcessAcrossProbes() {
        nonisolated(unsafe) var pending: [@Sendable () -> Void] = []
        nonisolated(unsafe) var wakes = 0
        let prober = makeProber(
            collect: { _ in elementFailureSignals },
            wake: { _ in wakes += 1 },
            schedule: { pending.append($0) })

        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        pending.removeFirst()()  // 첫 프로브 본체 — 요소 실패라 기상 1회
        #expect(wakes == 1)
        // 완료 hop은 main.async라 테스트 안에서는 오지 않는다 — 진입점을 직접 불러 승계를 싣는다.
        prober.completeProbe(
            processID: 7, bundleID: "com.example", wokeTree: true, verdict: .untrusted,
            failedLayer: .element, generation: prober.probeGeneration)

        prober.noteActivation(processID: 7)
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        pending.removeFirst()()  // 재프로브 본체
        #expect(wakes == 1, "이미 깨운 앱은 재프로브에서 다시 깨우지 않는다")
    }

    /// 큐 배관 관통 1건 — 트리거 → 프로브 본체 → main hop 완료가 실제로 판정을 싣는다.
    /// (큐 대신 인라인 실행 + main 큐 배수 — 배관 글루의 세대 캡처까지 이 경로가 덮는다.)
    @Test("배관 관통 — 완료가 main hop으로 착지한다")
    func probeCompletionLandsThroughPlumbing() async {
        let prober = makeProber(collect: { _ in trustedSignals }, schedule: { $0() })
        prober.noteReplaceDispatch(processID: 7, bundleID: "com.example", declaredStrategy: .auto)
        // 완료는 main.async 뒤에 있다 — main 큐를 한 번 비워 착지를 기다린다.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(prober.verdict(for: 7) == .trusted)
    }
}

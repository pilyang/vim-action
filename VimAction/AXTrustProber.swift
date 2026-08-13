//
//  AXTrustProber.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Foundation
import os
import VimActionConfig

/// auto 전략 프로브 협력자 — **pid 키 판정 캐시**와 **전용 직렬 큐 프로브**를 한 타입이
/// 소유한다 (`FocusedElementResolver` 동형: `@MainActor` 캐시 + 전용 큐 AX + 늦은 착지 폐기).
///
/// 리졸버 밖의 **별도 타입**인 것이 계약이다: 리졸버는 pid 하나만 아는 계약인데 프로브는
/// 번들 ID(거부 목록)·프로파일(auto 여부) 의존을 끌어온다 — 리졸버에 얹으면 그 계약이
/// 오염되고, 읽기 큐를 공유하면 프로브 최악 ~600ms가 계열 판정을 지연시켜 `.unresolved`
/// 창이 수백 ms로 넓어진다 (`20260813_auto-probe-async-cached-verdict-pid-lifetime.md`).
///
/// **판정 캐시의 키·수명은 pid**(앱 실행 1회)다 — 앱 재시작이 곧 재프로브이고, 번들 ID
/// (게이트)와 pid(리졸버)가 별개 옵저버 캐시라 생기는 앱 전환 어긋남 창도 소비 시
/// `context.processID` 조회가 원리적으로 닫는다. **트리거는 그 앱의 첫 `.replace` 디스패치**다
/// (콜백은 플래그만 세우고 프로브는 큐에서) — vim 키를 안 쓰는 앱은 왕복 0건이고, 마스터
/// 토글 off·config off 앱은 `.replace` 자체가 없어 프로브 없음이 구조적으로 성립한다.
///
/// **프로브는 trusted 방향으로만 캐시를 움직인다** (`update` 단조성 가드) — 반증은 런타임
/// 증거(auto발 `.axUnavailable` 연속 강등, 세션 3)뿐이라 판정이 왕복(플립플롭)하는 경로가
/// 없다. untrusted는 앱 활성화에서 재프로브 자격만 재장전되고(즉시 프로브 아님 — 프로브
/// 진입점은 디스패치 하나), 재프로브 횟수는 pid당 상한 상수로 바운드된다.
@MainActor
final class AXTrustProber {
    /// 프로브 AX 전용 직렬 큐. 직렬인 이유는 리졸버 읽기 큐와 같다 — 동시 AX 호출을 만들지
    /// 않기 위해서다. 리졸버 큐와 **분리**한 이유는 위 타입 주석(계열 판정 지연) 참조.
    private nonisolated static let probeQueue = DispatchQueue(
        label: "dev.pilyang.VimAction.axTrustProbe", qos: .utility)

    /// untrusted의 pid당 재프로브 횟수 상한 — 도그푸딩 조절값. 재장전이 앱 활성화 단위라
    /// 빈도는 이미 사용자 페이스로 바운드되어 있고, 이 상수는 총량만 자른다.
    nonisolated static let reProbeAttemptCap = 3
    /// 콜드 형태 실패의 유계 재시도 횟수 (결정 문언 "~200ms×1–2회"의 상한 쪽).
    nonisolated static let coldRetryCount = 2
    /// 재시도 간 지연 — PR-A 실측(콜드 웜업 재시도 2~3회/+10~23ms)과 Electron 트리 기상
    /// 소요를 덮는 잠정값.
    nonisolated static let coldRetryDelay: TimeInterval = 0.2
    /// Electron 트리 기상 속성. SDK 상수가 없어 문자열이다
    /// (`20260813_electron-tree-wake-on-probe-failure.md`).
    nonisolated static let manualAccessibilityAttribute = "AXManualAccessibility"

    /// 프로덕션 프로버 생성. 단위 테스트(TEST_HOST=앱 프로세스)에서는 라이브 알림을 구독하지
    /// 않는다 — 격리된 `NotificationCenter`면 옵저버가 실제 앱 활성화를 받지 않아 재장전이
    /// 머신 상태에 의존하지 않는다 (`FrontmostAppGate.forCurrentEnvironment()`와 같은 규칙).
    /// 프로브 동작을 검증하는 테스트는 seam을 명시 주입한다.
    static func forCurrentEnvironment() -> AXTrustProber {
        isRunningUnderXCTest()
            ? AXTrustProber(notificationCenter: NotificationCenter())
            : AXTrustProber()
    }

    /// pid 하나의 판정과 트리거 부기. 수명 = pid (엔트리를 지우는 것은 `clearVerdicts`뿐).
    private struct Entry {
        var verdict: AXTrustVerdict = .pending
        var failedLayer: AXTrustProbeLayer?
        /// untrusted 이후 재프로브를 몇 번 했는가 — `reProbeAttemptCap`이 자른다.
        var reProbeCount = 0
        /// 앱 활성화가 세우고 재프로브 enqueue가 소비하는 자격 플래그.
        var reArmed = false
        /// 프로브가 큐에 있거나 실행 중 — 같은 앱의 연타 `.replace`가 프로브를 중복
        /// enqueue하지 않게 한다.
        var inFlight = false
        /// 거부 목록 override `.info`를 이미 남겼는가 — pid당 1회.
        var overrideLogged = false
        /// 이 앱에 `AXManualAccessibility` 기상 쓰기를 이미 했는가 — **pid당 1회**이며
        /// 재프로브에도 승계된다 (`20260813_electron-tree-wake-on-probe-failure.md`).
        var wokeTree = false
    }

    private var entries: [pid_t: Entry] = [:]
    /// 캐시 클리어 뒤 착지하는 낡은 프로브 결과를 버리기 위한 세대 토큰
    /// (`FocusedElementResolver.refreshToken`과 같은 형태). 테스트가 완료 진입점을 직접
    /// 부를 때 현재 값을 읽어야 해서 연다.
    private(set) var probeGeneration = 0

    // MARK: - seam (헤드리스 테스트 — 실제 AX 무접촉)

    private let collectSignals: @Sendable (pid_t) -> AXTrustProbeSignals
    private let wakeTree: @Sendable (pid_t) -> Void
    private let coldRetryPause: @Sendable () -> Void
    /// 프로브 작업을 전용 큐에 얹는 자리 — 테스트는 캡처 실행기를 넣어 enqueue를 동기로
    /// 관찰한다 (얹힌 클로저는 완료 진입점 `completeProbe`를 직접 부르는 것과 등가다).
    private let schedule: @Sendable (@escaping @Sendable () -> Void) -> Void

    private let notificationCenter: NotificationCenter
    /// 옵저버 해제를 nonisolated `deinit`에서 하므로 격리 밖에서 읽혀야 한다
    /// (`FrontmostAppGate`와 같은 이유·같은 단언: 접근이 init/deinit 두 곳뿐이다).
    private nonisolated(unsafe) var observerToken: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        collectSignals: @escaping @Sendable (pid_t) -> AXTrustProbeSignals = AXTrustProber
            .collectViaAccessibility,
        wakeTree: @escaping @Sendable (pid_t) -> Void = AXTrustProber.wakeViaAccessibility,
        coldRetryPause: @escaping @Sendable () -> Void = {
            Thread.sleep(forTimeInterval: AXTrustProber.coldRetryDelay)
        },
        schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = {
            AXTrustProber.probeQueue.async(execute: $0)
        }
    ) {
        self.notificationCenter = notificationCenter
        self.collectSignals = collectSignals
        self.wakeTree = wakeTree
        self.coldRetryPause = coldRetryPause
        self.schedule = schedule
        observerToken = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app =
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // queue: .main 배달이라 항상 메인 스레드다 — assumeIsolated의 근거
            // (게이트·리졸버와 같은 패턴).
            MainActor.assumeIsolated {
                self?.noteActivation(processID: app?.processIdentifier)
            }
        }
    }

    deinit {
        if let observerToken { notificationCenter.removeObserver(observerToken) }
    }

    // MARK: - 조회 (콜백이 읽는다)

    /// pid의 현재 판정 — 부재·pid 없음은 `.pending`. 딕셔너리 읽기 1회라 콜백 경량 불변식
    /// 안에 있고, 콜백이 이 값을 `effectiveStrategy`로 접어 `DispatchContext`에 싣는다.
    func verdict(for processID: pid_t?) -> AXTrustVerdict {
        guard let processID else { return .pending }
        return entries[processID]?.verdict ?? .pending
    }

    // MARK: - 트리거 (콜백이 `.replace` 디스패치 뒤에 부른다)

    /// 트리거 판정의 결과 — 순수 함수 `probeDecision`의 출력이라 표로 테스트한다.
    nonisolated enum ProbeDecision: Hashable, Sendable {
        /// 아무것도 하지 않는다.
        case none
        /// 명시 `accessibility`가 거부 목록을 이겼다 — `.info` 1회만 남긴다.
        case logDenyListOverride
        /// 거부 목록 — AX 접촉 없이 즉시 untrusted (재시도 없음).
        case applyDenyListVerdict
        /// 프로브를 큐에 얹는다.
        case probe
    }

    /// 트리거 판정 — **순수 함수**다 (게이트 `isDisabled`와 같은 부류, 캐시와 무관하게
    /// 표로 테스트한다).
    ///
    /// 우선순위가 결정 문언 그대로다: 명시 전략은 프로브 대상이 아니고(판정도 안 본다 —
    /// `effectiveStrategy`), 명시 `accessibility` + 거부 목록 조합만 override 관측을 남긴다.
    /// auto에서는 거부 목록 → pending → untrusted(재장전·상한) → trusted(sticky) 순으로
    /// 갈린다 (`20260813_ax-trust-deny-list-code-constant.md`).
    nonisolated static func probeDecision(
        declaredStrategy: ProfileStrategy,
        isDenyListed: Bool,
        verdict: AXTrustVerdict,
        reArmed: Bool,
        reProbeCount: Int,
        inFlight: Bool,
        overrideLogged: Bool
    ) -> ProbeDecision {
        if declaredStrategy == .accessibility, isDenyListed {
            return overrideLogged ? .none : .logDenyListOverride
        }
        guard declaredStrategy == .auto else { return .none }
        if isDenyListed {
            // pending에서만 판정을 심는다 — 이미 untrusted면 반복 apply가 무의미하고(전이도
            // 로그도 없다), trusted는 목록이 정적 상수라 도달 불가다(프로브는 목록 검사를
            // 지나야 돌고, `update`의 단조성 가드도 겹으로 막는다).
            return verdict == .pending ? .applyDenyListVerdict : .none
        }
        guard !inFlight else { return .none }
        switch verdict {
        case .pending:
            return .probe
        case .trusted:
            // sticky — 재확인 왕복 없음. 반증 간선은 세션 3의 런타임 강등뿐이다.
            return .none
        case .untrusted:
            return (reArmed && reProbeCount < reProbeAttemptCap) ? .probe : .none
        }
    }

    /// `.replace` 디스패치 1건의 신호 — 콜백이 부른다. 하는 일은 순수 트리거 판정 + 플래그
    /// 부기 + 큐 enqueue뿐이라 콜백 경량 불변식 안에 있다 (프로브의 AX 접촉은 전부 큐 위).
    ///
    /// bundleID를 모르면 아무것도 하지 않는다 — 거부 목록 판정과 전이 로그 라벨이 둘 다
    /// 불가능하고, pending 유지는 keyboard라 안전 방향이다.
    func noteReplaceDispatch(processID: pid_t?, bundleID: String?, declaredStrategy: ProfileStrategy)
    {
        guard let processID, let bundleID else { return }
        var entry = entries[processID] ?? Entry()
        let decision = Self.probeDecision(
            declaredStrategy: declaredStrategy,
            isDenyListed: axTrustDenyList.contains(bundleID),
            verdict: entry.verdict,
            reArmed: entry.reArmed,
            reProbeCount: entry.reProbeCount,
            inFlight: entry.inFlight,
            overrideLogged: entry.overrideLogged)
        switch decision {
        case .none:
            return
        case .logDenyListOverride:
            entry.overrideLogged = true
            entries[processID] = entry
            // 이 조합의 도그푸딩 실사례가 아직 없다 — 이 로그가 첫 관측 데이터다
            // (`20260813_ax-trust-deny-list-code-constant.md`).
            Logger.eventTap.info(
                "AX 신뢰 거부 목록 override — 명시 accessibility가 이긴다 [\(bundleID, privacy: .public)]"
            )
        case .applyDenyListVerdict:
            entries[processID] = entry
            update(verdict: .untrusted, failedLayer: .denyList, for: processID, bundleID: bundleID)
        case .probe:
            if entry.verdict == .untrusted {
                entry.reArmed = false
                entry.reProbeCount += 1
            }
            entry.inFlight = true
            entries[processID] = entry
            enqueueProbe(processID: processID, bundleID: bundleID, alreadyWokeTree: entry.wokeTree)
        }
    }

    // MARK: - 캐시 갱신 진입점 (프로브 완료·재장전·클리어 — 테스트가 직접 부른다)

    /// 판정 갱신 지점 — 프로브 완료와 테스트가 함께 쓴다 (`FocusedElementResolver.update`와
    /// 같은 분리: 큐·알림 배선은 실기기 검증 몫이고 단위 테스트는 이 진입점을 직접 부른다).
    ///
    /// **단조성 가드가 여기 있다**: 프로브 결과는 `pending → trusted/untrusted`와
    /// `untrusted → trusted`만 만들 수 있고, trusted를 끌어내리는 간선은 이 진입점에 없다 —
    /// 강등은 런타임 증거 전용으로 세션 3이 **별도 진입점**으로 얹는다(플립플롭 금지).
    /// 실제 전이에만 판정 전이 `.info` 1줄(번들 ID + 판정 + 탈락 계층)을 남긴다 — 릴리스에서
    /// 생존해 `log show --info`로 사후 회수되는 판정 데이터다. **창 본문은 신호 타입이 Bool뿐이라
    /// 실릴 수 없다** (`20260813_auto-trusted-runtime-demotion-and-observability.md`).
    func update(
        verdict: AXTrustVerdict, failedLayer: AXTrustProbeLayer?, for processID: pid_t,
        bundleID: String?
    ) {
        guard verdict != .pending else { return }
        var entry = entries[processID] ?? Entry()
        guard entry.verdict != .trusted else { return }
        let transitioned = entry.verdict != verdict
        entry.verdict = verdict
        entry.failedLayer = failedLayer
        entries[processID] = entry
        guard transitioned else { return }
        switch verdict {
        case .trusted:
            Logger.eventTap.info(
                "auto 판정 전이 — trusted [\(bundleID ?? "앱 미상", privacy: .public)]")
        case .untrusted:
            Logger.eventTap.info(
                "auto 판정 전이 — untrusted (탈락: \(Self.layerLabel(failedLayer), privacy: .public)) [\(bundleID ?? "앱 미상", privacy: .public)]"
            )
        case .pending:
            break  // 위 가드로 도달 불가
        }
    }

    /// 앱 활성화 — untrusted의 재프로브 자격만 재장전한다 (즉시 프로브 아님 — 프로브
    /// 진입점은 `.replace` 디스패치 하나다). 거부 목록 탈락은 정적이라 재장전 대상이 아니다.
    func noteActivation(processID: pid_t?) {
        guard let processID, var entry = entries[processID],
            entry.verdict == .untrusted, entry.failedLayer != .denyList
        else { return }
        entry.reArmed = true
        entries[processID] = entry
    }

    /// 설정 리로드 = 판정 캐시 클리어. 재프로브 상한·기상 1회 부기까지 초기화되고, 클리어
    /// 이전에 큐에 실린 프로브 결과는 세대 토큰으로 폐기된다.
    func clearVerdicts() {
        probeGeneration &+= 1
        entries.removeAll()
    }

    /// 프로브 완료 진입점 — 큐 배관과 테스트가 함께 쓴다. 세대가 어긋나면(클리어 뒤 착지)
    /// 결과를 버린다.
    func completeProbe(
        processID: pid_t, bundleID: String, wokeTree: Bool, verdict: AXTrustVerdict,
        failedLayer: AXTrustProbeLayer?, generation: Int
    ) {
        guard generation == probeGeneration else { return }
        var entry = entries[processID] ?? Entry()
        entry.inFlight = false
        entry.wokeTree = entry.wokeTree || wokeTree
        entries[processID] = entry
        update(verdict: verdict, failedLayer: failedLayer, for: processID, bundleID: bundleID)
    }

    // MARK: - 프로브 실행

    private func enqueueProbe(processID: pid_t, bundleID: String, alreadyWokeTree: Bool) {
        let collect = collectSignals
        let wake = wakeTree
        let pause = coldRetryPause
        let generation = probeGeneration
        schedule { [weak self] in
            let run = Self.runProbe(
                processID: processID, alreadyWokeTree: alreadyWokeTree,
                collect: collect, wake: wake, retryPause: pause)
            let verdict = classifyAXTrustProbe(run.signals)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.completeProbe(
                        processID: processID, bundleID: bundleID, wokeTree: run.wokeTree,
                        verdict: verdict.verdict, failedLayer: verdict.failedLayer,
                        generation: generation)
                }
            }
        }
    }

    /// 프로브 1회의 **동기 오케스트레이션** — seam만 부르는 함수라 큐 없이 단독 테스트한다.
    ///
    /// 수집 → 콜드 형태 실패(`isColdFormFailure`)면 유계 재시도(~200ms × 최대 2회) —
    /// settable=false 단독은 확정 답변이라 재시도하지 않는다. 재시도 전, 탈락이 **요소
    /// 실증(계층 2)** 이고 이 앱을 아직 깨운 적 없으면 `AXManualAccessibility=true` 기상을
    /// **1회** 쓴다 (`20260813_electron-tree-wake-on-probe-failure.md`) — 비-Electron 앱에는
    /// 무해한 에러다. 판정은 마지막 수집의 신호로 낸다.
    nonisolated static func runProbe(
        processID: pid_t,
        alreadyWokeTree: Bool,
        collect: (pid_t) -> AXTrustProbeSignals,
        wake: (pid_t) -> Void,
        retryPause: () -> Void
    ) -> (signals: AXTrustProbeSignals, wokeTree: Bool) {
        var signals = collect(processID)
        var wokeTree = false
        var retriesLeft = coldRetryCount
        while signals.isColdFormFailure, retriesLeft > 0 {
            if signals.failsElementAttestation, !alreadyWokeTree, !wokeTree {
                wake(processID)
                wokeTree = true
            }
            retryPause()
            signals = collect(processID)
            retriesLeft -= 1
        }
        return (signals, wokeTree)
    }

    // MARK: - 라이브 seam (프로브 큐 위에서만 불린다)

    /// 신호 수집 프로덕션 구현 — 판정 계층이 실증하는 것은 **실행 경로가 실제로 소비할
    /// 프리미티브**다: 요소는 `AXRead.focusedElement`(50ms 상속), 읽기 3종은 AX 쓰기 경로가
    /// 쓰는 `FocusedTextReader.read`(반경 4096) 그대로, 쓰기 축은 값을 바꾸지 않는
    /// settable 질의뿐이다. **값을 바꾸는 쓰기는 어떤 형태로도 없다**
    /// (`20260813_ax-lie-detection-read-attestation-settable.md`).
    ///
    /// 계층 2는 리졸버와 같은 속성 이름 목록 검사를 **다시** 한다 — 재사용이 금지된 것은
    /// 폴백 방향이 반대(허용)인 family **값**이고, 프로브는 앱당 몇 회뿐이라 패스 재사용의
    /// 이득도 없다 (리졸버 무수정이 "pid만 안다" 계약을 지키는 쪽).
    @Sendable
    nonisolated static func collectViaAccessibility(processID: pid_t) -> AXTrustProbeSignals {
        var signals = AXTrustProbeSignals()
        guard let element = AXRead.focusedElement(ofProcess: processID) else { return signals }
        signals.focusedElementFound = true
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
            let attributes = names as? [String],
            attributes.contains(kAXSelectedTextRangeAttribute)
        else {
            return signals
        }
        signals.exposesSelectedTextRange = true
        signals.readsSucceeded =
            FocusedTextReader.read(element, radius: FocusedTextReader.axWindowRadius) != nil
        signals.selectedTextRangeSettable = AXRead.isAttributeSettable(
            element, kAXSelectedTextRangeAttribute)
        return signals
    }

    /// Electron 트리 기상 프로덕션 구현. 쓰기는 `AXWriter`를 지난다 —
    /// `AXUIElementSetAttributeValue` 호출자가 그 타입 외 0건이라는 단일 통로 불변식은
    /// 이 속성에도 예외가 없다. 대상은 포커스 요소가 아니라 **앱 요소**라
    /// `AXRead.applicationElement`가 타임아웃까지 실어 준다.
    @Sendable
    nonisolated static func wakeViaAccessibility(processID: pid_t) {
        let application = AXRead.applicationElement(ofProcess: processID)
        let status = AXWriter().write(application, manualAccessibilityAttribute, kCFBooleanTrue)
        #if DEBUG
        // 결과는 판정에 영향이 없다(재수집이 판정한다) — 흔적만 남긴다. 비-Electron 앱의
        // 에러가 정상이라 요약·보고 대상도 아니다.
        Logger.eventTap.debug(
            "Electron 트리 기상 쓰기 (pid \(processID, privacy: .public), AXError \(status.rawValue, privacy: .public))"
        )
        #else
        _ = status
        #endif
    }

    private nonisolated static func layerLabel(_ layer: AXTrustProbeLayer?) -> String {
        switch layer {
        case .denyList: return "거부 목록"
        case .element: return "요소 실증"
        case .readWrite: return "읽기·쓰기 실증"
        case nil: return "없음"
        }
    }
}

//
//  AXTrustProber.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Foundation
import Observation
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
/// 증거(auto가 라우팅한 실행의 `.axUnavailable` 슬라이딩 창 — `noteAutoAXUnavailable`)뿐이라
/// 판정이 왕복(플립플롭)하는 경로가 없다. untrusted는 앱 활성화에서 재프로브 자격만
/// 재장전되고(즉시 프로브 아님 — 프로브 진입점은 디스패치 하나. 거부 목록·런타임 강등은
/// 종단이라 제외), 재프로브 횟수는 pid당 상한 상수로 바운드된다.
///
/// `@Observable`인 것은 메뉴바가 최전면 앱의 판정("Strategy:" 줄)을 그려야 하기 때문이다 —
/// `FrontmostAppGate`와 같은 근거·같은 비용 분석: 콜백의 `verdict(for:)` 읽기가 더하는 것은
/// 추적 스코프 밖 즉시 반환하는 `access(keyPath:)`뿐이고, 엔트리 변이는 전부 사용자 페이스다
/// (프로브 트리거·완료·활성화·강등).
@MainActor
@Observable
final class AXTrustProber {
    /// 프로브 AX 전용 직렬 큐. 직렬인 이유는 리졸버 읽기 큐와 같다 — 동시 AX 호출을 만들지
    /// 않기 위해서다. 리졸버 큐와 **분리**한 이유는 위 타입 주석(계열 판정 지연) 참조.
    private nonisolated static let probeQueue = DispatchQueue(
        label: "dev.pilyang.VimAction.axTrustProbe", qos: .utility)

    /// untrusted의 pid당 재프로브 횟수 상한 — 도그푸딩 조절값. 재장전이 앱 활성화 단위라
    /// 빈도는 이미 사용자 페이스로 바운드되어 있고, 이 상수는 총량만 자른다.
    nonisolated static let reProbeAttemptCap = 3
    /// 런타임 강등 임계 — 슬라이딩 창(`demotionWindow`) 안에서 auto가 라우팅한 실행의
    /// `.axUnavailable`이 이 횟수에 닿으면 trusted를 untrusted로 강등한다. 도그푸딩 조절값.
    ///
    /// 결정 문언의 "연속 N회"를 창으로 근사한 것이다(사용자 확정 — 세션 3): 신호가
    /// execute(키 입력 1건)를 통째로 접어 키 입력당 최대 1건이고, 표적 실패(트리 수면·요소
    /// 핸들 무효화)는 지속 상태라 타이핑 페이스의 창 안 3회는 실질적으로 연속 3회다 —
    /// 실행 경로에 성공 보고 seam을 새로 뚫지 않는 쪽을 택했다
    /// (`20260813_auto-trusted-runtime-demotion-and-observability.md`).
    nonisolated static let demotionThreshold = 3
    /// 위 강등 창의 길이(초) — 도그푸딩 조절값.
    nonisolated static let demotionWindow: TimeInterval = 10
    /// 콜드 형태 실패의 유계 재시도 횟수 (결정 문언 "~200ms×1–2회"의 상한 쪽).
    nonisolated static let coldRetryCount = 2
    /// 재시도 간 지연 — PR-A 실측(콜드 웜업 재시도 2~3회/+10~23ms)과 Electron 트리 기상
    /// 소요를 덮는 잠정값.
    nonisolated static let coldRetryDelay: TimeInterval = 0.2
    /// Electron 트리 기상 속성. SDK 상수가 없어 문자열이다
    /// (`20260813_electron-tree-wake-on-probe-failure.md`).
    nonisolated static let manualAccessibilityAttribute = "AXManualAccessibility"

    /// 프로덕션 프로버 생성. 단위 테스트(TEST_HOST=앱 프로세스)에서는 라이브 알림을 구독하지
    /// 않고 **프로브 enqueue도 드롭한다** — 격리된 `NotificationCenter`가 재장전의 머신 상태
    /// 의존을 끊고, 드롭 schedule이 라이브 AX 접촉을 원천 차단한다(리졸버의 `nil` pid와 같은
    /// 강도). schedule만 무해화하면 되는 이유는 이 타입의 AX 접촉이 전부 schedule 안에
    /// 있어서다. 기본 전략이 auto로 뒤집혀도(세션 5) 실제 pid를 주입한 배선 테스트가 라이브
    /// 프로브 큐·기상 쓰기를 타지 않는다. 프로브 동작을 검증하는 테스트는 seam을 명시 주입한다.
    static func forCurrentEnvironment() -> AXTrustProber {
        isRunningUnderXCTest()
            ? AXTrustProber(notificationCenter: NotificationCenter(), schedule: { _ in })
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
        /// auto가 라우팅한 실행의 `.axUnavailable` 슬라이딩 창 — trusted에서만 굴러가고
        /// (`noteAutoAXUnavailable`), 임계 도달이 곧 런타임 강등이다. `FailureBurstCounter`를
        /// 창·임계만 바꿔 그대로 재사용한다(시간 주입 순수 타입 — 결정 문언의 "재사용 모양").
        /// 엔트리 필드라 pid 수명(종료 회수·클리어)을 공짜로 상속한다.
        var axUnavailableBurst = FailureBurstCounter(
            window: AXTrustProber.demotionWindow, threshold: AXTrustProber.demotionThreshold)

        /// pid 수명 **종단**인가 — 거부 목록("즉시 untrusted·재시도 없음")과 런타임 강등
        /// ("재승격은 앱 재실행뿐"). 재장전(`noteActivation`)과 프로브 상향 덮어쓰기
        /// (`update`)가 같은 판정을 봐야 한쪽만 고치는 조용한 회귀가 없다.
        var isTerminal: Bool { failedLayer == .denyList || failedLayer == .runtime }
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
    /// `@ObservationIgnored`도 게이트와 같다 — 매크로가 접근자를 감싸면 nonisolated
    /// `deinit`에서의 접근이 깨진다. 관찰할 값도 아니다.
    @ObservationIgnored private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []

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
        observerTokens.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let app =
                    notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                // queue: .main 배달이라 항상 메인 스레드다 — assumeIsolated의 근거
                // (게이트·리졸버와 같은 패턴).
                MainActor.assumeIsolated {
                    self?.noteActivation(processID: app?.processIdentifier)
                }
            })
        // 종료 회수가 있어야 "수명 = 앱 실행 1회" 문언이 코드에서 성립한다 — 지우지 않으면
        // 실제 수명이 "pid 값"이 되어, pid 되감기(99999 순환)가 낡은 판정을 무관한 새 앱에
        // 승계시킨다. trusted 승계가 특히 위험하다 — 회복 간선이 런타임 강등
        // (`noteAutoAXUnavailable`)뿐인데, 승계받은 앱이 auto가 아니면 그 간선도 닿지 않는다.
        observerTokens.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let app =
                    notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                MainActor.assumeIsolated {
                    self?.noteTermination(processID: app?.processIdentifier)
                }
            })
    }

    deinit {
        for token in observerTokens { notificationCenter.removeObserver(token) }
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
            // pending에서만 판정을 심는다 — 이미 untrusted면 반복 apply가 무의미하다(전이도
            // 로그도 없다). 목록 앱이 trusted에 이르는 정상 경로는 없고(프로브는 이 검사를
            // 지나야 돈다), 판정이 심어진 뒤에는 `update`의 거부 목록 종단 가드가 늦게 착지한
            // 프로브 결과의 상향 덮어쓰기까지 막는다.
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
            // 엔트리 저장은 `update`가 한다 — 이 분기는 entry를 바꾸지 않아 따로 쓸 것이 없다.
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
    /// 강등은 런타임 증거 전용의 별도 진입점 `noteAutoAXUnavailable`이 담당한다(플립플롭
    /// 금지 — 그쪽은 반대로 trusted에서만 내려간다).
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
        // 종단 판정(`Entry.isTerminal`)은 프로브가 덮지 못한다 — 이 가드가 없으면, 판정보다
        // 먼저 enqueue돼 있던(어긋난 짝의) 프로브가 나중에 착지해 untrusted → trusted 상향
        // 간선으로 종단 판정을 덮을 수 있다.
        guard !entry.isTerminal else { return }
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

    /// **런타임 강등 진입점** — auto가 라우팅한 실행의 `.axUnavailable` 신호가 게시 큐 →
    /// main 홉으로 착지하는 자리다. `update`(프로브 전용 — 단조성 가드가 trusted 하강을
    /// 막는다)를 우회하지 않고 **나란히** 서 있는 별도 간선이며, trusted를 끌어내리는 유일한
    /// 경로다. 창 안 임계 도달이면 untrusted로 강등하고, 실패한 그 액션은 이미 접혔으므로
    /// (재실행 없음 — "쓰기 후 폴백 금지"와 무충돌) 다음 키의 콜백 접기가 untrusted를 읽는
    /// 것이 효과의 전부다 (`20260813_auto-trusted-runtime-demotion-and-observability.md`).
    ///
    /// 엔트리가 없으면 만들지 않고 버린다 — 이 신호는 항상 trusted 엔트리가 있던 시점에
    /// 출발하므로 부재는 종료 회수·클리어의 증거이고, 되살리면 회수가 무의미해진다
    /// (`completeProbe`와 같은 방어). trusted가 아니어도 버린다 — pending·untrusted는
    /// keyboard로 도는 중이라 그 신호 자체가 낡은 홉이다. 종료·클리어 뒤 trusted 재수립
    /// 사이로 낡은 보고가 끼어드는 창은 원리적으로 남지만, 시각이 게시 큐 캡처 값이라
    /// 슬라이딩 창이 낡은 시각을 자연 만료시킨다.
    ///
    /// 강등은 pid 수명 sticky다 — 재승격은 앱 재실행(= 엔트리 백지 + 재프로브)뿐이고,
    /// `noteActivation`의 재장전 제외와 `update`의 종단 가드가 `.runtime`을 함께 제외해
    /// 그 문언을 코드로 만든다. 강등 `.info` 1줄이 판정 전이(번들 ID + 판정 + 탈락 계층)와
    /// 강등 이벤트 관측을 겸한다 — `update` 전이 로그와 중복되지 않는다(이 전이는 이
    /// 진입점만 만든다).
    func noteAutoAXUnavailable(processID: pid_t, bundleID: String?, at failedAt: TimeInterval) {
        guard var entry = entries[processID], entry.verdict == .trusted else { return }
        guard entry.axUnavailableBurst.record(at: failedAt) else {
            entries[processID] = entry
            return
        }
        entry.verdict = .untrusted
        entry.failedLayer = .runtime
        entries[processID] = entry
        Logger.eventTap.info(
            "auto 판정 강등 — untrusted (탈락: \(Self.layerLabel(.runtime), privacy: .public), 창 \(Self.demotionWindow, format: .fixed(precision: 0), privacy: .public)s 안 .axUnavailable ×\(Self.demotionThreshold, privacy: .public) — 다음 액션부터 keyboard) [\(bundleID ?? "앱 미상", privacy: .public)]"
        )
    }

    /// 앱 활성화 — untrusted의 재프로브 자격만 재장전한다 (즉시 프로브 아님 — 프로브
    /// 진입점은 `.replace` 디스패치 하나다). 종단 판정(`Entry.isTerminal` — 거부 목록은
    /// 정적이고, 런타임 강등은 "재승격은 앱 재실행 = 재프로브뿐")은 재장전 대상이 아니다.
    func noteActivation(processID: pid_t?) {
        guard let processID, var entry = entries[processID],
            entry.verdict == .untrusted, !entry.isTerminal
        else { return }
        entry.reArmed = true
        entries[processID] = entry
    }

    /// 앱 종료 — 엔트리를 통째로 회수한다. 판정·재프로브 상한·기상 1회 부기가 전부 앱 실행
    /// 1회의 것이라, 같은 pid를 물려받은 다음 프로세스는 백지에서 시작한다(앱 재시작 = 재프로브).
    func noteTermination(processID: pid_t?) {
        guard let processID else { return }
        entries[processID] = nil
    }

    /// 설정 리로드 = 판정 캐시 클리어. 재프로브 상한·기상 1회 부기까지 초기화되고, 클리어
    /// 이전에 큐에 실린 프로브 결과는 세대 토큰으로 폐기된다.
    func clearVerdicts() {
        probeGeneration &+= 1
        entries.removeAll()
    }

    /// 프로브 완료 진입점 — 큐 배관과 테스트가 함께 쓴다. 세대가 어긋나거나(클리어 뒤 착지)
    /// 엔트리가 사라졌으면(그 사이 앱 종료 — enqueue가 항상 엔트리를 먼저 세우므로 부재는
    /// 회수의 증거다) 결과를 버린다 — 죽은 pid의 판정을 되살리면 종료 회수가 무의미해진다.
    func completeProbe(
        processID: pid_t, bundleID: String, wokeTree: Bool, verdict: AXTrustVerdict,
        failedLayer: AXTrustProbeLayer?, generation: Int
    ) {
        guard generation == probeGeneration, var entry = entries[processID] else { return }
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
        case .runtime: return "런타임 강등"
        case nil: return "없음"
        }
    }
}

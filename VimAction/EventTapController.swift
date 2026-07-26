//
//  EventTapController.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox  // IsSecureEventInputEnabled() 제공 — 제거 시 빌드 실패 (곧 kVK_* 키코드도 사용).
import Observation
import os
import VimEngine

/// 유일한 메인 CGEventTap의 소유자. keyDown을 `KeyTranslator`→`VimEngine`으로 흘려
/// 엔진 결정(통과/삼킴/대체)을 이벤트에 적용하고, `ActionExecutor`가 마킹한 합성
/// 이벤트는 재해석 없이 통과시킨다. 대체(replace)의 실제 실행은 디스패처 마일스톤 —
/// 지금은 삼키고 로그만 남긴다.
@MainActor
@Observable
final class EventTapController {
    enum Status: Equatable {
        /// Accessibility 미허용 — 불변식에 따라 설치 거부 상태.
        case waitingForPermission
        /// 탭 설치·헬스 정상. 가로채기 on/off는 이 상태가 아니라 `isInterceptionEnabled`가
        /// 표현한다 — off로 설치돼 탭이 비활성이어도 설치 자체가 정상이면 `.running`이다.
        case running
        /// 권한 외 원인으로 tapCreate 실패, 또는 재활성화 후에도 탭 불능.
        case failed
        /// 탭 설치는 정상이나 OS Secure Event Input(비밀번호 입력 등)이 키보드 탭을
        /// 억제 중 — 고장이 아니라 보호 상태다. 워치독은 재활성화를 보류하고(OS 보호와
        /// 싸우지 않음), 해제되면 다음 폴링(≤2초)이 자동 복귀시킨다.
        case secureInput
        /// 종료 정리 후.
        case stopped
    }

    private(set) var status: Status = .waitingForPermission

    /// 현재 모드 — `handle` 후 `engine.mode`의 복사본. 메뉴바 글리프가 관찰한다.
    private(set) var mode: Mode = .insert

    /// 가로채기 마스터 토글 (UserDefaults 영속). off 의미론: `tapEnable(false)`로 스트림
    /// 해방(포트는 유지) + 엔진 Insert 리셋 + `handleKeyDown` 번역 전 가드(탭이 어떤
    /// 이유로든 살아 있어도 전부 통과하는 이중 방어). 이 가드는 최상단이 아니라 마커
    /// 가드 **다음**이다 — 마커는 상태 무관 불변식이라 어떤 상태 가드보다 앞선다
    /// (20260725_marker-guard-highest-precedence). off 중에는 아무도 탭을 되살리지
    /// 않는다 — 콜백의 `tapDisabledBy*` 재활성화도 게이트되며, 복귀 경로는 on 분기의
    /// 선제 tapEnable뿐이다.
    ///
    /// 런타임 SSOT는 이 프로퍼티다 — defaults는 didSet이 쓰는 팔로워라, 실행 중
    /// 외부 `defaults write`는 재시작까지 무시된다 (탈출 옵션도 같은 소유 모델).
    var isInterceptionEnabled: Bool {
        didSet {
            // didSet은 등가 대입에도 발화한다 — 가드 없이는 엔진 재생성·tapEnable이 중복 실행.
            guard oldValue != isInterceptionEnabled else { return }
            defaults.set(isInterceptionEnabled, forKey: PreferenceKeys.interceptionEnabled)
            if isInterceptionEnabled {
                // 킬스위치 래치 해제 — on 복귀가 유일한 해제 지점이다. 빠뜨리면 킬스위치
                // 이후 콜백·워치독 재활성화가 영구 보류되는 조용한 고장이 된다.
                killSwitchRequested.withLock { $0 = false }
                // off가 탭을 비활성화하므로 이 재활성화가 유일한 복귀 경로다
                // (워치독 첫 폴링을 기다리지 않음).
                // 이 분기는 TEST_HOST에서 포트가 항상 nil이라 로그가 유일한 관측 수단 —
                // 하지 않은 재활성화를 성공처럼 남기면 안 된다.
                if tapPort != nil {
                    enableTapAndVerify(reason: "가로채기 on")
                    startWatchdog()
                } else {
                    // 포트가 없다 = tapCreate가 (권한 외 원인으로) 실패했거나 아직 설치 전.
                    // off→on 토글이 문서화된 수동 복구 경로이므로, 로그만 남기지 말고
                    // 실제로 전체 설치를 재시도한다 (권한 없으면 startIfPermitted가
                    // .waitingForPermission으로, 재실패면 .failed로 정리한다).
                    Logger.eventTap.notice(
                        "가로채기 on — 탭 포트 없음, 설치 재시도 (status=\(String(describing: self.status), privacy: .public))")
                    startIfPermitted()
                }
            } else {
                resetEngine()
                // cancel을 비활성화보다 먼저 — 이후 새 폴링은 안 뜨므로, 남는 경합은
                // in-flight 핸들러 하나뿐.
                stopWatchdog()
                // off = 스트림 해방. 비활성화 없이 통과만 하면 모든 키가 여전히 메인 스레드
                // 콜백을 왕복해, 앱이 오동작(스톨)할 때 끄는 안전장치 목적을 못 지킨다.
                if let port = tapPort {
                    CGEvent.tapEnable(tap: port, enable: false)
                    // in-flight 틱이 위 disable 직후 탭을 되살릴 수 있다. 최종 disable을
                    // 워치독 시리얼 큐 *뒤에* 걸어 "마지막 동작은 반드시 disable"을 큐
                    // 순서로 보장한다 — applyWatchdogResult의 off 가드는 메인 홉이라
                    // 메인 스톨 중엔 못 닫는 경합을 이 경로가 메인 무관하게 닫는다.
                    nonisolated(unsafe) let offPort = port
                    watchdogQueue.async { CGEvent.tapEnable(tap: offPort, enable: false) }
                }
                Logger.eventTap.info("가로채기 off — 탭 비활성화, 엔진 Insert 리셋")
            }
        }
    }

    /// Normal 탈출 옵션 (UserDefaults 영속). 가로채기 토글과 같은 소유 모델 — 런타임
    /// SSOT는 이 프로퍼티이고, didSet이 저장과 엔진 주입을 함께 책임져 UI 표시와 엔진
    /// 동작이 어긋날 수 없다. 실행 중 외부 `defaults write`는 재시작까지 무시된다.
    var isNormalModeEscapeEnabled: Bool {
        didSet {
            guard oldValue != isNormalModeEscapeEnabled else { return }
            defaults.set(
                isNormalModeEscapeEnabled, forKey: PreferenceKeys.normalModeEscapeEnabled)
            updateConfiguration(
                makeConfiguration(normalModeEscapeEnabled: isNormalModeEscapeEnabled))
        }
    }

    /// 엔진 소유 — UI 관찰 대상이 아니다. 설정 변경 시 `updateConfiguration`으로 재생성.
    @ObservationIgnored private var engine: VimEngine
    @ObservationIgnored private var configuration: VimEngine.Configuration
    @ObservationIgnored private let defaults: UserDefaults

    /// 실행 실패 폭주 감지기 — `reportExecutionFailure`가 유일한 소비자다.
    @ObservationIgnored private var failureBurst = FailureBurstCounter()

    /// 메인 탭 포트. 저장은 잠금 상자다 — 킬 탭의 전용 스레드가 `triggerKillSwitch`에서
    /// 같은 포트를 읽어 즉시 비활성화하기 때문이다(메인 격리로는 스톨 중 도달 불가).
    /// 미러를 따로 두면 두 상태가 어긋날 수 있으므로 상자 하나를 SSOT로 둔다.
    @ObservationIgnored private nonisolated let tapPortBox = TapPortBox()
    private var tapPort: CFMachPort? {
        get { tapPortBox.get() }
        set { tapPortBox.set(newValue) }
    }

    /// 킬스위치 요청 래치 — 킬 탭 스레드가 세우고, 토글 on 복귀가 내린다.
    ///
    /// `reenableAfterDisable`·워치독 틱의 토글 가드와 역할이 같지만 그 가드들은 발동 ②의
    /// **메인 홉이 착지한 뒤에야** 참이 된다. 킬 스레드가 탭을 끄는 즉시 OS가 메인 콜백에
    /// `tapDisabledBy*` 통지를 보내므로 홉보다 통지가 먼저 도착하고, 방금 끈 탭이 되살아난다
    /// (실기기 로그로 확인). 래치는 그 창을 메인 격리 밖에서 닫는다 — "래치가 서 있으면
    /// 아무도 탭을 되살리지 않는다"가 불변식이다.
    @ObservationIgnored private nonisolated let killSwitchRequested =
        OSAllocatedUnfairLock(initialState: false)

    /// 래치 상태. 읽기는 테스트 검증용으로 연다 — 해제 누락은 "킬스위치 이후 재활성화가
    /// 영구 보류"라는 조용한 고장이라 계약으로 고정한다.
    nonisolated var isKillSwitchRequested: Bool { killSwitchRequested.withLock { $0 } }

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    /// 탭 워치독 — 콜백 재활성화가 못 덮는 실패 모드(완전 정지/장기 스톨은 `tapDisabledBy*`
    /// 통지 자체가 유실됨) 대응으로 탭 활성 여부를 백그라운드에서 주기 폴링한다.
    /// 복구 시점은 정지/스톨이 풀린 뒤다 — 스톨 "중"에는 재활성화를 보류한다 (스톨 게이트).
    @ObservationIgnored private var watchdogTimer: DispatchSourceTimer?
    @ObservationIgnored private let watchdogQueue =
        DispatchQueue(label: "dev.pilyang.VimAction.tapWatchdog", qos: .utility)
    /// 스톨 게이트의 신호: 직전 틱의 status 홉이 아직 메인에서 소비되지 않았으면 true.
    /// bg 틱이 세우고 메인 홉이 내린다 — 잠금은 두 스레드 간 가시성·원자성용.
    @ObservationIgnored private nonisolated let watchdogHopPending =
        OSAllocatedUnfairLock(initialState: false)

    /// `defaults` 주입은 테스트용 — 실제 앱은 `.standard`. 테스트가 `.standard`를 쓰면
    /// TEST_HOST가 앱 프로세스라 실기기에서 영속된 값이 새어 들어온다.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isInterceptionEnabled = defaults.bool(
            forKey: PreferenceKeys.interceptionEnabled, default: true)
        let escapeEnabled = defaults.bool(
            forKey: PreferenceKeys.normalModeEscapeEnabled,
            default: PreferenceKeys.normalModeEscapeEnabledDefault)
        self.isNormalModeEscapeEnabled = escapeEnabled
        let configuration = makeConfiguration(normalModeEscapeEnabled: escapeEnabled)
        self.configuration = configuration
        self.engine = VimEngine(configuration: configuration)
    }

    /// 설정 변경 주입 — 엔진 재생성이라 모드는 Insert로 리셋된다 (설정 조작 중이므로 수용).
    /// 호출 경로는 설정 프로퍼티의 didSet뿐 — 프로퍼티를 우회한 주입은 SSOT를 깬다.
    private func updateConfiguration(_ configuration: VimEngine.Configuration) {
        self.configuration = configuration
        resetEngine()
        // 사용자 가시 전이(모드 리셋 + 동작 변경) — 로그 없이는 "엔진 버그"와 구분 불가.
        Logger.eventTap.info(
            "엔진 재생성 — 설정 주입 (escapeModifiers=\(String(describing: configuration.normalModeEscapeModifiers), privacy: .public)), 모드 Insert 리셋")
    }

    private func resetEngine() {
        engine = VimEngine(configuration: configuration)
        if mode != .insert { mode = .insert }
    }

    /// Accessibility 권한이 있을 때만 탭을 설치한다 (권한 없으면 설치 거부 — 불변식).
    func startIfPermitted() {
        // 단위 테스트(TEST_HOST=앱 프로세스)가 이 경로를 타면 라이브 탭을 설치한다 —
        // off→on 토글 테스트가 didSet을 통해 여기 도달하므로 bootstrap과 같은 가드가 필요하다.
        guard !isRunningUnderXCTest() else { return }
        guard tapPort == nil else { return }
        guard AXIsProcessTrusted() else {
            status = .waitingForPermission
            Logger.eventTap.info("Accessibility 미허용 — 탭 설치 보류")
            return
        }

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        // refcon 가정: self는 AppState가 앱 수명 동안 보유하고, 해제 전에 stop()으로 invalidate된다.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = .failed
            Logger.eventTap.fault("CGEvent.tapCreate 실패 — 권한 외 원인 의심")
            return
        }
        tapPort = port

        // 스파이크는 메인 런루프에 부착한다: 콜백이 거의 no-op이고 프로젝트의 MainActor 기본
        // 격리와 정합. 엔진 연결 전에 전용 CFRunLoop 스레드 필요 여부를 재검토할 것 —
        // 아래 재활성화 로그 빈도가 판단 데이터가 된다.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        Logger.eventTap.info(
            "탭 설치 완료 (secureInput=\(IsSecureEventInputEnabled()), 가로채기=\(self.isInterceptionEnabled))")
        // 설치 시점에도 off 의미론을 지킨다 — persisted off로 부팅하거나 권한이 나중에
        // 부여돼 이 경로가 뒤늦게 돌 때, 무조건 enable하면 off 상태인데 탭이 살아 키가
        // 메인 스레드 콜백을 왕복한다 (didSet off 분기와 같은 규칙: 포트 유지·탭 비활성).
        if isInterceptionEnabled {
            // enable 성공을 검증한 뒤에만 .running으로 — 검증 없이 .running을 찍으면
            // (예: 설치 시점 secure input) 탭이 죽었는데 UI가 활성인 척한다.
            enableTapAndVerify(reason: "탭 설치")
            // verify 실패(.failed)여도 시작 — 일시적 실패의 자동 재확인(연속 폴링)이
            // 워치독 몫이므로, 게이팅은 status가 아니라 "탭 설치됨 && 토글 on"이다.
            startWatchdog()
        } else {
            CGEvent.tapEnable(tap: port, enable: false)
            // 탭 설치·헬스는 정상 — 가로채기 off는 status가 아니라 토글이 표현한다.
            status = .running
        }

        if terminationObserver == nil {
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                }
            }
        }
    }

    /// 탭 정리: 워치독 정지 → 비활성화 → 런루프 소스 제거 → 포트 invalidate. 앱 종료 시 호출된다.
    func stop() {
        stopWatchdog()
        guard let port = tapPort else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        tapPort = nil
        runLoopSource = nil
        status = .stopped
        Logger.eventTap.info("탭 제거 완료")
    }

    /// 시스템이 탭을 비활성화(타임아웃/사용자 개입)했을 때 재활성화한다.
    fileprivate func reenableAfterDisable(type: CGEventType) {
        // 킬스위치가 끈 탭은 되살리지 않는다 — 아래 토글 가드는 발동 ②의 메인 홉이
        // 착지해야 참이 되는데, 우리가 끈 데 대한 OS 통지가 그보다 먼저 도착한다.
        guard !isKillSwitchRequested else {
            Logger.eventTap.notice(
                "킬스위치 요청 — 탭 재활성화 보류 (\(Self.disableReasonName(type), privacy: .public))")
            return
        }
        // off 중에는 되살리지 않는다 — off가 탭을 비활성화하므로 여기서 재활성화하면
        // 안전장치가 풀린다 (비활성화 직전 in-flight 통지가 이 가드에 걸린다).
        guard isInterceptionEnabled else { return }
        enableTapAndVerify(reason: "탭 비활성화 통지(\(Self.disableReasonName(type)))")
    }

    /// `tapDisabledBy*` 통지의 사람이 읽는 이름 — raw는 0xFFFFFFFE/0xFFFFFFFF라
    /// 로그에서 판독이 안 된다.
    private nonisolated static func disableReasonName(_ type: CGEventType) -> String {
        switch type {
        case .tapDisabledByTimeout: "timeout"
        case .tapDisabledByUserInput: "userInput"
        default: "type=\(type.rawValue)"
        }
    }

    /// tapEnable(true)→tapIsEnabled 검증 쌍 — CGEvent는 스레드 안전 C API라 메인
    /// (`enableTapAndVerify`)과 워치독 bg 틱이 공유한다. 재시도·지연 등 enable 시퀀스
    /// 수정은 반드시 여기서 — 두 복구 경로가 어긋나지 않게 하는 단일 지점이다.
    /// status 반영은 각자의 격리에서 별도로 한다.
    private nonisolated static func enableAndCheck(_ port: CFMachPort) -> Bool {
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// tapEnable(true) → tapIsEnabled 검증 → status 전이의 단일 지점. on 복귀·설치·
    /// 시스템 재활성화 세 경로가 공유한다 — 검증 없이 tapEnable만 하면 실제로는 죽은
    /// 탭을 .running으로 표시(UI 거짓)하게 된다. `.running`은 "탭 설치·헬스 정상"을
    /// 뜻하고, 가로채기 on/off는 `isInterceptionEnabled`가 별도로 표현한다.
    ///
    /// 자동 재확인(일시적 실패 후 재시도)은 워치독 몫 — 여기서는 정직한 상태 전이까지만
    /// 하고, 실패 후 복구는 토글 off→on 재시도(또는 워치독)로 이뤄진다.
    ///
    /// 워치독은 백그라운드 큐에서 도므로 이 @MainActor 헬퍼를 그대로 재사용하지 못한다 —
    /// CGEvent 쌍(`enableAndCheck`)만 공유하고 status 반영은 홉 뒤 `applyWatchdogResult`가 한다.
    @discardableResult
    private func enableTapAndVerify(reason: String) -> Bool {
        guard let port = tapPort else { return false }
        let live = Self.enableAndCheck(port)
        if live {
            // 등가 가드 — @Observable은 등가 대입에도 발화하므로 반복 성공 시 과발화 방지.
            if status != .running { status = .running }
            Logger.eventTap.info("\(reason, privacy: .public) — 탭 재활성화")
        } else if IsSecureEventInputEnabled() {
            // 실패 원인이 OS 보호(비밀번호 입력 등)면 고장이 아니다 — 워치독 틱의
            // secureInput 판정과 같은 규칙. 해제 후 복귀는 워치독 폴링 몫.
            if status != .secureInput { status = .secureInput }
            Logger.eventTap.info("\(reason, privacy: .public) — Secure Input 활성, 탭 활성화 보류")
        } else {
            // 실패 분기에도 등가 가드 — tapDisabledBy* 반복 실패가 콜백 경로에서 돌 수 있다.
            if status != .failed { status = .failed }
            Logger.eventTap.error("\(reason, privacy: .public) — tapEnable 후에도 탭 비활성 (가로채기 불능)")
        }
        return live
    }

    /// 워치독 가동 — 게이팅은 "탭 설치됨 && 토글 on" (status 무관 — .failed여도 돌아야
    /// 일시적 실패가 다음 폴링에서 자동 재확인된다).
    ///
    /// 목적: 완전 정지/장기 스톨 중 OS가 끈 탭은 `tapDisabledBy*` 통지가 유실돼 콜백
    /// 재활성화가 못 살린다 — 정지가 *풀린 뒤에도* 죽은 채 방치되는 탭을 폴링으로
    /// 감지해 복구한다. 스톨 "중"의 복구는 목적이 아니다: 탭 소스가 메인 런루프에
    /// 있어 스톨 중 되살린 탭은 키를 처리하지 못한다 (핸들러의 스톨 게이트 주석 참고).
    ///
    /// 핵심 불변식: 폴링·재활성화는 전용 백그라운드 큐에서 `tapIsEnabled`/`tapEnable`을
    /// 직접 호출한다 — SIGSTOP류 완전 정지에서 깨어난 직후, 메인 큐 적체와 무관하게
    /// 첫 틱이 즉시 복구·로그할 수 있어야 한다. status 반영만 main.async 홉
    /// (폴링은 메인을 기다리지 않는다).
    private func startWatchdog() {
        guard watchdogTimer == nil, isInterceptionEnabled, let tapPort else { return }
        // CFMachPort 강캡처 — 스레드 안전 C API 대상이라 bg 호출이 안전하고, stop()이
        // invalidate한 뒤의 늦은 호출은 무해한 no-op이다 (약참조·매 폴링 재조회가
        // 오히려 nil 경합·격리 위반을 만든다).
        nonisolated(unsafe) let port = tapPort
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(
            deadline: .now() + .seconds(2), repeating: .seconds(2), leeway: .milliseconds(500))
        // [weak self]: 핸들러가 self를 잡으면 self→timer→handler→self 사이클이 cancel에만
        // 의존한다 — stop() 없는 해제 경로가 생기는 순간 좀비 워치독이 2초마다 탭을
        // 되살리는 최악 부류의 누수라, 사이클 자체를 두지 않는다. CGEvent 호출은 별도
        // 강캡처된 port만 쓰므로 weak 전환의 기능 비용은 없다.
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // 스톨 게이트: 직전 홉이 아직 메인에서 소비되지 않았다 = 메인이 ≥1 폴링
            // 주기만큼 적체(스톨)됐다. 이때는 틱을 통째로 건너뛴다 —
            // ① 재활성화 보류: 탭 소스가 메인 런루프에 있어 스톨 중 되살린 탭은 키를
            //    처리하지 못한 채 ~1초씩 잡아두다 OS에 다시 꺼진다 (2초마다 타이핑
            //    지연만 반복하며 OS 보호와 싸움). 꺼진 탭은 키를 즉시 통과시키므로
            //    스톨 중엔 그대로 두는 게 올바른 degrade다.
            // ② 홉 미적재: 장기 스톨에 홉이 2초당 1건씩 메인 큐에 붇는 것을 막는다
            //    (pending 최대 1건). 복구는 스톨 해소 → 홉 소진 → 다음 틱(≤2초)이 한다.
            guard !watchdogHopPending.withLock({ $0 }) else { return }
            // 킬스위치 게이트: 이 틱은 토글 가드 없이 enableAndCheck를 부르므로
            // (토글 반영은 didSet의 stopWatchdog 몫이고 그건 메인 홉 뒤다) 발동 직후
            // in-flight 틱이 방금 끈 탭을 되살릴 수 있다 — 콜백 경로와 같은 래치로 닫는다.
            guard !isKillSwitchRequested else { return }
            let observation = Self.watchdogTick(
                isEnabled: { CGEvent.tapIsEnabled(tap: port) },
                enableAndVerify: {
                    // 위 진입 가드는 틱 **시작 시점**만 막는다 — 래치는 킬 스레드가 세우므로
                    // 이 틱이 진행 중에 설 수 있고, 그러면 방금 킬스위치가 끈 탭을 되살린다.
                    // "래치가 서 있으면 아무도 탭을 되살리지 않는다"는 불변식이라 창을 닫는다.
                    guard !self.isKillSwitchRequested else { return false }
                    return Self.enableAndCheck(port)
                },
                isSecureInput: { IsSecureEventInputEnabled() }
            )
            // 래치가 이 틱 진행 중에 섰으면 관측값을 통째로 버린다 — 위 클로저의 false를
            // 그대로 흘리면 .dead가 되어, 홉 착지 순서에 따라 메인이 거짓 .failed를 찍는다.
            guard !isKillSwitchRequested else { return }
            if observation == .recovered {
                // 성공 로그만 bg에서 직접 — 희귀 이벤트라 스팸 불가능하고, 메인 스톨
                // 중에도 즉시 기록돼야 복구를 관측할 수 있다. 실패 로그는 메인 전이
                // 가드 뒤 1건 (매 시도 로그는 장기 불능 시 2초당 1건씩 도배).
                Logger.eventTap.info("워치독 — 비활성 탭 복구")
            }
            // 매 폴링 홉: 비활성 감지 시에만 홉하면 "탭은 살았는데 status만 .failed"인
            // 낡은 래치를 영원히 못 고친다. 항상 관측값을 흘려 status↔실제가 ≤2초 내
            // 수렴시키고, 등가 가드가 과발화를 흡수한다.
            //
            // 홉은 main.async — unstructured Task의 메인 액터 실행 순서는 FIFO 보장이
            // 없어, 탭이 flap하면 낡은 dead 홉이 최신 홉을 덮어쓸 수 있다. GCD
            // 메인 큐는 FIFO라 이 버그 클래스가 없다 (스톨 게이트의 pending ≤1건과
            // 합쳐 홉 순서 문제가 이중으로 봉인된다).
            watchdogHopPending.withLock { $0 = true }
            DispatchQueue.main.async {
                self.watchdogHopPending.withLock { $0 = false }
                MainActor.assumeIsolated { self.applyWatchdogResult(observation) }
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        // cancel은 in-flight 핸들러를 기다리지 않는다 — 남는 경합은 강캡처(메모리 안전)와
        // 시리얼 큐 최종 disable + applyWatchdogResult의 가드(의미론)가 수용한다.
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    /// 워치독 틱의 관측 결과 — bg 틱이 산출하고 `applyWatchdogResult`가 소비한다.
    enum WatchdogObservation: Equatable {
        /// 탭이 이미 활성 — 재활성화 시도 없음.
        case live
        /// 비활성 탭을 재활성화해 살렸다.
        case recovered
        /// 재활성화 후에도 비활성 — 가로채기 불능.
        case dead
        /// 탭 비활성이나 Secure Event Input이 원인 — 재활성화 미시도 (OS 보호 존중).
        case secureInput
    }

    /// 워치독 틱의 판정 로직 — CGEvent 의존을 클로저로 주입받는 순수 함수. 실탭 경로는
    /// TEST_HOST 포트가 항상 nil이라 CI에서 도달 불가하므로, 판정만 분리해 단위 테스트한다
    /// (타이머 스케줄·실탭 결합은 실기기 GREEN 몫). 프로덕션 주입은 `startWatchdog` 핸들러.
    ///
    /// Secure Input 확인은 탭이 죽어 있을 때만 — 비활성의 원인이 OS 보호(비밀번호 입력
    /// 등)면 재활성화를 시도하지 않는다. 시도하면 매 2초 거부→.failed 반복으로 정상
    /// 보호 동작이 고장(false failure)처럼 표시된다.
    nonisolated static func watchdogTick(
        isEnabled: () -> Bool,
        enableAndVerify: () -> Bool,
        isSecureInput: () -> Bool
    ) -> WatchdogObservation {
        if isEnabled() { return .live }
        if isSecureInput() { return .secureInput }
        return enableAndVerify() ? .recovered : .dead
    }

    /// 워치독 관측값의 메인측 status 반영 — `enableTapAndVerify`와 같은 전이 규칙
    /// (live→.running / dead→.failed)의 4번째 소비자. 탭 설치와 무관한 순수 경로라
    /// internal — 늦은 홉 무시·off 가드를 단위 테스트하는 계약.
    func applyWatchdogResult(_ observation: WatchdogObservation) {
        // 토글 off 경합 자가 치유: off 직전 in-flight 폴링이 탭을 되살렸을 수 있다.
        // 시리얼 큐 최종 disable이 1차로 닫고, 이 가드는 늦은 홉의 status 오염 방지 +
        // 이중 방어의 되돌림이다.
        guard isInterceptionEnabled else {
            if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: false) }
            return
        }
        // stop() 이후·설치 전 늦은 홉 무시 — 탭 없는 status를 오염시키지 않는다.
        guard tapPort != nil else { return }
        switch observation {
        case .live, .recovered:
            if status != .running { status = .running }
        case .secureInput:
            if status != .secureInput {
                status = .secureInput
                Logger.eventTap.info("워치독 — Secure Input 활성, 재활성화 보류 (OS 보호)")
            }
        case .dead:
            if status != .failed {
                status = .failed
                Logger.eventTap.error("워치독 — tapEnable 후에도 탭 비활성 (가로채기 불능)")
            }
        }
    }

    /// 실행 실패 1건 보고 — 폭주(기본 1초 5회)면 가로채기를 자동으로 끈다.
    ///
    /// M1 시점엔 호출자가 없다: 엔진은 throw하지 않고 어댑터도 아직 없어서 보고할
    /// 오류원 자체가 없다. 실행 계층(Keyboard 어댑터)이 들어올 때 실패 지점들이 이리로
    /// 모인다 — 그때 새 off 경로를 만들지 말 것.
    ///
    /// off는 `isInterceptionEnabled = false` 대입뿐이다 — 기존 소프트 off 경로의 didSet이
    /// 엔진 Insert 리셋·워치독 정지·탭 비활성·경합 봉인·영속·메뉴바 반영을 이미 책임진다.
    /// 사용자 알림도 그 경로가 만드는 메뉴바 글리프 변화 + 아래 로그가 전부다
    /// (새 알림 프레임워크·권한을 들이지 않는다).
    ///
    /// `now` 주입은 테스트용 — 프로덕션은 `systemUptime`(단조 증가라 시스템 시계 조정에
    /// 흔들리지 않는다).
    func reportExecutionFailure(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        // 이미 off면 셀 필요는 있어도(창은 계속 굴러간다) 끌 것도 알릴 것도 없다.
        guard failureBurst.record(at: now), isInterceptionEnabled else { return }
        Logger.eventTap.fault("실행 실패 폭주 감지 — 가로채기 자동 off")
        isInterceptionEnabled = false
    }

    /// 안전장치 단축키 발동 — 킬 탭의 **전용 스레드에서** 호출된다. 효과는 두 겹이다.
    ///
    /// ① 메인 스톨과 무관하게 스트림을 즉시 놓는다. 새 off "의미론"이 아니라 ②가 멱등하게
    ///    반복할 disable의 선행 실행이다 — 메인이 굳어 있어도 이 한 줄은 실행된다.
    /// ② 나머지(엔진 Insert 리셋·워치독 정지·경합 봉인·영속·메뉴바 글리프)는 전부 기존
    ///    소프트 off의 didSet에 위임한다. `reportExecutionFailure`와 같은 규칙 —
    ///    자동/외부 off 전용 경로를 만들지 않는다.
    ///
    /// ①이 도로 풀리지 않게 하는 것은 `killSwitchRequested` 래치다 — 홉이 착지하기 전까지
    /// 콜백·워치독의 토글 가드는 아직 on을 보고 있어, 래치 없이는 우리가 끈 탭을 이들이
    /// 즉시 되살린다. 마지막 방어는 didSet off 분기의 "워치독 시리얼 큐 뒤 최종 disable".
    nonisolated func triggerKillSwitch() {
        // 래치는 반드시 disable **앞에** — 순서가 뒤집히면 그 사이에 도착한 비활성화 통지가
        // 래치 없는 상태로 판정돼 탭이 되살아난다.
        killSwitchRequested.withLock { $0 = true }
        if let port = tapPortBox.get() {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        Logger.eventTap.fault("킬스위치 발동 — 메인 탭 즉시 비활성")
        // 홉은 main.async — 워치독 홉과 같은 이유로 FIFO 보장이 필요하다.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.isInterceptionEnabled = false }
        }
    }

    /// keyDown 하나를 엔진 결정으로 번역해 적용한다. 탭 설치와 무관한 순수 경로라
    /// internal이다 — 합성 CGEvent 시퀀스로 단위 테스트하는 계약.
    func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // 우리가 게시한 합성 이벤트 — 번역·엔진 재해석 없이 즉시 통과.
        // 어떤 가드보다도 앞이다: "자기 출력을 재해석하지 않는다"는 앱 상태(토글 포함)와
        // 무관한 불변식이라 어떤 상태 조합보다 먼저 판정해야 한다. 뒤로 밀리면 상태
        // 조합 하나가 무한 루프의 입구가 된다.
        guard !SyntheticEventMarker.isMarked(event) else {
            return Unmanaged.passUnretained(event)
        }
        // 마스터 토글 off — 번역 전에 전부 통과 (off 의미론).
        guard isInterceptionEnabled else {
            return Unmanaged.passUnretained(event)
        }
        // 번역 불가는 무조건 통과 — 번역기 계약.
        guard let key = KeyTranslator.translate(event) else {
            return Unmanaged.passUnretained(event)
        }
        let output = engine.handle(key)
        // 등가 가드: @Observable은 등가 비교 없이 대입만으로 발화하므로, 무조건 대입이면
        // Insert 타이핑 내내 매 keyDown마다 메뉴바 SwiftUI 무효화가 콜백 경로에서 돈다.
        if mode != engine.mode { mode = engine.mode }

        // 로그는 swallow/replace만 — passthrough(Insert 타이핑)까지 남기면 키로거가 된다.
        switch output.decision {
        case .passthrough:
            return Unmanaged.passUnretained(event)
        case .swallow:
            #if DEBUG
            Logger.eventTap.debug("swallow")
            #endif
            return nil
        case .replace:
            // 과도기: 실행 없이 삼키고 요약 1건만 로그. actions는 수천 개일 수 있어
            // (카운트 도입 예정) 콜백 내 다발 로그는 탭 타임아웃을 유발한다.
            #if DEBUG
            Logger.eventTap.debug(
                "replace ×\(output.actions.count, privacy: .public): \(String(describing: output.actions.first), privacy: .public)"
            )
            #endif
            return nil
        }
    }
}

/// C 함수 포인터 콜백 — 프로젝트 기본 MainActor 격리를 벗어나야 하므로 명시적 nonisolated.
/// 탭 소스를 메인 런루프에 붙였으므로 항상 메인 스레드에서 실행된다 — `assumeIsolated`의 근거.
/// (런루프 선택이 바뀌면 이 가정부터 깨진다.)
private nonisolated func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()

    return MainActor.assumeIsolated { () -> Unmanaged<CGEvent>? in
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 키 이벤트가 아니라 아웃오브밴드 제어 통지 — 반환값은 시스템이 무시한다.
            // 재활성화만 하고, 이벤트가 흐르지 않음을 드러내려 nil 반환.
            controller.reenableAfterDisable(type: type)
            return nil
        case .keyDown:
            return controller.handleKeyDown(event)
        default:
            break
        }
        // flagsChanged 등 나머지는 무수정 통과 — modifier는 keyDown의 flags로 이미
        // 엔진에 전달되므로 flagsChanged를 엔진에 넣지 않는다.
        return Unmanaged.passUnretained(event)
    }
}

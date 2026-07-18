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
/// 엔진 결정(통과/삼킴/대체)을 이벤트에 적용한다. 대체(replace)의 실제 실행은 디스패처
/// 마일스톤 — 지금은 삼키고 로그만 남긴다. 합성 이벤트 마커 확인도 그때 얹힌다.
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
        /// 종료 정리 후.
        case stopped
    }

    private(set) var status: Status = .waitingForPermission

    /// 현재 모드 — `handle` 후 `engine.mode`의 복사본. 메뉴바 글리프가 관찰한다.
    private(set) var mode: Mode = .insert

    /// 가로채기 마스터 토글 (UserDefaults 영속). off 의미론: `tapEnable(false)`로 스트림
    /// 해방(포트는 유지) + 엔진 Insert 리셋 + `handleKeyDown` 최상단 가드(탭이 어떤
    /// 이유로든 살아 있어도 전부 통과하는 이중 방어). off 중에는 아무도 탭을 되살리지
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
                // off가 탭을 비활성화하므로 이 재활성화가 유일한 복귀 경로다
                // (워치독 첫 폴링을 기다리지 않음).
                // 이 분기는 TEST_HOST에서 포트가 항상 nil이라 로그가 유일한 관측 수단 —
                // 하지 않은 재활성화를 성공처럼 남기면 안 된다.
                if tapPort != nil {
                    enableTapAndVerify(reason: "가로채기 on")
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
                // off = 스트림 해방. 비활성화 없이 통과만 하면 모든 키가 여전히 메인 스레드
                // 콜백을 왕복해, 앱이 오동작(스톨)할 때 끄는 안전장치 목적을 못 지킨다.
                if let port = tapPort {
                    CGEvent.tapEnable(tap: port, enable: false)
                }
                Logger.eventTap.info("가로채기 off — 탭 비활성화, 엔진 Insert 리셋")
            }
            // 워치독(다음 항목): off→정지 / on→재가동 훅이 여기 들어간다.
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

    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

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

    /// 탭 정리: 비활성화 → 런루프 소스 제거 → 포트 invalidate. 앱 종료 시 호출된다.
    func stop() {
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
        // off 중에는 되살리지 않는다 — off가 탭을 비활성화하므로 여기서 재활성화하면
        // 안전장치가 풀린다 (비활성화 직전 in-flight 통지가 이 가드에 걸린다).
        guard isInterceptionEnabled else { return }
        enableTapAndVerify(reason: "시스템이 탭 비활성화(type=\(type.rawValue))")
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
    /// tapEnable/tapIsEnabled는 bg에서 직접 호출하고 status 반영만 메인으로 홉해야 한다.
    @discardableResult
    private func enableTapAndVerify(reason: String) -> Bool {
        guard let port = tapPort else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        let live = CGEvent.tapIsEnabled(tap: port)
        if live {
            // 등가 가드 — @Observable은 등가 대입에도 발화하므로 반복 성공 시 과발화 방지.
            if status != .running { status = .running }
            Logger.eventTap.info("\(reason, privacy: .public) — 탭 재활성화")
        } else {
            // 실패 분기에도 등가 가드 — tapDisabledBy* 반복 실패가 콜백 경로에서 돌 수 있다.
            if status != .failed { status = .failed }
            Logger.eventTap.error("\(reason, privacy: .public) — tapEnable 후에도 탭 비활성 (가로채기 불능)")
        }
        return live
    }

    /// keyDown 하나를 엔진 결정으로 번역해 적용한다. 탭 설치와 무관한 순수 경로라
    /// internal이다 — 합성 CGEvent 시퀀스로 단위 테스트하는 계약.
    func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
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

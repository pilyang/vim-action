//
//  FocusedElementResolver.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Foundation
import os

/// 리졸버가 보고하는 요소 계열 — 어댑터가 이 값으로 **걸러낼지**를 정한다.
///
/// 계열이 시퀀스를 다변화하지는 않는다: `.textField`는 `.textArea`와 **같은 시퀀스**를 쓴다
/// (단일행 필드에서 TextArea 시퀀스가 자연 수렴하고, 전용 분기는 role 오보고 시 여러 줄
/// 검색창의 `dd`를 전체 삭제로 개악한다 — `20260801_textfield-edit-sequences-scrapped.md`).
/// 계열이 실제로 가르는 것은 둘뿐이다: `.textField`의 `o`/`O`(Return=submit 회피)와
/// `.nonText`의 편집·Visual·명령 위임.
nonisolated enum ElementFamily: Sendable, CaseIterable {
    /// 여러 줄 텍스트. 모든 시퀀스가 설계된 기준 계열이자 **폴백**이다.
    case textArea
    /// 단일행 필드. 편집은 `.textArea`와 같고 `o`/`O`만 걸러낸다.
    case textField
    /// 확실히 비텍스트로 보고된 요소 (Finder 리스트 등).
    case nonText
    /// 앱 전환 직후, 새 앱의 첫 읽기가 아직 착지하지 않은 상태.
    ///
    /// **폴백(`.textArea`)과 구분되는 별개 상태다**: 폴백은 "읽었는데 텍스트로 볼 근거밖에
    /// 없다"이고 이쪽은 "아직 아무것도 모른다"다. 걸러내기는 `.nonText`와 같게 걸리며,
    /// 그 대가는 전환 직후 ~20ms 안의 첫 편집 1회가 조용히 떨어지는 것이다
    /// (`20260801_unresolved-window-after-app-switch.md`).
    case unresolved
}

/// 포커스 요소 계열 캐시 — 키 입력마다 AX를 재탐지하지 않기 위한 리졸버.
///
/// `FrontmostAppGate`와 같은 형태다: `@MainActor` 캐시를 알림이 갱신하고, **탭 콜백은
/// 캐시만 읽는다**(콜백 경량 불변식, `20260725_callback-light-invariant.md`).
///
/// 다만 앱 게이트와 달리 갱신에 **AX 호출**이 든다. 그래서 읽기는 메인이 아니라 전용 직렬
/// 큐에서 한다 — 메인 스레드는 AX 호출을 아예 하지 않으므로 콜백 경량 불변식보다 강한
/// 보장이다. 실측이 근거다: 앱과의 **최초 접촉**에서 focusedRole 읽기는 ~20ms가 걸리고
/// (앱 6종 전부), 3ms 캡으로는 6종 모두 `kAXErrorCannotComplete`로 실패한다. 웜 상태에서는
/// 0.3~1.7ms다. 즉 3ms를 메인에서 지키면 **앱을 바꿀 때마다 첫 판정이 반드시 폴백**이 되어
/// 리졸버가 겨냥한 Finder 위험이 그대로 남는다 (`20260801_focused-role-cache-shape.md`).
@MainActor
final class FocusedElementResolver {
    /// AX 메시징 타임아웃. 콜드 ~20ms 실측 위의 여유값이며, 메인을 막지 않으므로 탭 안정성과
    /// 무관하다 (막는 것은 이 전용 큐뿐이다).
    private nonisolated static let messagingTimeout: Float = 0.05

    /// AX 읽기 전용 직렬 큐. 직렬인 이유는 순서가 아니라 **동시 AX 호출을 만들지 않기**
    /// 위해서다 — 앱 전환이 연타되면 읽기가 겹친다.
    private nonisolated static let readQueue = DispatchQueue(
        label: "dev.pilyang.VimAction.focusedElement", qos: .userInitiated)

    /// 프로덕션 리졸버 생성. 단위 테스트(TEST_HOST=앱 프로세스)에서는 **AX도 알림도 건드리지
    /// 않는다** — 격리된 `NotificationCenter`와 `nil` pid면 옵저버가 붙지 않아 캐시가
    /// 폴백에 머문다. 분류·캐시 동작을 검증하는 테스트는 `update(family:)`를 직접 부른다
    /// (`FrontmostAppGate.forCurrentEnvironment()`와 같은 규칙).
    static func forCurrentEnvironment() -> FocusedElementResolver {
        isRunningUnderXCTest()
            ? FocusedElementResolver(notificationCenter: NotificationCenter(), frontmostProcessID: nil)
            : FocusedElementResolver()
    }

    /// 포커스 요소 계열 캐시. 읽기는 콜백과 테스트가 함께 쓴다.
    ///
    /// 초기값이 `.textArea`인 것은 계약이다 — 걸러내기는 "확실히 비텍스트/TextField로
    /// **보고된** 경우"에만 발동한다 (`20260801_resolver-fallback-defaults-to-text-area.md`).
    private(set) var family: ElementFamily = .textArea

    /// 늦게 도착한 읽기를 버리기 위한 토큰. 앱 전환이 연타되면 먼저 건 읽기가 나중에
    /// 착지해 **낡은 계열로 캐시를 덮을 수 있다**.
    private var refreshToken = 0

    private let notificationCenter: NotificationCenter
    /// 옵저버 해제를 nonisolated `deinit`에서 하므로 격리 밖에서 읽혀야 한다
    /// (`FrontmostAppGate`와 같은 이유·같은 단언: 접근이 init/deinit/전환 세 곳뿐이다).
    private nonisolated(unsafe) var observerToken: NSObjectProtocol?
    private nonisolated(unsafe) var axObserver: AXObserver?
    /// 관측 중인 앱. 읽기 요청이 이 pid로만 나가므로 전환 시 함께 갈아탄다.
    private var observedProcessID: pid_t?

    /// `frontmostProcessID`가 `@autoclosure`인 것은 `FrontmostAppGate`와 같다 — 테스트가
    /// `NSWorkspace` 조회 없이 값을 넣는다. 격리된 `NotificationCenter`를 함께 주입하면
    /// 라이브 구독도 피한다.
    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        frontmostProcessID: @autoclosure () -> pid_t? = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
    ) {
        self.notificationCenter = notificationCenter
        // 등록이 시드보다 **먼저인 것이 계약이다** (앱 게이트와 같다): 순서가 뒤집히면 그
        // 사이의 앱 전환 알림이 유실돼 옵저버가 낡은 앱에 붙은 채 굳는다.
        observerToken = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app =
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // queue: .main 배달이라 항상 메인 스레드다 — assumeIsolated의 근거.
            MainActor.assumeIsolated {
                self?.attach(to: app?.processIdentifier)
            }
        }
        attach(to: frontmostProcessID())
    }

    deinit {
        if let observerToken { notificationCenter.removeObserver(observerToken) }
        // 옵저버를 남긴 채 해제되면 런루프 소스가 죽은 refcon을 들고 남는다.
        Self.teardown(axObserver)
    }

    // MARK: - 분류 (순수)

    /// 포커스 요소의 AX 보고 → 계열. **어떤 AX 호출도 하지 않는 순수 함수**라 표로 검증한다.
    ///
    /// 텍스트/비텍스트를 가르는 것은 role이 아니라 **`AXSelectedTextRange` 노출 여부**다.
    /// role 화이트리스트가 실측에서 무너졌기 때문이다: Finder는 리스트에 포커스가 있어도
    /// `AXGroup`을 보고하는데, `AXGroup`은 Chromium·Electron이 편집 가능한 영역에도 붙이는
    /// 대표적인 애매한 role이라 비텍스트로 분류할 수 없다. 반면 속성 노출은 갈렸다 —
    /// Finder의 `AXGroup`은 속성 13개에 `AXSelectedTextRange`가 **없고**, TextEdit·Notion·
    /// Slack·Chrome 주소창은 전부 **있다**. (값 조회는 판별자가 못 된다: Finder도 `.success`를
    /// 돌려준다. 이름 목록만이 갈린다 — `20260801_element-family-classification-table.md`.)
    ///
    /// `exposesSelectedTextRange`가 참일 때만 role이 쓰이고, 그때 role이 하는 일은
    /// TextArea/TextField를 가르는 것뿐이다.
    nonisolated static func family(
        role: String?, subrole: String?, exposesSelectedTextRange: Bool
    ) -> ElementFamily {
        guard exposesSelectedTextRange else { return .nonText }
        guard let role else { return .textArea }
        if role == (kAXTextFieldRole as String) { return .textField }
        // 검색창·비밀번호 필드는 role이 아니라 subrole로 오는 앱이 있다.
        if let subrole,
            subrole == (kAXSearchFieldSubrole as String)
                || subrole == (kAXSecureTextFieldSubrole as String)
        {
            return .textField
        }
        // 모르는 role은 전부 폴백이다 — 걸러내기는 확실한 보고에만 발동한다.
        return .textArea
    }

    // MARK: - 캐시 갱신

    /// 캐시 갱신 지점 — 읽기 결과와 테스트가 함께 쓴다. 실제 AX 알림 배선은 유닛 테스트에서
    /// 만들 수 없어 실기기 검증 몫이고, 단위 테스트는 이 진입점을 직접 부른다
    /// (`FrontmostAppGate.update`와 같은 분리).
    func update(family: ElementFamily) {
        guard family != self.family else { return }
        self.family = family
        #if DEBUG
        // 전이 시점만 남긴다 — 포커스 변경은 사용자 페이스라 스팸이 아니고, 세션 2의
        // "앱별 실보고 vs 실측표 대조"가 정확히 이 로그를 읽는다.
        Logger.eventTap.debug("포커스 요소 계열 → \(String(describing: family), privacy: .public)")
        #endif
    }

    /// 앱 전환 — 옵저버를 새 앱으로 갈아타고 현재 포커스를 다시 읽는다.
    private func attach(to processID: pid_t?) {
        guard processID != observedProcessID else { return }
        Self.teardown(axObserver)
        axObserver = nil
        observedProcessID = processID

        // 이전 앱의 계열을 즉시 버리는 것이 계약이다 — 들고 있으면 Finder(`.nonText`)에서
        // 편집기로 넘어온 직후 편집 어휘가 통째로 죽는다.
        //
        // 다만 그 자리를 폴백이 아니라 `.unresolved`로 메운다. 읽기가 착지하기 전(콜드 ~20ms)에
        // 도착한 첫 키를 폴백으로 판정하면 **반대 방향으로 틀린다**: 실측에서 TextEdit→Finder
        // 전환 직후의 `u`가 그 창을 타고 나가 `Cmd-Z`가 Finder에 도달했다(3회 중 2회꼴).
        // 읽을 대상이 없으면(pid nil) 읽기 자체가 없으므로 그때는 폴백이 곧 최종 판정이다
        // (`20260801_unresolved-window-after-app-switch.md`).
        guard let processID else {
            update(family: .textArea)
            return
        }
        update(family: .unresolved)
        axObserver = Self.makeObserver(processID: processID, resolver: self)
        refresh()
    }

    /// 포커스 요소를 다시 읽어 캐시에 반영한다. **AX 호출은 전부 읽기 큐 위**다.
    fileprivate func refresh() {
        guard let processID = observedProcessID else { return }
        refreshToken &+= 1
        let token = refreshToken
        Self.readQueue.async { [weak self] in
            let family = Self.readFamily(processID: processID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.refreshToken else { return }
                    self.update(family: family)
                }
            }
        }
    }

    // MARK: - AX (읽기 큐 위에서만 호출된다)

    /// 앱의 현재 포커스 요소를 읽어 계열을 정한다. 어느 단계에서 실패하든 **폴백은
    /// `.textArea`** 다 — 걸러내기는 확실한 보고에만 발동한다.
    ///
    /// pid만 받는 것이 요점이다: `AXUIElement`를 큐 경계로 넘기지 않으므로 비-`Sendable`
    /// 값이 격리를 건너는 일이 애초에 없다 (`ActionExecutor`의 CGEvent 계약과 같은 규칙).
    private nonisolated static func readFamily(processID: pid_t) -> ElementFamily {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        guard let element = copyElement(application, kAXFocusedUIElementAttribute) else {
            return .textArea
        }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
            let attributes = names as? [String]
        else {
            return .textArea
        }
        return family(
            role: copyString(element, kAXRoleAttribute),
            subrole: copyString(element, kAXSubroleAttribute),
            exposesSelectedTextRange: attributes.contains(kAXSelectedTextRangeAttribute as String))
    }

    private nonisolated static func copyElement(
        _ element: AXUIElement, _ attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private nonisolated static func copyString(
        _ element: AXUIElement, _ attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else {
            return nil
        }
        return value as? String
    }

    /// 앱에 `kAXFocusedUIElementChanged` 옵저버를 걸고 메인 런루프에 붙인다.
    ///
    /// 소스가 메인 런루프인데도 콜백이 가벼운 이유는 콜백이 **AX를 읽지 않기** 때문이다 —
    /// `refresh()`로 읽기 큐에 넘길 뿐이다.
    private static func makeObserver(
        processID: pid_t, resolver: FocusedElementResolver
    ) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(processID, focusedElementChanged, &observer) == .success,
            let observer
        else {
            // 조용히 실패하면 세션 2에서 "왜 안 걸러지지"를 진단할 수 없다.
            Logger.eventTap.notice(
                "AXObserver 생성 실패 (pid \(processID, privacy: .public)) — 계열은 폴백에 머문다")
            return nil
        }
        let application = AXUIElementCreateApplication(processID)
        let status = AXObserverAddNotification(
            observer, application, kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(resolver).toOpaque())
        guard status == .success else {
            Logger.eventTap.notice(
                "AXObserver 등록 실패 (pid \(processID, privacy: .public), AXError \(status.rawValue, privacy: .public)) — 계열은 폴백에 머문다"
            )
            return nil
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return observer
    }

    private nonisolated static func teardown(_ observer: AXObserver?) {
        guard let observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

/// `AXObserver` C 콜백 — 포커스 요소가 바뀌었다는 신호만 받는다.
///
/// 넘어온 `element`를 쓰지 않고 pid로 다시 읽는 것이 의도다: 비-`Sendable` 값을 큐로 넘기지
/// 않아도 되고, 웜 상태의 재조회는 실측 1ms 미만이라 왕복 한 번의 값이 그 대가보다 작다.
/// `nonisolated`는 필수다 — 프로젝트 기본 격리가 MainActor라 그냥 두면 이 함수가 MainActor에
/// 묶이고, 격리된 함수는 C 함수 포인터로 변환되지 않는다 (`eventTapCallback`과 같은 이유).
private nonisolated func focusedElementChanged(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let resolver = Unmanaged<FocusedElementResolver>.fromOpaque(refcon).takeUnretainedValue()
    // 런루프 소스를 메인에 붙였으므로 항상 메인 스레드다 — assumeIsolated의 근거
    // (`eventTapCallback`과 같은 패턴).
    MainActor.assumeIsolated { resolver.refresh() }
}

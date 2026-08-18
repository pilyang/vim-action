//
//  FrontmostAppGate.swift
//  VimAction
//

import AppKit
import Foundation
import Observation
import os

/// 앱 수준 게이트 — 최전면 앱이 disable 목록이면 그 앱 안에서 VimAction은 존재하지
/// 않는 것처럼 동작한다 (번역·엔진 없이 원본 키 통과, 모드 상태는 동결).
///
/// 판정 위치는 탭 콜백의 **엔진 진입 전**이다: 디스패치 시점에 막으면 엔진이 평소처럼
/// 키를 삼키는데 실행만 안 돼 "죽은 키"가 된다 — 끈 것이 아니라 고장낸 것이다
/// (`20260726_m2-app-gate-pre-engine-passthrough.md`).
///
/// 콜백은 **캐시만 읽는다** — 키마다 `NSWorkspace`를 조회하지 않는다(콜백 경량 불변식).
/// 캐시는 앱 활성화 알림이 갱신한다.
///
/// `@Observable`인 것은 메뉴바가 `lastNonSelfBundleID`를 그려야 하기 때문이다. 핫 패스가
/// 더 무거워지지는 않는다: 읽기가 더하는 것은 추적 스코프 없을 때 즉시 반환하는
/// `access(keyPath:)`뿐이고(같은 콜백이 이미 `@Observable`인 `EventTapController`의
/// 프로퍼티를 읽는다), 발화는 아래 두 `update`의 동등성 가드 덕에 실제 전이에만 돈다.
@MainActor
@Observable
final class FrontmostAppGate {
    /// 순수 판정 — 캐시와 무관하게 테스트한다. bundleID 없음(= 최전면 앱 미확인)은
    /// 통과다: 게이트는 "확실히 disable 앱일 때만" 개입한다. 목록에 없는 앱도 통과다 —
    /// `config.yaml` `apps` 맵에 없는 앱은 기본 on이라는 스키마 규칙이 여기서 실현된다.
    static func isDisabled(_ bundleID: String?, disabledBundleIDs: Set<String>) -> Bool {
        guard let bundleID else { return false }
        return disabledBundleIDs.contains(bundleID)
    }

    /// 비자신 캐시의 순수 파생 — `isDisabled`와 같은 부류로 인스턴스 없이 표로 테스트한다.
    ///
    /// nil(최전면 미확인)과 자기 자신은 **직전 짝을 유지한다**: 둘 다 "대상 앱이 없어졌다"가
    /// 아니라 "지금은 알 수 없다"이고, 지우면 메뉴가 방금까지 쓰던 앱을 잃는다.
    /// 같은 값이 두 번 와도 결과가 같으므로(멱등) 재통지가 캐시를 어긋내지 않는다.
    ///
    /// 번들 ID와 pid가 **한 짝으로** 갱신되는 것이 계약이다: 판정 캐시(`AXTrustProber`)의
    /// 키가 pid라 메뉴의 "Strategy:" 줄이 이 pid로 판정을 조회하는데, 둘이 따로 갱신되면
    /// 라벨(번들)과 판정(pid)이 서로 다른 앱을 가리킬 수 있다.
    static func nonSelfTarget(
        bundleID: String?, processID: pid_t?, selfBundleID: String?,
        previous: (bundleID: String?, processID: pid_t?)
    ) -> (bundleID: String?, processID: pid_t?) {
        guard let bundleID, bundleID != selfBundleID else { return previous }
        return (bundleID, processID)
    }

    /// 프로덕션 게이트 생성. 단위 테스트(TEST_HOST=앱 프로세스)에서는 실제 최전면 앱을
    /// **읽지 않는다** — Ghostty에서 `xcodebuild test`를 돌리면(주력 터미널이라 정상
    /// 워크플로우다) 게이트가 켜진 채로 모든 `handleKeyDown` 테스트가 "통과"로 뒤집힌다.
    /// 게이트 동작을 검증하는 테스트는 자체 게이트를 명시 주입한다.
    ///
    /// 프로덕션 분기가 `frontmostApplication`을 **한 번만 읽어** 두 시드를 뽑는 것도
    /// 계약이다 — 두 번 읽으면 그 사이 앱 전환이 시드의 라벨과 pid를 가른다
    /// (비자신 짝 계약은 시드에도 적용된다). 시드의 라이브 읽기는 **여기가 유일하다** —
    /// init 기본값은 inert(nil)라 시드를 일부만 주입한 테스트가 머신 상태를 읽지 않는다.
    static func forCurrentEnvironment() -> FrontmostAppGate {
        guard !isRunningUnderXCTest() else {
            return FrontmostAppGate(notificationCenter: NotificationCenter())
        }
        let app = NSWorkspace.shared.frontmostApplication
        return FrontmostAppGate(
            frontmostBundleID: app?.bundleIdentifier, frontmostProcessID: app?.processIdentifier)
    }

    /// 최전면 앱 bundleID 캐시. 읽기는 테스트 검증용으로 연다.
    private(set) var frontmostBundleID: String?

    /// 마지막으로 본 **자기 자신이 아닌** 앱 — 메뉴바 편의 기능이 겨누는 대상이다.
    /// 메뉴 조작(메뉴 클릭, 리로드 실패 알림의 `NSApp.activate`, Preferences 창)이
    /// VimAction을 최전면으로 만들어도 "직전에 쓰던 앱"이 흔들리지 않게 한다.
    ///
    /// **게이트 판정에는 쓰지 않는다** — 판정은 계속 `frontmostBundleID`다. 이걸로 판정하면
    /// 다른 앱으로 갔는데 disable이 따라오는 오동작이 된다.
    private(set) var lastNonSelfBundleID: String?

    /// 위 캐시와 **한 짝**인 pid — 메뉴의 판정 표시(`AXTrustProber.verdict(for:)` 조회)가
    /// 쓴다. 리졸버의 `observedProcessID`를 메뉴에 그대로 쓰지 않는 이유가 곧 이 캐시의
    /// 존재 이유다: 메뉴를 여는 행위가 VimAction을 최전면으로 만들면 리졸버는 자기 pid를
    /// 관측해 대상 앱 판정이 "판정 중"으로 오표시된다 (세션 3 사용자 확정 — 20260813
    /// 강등·관측 결정의 메뉴 표시 문언 보강).
    private(set) var lastNonSelfProcessID: pid_t?

    /// disable 앱 집합 — 소스는 `config.yaml`의 `apps` 맵(`false`인 항목)이고,
    /// `AppState`가 설정 로드·리로드 때 `update(disabledBundleIDs:)`로 푸시한다.
    /// 설정이 로드되기 전에는 비어 있다 — bootstrap이 설정 로드를 탭 설치보다 먼저
    /// 수행하는 것이 그 창을 닫는 계약이다.
    private(set) var disabledBundleIDs: Set<String>

    var isFrontmostAppDisabled: Bool {
        Self.isDisabled(frontmostBundleID, disabledBundleIDs: disabledBundleIDs)
    }

    /// 메뉴바 글리프용 — **표시 축**은 비자신 캐시다 (판정 축은 위의 `isFrontmostAppDisabled`).
    /// 두 축이 갈리는 이유는 각자 답하는 질문이 다르기 때문이다: 게이트는 "지금 이 키를
    /// 삼켜도 되는가"(반드시 실제 최전면), 표시는 "사용자가 방금까지 쓰던 앱은 무엇인가".
    ///
    /// 메뉴바 아이콘을 클릭하면 VimAction 자신이 최전면이 된다 — 표시를 판정 축에 걸면
    /// 누르는 순간 인디케이터가 사라져 "눌렀더니 상태가 바뀌었다"로 읽히고, 바로 아래
    /// 메뉴의 'Disable for This App' 체크마크(같은 비자신 캐시)와도 어긋난다.
    var isTargetAppDisabled: Bool {
        Self.isDisabled(lastNonSelfBundleID, disabledBundleIDs: disabledBundleIDs)
    }

    /// 옵저버 해제를 `deinit`(nonisolated)에서 하므로 두 저장 프로퍼티 모두 격리 밖에서
    /// 읽혀야 한다. `NotificationCenter`는 `Sendable`이라 `let`만으로 되고, 토큰은
    /// `var`+비-`Sendable`이라 `nonisolated(unsafe)`가 필요하다 — 접근이 init과 deinit
    /// 두 곳뿐이고 그 사이 경합이 없다는 사실을 여기서 단언한다.
    private let notificationCenter: NotificationCenter
    /// `@ObservationIgnored`가 필수다 — 매크로가 접근자를 감싸면 `nonisolated` `deinit`에서의
    /// 접근이 깨진다. 관찰할 값도 아니다.
    @ObservationIgnored private nonisolated(unsafe) var observerToken: NSObjectProtocol?

    /// 자기 자신의 bundle id — 비자신 캐시 판정에만 쓴다. 주입인 이유는 테스트다:
    /// XCTest는 TEST_HOST가 앱 프로세스라 `Bundle.main`이 실제 앱 id가 되어, 주입이 없으면
    /// "자기 자신" 케이스가 머신 상태에 의존한다.
    private let selfBundleID: String?

    /// 시드 기본값은 **inert(nil)** 다 — 라이브 `NSWorkspace` 읽기는 `forCurrentEnvironment()`의
    /// 프로덕션 분기 한 곳뿐이다. 기본값이 라이브면 시드를 일부만 주입한 테스트가 실제
    /// 최전면 앱을 읽어 "합성 번들 + 머신 pid"라는 어긋난 짝이 된다 (실재했던 함정).
    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        frontmostBundleID: String? = nil,
        frontmostProcessID: pid_t? = nil,
        disabledBundleIDs: Set<String> = [],
        selfBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        self.notificationCenter = notificationCenter
        self.disabledBundleIDs = disabledBundleIDs
        self.selfBundleID = selfBundleID
        observerToken = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app =
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // queue: .main 배달이라 항상 메인 스레드다 — assumeIsolated의 근거
            // (EventTapController의 willTerminate 옵저버와 같은 패턴).
            MainActor.assumeIsolated {
                self?.update(bundleID: app?.bundleIdentifier, processID: app?.processIdentifier)
            }
        }
        // 시드가 필요한 이유: 이 앱은 LSUIElement라 실행이 최전면을 바꾸지 않는다.
        // disable 앱이 최전면인 채로 앱을 켜거나 TCC를 재부여하면(로컬 개발에서 흔하다)
        // 다음 앱 전환까지 알림이 오지 않아, nil 시드는 그동안 게이트를 열어 둔다.
        self.frontmostBundleID = frontmostBundleID
        let target = Self.nonSelfTarget(
            bundleID: frontmostBundleID, processID: frontmostProcessID, selfBundleID: selfBundleID,
            previous: (nil, nil))
        lastNonSelfBundleID = target.bundleID
        lastNonSelfProcessID = target.processID
    }

    deinit {
        if let observerToken { notificationCenter.removeObserver(observerToken) }
    }

    /// 캐시 갱신 지점 — 옵저버 콜백과 테스트가 함께 쓴다. 알림 배선 자체(`NSRunningApplication`
    /// 페이로드)는 테스트에서 만들 수 없어 실기기 검증 몫이고, 단위 테스트는 이 진입점을
    /// 직접 부른다 (`EventTapController.watchdogTick`과 같은 분리).
    func update(bundleID: String?, processID: pid_t? = nil) {
        // 비자신 짝 갱신은 dedupe 가드 **앞**이다 — 같은 번들 ID의 재실행(새 pid)은
        // `frontmostBundleID` 기준 무변화라 가드에 걸리는데, 짝 갱신이 함께 걸러지면 메뉴
        // 판정 조회가 죽은 pid로 남는다. 진짜 재통지(같은 번들·같은 pid)는 파생이 멱등이라
        // 아래 동등성 검사로 대입 자체가 없다 (@Observable 발화도 실제 전이에만).
        let target = Self.nonSelfTarget(
            bundleID: bundleID, processID: processID, selfBundleID: selfBundleID,
            previous: (lastNonSelfBundleID, lastNonSelfProcessID))
        if target.bundleID != lastNonSelfBundleID || target.processID != lastNonSelfProcessID {
            lastNonSelfBundleID = target.bundleID
            lastNonSelfProcessID = target.processID
        }
        guard bundleID != frontmostBundleID else { return }
        frontmostBundleID = bundleID
        // 게이트 전이는 사용자 가시 동작 변화다 — 로그 없이는 "가로채기가 안 먹는다"와
        // 구분되지 않는다. 앱 전환마다 1건이라 스팸은 아니지만, 전이 시점만 남긴다.
        #if DEBUG
        Logger.eventTap.debug(
            "최전면 앱 → \(bundleID ?? "(없음)", privacy: .public) (게이트 \(self.isFrontmostAppDisabled ? "on" : "off", privacy: .public))"
        )
        #endif
    }

    /// disable 집합 갱신 지점 — 설정 로드·리로드가 부른다. 최전면 앱이 그대로인 채
    /// 게이트만 뒤집히는 전이라 `update(bundleID:)`와 같은 이유로 로그를 남긴다
    /// ("Reload가 안 먹었다"와 "게이트가 안 먹는다"를 가른다).
    func update(disabledBundleIDs: Set<String>) {
        guard disabledBundleIDs != self.disabledBundleIDs else { return }
        let wasDisabled = isFrontmostAppDisabled
        self.disabledBundleIDs = disabledBundleIDs
        #if DEBUG
        if wasDisabled != isFrontmostAppDisabled {
            Logger.eventTap.debug(
                "disable 목록 갱신 — 현재 앱 게이트 \(self.isFrontmostAppDisabled ? "on" : "off", privacy: .public)"
            )
        }
        #endif
    }
}

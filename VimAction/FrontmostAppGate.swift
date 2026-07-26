//
//  FrontmostAppGate.swift
//  VimAction
//

import AppKit
import Foundation
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
@MainActor
final class FrontmostAppGate {
    /// disable 앱 목록 — M2에서는 하드코딩이고, M4 프로파일의 `enabled:` 필드가 교체한다.
    /// Ghostty는 자체 Vim 키바인딩을 갖는 터미널이라 이중 해석이 되면 양쪽 다 깨진다.
    static let disabledBundleIDs: Set<String> = ["com.mitchellh.ghostty"]

    /// 순수 판정 — 캐시와 무관하게 테스트한다. bundleID 없음(= 최전면 앱 미확인)은
    /// 통과다: 게이트는 "확실히 disable 앱일 때만" 개입한다.
    static func isDisabled(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return disabledBundleIDs.contains(bundleID)
    }

    /// 프로덕션 게이트 생성. 단위 테스트(TEST_HOST=앱 프로세스)에서는 실제 최전면 앱을
    /// **읽지 않는다** — Ghostty에서 `xcodebuild test`를 돌리면(주력 터미널이라 정상
    /// 워크플로우다) 게이트가 켜진 채로 모든 `handleKeyDown` 테스트가 "통과"로 뒤집힌다.
    /// 게이트 동작을 검증하는 테스트는 자체 게이트를 명시 주입한다.
    static func forCurrentEnvironment() -> FrontmostAppGate {
        isRunningUnderXCTest()
            ? FrontmostAppGate(notificationCenter: NotificationCenter(), frontmostBundleID: nil)
            : FrontmostAppGate()
    }

    /// 최전면 앱 bundleID 캐시. 읽기는 테스트 검증용으로 연다.
    private(set) var frontmostBundleID: String?

    var isFrontmostAppDisabled: Bool { Self.isDisabled(frontmostBundleID) }

    /// 옵저버 해제를 `deinit`(nonisolated)에서 하므로 두 저장 프로퍼티 모두 격리 밖에서
    /// 읽혀야 한다. `NotificationCenter`는 `Sendable`이라 `let`만으로 되고, 토큰은
    /// `var`+비-`Sendable`이라 `nonisolated(unsafe)`가 필요하다 — 접근이 init과 deinit
    /// 두 곳뿐이고 그 사이 경합이 없다는 사실을 여기서 단언한다.
    private let notificationCenter: NotificationCenter
    private nonisolated(unsafe) var observerToken: NSObjectProtocol?

    /// `frontmostBundleID` 시드는 `@autoclosure` — 테스트가 `NSWorkspace` 조회 없이
    /// 값을 넣는다. 격리된 `NotificationCenter`를 함께 주입하면 라이브 구독도 피한다.
    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        frontmostBundleID: @autoclosure () -> String? = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier
    ) {
        self.notificationCenter = notificationCenter
        // 등록이 시드보다 **먼저인 것이 계약이다**: 순서가 뒤집히면 그 사이에 일어난 앱
        // 전환의 알림이 유실돼 캐시가 낡은 값으로 굳는다 (게이트가 조용히 어긋난다).
        observerToken = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app =
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // queue: .main 배달이라 항상 메인 스레드다 — assumeIsolated의 근거
            // (EventTapController의 willTerminate 옵저버와 같은 패턴).
            MainActor.assumeIsolated {
                self?.update(bundleID: app?.bundleIdentifier)
            }
        }
        // 시드가 필요한 이유: 이 앱은 LSUIElement라 실행이 최전면을 바꾸지 않는다.
        // disable 앱이 최전면인 채로 앱을 켜거나 TCC를 재부여하면(로컬 개발에서 흔하다)
        // 다음 앱 전환까지 알림이 오지 않아, nil 시드는 그동안 게이트를 열어 둔다.
        self.frontmostBundleID = frontmostBundleID()
    }

    deinit {
        if let observerToken { notificationCenter.removeObserver(observerToken) }
    }

    /// 캐시 갱신 지점 — 옵저버 콜백과 테스트가 함께 쓴다. 알림 배선 자체(`NSRunningApplication`
    /// 페이로드)는 테스트에서 만들 수 없어 실기기 검증 몫이고, 단위 테스트는 이 진입점을
    /// 직접 부른다 (`EventTapController.watchdogTick`과 같은 분리).
    func update(bundleID: String?) {
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
}

//
//  OnboardingPresentationTests.swift
//  VimActionTests
//

import Foundation
import Testing

@testable import VimAction

@MainActor
struct OnboardingPresentationTests {
    @Test("미허용 + 한 번도 안 띄움: 띄운다")
    func untrustedFirstLaunchPresents() {
        withTemporaryDefaults { defaults in
            #expect(shouldPresentOnboarding(isTrusted: false, defaults: defaults))
        }
    }

    /// **이 케이스가 판정 방식을 고정한다** — `defaults.bool`은 미설정 키에도 false를 주므로,
    /// 값을 보고 판정하면 "false로 기록됨"과 "미설정"이 구분되지 않아 매 실행 창이 뜬다.
    @Test("미허용 + 플래그가 false로 기록됨: 안 띄운다 (값이 아니라 키 존재로 판정)")
    func untrustedWithFalseFlagDoesNotPresent() {
        withTemporaryDefaults { defaults in
            defaults.set(false, forKey: PreferenceKeys.didShowOnboarding)
            #expect(!shouldPresentOnboarding(isTrusted: false, defaults: defaults))
        }
    }

    @Test("미허용 + 이미 띄움: 안 띄운다")
    func untrustedAlreadyShownDoesNotPresent() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: PreferenceKeys.didShowOnboarding)
            #expect(!shouldPresentOnboarding(isTrusted: false, defaults: defaults))
        }
    }

    @Test("이미 허용됨: 최초 실행이어도 안 띄운다")
    func trustedNeverPresents() {
        withTemporaryDefaults { defaults in
            #expect(!shouldPresentOnboarding(isTrusted: true, defaults: defaults))
        }
    }
}

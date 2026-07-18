//
//  TemporaryDefaults.swift
//  VimActionTests
//

import Foundation

/// 임시 UserDefaults suite로 격리 실행. 테스트는 TEST_HOST(앱 프로세스)에서 돌아
/// `.standard`가 실제 앱 도메인이다 — 실기기 사용으로 영속된 값(토글 off 등)이
/// 새어 들면 머신 상태 의존 실패가 된다. 컨트롤러를 만드는 모든 테스트가 쓸 것.
@MainActor
func withTemporaryDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let suiteName = "VimActionTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try body(defaults)
}

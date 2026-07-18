//
//  TestEnvironment.swift
//  VimAction
//

import Foundation

/// TEST_HOST로 launch된 단위 테스트 실행 중인지. 이 앱은 TEST_HOST가 앱 프로세스라
/// 테스트가 라이브 CGEventTap을 설치하거나 권한 폴링을 돌리면 안 된다 — 탭 설치 경로
/// (`bootstrap`, `startIfPermitted`)는 이 가드로 실기기 부작용을 차단한다.
func isRunningUnderXCTest() -> Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
}

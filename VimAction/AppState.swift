//
//  AppState.swift
//  VimAction
//

import Foundation
import Observation
import os
import VimEngine

/// 앱 셸이 관찰하는 UI 상태와 전역 컴포넌트(권한 모니터, 이벤트 탭)의 소유자.
@Observable
final class AppState {
    let permissionMonitor = AccessibilityPermissionMonitor()
    let eventTap = EventTapController()

    /// 앱 시작 시 1회: 권한 확인 → 탭 설치 시도, 미허용이면 부여 감지 폴링 시작.
    func bootstrap() {
        // TEST_HOST로 launch된 단위 테스트 실행 중에는 시동하지 않는다 —
        // 테스트가 라이브 이벤트 탭을 설치하거나 권한 폴링을 돌리면 안 된다.
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil {
            // 이 변수가 일반 launch에 새어 들어오면 앱이 통째로 비활성이 되므로 흔적을 남긴다.
            Logger.eventTap.notice("XCTest 환경변수 감지 — bootstrap 생략 (탭 설치·권한 폴링 비활성)")
            return
        }
        permissionMonitor.onGranted = { [eventTap] in
            eventTap.startIfPermitted()
        }
        permissionMonitor.refresh()
        // 미허용이어도 항상 호출한다 — "설치 보류" 로그가 launch 시 관측 가능해야 한다.
        eventTap.startIfPermitted()
        if !permissionMonitor.isTrusted {
            permissionMonitor.startPollingUntilGranted()
        }
    }

    /// 메뉴바 글리프 — 탭이 안 돌면 비활성(square.dashed), 토글 off면 square.slash,
    /// 그 외 모드 글리프 (PRD §7.7 최소 구현). 탭 비활성이 토글보다 우선한다 —
    /// 탭이 안 돌면 토글 상태와 무관하게 가로채기가 불가능하기 때문.
    var menuBarGlyph: String {
        guard eventTap.status == .running else { return "square.dashed" }
        return eventTap.isInterceptionEnabled ? eventTap.mode.menuBarGlyph : "square.slash"
    }

    /// VoiceOver 등 사람이 읽는 메뉴바 상태 문구.
    var menuBarAccessibilityLabel: String {
        guard eventTap.status == .running else { return "VimAction — inactive" }
        return eventTap.isInterceptionEnabled
            ? "VimAction — \(eventTap.mode.displayName) mode"
            : "VimAction — disabled"
    }
}

extension Mode {
    /// 메뉴바 아이템에 표시할 SF Symbol 이름. macOS 표현은 앱 레이어에만 둔다
    /// (엔진 `Mode`는 플랫폼을 모른다).
    var menuBarGlyph: String {
        switch self {
        case .normal: "n.square.fill"
        case .insert: "i.square"
        }
    }

    /// 접근성 레이블 등 사람이 읽는 모드 이름.
    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .insert: "Insert"
        }
    }
}

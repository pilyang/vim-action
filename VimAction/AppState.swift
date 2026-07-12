//
//  AppState.swift
//  VimAction
//

import Observation
import VimEngine

/// 앱 셸이 관찰하는 UI 상태와 전역 컴포넌트(권한 모니터, 이벤트 탭)의 소유자.
@Observable
final class AppState {
    /// 현재 모드. 다음 플랜에서 CGEventTap→엔진이 이 값을 갱신한다 — 지금은 정적 스켈레톤.
    var mode: Mode = .insert

    let permissionMonitor = AccessibilityPermissionMonitor()
    let eventTap = EventTapController()

    /// 앱 시작 시 1회: 권한 확인 → 탭 설치 시도, 미허용이면 부여 감지 폴링 시작.
    func bootstrap() {
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

    /// 뉴바 글리프 — 탭이 안 돌면 흐림/비활성 표시 (PRD §7.7 최소 구현).
    var menuBarGlyph: String {
        eventTap.status == .running ? mode.menuBarGlyph : "square.dashed"
    }

    /// VoiceOver 등 사람이 읽는 메뉴바 상태 문구.
    var menuBarAccessibilityLabel: String {
        eventTap.status == .running
            ? "VimAction — \(mode.displayName) mode"
            : "VimAction — inactive"
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

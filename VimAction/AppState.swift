//
//  AppState.swift
//  VimAction
//

import Observation
import VimEngine

/// 앱 셸이 관찰하는 UI 상태. 지금은 메뉴바 글리프가 읽는 모드만 보유한다.
@Observable
final class AppState {
    /// 현재 모드. 다음 플랜에서 CGEventTap→엔진이 이 값을 갱신한다 — 지금은 정적 스켈레톤.
    var mode: Mode = .insert
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

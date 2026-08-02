//
//  ConfigPaths.swift
//  VimAction
//

import Foundation

/// 설정 루트 `~/.config/vim-action/` — dotfiles로 관리·직접 편집하는 대상이라
/// `~/Library/Application Support`가 아니다 (`20260801_config-root-dot-config.md`).
/// 앱은 비샌드박스(이벤트 탭 요구)라 `NSHomeDirectory()`가 실제 홈이다.
nonisolated enum ConfigPaths {
    static var directory: String { NSHomeDirectory() + "/.config/vim-action" }
    static var configPath: String { directory + "/config.yaml" }
    static var profilesDirectory: String { directory + "/profiles" }
}

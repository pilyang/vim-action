//
//  ProfileScaffold.swift
//  VimAction
//

/// 새 프로파일 파일의 초기 내용 — 메뉴의 'Create Profile'이 없는 파일을 만들 때 쓴다.
///
/// **전부 주석이라 만들자마자는 아무 동작도 바꾸지 않는다**: 주석뿐인 파일을
/// `AppProfileParser`가 빈 프로파일로 읽는다(에러도 경고도 아니다). 활성 키가 하나라도
/// 들어가면 "프로파일 열기" 클릭만으로 그 앱의 동작이 바뀌므로 이것이 계약이다.
///
/// 번들 `notion.id.yaml`과 같은 "실물 예시 문서" 역할이되, 지금 이 앱의 올바른 파일명으로
/// 시작점을 만들어 준다는 점이 다르다. 문구는 번들 설정 파일과 같이 영어로 쓴다.
nonisolated func profileScaffoldYAML(bundleID: String) -> String {
    """
    # VimAction profile for \(bundleID)
    #
    # Everything below is commented out, so this file changes nothing until you
    # edit it. Uncomment what you need, then use 'Reload Config' in the menu bar.
    #
    # All fields are optional:
    #   name             display name
    #   scroll           half_page_lines / full_page_lines (valid 1...200). When set, the value
    #                    wins over the AX-measured viewport; when absent, the app reads the
    #                    viewport and falls back to 15/30 where that read fails.
    #   motions          per-motion key sequence override, or disabled
    #   actions          open_line / paste / undo / redo: the action's own key, or disabled
    #                    (scroll takes disabled only — its keys come from the line_down/line_up motions)
    #   strategy         which execution path the app uses — auto (default: probe the app,
    #                    Accessibility editing where it proves trustworthy, key synthesis
    #                    otherwise) / accessibility / keyboard
    #   keyboard_family  key_mapping (default) / force_text — force_text bypasses element
    #                    detection and its safety filter; explicit last resort
    #                    (see docs/CONFIGURATION.md for both fields)
    #
    # Key token notation: [modifier-]key — modifiers are cmd/opt/ctrl/shift (any order),
    # keys are left/right/up/down/return/escape/tab/home/end/page_up/page_down. All lowercase.
    #
    # name: My App
    # scroll:
    #   half_page_lines: 12
    #   full_page_lines: 24
    # motions:
    #   document_start: [cmd-up]        # sequence override example
    #   line_first_non_blank: disabled  # skips every binding that uses this motion (^ and d^)
    # actions:
    #   open_line: [shift-return]       # for apps where Return sends instead of inserting a line

    """
}

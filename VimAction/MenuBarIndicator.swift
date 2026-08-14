//
//  MenuBarIndicator.swift
//  VimAction
//

import VimEngine

/// 메뉴바가 지금 표시하는 것 — 우선순위 사다리의 결과 하나. 글리프·접근성 문구·커스텀
/// 이미지 사용 여부가 전부 여기서 파생된다.
///
/// 사다리를 값 하나로 모아 두는 이유는 드리프트 방지다: 파생 셋이 각자 우선순위를
/// 재구현하면 한 곳만 고쳐도 컴파일이 통과하고, 그때 생기는 고장은 조용하다
/// (예: Visual-line의 커스텀 "Vl" 이미지가 가로채지 않는 상태에서 동결된 채 남는다).
enum MenuBarIndicator: Equatable {
    /// 탭이 서 있지 않다 (미허용·고장·종료).
    case inactive
    /// 가로채기 마스터 토글 off.
    /// 대상 앱(비자신 캐시 `lastNonSelfBundleID`)이 `config.yaml`의 disable 목록에 있다.
    case appDisabled
    case secureInput
    /// 위 어느 것도 아니라 모드가 실제로 살아 있다.
    case mode(Mode)

    /// 표시할 SF Symbol 이름. fill은 "키 차단 여부" 축이라 키가 통과하는 상태
    /// (`appDisabled`·Insert)는 미채움이다.
    var glyph: String {
        switch self {
        case .inactive: "square.dashed"
        case .interceptionOff: "square.slash"
        case .appDisabled: "minus.square"
        case .secureInput: "lock.square"
        case .mode(let mode): mode.menuBarGlyph
        }
    }

    /// VoiceOver 등 사람이 읽는 메뉴바 상태 문구.
    var accessibilityLabel: String {
        switch self {
        case .inactive: "VimAction — inactive"
        case .interceptionOff: "VimAction — disabled"
        // 메뉴 항목 'Disable for This App'과 같은 어휘 — 원인과 해제 방법이 이어진다.
        case .appDisabled: "VimAction — disabled for this app"
        case .secureInput: "VimAction — paused for secure input"
        case .mode(let mode): "VimAction — \(mode.displayName) mode"
        }
    }

    /// Visual-line만 커스텀 "Vl" 템플릿 이미지로 그린다 (SF Symbols의 글자 사각형은
    /// 1글자뿐이라 `vl.square`가 없다). 사다리를 통과해 **모드가 실제로 표시될 때만**
    /// 참이므로, 새 상태가 사다리에 끼어들어도 이 파생은 따라올 필요가 없다.
    var showsVisualLineGlyph: Bool { self == .mode(.visualLine) }

    /// 우선순위 사다리 — 여기 한 번만 적힌다.
    ///
    /// **탭 고장 > 마스터 토글 off > 앱별 disabled > Secure Input > 모드**. 넓은 상태가 좁은
    /// 상태를 이기고(앞의 둘은 앱과 무관하게 가로채기가 없다), 사용자 의도가 OS의 일시
    /// 억제를 이긴다 — disable해 둔 앱에서 `lock.square`를 보이면 "SEI가 풀리면 재개된다"는
    /// 오해를 주는데, 이 앱에서는 풀려도 가로채지 않는다.
    ///
    /// `isTargetAppDisabled`가 **비자신 캐시 축**인 것이 계약이다 (게이트 판정 축인 최전면이
    /// 아니다) — `FrontmostAppGate.isTargetAppDisabled` 참고.
    ///
    /// status·mode가 `private(set)`이라 컨트롤러로는 `.running`/`.secureInput`을 만들 수
    /// 없다 — 순수 함수라야 전 분기를 단위 테스트할 수 있다 (`eventTapStatusText`와 같은
    /// 패턴, 타입 위 static인 것은 `FrontmostAppGate.isDisabled`와 같다).
    static func resolve(
        status: EventTapController.Status,
        isInterceptionEnabled: Bool,
        isTargetAppDisabled: Bool,
        mode: Mode
    ) -> MenuBarIndicator {
        switch status {
        case .running, .secureInput:
            guard isInterceptionEnabled else { return .interceptionOff }
            if isTargetAppDisabled { return .appDisabled }
            return status == .secureInput ? .secureInput : .mode(mode)
        default:
            return .inactive
        }
    }
}

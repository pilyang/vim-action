//
//  MenuBarIndicatorTests.swift
//  VimActionTests
//

import AppKit
import Testing
import VimEngine

@testable import VimAction

/// 메뉴바 상태 파생 — `EventTapController`의 `status`·`mode`가 `private(set)`이라
/// 컨트롤러로는 `.running`/`.secureInput`을 만들 수 없다. 순수 함수를 직접 불러
/// 우선순위 사다리 전 분기를 검증한다 (`EventTapStatusTextTests`와 같은 이유).
@MainActor
struct MenuBarIndicatorTests {
    /// 기본값은 "전부 정상, 아무것도 겹치지 않음" — 각 테스트는 관심 있는 축만 뒤집는다.
    private func resolve(
        status: EventTapController.Status = .running,
        interception: Bool = true,
        appDisabled: Bool = false,
        mode: Mode = .normal
    ) -> MenuBarIndicator {
        MenuBarIndicator.resolve(
            status: status, isInterceptionEnabled: interception,
            isTargetAppDisabled: appDisabled, mode: mode)
    }

    @Test("사다리 5단이 각각의 조건에서 나온다")
    func ladderCoversEveryRung() {
        #expect(resolve(status: .failed) == .inactive)
        #expect(resolve(interception: false) == .interceptionOff)
        #expect(resolve(appDisabled: true) == .appDisabled)
        #expect(resolve(status: .secureInput) == .secureInput)
        #expect(resolve(mode: .insert) == .mode(.insert))
    }

    /// 탭이 안 서 있으면 나머지는 볼 필요가 없다 — 고장이면 토글·앱 설정과 무관하게
    /// 가로채기가 불가능하다.
    @Test("탭 고장이 모든 단을 이긴다")
    func inactiveOutranksEverything() {
        for status: EventTapController.Status in [.waitingForPermission, .failed, .stopped] {
            #expect(resolve(status: status, interception: false, appDisabled: true) == .inactive)
            #expect(resolve(status: status, appDisabled: true, mode: .visualLine) == .inactive)
        }
    }

    /// 마스터 토글 off는 앱 설정보다 넓다 — 앱을 가리지 않고 전부 통과 중이다.
    @Test("토글 off가 앱별 disabled를 이긴다")
    func interceptionOffOutranksAppDisabled() {
        #expect(resolve(interception: false, appDisabled: true) == .interceptionOff)
    }

    /// 이 PR의 핵심 우선순위 판단 — Secure Input이 풀려도 이 앱에서는 가로채지 않으므로,
    /// `lock.square`("곧 재개된다")를 보이면 거짓말이 된다.
    @Test("앱별 disabled가 Secure Input을 이긴다")
    func appDisabledOutranksSecureInput() {
        #expect(resolve(status: .secureInput, appDisabled: true) == .appDisabled)
        #expect(resolve(status: .secureInput, appDisabled: false) == .secureInput)
    }

    @Test("앱별 disabled가 동결된 모드를 덮는다")
    func appDisabledOutranksMode() {
        // 게이트는 엔진 진입 전에 통과시키므로 모드가 직전 값으로 동결돼 있다 —
        // 그 값을 그리면 "가로채는 중"이라고 거짓말한다.
        for mode: Mode in [.normal, .insert, .visualChar, .visualLine] {
            #expect(resolve(appDisabled: true, mode: mode) == .appDisabled)
        }
    }

    @Test("글리프 이름")
    func glyphNames() {
        #expect(MenuBarIndicator.inactive.glyph == "square.dashed")
        #expect(MenuBarIndicator.interceptionOff.glyph == "square.slash")
        #expect(MenuBarIndicator.appDisabled.glyph == "minus.square")
        #expect(MenuBarIndicator.secureInput.glyph == "lock.square")
        #expect(MenuBarIndicator.mode(.normal).glyph == "n.square.fill")
    }

    /// `NSImage.menuBarSymbol(named:)`이 `!`로 강제 언랩한다 — 이름 오타 하나가
    /// 메뉴바 렌더 시점의 런타임 크래시다.
    @Test("모든 글리프 이름이 실존하는 SF Symbol이다")
    func everyGlyphNameResolves() {
        let indicators: [MenuBarIndicator] = [
            .inactive, .interceptionOff, .appDisabled, .secureInput,
            .mode(.normal), .mode(.insert), .mode(.visualChar), .mode(.visualLine),
        ]
        for indicator in indicators {
            #expect(
                NSImage(systemSymbolName: indicator.glyph, accessibilityDescription: nil) != nil,
                "\(indicator.glyph)")
        }
    }

    @Test("접근성 문구")
    func accessibilityLabels() {
        #expect(MenuBarIndicator.inactive.accessibilityLabel == "VimAction — inactive")
        #expect(MenuBarIndicator.interceptionOff.accessibilityLabel == "VimAction — disabled")
        #expect(
            MenuBarIndicator.appDisabled.accessibilityLabel == "VimAction — disabled for this app")
        #expect(
            MenuBarIndicator.secureInput.accessibilityLabel
                == "VimAction — paused for secure input")
        #expect(MenuBarIndicator.mode(.visualLine).accessibilityLabel == "VimAction — Visual Line mode")
    }

    /// 커스텀 "Vl" 이미지는 SF Symbol과 렌더 경로가 갈리므로, 모드가 실제로 표시되는
    /// 조건에서만 참이어야 한다 — 아니면 가로채지 않는 상태에 "Vl"이 동결된 채 남는다.
    @Test("Visual-line 커스텀 글리프는 모드가 살아 있을 때만 쓰인다")
    func visualLineGlyphOnlyWhenModeIsShown() {
        #expect(resolve(mode: .visualLine).showsVisualLineGlyph)

        #expect(!resolve(appDisabled: true, mode: .visualLine).showsVisualLineGlyph)
        #expect(!resolve(interception: false, mode: .visualLine).showsVisualLineGlyph)
        #expect(!resolve(status: .secureInput, mode: .visualLine).showsVisualLineGlyph)
        #expect(!resolve(status: .failed, mode: .visualLine).showsVisualLineGlyph)
        // 다른 Visual wise는 SF Symbol 경로 그대로다.
        #expect(!resolve(mode: .visualChar).showsVisualLineGlyph)
    }
}

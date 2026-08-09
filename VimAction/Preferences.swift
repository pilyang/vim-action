//
//  Preferences.swift
//  VimAction
//

import Foundation
import VimEngine

/// UserDefaults 키 — 두 키 모두 EventTapController가 로드(init)·저장(didSet)하는
/// 단일 소유다. (단수형 `PreferenceKey`는 SwiftUI 프로토콜과 이름이 충돌해 피한다.)
/// `nonisolated` — 프로젝트 기본이 MainActor 격리라 키 상수까지 메인 격리가 붙는데,
/// 킬스위치 발동은 전용 스레드에서 이 키로 영속하므로 격리 밖에서 읽을 수 있어야 한다.
nonisolated enum PreferenceKeys {
    /// 가로채기 마스터 토글. 기본 on.
    static let interceptionEnabled = "interceptionEnabled"
    /// Normal 모드 cmd/opt 콤보 자동 탈출 옵션.
    static let normalModeEscapeEnabled = "normalModeEscapeEnabled"
    /// 최초 실행 온보딩(설정 창 자동 오픈)을 이미 띄웠는가. 위 둘과 달리 AppState가 소유한다.
    static let didShowOnboarding = "didShowOnboarding"

    /// 탈출 옵션의 제품 기본값 — EventTapController init이 읽는다.
    static let normalModeEscapeEnabledDefault = true
}

/// 런치 시 설정 창을 밀어 올릴지 — 미허용 + 아직 한 번도 안 띄운 경우만.
///
/// `LSUIElement`라 실행해도 창이 뜨지 않고 미허용 신호는 메뉴바 글리프 하나뿐이라, 사용자가
/// 권한이 필요하다는 사실 자체를 모른다. 발견성은 밀어내기로만 풀린다.
///
/// "띄운 적 있음"은 반드시 `object(forKey:) != nil`로 판정한다 — `defaults.bool`은 미설정 키에도
/// false를 주므로 값 비교만 하면 영속 코드를 지워도 눈치채지 못한다 (레포의 알려진 단언 함정).
/// 순수 함수라 단위 테스트가 전 분기를 커버한다 (`eventTapStatusText`와 같은 패턴).
func shouldPresentOnboarding(isTrusted: Bool, defaults: UserDefaults) -> Bool {
    !isTrusted && defaults.object(forKey: PreferenceKeys.didShowOnboarding) == nil
}

/// 탈출 옵션 → 엔진 Configuration 번역의 단일 지점. on=cmd/opt (제품 기본),
/// off=빈 셋 (ctrl은 향후 Vim 키와 충돌 소지로 제외 — 사용자 확정 2026-07-14).
func makeConfiguration(normalModeEscapeEnabled: Bool) -> VimEngine.Configuration {
    .init(normalModeEscapeModifiers: normalModeEscapeEnabled ? [.command, .option] : [])
}

extension UserDefaults {
    /// 미설정 키를 주어진 기본값으로 읽는다 — `register(defaults:)`는 프로세스 전역이라
    /// 테스트의 suite 주입과 얽히므로 쓰지 않는다.
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
}

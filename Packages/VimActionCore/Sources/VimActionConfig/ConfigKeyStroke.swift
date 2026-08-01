/// 설정이 표현하는 키 한 타.
///
/// **플랫폼 중립이다** — `CGKeyCode`/`CGEventFlags` 변환은 앱(`KeyStroke`)의 몫이라 여기 없다.
public struct ConfigKeyStroke: Hashable, Sendable {
    public let key: ConfigKey
    public let modifiers: Set<ConfigModifier>

    public init(_ key: ConfigKey, _ modifiers: Set<ConfigModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// `[modifier-]key` 토큰 파싱. modifier는 순서 무관이고, **전부 소문자만** 유효하다 —
    /// `Cmd-Down`은 미지 키워드와 같은 실패다(대소문자 관용 없음).
    ///
    /// 표기가 파일 밖으로 나가지 않도록 파서 내부 전용으로 둔다.
    init?(token: String) {
        let components = token.split(separator: "-", omittingEmptySubsequences: false)
        guard let keyName = components.last, let key = ConfigKey(rawValue: String(keyName)) else {
            return nil
        }

        var modifiers: Set<ConfigModifier> = []
        for component in components.dropLast() {
            guard let modifier = ConfigModifier(rawValue: String(component)) else { return nil }
            modifiers.insert(modifier)
        }

        self.init(key, modifiers)
    }
}

/// 키 이름 v1 11종. 문자 키(`cmd-z` 류)는 레이아웃 의존이라 v1에서 제외한다.
public enum ConfigKey: String, Hashable, Sendable, CaseIterable {
    case left
    case right
    case up
    case down
    case `return`
    case escape
    case tab
    case home
    case end
    case pageUp = "page_up"
    case pageDown = "page_down"
}

public enum ConfigModifier: String, Hashable, Sendable, CaseIterable {
    case cmd
    case opt
    case ctrl
    case shift
}

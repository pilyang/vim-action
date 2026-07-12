/// 이벤트 탭 계층이 `CGEvent`를 정규화해 엔진에 넘기는 입력 값.
///
/// 엔진은 macOS 의존성이 없으므로 `CGKeyCode`나 `CGEventFlags`를 알지 못한다.
/// 탭 계층이 그것들을 이 표현으로 번역하는 것이 두 세계의 계약이다.
public struct Key: Hashable, Sendable {
    /// 물리 키의 정규화된 본체. 문자 키는 하나의 `Character`로 일반화하고,
    /// 문자로 표현되지 않는 키만 개별 케이스로 둔다.
    public enum Base: Hashable, Sendable {
        case char(Character)
        case escape
        case enter
        case tab
        case space
    }

    /// Shift는 여기에 포함하지 않는다 — 아래 정규화 규칙 참고.
    public enum Modifier: Hashable, Sendable {
        case control
        case option
        case command
    }

    public var base: Base
    public var modifiers: Set<Modifier>

    public init(_ base: Base, _ modifiers: Set<Modifier> = []) {
        self.base = base
        self.modifiers = modifiers
    }
}

extension Key {
    /// 정규화 규칙: 문자에 이미 반영된 shift는 `modifiers`에 넣지 않는다.
    ///
    /// 즉 `$`, `G`, `^`는 그 자체의 `Character`로 들어오며 `.shift` 수식자를 갖지 않는다.
    /// (애초에 `Modifier`에 shift가 없다.) `modifiers`는 문자로 흡수되지 않는
    /// Ctrl/Option/Command 조합(예: `Ctrl-d`)에만 쓴다.
    public static func char(_ character: Character, _ modifiers: Set<Modifier> = []) -> Key {
        Key(.char(character), modifiers)
    }

    public static let escape = Key(.escape)
    public static let enter = Key(.enter)
    public static let tab = Key(.tab)
    public static let space = Key(.space)
}

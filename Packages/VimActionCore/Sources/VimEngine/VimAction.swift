/// 엔진이 생산하는 추상 동작. "무엇을 해야 하는가"만 표현하고
/// "어떻게 실행하는가"(AX 호출인지 키 합성인지)는 전략 어댑터의 몫이다.
public enum VimAction: Hashable, Sendable {
    case move(Motion)
    case edit(Operator, TextRange)
}

/// 편집 오퍼레이터의 종류. 적용 범위는 `TextRange`가 함께 나른다.
public enum Operator: Hashable, Sendable {
    case delete
}

/// 오퍼레이터가 적용될 범위.
public enum TextRange: Hashable, Sendable {
    /// 커서에서 모션을 count회 적용한 지점까지 — 한 편집 단위다 (`d3w`는
    /// move 3회 반복이 아니라 3단어를 한 번에 지우는 범위).
    case motion(Motion, count: Int)
    /// 커서가 놓인 텍스트 오브젝트 — `diw`/`daw`.
    case textObject(TextObject)
    /// 현재 줄부터 count줄 — `dd`, `2dd`.
    case line(count: Int)
}

/// 텍스트 오브젝트. 경계의 실제 의미(단어의 정의, 주변 공백 포함 범위)는
/// 어댑터가 정하며, 엔진은 종류와 스코프만 낸다.
public enum TextObject: Hashable, Sendable {
    case word(Scope)

    /// `i`(inner: 오브젝트 본체만) / `a`(around: 주변 공백 포함).
    public enum Scope: Hashable, Sendable {
        case inner
        case around
    }
}

/// 커서 이동의 종류. 단어 경계·줄 경계의 실제 의미(어디까지가 단어인가 등)는
/// 어댑터가 정하며, 엔진은 추상 케이스만 낸다.
public enum Motion: Hashable, Sendable {
    case charLeft
    case charRight
    case lineUp
    case lineDown
    case wordForward
    case wordBackward
    case wordEndForward
    case lineStart
    case lineFirstNonBlank
    case lineEnd
    case documentStart
    case documentEnd
    /// `a` 전용. Vim에서 `l`(charRight)은 줄 끝 문자 위에서 멈추지만 append는
    /// 마지막 문자 뒤까지 가야 하므로, 어댑터가 구분할 수 있게 별도 케이스로 둔다.
    case charRightForAppend
    /// `A` 전용. `$`(lineEnd)는 마지막 문자 위, `A`는 마지막 문자 뒤 — 위와 같은 이유.
    case lineEndForAppend
}

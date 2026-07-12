/// 엔진이 생산하는 추상 동작. "무엇을 해야 하는가"만 표현하고
/// "어떻게 실행하는가"(AX 호출인지 키 합성인지)는 전략 어댑터의 몫이다.
public enum VimAction: Hashable, Sendable {
    case move(Motion)
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

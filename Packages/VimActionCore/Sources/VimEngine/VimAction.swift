/// 엔진이 생산하는 추상 동작. "무엇을 해야 하는가"만 표현하고
/// "어떻게 실행하는가"(AX 호출인지 키 합성인지)는 전략 어댑터의 몫이다.
///
/// 스켈레톤 단계에서는 케이스 뼈대만 둔다. 이동 키셋(h j k l / w b e / 0 ^ $ / gg G)의
/// 실제 케이스는 다음 마일스톤에서 `Motion`을 채우며 추가한다.
public enum VimAction: Hashable, Sendable {
    case move(Motion)
}

/// 커서 이동의 종류. 다음 마일스톤에서 이동 키셋에 맞춰 케이스를 채운다.
public enum Motion: Hashable, Sendable {
    case charLeft
    case charRight
}

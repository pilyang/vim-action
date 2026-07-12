/// 엔진의 현재 모드. Visual-char / Visual-line은 다음 마일스톤에서 추가한다.
public enum Mode: Hashable, Sendable {
    case insert
    case normal
}

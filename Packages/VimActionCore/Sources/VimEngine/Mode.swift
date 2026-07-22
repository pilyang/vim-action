/// 엔진의 현재 모드. Visual의 charwise/linewise 구분은 세션 속성이라
/// 모드 케이스로 나눈다 — 개별 확장 액션에는 싣지 않는다.
public enum Mode: Hashable, Sendable {
    case insert
    case normal
    case visualChar
    case visualLine
}

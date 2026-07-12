/// 엔진이 입력 키 이벤트를 어떻게 처리하라고 탭 계층에 지시하는 결정.
public enum EventDecision: Hashable, Sendable {
    /// 이벤트를 삼킨다 — 원본 키 입력이 최전면 앱에 전달되지 않는다.
    case swallow
    /// 이벤트를 통과시킨다 — 엔진이 관여하지 않고 원본 그대로 앱에 전달된다.
    case passthrough
    /// 원본을 대체한다 — 삼킨 뒤 `actions`가 대신 실행된다.
    case replace
}

/// `handle(_:)` 한 번의 결과: 이 키를 어떻게 처리할지와, 실행할 추상 동작들.
public struct EngineOutput: Hashable, Sendable {
    public var decision: EventDecision
    public var actions: [VimAction]

    public init(decision: EventDecision, actions: [VimAction] = []) {
        self.decision = decision
        self.actions = actions
    }

    /// 원본 키를 앱에 그대로 흘려보낸다 (엔진 미관여).
    public static let passthrough = EngineOutput(decision: .passthrough)
    /// 원본 키를 삼킨다 (동작 없음 — 예: 모드 전환 키).
    public static let swallow = EngineOutput(decision: .swallow)
    /// 원본 키를 삼키고 `actions`를 대신 실행한다 (예: 모션 키).
    public static func replace(_ actions: [VimAction]) -> EngineOutput {
        EngineOutput(decision: .replace, actions: actions)
    }
}

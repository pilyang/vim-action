/// 모드 상태 머신. 정규화된 `Key`를 받아 처리 결정과 추상 동작을 낸다.
///
/// 이 타입은 macOS를 전혀 알지 못한다 — AX 호출, 키 이벤트 합성, 최전면 앱 인식을
/// 하지 않는다. 그런 로직은 전략 디스패처/어댑터의 몫이며, 여기 들어오면 안 된다.
///
/// 스켈레톤 단계에서는 모드 전환(Esc/i)과 통과만 구현한다. 이동 키셋 처리는
/// 다음 마일스톤에서 이 `handle(_:)`에 추가한다.
public struct VimEngine: Sendable {
    /// 현재 모드. 시작 모드는 Insert — 기본적으로 앱의 평소 타이핑을 방해하지 않는다.
    public private(set) var mode: Mode

    public init(mode: Mode = .insert) {
        self.mode = mode
    }

    /// 키 하나를 처리하고 그 결과를 낸다. 필요 시 내부 모드를 전이시킨다.
    public mutating func handle(_ key: Key) -> EngineOutput {
        switch mode {
        case .insert:
            return handleInsert(key)
        case .normal:
            return handleNormal(key)
        }
    }

    private mutating func handleInsert(_ key: Key) -> EngineOutput {
        // Esc는 Normal 모드로 나가며 삼킨다. 그 외 모든 키는 앱으로 통과.
        if key == .escape {
            mode = .normal
            return .swallow
        }
        return .passthrough
    }

    private mutating func handleNormal(_ key: Key) -> EngineOutput {
        // 스켈레톤: i만 Insert 진입으로 처리한다. 이동 키셋은 다음 마일스톤에서 추가.
        if key == .char("i") {
            mode = .insert
            return .swallow
        }
        return .swallow
    }
}

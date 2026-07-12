/// 모드 상태 머신. 정규화된 `Key`를 받아 처리 결정과 추상 동작을 낸다.
///
/// 이 타입은 macOS를 전혀 알지 못한다 — AX 호출, 키 이벤트 합성, 최전면 앱 인식을
/// 하지 않는다. 그런 로직은 전략 디스패처/어댑터의 몫이며, 여기 들어오면 안 된다.
public struct VimEngine: Sendable {
    /// Normal 모드에서 멀티키 시퀀스의 나머지 키를 기다리는 상태 (모드 외 유일한 내부 상태).
    /// 무효한 연속 키가 오면 pending과 그 키를 함께 버리는 no-op이다 (Vim의 무효 커맨드 동작).
    private enum Pending: Sendable {
        case g
    }

    /// 현재 모드. 시작 모드는 Insert — 기본적으로 앱의 평소 타이핑을 방해하지 않는다.
    public private(set) var mode: Mode

    private var pending: Pending?

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
        if let pending {
            self.pending = nil
            return resolve(pending, then: key)
        }

        switch key {
        case .char("i"):
            mode = .insert
            return .swallow
        case .char("a"):
            mode = .insert
            return .replace([.move(.charRightForAppend)])
        case .char("I"):
            mode = .insert
            return .replace([.move(.lineFirstNonBlank)])
        case .char("A"):
            mode = .insert
            return .replace([.move(.lineEndForAppend)])
        case .char("g"):
            pending = .g
            return .swallow
        default:
            break
        }

        if let motion = Self.singleKeyMotions[key] {
            return .replace([.move(motion)])
        }

        // 매핑 없는 modifier 조합(Cmd+C 등)은 시스템 단축키이므로 통과시킨다.
        // modifier 없는 미매핑 키만 삼킨다 (Normal 모드 키가 앱에 새지 않게).
        return key.modifiers.isEmpty ? .swallow : .passthrough
    }

    /// pending을 다음 키로 해소한다. 유효한 연속(gg)만 동작하고, Esc를 포함한
    /// 그 외 키는 no-op으로 삼킨다. `gi`(마지막 삽입 위치로 insert) 같은 실제
    /// Vim 커맨드도 지원 전까지는 여기서 no-op으로 떨어진다.
    private func resolve(_ pending: Pending, then key: Key) -> EngineOutput {
        switch pending {
        case .g:
            if key == .char("g") {
                return .replace([.move(.documentStart)])
            }
            return .swallow
        }
    }

    /// pending 없이 단일 키로 완결되는 모션. `Key`의 Hashable 매칭이라
    /// modifier가 붙은 키(Ctrl+h 등)는 자연히 걸리지 않는다.
    private static let singleKeyMotions: [Key: Motion] = [
        .char("h"): .charLeft,
        .char("l"): .charRight,
        .char("j"): .lineDown,
        .char("k"): .lineUp,
        .char("w"): .wordForward,
        .char("b"): .wordBackward,
        .char("e"): .wordEndForward,
        .char("0"): .lineStart,
        .char("^"): .lineFirstNonBlank,
        .char("$"): .lineEnd,
        .char("G"): .documentEnd,
    ]
}

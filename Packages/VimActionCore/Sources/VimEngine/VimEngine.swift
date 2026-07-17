/// 모드 상태 머신. 정규화된 `Key`를 받아 처리 결정과 추상 동작을 낸다.
///
/// 이 타입은 macOS를 전혀 알지 못한다 — AX 호출, 키 이벤트 합성, 최전면 앱 인식을
/// 하지 않는다. 그런 로직은 전략 디스패처/어댑터의 몫이며, 여기 들어오면 안 된다.
public struct VimEngine: Sendable {
    /// Normal 모드에서 누적 중인 부분 커맨드 (모드 외 유일한 내부 상태).
    /// `3w`·`dd`·`diw` 같은 멀티키 커맨드의 문법 슬롯을 채워가는 빌더이며,
    /// 무효한 연속 키가 오면 pending과 그 키를 함께 버리는 no-op이다 (Vim의 무효 커맨드 동작).
    private struct PendingCommand: Sendable {
        /// 선행 카운트 — `3w`의 3, `2dd`의 2.
        var count: Int?
        /// 대기 중인 오퍼레이터 — `d`.
        var op: VimAction.Operator?
        /// 오퍼레이터 뒤 카운트 — `d3w`의 3. 유효 카운트는 두 카운트의 곱이다 (`2d3w` = 6).
        var opCount: Int?
        /// 완결 키 하나를 기다리는 접두. `op` 유무로 두 케이스가 구분된다.
        var prefix: Prefix?

        enum Prefix: Sendable {
            /// `g` — `gg` 대기 (`op == nil`일 때만).
            case g
            /// `di`/`da` 후 오브젝트 키 대기 (`op != nil` 보장).
            case textObjectScope(VimAction.TextObject.Scope)
        }
    }

    /// 현재 모드. 시작 모드는 Insert — 기본적으로 앱의 평소 타이핑을 방해하지 않는다.
    public private(set) var mode: Mode

    private var pending: PendingCommand?

    /// 주입된 동작 설정. 기본값(빈 셋)은 기존 동작을 그대로 유지한다.
    private let configuration: Configuration

    public init(mode: Mode = .insert, configuration: Configuration = Configuration()) {
        self.mode = mode
        self.configuration = configuration
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
        // 취소 — 어떤 매핑보다 우선하는 cross-cutting 규칙 (step 진입 전).
        //
        // Esc는 정확 매치(수식자 없음)로 pending을 폐기하고 Normal에 머문다.
        // 탈출 modifier 콤보는 커맨드 입력 도중이라도 pending을 폐기하고 Insert로
        // 탈출시킨다 — 시스템 단축키(Spotlight/Raycast 등) 직후 타이핑을 막지
        // 않기 위함. 수식자 붙은 Esc(Cmd+Esc 등)는 Esc 분기가 아니라 이 판정을 탄다.
        if key == .escape {
            pending = nil
            return .swallow
        }
        if isEscapeCombo(key) {
            pending = nil
            mode = .insert
            return .passthrough
        }

        return step(key)
    }

    /// 누적 중인 부분 커맨드를 이번 키로 한 스텝 진행시킨다 — 결과는 셋 중 하나다.
    ///
    /// - extend: 문법이 계속되면 pending에 슬롯을 채워 유지한다 (`g`, 이후 카운트·오퍼레이터).
    /// - complete: 커맨드가 완결되면 pending을 비우고 액션을 낸다.
    /// - invalid: 무효한 연속이면 pending과 이번 키를 함께 버리는 no-op이다.
    ///
    /// 진입 시 pending을 비워두므로 extend 경로만 명시적으로 되채운다.
    private mutating func step(_ key: Key) -> EngineOutput {
        let current = pending ?? PendingCommand()
        pending = nil

        // 접두(prefix)는 완결 키 하나만 기다린다 — 다른 어떤 매핑보다 먼저 본다.
        // 케이스 망라 switch라 Prefix가 늘면 여기서 컴파일이 깨진다 — 새 접두가
        // 아래 일반 매핑으로 새는 실수를 타입으로 막는다.
        // `gi` 같은 실제 Vim 커맨드도 지원 전까지는 invalid로 떨어진다.
        if let prefix = current.prefix {
            switch prefix {
            case .g:
                if key == .char("g") {
                    return .replace([.move(.documentStart)])
                }
                return .swallow
            case .textObjectScope:
                // 생산 경로 없음 — `di`/`da`를 만드는 Phase 3에서 구현한다.
                return .swallow
            }
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
            var next = current
            next.prefix = .g
            pending = next
            return .swallow
        case .char("x"):
            // 전용 케이스 없이 delete-over-motion 재사용 — 카운트는 반복이 아니라
            // 범위의 count로 담는다 (3x = 3문자를 한 편집 단위로).
            return .replace([.edit(.delete, .motion(.charRight, count: current.count ?? 1))])
        default:
            break
        }

        // 카운트 digit — 1–9는 누적 시작/연장, 0은 누적 중일 때만 자리값이다
        // (카운트 슬롯이 비어 있으면 아래 모션 매핑의 lineStart로 떨어진다).
        if key.modifiers.isEmpty, case .char(let c) = key.base, c.isASCII,
            let digit = c.wholeNumberValue, c.isNumber,
            digit >= 1 || current.count != nil
        {
            var next = current
            next.count = Self.accumulate(next.count, digit: digit)
            pending = next
            return .swallow
        }

        if let motion = Self.singleKeyMotions[key] {
            // 카운트 붙은 모션은 `.move` 반복으로 낸다 — `.move`에 count 슬롯을
            // 두지 않아 단일 모션 경로(count 1)가 기존 계약 그대로 유지된다.
            return .replace(Array(repeating: VimAction.move(motion), count: current.count ?? 1))
        }

        // 매핑 없는 modifier 조합(Cmd+C 등)은 시스템 단축키이므로 통과시킨다.
        // (탈출 콤보는 handleNormal이 이미 걸렀으므로 여기는 비탈출 콤보만 온다.)
        // modifier 없는 미매핑 키만 삼킨다 (Normal 모드 키가 앱에 새지 않게).
        if key.modifiers.isEmpty {
            return .swallow
        }
        return .passthrough
    }

    /// 탈출 modifier(예: Cmd/Opt)와 교집합이 있는 콤보인지 — Spotlight/Raycast 등
    /// 시스템 단축키 직후의 타이핑을 막지 않기 위해 이런 콤보는 Insert로 탈출시킨다.
    private func isEscapeCombo(_ key: Key) -> Bool {
        !key.modifiers.isDisjoint(with: configuration.normalModeEscapeModifiers)
    }

    /// 카운트 누적 상한. 무제한이면 Int 오버플로 트랩(시스템 전역 훅 크래시)과
    /// 반복 출력 배열 폭주(탭 콜백 타임아웃) 리스크가 있어 여기서 클램프한다.
    private static let maxCount = 9_999

    /// digit 하나를 카운트에 누적한다 — 상한 도달 후의 초과 자리 digit은
    /// 무시하고 누적 상태를 유지한다.
    private static func accumulate(_ count: Int?, digit: Int) -> Int {
        min((count ?? 0) * 10 + digit, maxCount)
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

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
        /// 대기 중인 오퍼레이터 — `d`/`c`/`y`.
        var op: VimAction.Operator?
        /// 오퍼레이터 뒤 카운트 — `d3w`의 3. 유효 카운트는 두 카운트의 곱이다 (`2d3w` = 6).
        var opCount: Int?
        /// 완결 키 하나를 기다리는 접두. `op` 유무로 두 케이스가 구분된다.
        var prefix: Prefix?

        enum Prefix: Sendable {
            /// `g` — `gg` 대기. `op == nil`이면 모션 gg, `op != nil`이면
            /// linewise documentStart(dgg/cgg)로 완결된다.
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
        case .visualChar, .visualLine:
            return handleVisual(key)
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
        switch current.prefix {
        case .g:
            // `gi` 같은 실제 Vim 커맨드도 지원 전까지는 invalid로 떨어진다.
            if key == .char("g") {
                if let op = current.op {
                    // dgg/cgg — 절대 모션이라 카운트(선행·op 뒤 어느 쪽이든)가
                    // 있으면 invalid다 (dG와 같은 기준). extend 시점이 아니라
                    // 여기서 거른다 — extend에서 거르면 invalid 직후의 g가 새
                    // .g pending을 열어 잔류 상태가 생긴다.
                    guard current.count == nil && current.opCount == nil else { return .swallow }
                    return complete(op, .linewiseMotion(.documentStart, count: 1))
                }
                // 모션 gg의 선행 카운트는 버린다 — 3gg도 documentStart 단일
                // 출력 (mode-change 키의 count 무시와 같은 원칙).
                return .replace([.move(.documentStart)])
            }
            return .swallow
        case .textObjectScope(let scope):
            // 오퍼레이터+i/a(di/ci/ya 등)로만 진입하므로 op != nil이 보장된다.
            //
            // 카운트+오브젝트(d2i(·3diw 등)는 Vim 의미(괄호 중첩 단계·단어 수)가
            // 있는데 표현할 수 없다. 파괴적 편집이라 오해석 대신 invalid로
            // 이연한다 (d3G와 같은 기준).
            guard current.count == nil && current.opCount == nil else { return .swallow }
            guard let op = current.op else { return .swallow }
            if key == .char("w") {
                return complete(op, .textObject(.word(scope)))
            }
            if let quote = Self.quoteObjectKeys[key] {
                return complete(op, .textObject(.quote(quote, scope)))
            }
            if let pair = Self.pairObjectKeys[key] {
                return complete(op, .textObject(.pair(pair, scope)))
            }
            return .swallow
        case nil:
            break
        }

        // g — op 유무와 무관하게 같은 prefix extend다 (gg / dgg).
        if key == .char("g") {
            return openGPrefix(current)
        }

        // 오퍼레이터 대기 — 뒤에 올 수 있는 건 스코프(i/a)·카운트·모션·
        // 오퍼레이터 키(dd) 뿐이다.
        if let op = current.op {
            // i/a는 Insert 진입이 아니라 텍스트 오브젝트 스코프 접두다.
            if key == .char("i") || key == .char("a") {
                var next = current
                next.prefix = .textObjectScope(key == .char("i") ? .inner : .around)
                pending = next
                return .swallow
            }

            // 카운트 digit → opCount 누적. d 뒤의 0은 opCount가 비어 있으면
            // 아래 화이트리스트의 lineStart로 떨어져 모션 d0이 된다 (0-규칙).
            if let digit = Self.countDigit(key, accumulating: current.opCount != nil) {
                var next = current
                next.opCount = Self.accumulate(next.opCount, digit: digit)
                pending = next
                return .swallow
            }

            // 유효 카운트는 두 카운트의 곱 — 2d3w = 6단어. 곱은 개별 카운트의
            // 9,999 클램프를 우회할 수 있어(9999d9999w ≈ 1e8) 동일 상한으로 다시
            // 클램프한다 — 소비자가 신뢰하는 카운트 상한을 곱 경로도 지키게 한다.
            let effectiveCount = min((current.count ?? 1) * (current.opCount ?? 1), Self.maxCount)
            // 오퍼레이터 키 반복(dd/cc/yy)은 줄 단위 범위다. 혼합(dc, yd 등)은
            // 문법에 없으므로 아래 invalid로 떨어진다.
            if Self.operatorKeys[key] == op {
                return complete(op, .line(count: effectiveCount))
            }
            if let entry = Self.opMotions[key] {
                switch entry.kind {
                case .charwise:
                    return complete(op, .motion(entry.motion, count: effectiveCount))
                case .linewiseRelative:
                    return complete(op, .linewiseMotion(entry.motion, count: effectiveCount))
                case .linewiseAbsolute:
                    // Vim의 d3G는 "3번 줄까지"라는 절대 줄 의미인데 표현할 수
                    // 없다. 파괴적 편집이라 오해석 대신 카운트가 하나라도 있으면
                    // invalid로 이연한다 (모션 3G의 반복-수용과 다른 기준).
                    guard current.count == nil && current.opCount == nil else { return .swallow }
                    return complete(op, .linewiseMotion(entry.motion, count: 1))
                }
            }
            // 화이트리스트 밖은 전부 invalid — dq 같은 무효 키를 포함한다.
            return .swallow
        }

        // 최상위 오퍼레이터 키(d/c/y) — op 슬롯을 채우고 다음 키를 기다린다.
        if let op = Self.operatorKeys[key] {
            var next = current
            next.op = op
            pending = next
            return .swallow
        }

        switch key {
        case .char("i"):
            mode = .insert
            return .swallow
        case .char("v"):
            // 선행 카운트는 버린다 (3i와 같은 원칙). 오퍼레이터 대기 중의 v(dv)는
            // 여기 오지 않고 위 op 분기에서 invalid로 떨어진다 — 특례 없음.
            mode = .visualChar
            return .replace([.beginSelection(linewise: false)])
        case .char("V"):
            mode = .visualLine
            return .replace([.beginSelection(linewise: true)])
        case .char("a"):
            mode = .insert
            return .replace([.move(.charRightForAppend)])
        case .char("I"):
            mode = .insert
            return .replace([.move(.lineFirstNonBlank)])
        case .char("A"):
            mode = .insert
            return .replace([.move(.lineEndForAppend)])
        case .char("x"):
            // 전용 케이스 없이 delete-over-motion 재사용 — 카운트는 반복이 아니라
            // 범위의 count로 담는다 (3x = 3문자를 한 편집 단위로).
            return .replace([.edit(.delete, .motion(.charRight, count: current.count ?? 1))])
        default:
            break
        }

        // 카운트 붙은 모션은 `.move` 반복으로 낸다 — `.move`에 count 슬롯을
        // 두지 않아 단일 모션 경로(count 1)가 기존 계약 그대로 유지된다.
        return motionTail(key, current, make: VimAction.move)
    }

    private mutating func handleVisual(_ key: Key) -> EngineOutput {
        // 취소 최우선 — Normal과 동일한 cross-cutting 규칙 (step 진입 전).
        //
        // Esc 정확 매치는 선택을 해제하며 Normal로 복귀한다. 탈출 modifier 콤보는
        // passthrough라 clearSelection을 함께 실을 수 없다(결정이 배타적) —
        // 원본 콤보 전달이 우선이고(Cmd+C가 선택에 작용할 수 있어 오히려 유용),
        // 남는 화면 선택·어댑터 세션은 수용한다: beginSelection이 항상 리셋이라
        // stale 세션이 다음 진입을 오염시키지 않는다.
        if key == .escape {
            pending = nil
            mode = .normal
            return .replace([.clearSelection])
        }
        if isEscapeCombo(key) {
            pending = nil
            mode = .insert
            return .passthrough
        }

        return visualStep(key)
    }

    /// Visual의 step — Normal `step`과 같은 extend/complete/invalid 구조지만
    /// 문법이 다르다: 오퍼레이터는 대기 없이 선택 범위로 즉시 완결되고,
    /// pending에는 카운트와 g 접두만 쌓인다.
    private mutating func visualStep(_ key: Key) -> EngineOutput {
        let current = pending ?? PendingCommand()
        pending = nil

        switch current.prefix {
        case .g:
            // 모션 gg — 선행 카운트는 버린다 (Normal의 gg와 동일 원칙).
            if key == .char("g") {
                return .replace([.extendSelection(.documentStart)])
            }
            return .swallow
        case .textObjectScope:
            // Visual에는 진입 경로가 없다 (오퍼레이터 대기가 없으므로) — 방어적 invalid.
            return .swallow
        case nil:
            break
        }

        if key == .char("g") {
            return openGPrefix(current)
        }

        // v/V — 같은 키는 이탈, 다른 키는 wise 전환 (Vim 동일). 전환은 진입과
        // 다른 신호다: begin은 항상 리셋, switchSelectionWise는 앵커 유지 +
        // wise 교체·재적용.
        switch key {
        case .char("v"):
            if mode == .visualChar {
                mode = .normal
                return .replace([.clearSelection])
            }
            mode = .visualChar
            return .replace([.switchSelectionWise(linewise: false)])
        case .char("V"):
            if mode == .visualLine {
                mode = .normal
                return .replace([.clearSelection])
            }
            mode = .visualLine
            return .replace([.switchSelectionWise(linewise: true)])
        default:
            break
        }

        // 선택 동작 y d x c — 선택 범위로 즉시 완결. 선행 카운트는 버리고
        // 실행한다 (Vim 동일): 피연산자가 이미 확정된 선택 범위라 카운트가
        // 결과를 바꿀 여지가 없다 — 오해석이 가능해 invalid인 d3G와 다른 기준.
        // y/d/x는 Normal 복귀, c는 complete가 Insert로 전이한다(기존 단일화 헬퍼).
        if let op = Self.visualOperatorKeys[key] {
            mode = .normal
            // y는 범위를 파괴하지 않아 화면 선택이 남는다 — Vim처럼 collapse를
            // 명시 출력한다 (복사 → 해제 순서는 배열이 보장). d/x/c는 범위
            // 삭제로 하이라이트가 자연 소멸하므로 동반하지 않는다.
            if op == .yank {
                return .replace([.edit(.yank, .selection), .clearSelection])
            }
            return complete(op, .selection)
        }

        // 모션은 전부 선택 확장이다 — 카운트는 `.move`와 같은 반복 출력.
        // linewise 세션의 줄 반올림은 wise를 아는 어댑터의 실행 규칙이다.
        return motionTail(key, current, make: VimAction.extendSelection)
    }

    /// step/visualStep 공통 꼬리 문법 — 카운트 digit 축적, 단일 키 모션(카운트는
    /// 반복 출력), 미매핑 폴백. Normal은 `.move`, Visual은 `.extendSelection`
    /// 생성자를 주입한다 — 0-규칙·클램프·통과 기준이 두 모드에서 조용히
    /// 어긋나지 않게 정책을 한 곳에 둔다.
    private mutating func motionTail(
        _ key: Key, _ current: PendingCommand, make: (Motion) -> VimAction
    ) -> EngineOutput {
        // 카운트 digit — 카운트 슬롯이 비어 있는 0은 아래 모션 매핑의
        // lineStart로 떨어진다 (0-규칙).
        if let digit = Self.countDigit(key, accumulating: current.count != nil) {
            var next = current
            next.count = Self.accumulate(next.count, digit: digit)
            pending = next
            return .swallow
        }

        if let motion = Self.singleKeyMotions[key] {
            return .replace(Array(repeating: make(motion), count: current.count ?? 1))
        }

        // 매핑 없는 modifier 조합(Cmd+C 등)은 시스템 단축키이므로 통과시킨다.
        // (탈출 콤보는 handleNormal/handleVisual이 이미 걸렀으므로 여기는
        // 비탈출 콤보만 온다.) modifier 없는 미매핑 키만 삼킨다 (모드 키가
        // 앱에 새지 않게).
        if key.modifiers.isEmpty {
            return .swallow
        }
        return .passthrough
    }

    /// g 접두 열기 — 완결 키(gg 등) 하나를 기다리는 extend. Normal·Visual 공통이며,
    /// 카운트 invalid 판정은 완결 시점(둘째 g)의 몫이다.
    private mutating func openGPrefix(_ current: PendingCommand) -> EngineOutput {
        var next = current
        next.prefix = .g
        pending = next
        return .swallow
    }

    /// 커맨드 완결 공통 경로 — change는 편집 출력과 함께 Insert로 전이한다
    /// (`cc`/`c$`/`ciw` 전부, `a`/`A`의 전이+출력 동시 패턴과 동일).
    private mutating func complete(_ op: VimAction.Operator, _ range: VimAction.TextRange) -> EngineOutput {
        if op == .change {
            mode = .insert
        }
        return .replace([.edit(op, range)])
    }

    /// 탈출 modifier(예: Cmd/Opt)와 교집합이 있는 콤보인지 — Spotlight/Raycast 등
    /// 시스템 단축키 직후의 타이핑을 막지 않기 위해 이런 콤보는 Insert로 탈출시킨다.
    private func isEscapeCombo(_ key: Key) -> Bool {
        !key.modifiers.isDisjoint(with: configuration.normalModeEscapeModifiers)
    }

    /// 이 키가 카운트 digit이면 그 값 (0-규칙 적용) — 1–9는 항상 누적을
    /// 시작/연장하고, 0은 해당 카운트 슬롯이 이미 누적 중일 때만 자리값이다.
    /// modifier가 붙은 digit(Ctrl+3 등)은 카운트가 아니다.
    private static func countDigit(_ key: Key, accumulating: Bool) -> Int? {
        guard key.modifiers.isEmpty, case .char(let c) = key.base, c.isASCII, c.isNumber,
            let digit = c.wholeNumberValue, digit >= 1 || accumulating
        else { return nil }
        return digit
    }

    /// 카운트 누적 상한. 무제한이면 Int 오버플로 트랩(시스템 전역 훅 크래시)과
    /// 반복 출력 배열 폭주(탭 콜백 타임아웃) 리스크가 있어 여기서 클램프한다.
    private static let maxCount = 9_999

    /// digit 하나를 카운트에 누적한다 — 상한 도달 후의 초과 자리 digit은
    /// 무시하고 누적 상태를 유지한다.
    private static func accumulate(_ count: Int?, digit: Int) -> Int {
        min((count ?? 0) * 10 + digit, maxCount)
    }

    /// 최상위에서 op 슬롯을 여는 오퍼레이터 키. 오퍼레이터 대기 중 "자신의 키"
    /// 반복(dd/cc/yy = 줄 범위) 판정에도 같은 테이블을 쓴다.
    private static let operatorKeys: [Key: VimAction.Operator] = [
        .char("d"): .delete,
        .char("c"): .change,
        .char("y"): .yank,
    ]

    /// 오퍼레이터 뒤 모션의 종류 — 출력 범위와 카운트 규칙이 kind별로 갈린다.
    private enum OpMotionKind: Sendable {
        /// charwise-safe 범위 (`.motion`) — 카운트는 두 카운트의 곱.
        case charwise
        /// 줄 단위 상대 범위 (`.linewiseMotion`, `d2j` = 아래로 2) — 카운트는
        /// charwise와 같은 곱 규칙.
        case linewiseRelative
        /// 줄 단위 절대 범위 (`.linewiseMotion`) — 절대 줄 의미를 표현할 수
        /// 없어 카운트가 하나라도 있으면 invalid.
        case linewiseAbsolute
    }

    /// 오퍼레이터 뒤에 올 수 있는 단일 키 모션 화이트리스트 — kind가 출력
    /// 범위와 카운트 규칙을 정한다. 멀티키인 gg만 prefix 메커니즘(`.g`)이
    /// 따로 완결한다.
    private static let opMotions: [Key: (motion: Motion, kind: OpMotionKind)] = [
        .char("w"): (.wordForward, .charwise),
        .char("b"): (.wordBackward, .charwise),
        .char("e"): (.wordEndForward, .charwise),
        .char("h"): (.charLeft, .charwise),
        .char("l"): (.charRight, .charwise),
        .char("0"): (.lineStart, .charwise),
        .char("^"): (.lineFirstNonBlank, .charwise),
        .char("$"): (.lineEnd, .charwise),
        .char("j"): (.lineDown, .linewiseRelative),
        .char("k"): (.lineUp, .linewiseRelative),
        .char("G"): (.documentEnd, .linewiseAbsolute),
    ]

    /// Visual에서 선택 범위로 즉시 완결되는 오퍼레이터 키 — `operatorKeys`에서
    /// 파생해 두 테이블이 어긋날 수 없게 한다. `x`는 전용 케이스 없이 `d`와
    /// 동일 출력이다 (PRD가 둘 다 "선택 삭제"로 정의).
    private static let visualOperatorKeys: [Key: VimAction.Operator] =
        operatorKeys.merging([.char("x"): .delete]) { _, added in added }

    /// 스코프 접두(i/a) 뒤 quote 오브젝트 완결 키.
    private static let quoteObjectKeys: [Key: VimAction.TextObject.Quote] = [
        .char("\""): .double,
        .char("'"): .single,
        .char("`"): .backtick,
    ]

    /// 스코프 접두(i/a) 뒤 pair 오브젝트 완결 키 — 여닫이 양쪽 키와
    /// Vim 별칭(b=paren, B=brace)을 모두 인정한다.
    private static let pairObjectKeys: [Key: VimAction.TextObject.Pair] = [
        .char("("): .paren, .char(")"): .paren, .char("b"): .paren,
        .char("["): .bracket, .char("]"): .bracket,
        .char("{"): .brace, .char("}"): .brace, .char("B"): .brace,
        .char("<"): .angle, .char(">"): .angle,
    ]

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

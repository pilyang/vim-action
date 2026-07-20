import Testing

@testable import VimEngine

/// quote·pair 텍스트 오브젝트 픽스처 — 완결 키 매핑(별칭 포함)과
/// 카운트+오브젝트 invalid 규칙의 커버. word 오브젝트와 스코프 접두(i/a)
/// 경로 자체는 `EditFixtures`/`OperatorFixtures`가 담당한다.

// 완결 키 전수 — 여닫이 양쪽 키와 Vim 별칭(b=paren, B=brace)을 모두 인정한다.
private let quoteObjectKeys: [(Character, VimAction.TextObject.Quote)] = [
    ("\"", .double),
    ("'", .single),
    ("`", .backtick),
]

private let pairObjectKeys: [(Character, VimAction.TextObject.Pair)] = [
    ("(", .paren), (")", .paren), ("b", .paren),
    ("[", .bracket), ("]", .bracket),
    ("{", .brace), ("}", .brace), ("B", .brace),
    ("<", .angle), (">", .angle),
]

private let scopes: [(Character, VimAction.TextObject.Scope)] = [
    ("i", .inner),
    ("a", .around),
]

// 전수 매트릭스 (d 기준): quote 3키 × {i,a} + pair 10키 × {i,a}.
let quoteObjectFixtures: [KeySequenceFixture] = scopes.flatMap { scopeKey, scope in
    quoteObjectKeys.map { key, quote in
        KeySequenceFixture(
            "d\(scopeKey)\(key) → delete \(scope) quote(\(quote))",
            startMode: .normal,
            steps: [
                step(.char("d"), .swallow),
                step(.char(scopeKey), .swallow),
                step(.char(key), .replace([.edit(.delete, .textObject(.quote(quote, scope)))])),
            ],
            finalMode: .normal
        )
    }
}

@Test(arguments: quoteObjectFixtures)
func quoteObjects(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let pairObjectFixtures: [KeySequenceFixture] = scopes.flatMap { scopeKey, scope in
    pairObjectKeys.map { key, pair in
        KeySequenceFixture(
            "d\(scopeKey)\(key) → delete \(scope) pair(\(pair))",
            startMode: .normal,
            steps: [
                step(.char("d"), .swallow),
                step(.char(scopeKey), .swallow),
                step(.char(key), .replace([.edit(.delete, .textObject(.pair(pair, scope)))])),
            ],
            finalMode: .normal
        )
    }
}

@Test(arguments: pairObjectFixtures)
func pairObjects(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 오퍼레이터별 모드 전이 — change는 완결과 함께 Insert, yank는 Normal 유지.
let textObjectModeTransitionFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "ci\" → change inner double-quote, Insert 전이 — 이후 키는 통과",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("i"), .swallow),
            step(.char("\""), .replace([.edit(.change, .textObject(.quote(.double, .inner)))])),
            step(.char("w"), .passthrough),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "ya( → yank around paren, Normal 유지 — 이후 j는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("y"), .swallow),
            step(.char("a"), .swallow),
            step(.char("("), .replace([.edit(.yank, .textObject(.pair(.paren, .around)))])),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: textObjectModeTransitionFixtures)
func textObjectModeTransitions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 카운트+텍스트 오브젝트는 invalid — Vim의 d2i((중첩 2단계)·3diw(3단어)는
// 실제 의미가 있는데 표현할 수 없고, 파괴적 편집이라 오해석 대신 invalid로
// 이연한다 (d3G와 같은 기준). 선행 카운트·오퍼레이터 뒤 카운트 모두 해당.
let countedTextObjectFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "d3iw → no-op (op 뒤 카운트+오브젝트) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("3"), .swallow),
            step(.char("i"), .swallow),
            step(.char("w"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "2diw → no-op (선행 카운트+오브젝트) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("2"), .swallow),
            step(.char("d"), .swallow),
            step(.char("i"), .swallow),
            step(.char("w"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "d2i( → no-op (카운트+pair 오브젝트)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("2"), .swallow),
            step(.char("i"), .swallow),
            step(.char("("), .swallow),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "c2a\" → no-op — Insert 진입 없음, 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("2"), .swallow),
            step(.char("a"), .swallow),
            step(.char("\""), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: countedTextObjectFixtures)
func countedTextObjects(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 오브젝트 자리의 무효 키는 pending과 키를 함께 버리는 no-op — change라도
// Insert 진입이 없다 (diq 핀의 change 대응).
let textObjectInvalidFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "ciq → no-op (무효 object 키) — Insert 진입 없음, 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("i"), .swallow),
            step(.char("q"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    )
]

@Test(arguments: textObjectInvalidFixtures)
func textObjectInvalids(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

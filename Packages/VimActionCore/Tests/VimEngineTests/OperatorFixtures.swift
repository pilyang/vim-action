import Testing

@testable import VimEngine

/// c/y 오퍼레이터 픽스처 — 오퍼레이터 배관 일반화의 커버.
/// d 계열은 `EditFixtures.swift`가 담당하고, 여기는 change/yank 고유 동작
/// (change의 Insert 전이, yank의 Normal 유지)과 혼합 오퍼레이터 invalid를 편다.

// 오퍼레이터 뒤 모션 화이트리스트 — d와 같은 charwise-safe 집합 8종.
private let operatorMotionKeys: [(Character, Motion)] = [
    ("w", .wordForward),
    ("b", .wordBackward),
    ("e", .wordEndForward),
    ("h", .charLeft),
    ("l", .charRight),
    ("0", .lineStart),
    ("^", .lineFirstNonBlank),
    ("$", .lineEnd),
]

// change는 완결과 함께 Insert로 전이한다. cw 특례(Vim의 ce 동작)는 엔진이
// 흉내내지 않는다 — 특례 조건(커서가 공백 위인지)은 버퍼 문맥이 필요해 엔진이
// 판단 불가. literal 출력을 내고 의미 복원은 어댑터 몫이다.
let changeMotionFixtures: [KeySequenceFixture] = operatorMotionKeys.map { key, motion in
    KeySequenceFixture(
        "c\(key) → change over \(motion), Insert 전이",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char(key), .replace([.edit(.change, .motion(motion, count: 1))])),
        ],
        finalMode: .insert
    )
}

@Test(arguments: changeMotionFixtures)
func changeMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let yankMotionFixtures: [KeySequenceFixture] = operatorMotionKeys.map { key, motion in
    KeySequenceFixture(
        "y\(key) → yank over \(motion), Normal 유지",
        startMode: .normal,
        steps: [
            step(.char("y"), .swallow),
            step(.char(key), .replace([.edit(.yank, .motion(motion, count: 1))])),
        ],
        finalMode: .normal
    )
}

@Test(arguments: yankMotionFixtures)
func yankMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 오퍼레이터 키 반복(cc/yy)은 dd와 같은 줄 단위 범위 — 카운트도 같은 곱 규칙.
let operatorLineFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "cc → 현재 줄 change, Insert 전이 — 이후 키는 Insert 통과",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("c"), .replace([.edit(.change, .line(count: 1))])),
            step(.char("w"), .passthrough),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "yy → 현재 줄 yank, Normal 유지 — 이후 j는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("y"), .swallow),
            step(.char("y"), .replace([.edit(.yank, .line(count: 1))])),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "2cc → 2줄 change (선행 카운트)",
        startMode: .normal,
        steps: [
            step(.char("2"), .swallow),
            step(.char("c"), .swallow),
            step(.char("c"), .replace([.edit(.change, .line(count: 2))])),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "c2c → 2줄 change (opCount)",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("2"), .swallow),
            step(.char("c"), .replace([.edit(.change, .line(count: 2))])),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "2y3y → 카운트 곱 6줄 yank",
        startMode: .normal,
        steps: [
            step(.char("2"), .swallow),
            step(.char("y"), .swallow),
            step(.char("3"), .swallow),
            step(.char("y"), .replace([.edit(.yank, .line(count: 6))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: operatorLineFixtures)
func operatorLines(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 텍스트 오브젝트 조합 — 스코프 접두(i/a) 경로는 오퍼레이터 공용이다.
let operatorTextObjectFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "ciw → change inner word, Insert 전이",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("i"), .swallow),
            step(.char("w"), .replace([.edit(.change, .textObject(.word(.inner)))])),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "caw → change around word, Insert 전이",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("a"), .swallow),
            step(.char("w"), .replace([.edit(.change, .textObject(.word(.around)))])),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "yiw → yank inner word, Normal 유지",
        startMode: .normal,
        steps: [
            step(.char("y"), .swallow),
            step(.char("i"), .swallow),
            step(.char("w"), .replace([.edit(.yank, .textObject(.word(.inner)))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "yaw → yank around word, Normal 유지",
        startMode: .normal,
        steps: [
            step(.char("y"), .swallow),
            step(.char("a"), .swallow),
            step(.char("w"), .replace([.edit(.yank, .textObject(.word(.around)))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: operatorTextObjectFixtures)
func operatorTextObjects(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 혼합 오퍼레이터(dc, yd 등)는 문법에 없다 — pending과 키를 함께 버리는
// invalid no-op. change가 무효로 끝나면 Insert 전이도 없다.
private let mixedOperatorPairs: [(Character, Character)] = [
    ("d", "c"), ("d", "y"),
    ("c", "d"), ("c", "y"),
    ("y", "d"), ("y", "c"),
]

let mixedOperatorFixtures: [KeySequenceFixture] = mixedOperatorPairs.map { first, second in
    KeySequenceFixture(
        "\(first)\(second) → no-op (혼합 오퍼레이터) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char(first), .swallow),
            step(.char(second), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    )
}

@Test(arguments: mixedOperatorFixtures)
func mixedOperators(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// c 뒤 무효·이연 키 핀 — dq/dj/dg 핀(EditFixtures)의 change 대응.
// cj(linewise)·cg(dgg 문법)는 이후 확장에서 의미가 생기며 이 핀이 갱신된다.
let changeInvalidFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "cq → no-op (무효 키) — 이후 w는 단일 모션, Insert 진입 없음",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("q"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "cj → no-op (linewise-over-motion 이연)",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("j"), .swallow),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "cg → no-op (g 접두는 오퍼레이터 뒤에 못 온다) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("g"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: changeInvalidFixtures)
func changeInvalids(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

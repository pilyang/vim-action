import Testing

@testable import VimEngine

/// 편집 커맨드(`.edit` 출력) 픽스처 — `x`, `d`+모션, `dd`, 텍스트 오브젝트.

// `x`는 전용 케이스가 아니라 delete-over-motion의 재사용이다 —
// `.edit(.delete, .motion(.charRight, count:))`. 줄 끝 문자 삭제 같은 경계는
// 어댑터 몫 (charRight/charRightForAppend 분리와 동일 원칙).
let deleteCharFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "x → delete over charRight ×1",
        startMode: .normal,
        steps: [step(.char("x"), .replace([.edit(.delete, .motion(.charRight, count: 1))]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3x → delete over charRight ×3 (한 편집 단위)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("x"), .replace([.edit(.delete, .motion(.charRight, count: 3))])),
        ],
        finalMode: .normal
    ),
    // 편집 후에도 Normal 유지 — 후속 키가 정상 동작하는지 겸사 확인.
    KeySequenceFixture(
        "x 후 j는 단일 모션 — 편집이 pending을 남기지 않는다",
        startMode: .normal,
        steps: [
            step(.char("x"), .replace([.edit(.delete, .motion(.charRight, count: 1))])),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: deleteCharFixtures)
func deleteChar(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// `d`+모션 — 오퍼레이터 뒤 charwise 모션은 charwise-safe 집합(w e $ 0 h l b ^)만.
// j/k/G/gg는 linewise 범위로 별도 케이스(`LinewiseFixtures.swift`)가 담당한다.
// 화이트리스트 8종 전수. d 뒤의 0은 카운트 슬롯(opCount)이 비어 있으므로
// 모션 d0이다 (0-규칙).
let deleteMotionFixtures: [KeySequenceFixture] = [
    (Character("w"), Motion.wordForward),
    (Character("b"), Motion.wordBackward),
    (Character("e"), Motion.wordEndForward),
    (Character("h"), Motion.charLeft),
    (Character("l"), Motion.charRight),
    (Character("0"), Motion.lineStart),
    (Character("^"), Motion.lineFirstNonBlank),
    (Character("$"), Motion.lineEnd),
].map { key, motion in
    KeySequenceFixture(
        "d\(key) → delete over \(motion)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char(key), .replace([.edit(.delete, .motion(motion, count: 1))])),
        ],
        finalMode: .normal
    )
}

@Test(arguments: deleteMotionFixtures)
func deleteMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// `D`/`C`/`Y`는 d$/c$/y$의 축약 — 동일 출력이라 어댑터 추가 규칙이 없다.
// 카운트(3D/3C/3Y)는 Vim 의미(줄 끝 + 아래 N-1줄)를 표현할 수 없어 invalid다
// (d3G와 같은 기준).
let lineEndShorthandFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "D → delete over lineEnd (d$ 동일 출력), Normal 유지",
        startMode: .normal,
        steps: [step(.char("D"), .replace([.edit(.delete, .motion(.lineEnd, count: 1))]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "C → change over lineEnd (c$ 동일 출력), Insert 전이",
        startMode: .normal,
        steps: [step(.char("C"), .replace([.edit(.change, .motion(.lineEnd, count: 1))]))],
        finalMode: .insert
    ),
    // yank는 complete가 모드를 바꾸지 않아 Normal이 유지된다 (D와 같고 C와 다름).
    KeySequenceFixture(
        "Y → yank over lineEnd (y$ 동일 출력), Normal 유지",
        startMode: .normal,
        steps: [step(.char("Y"), .replace([.edit(.yank, .motion(.lineEnd, count: 1))]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3D → invalid no-op (절대 의미 표현 불가) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("D"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3C → invalid no-op — Insert 진입 없음, 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("C"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3Y → invalid no-op (클립보드 오염 대신 이연) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("Y"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    // 오퍼레이터 대기 중의 D는 화이트리스트 밖이다 — dD가 dd나 d$로 새지 않는다.
    KeySequenceFixture(
        "dD → invalid no-op (D는 오퍼레이터 뒤에 못 온다) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("D"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "dY → invalid no-op (Y는 오퍼레이터 뒤에 못 온다) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("Y"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: lineEndShorthandFixtures)
func lineEndShorthands(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let deleteLineFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "dd → 현재 줄 삭제",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("d"), .replace([.edit(.delete, .line(count: 1))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "2dd → 2줄 삭제 (선행 카운트)",
        startMode: .normal,
        steps: [
            step(.char("2"), .swallow),
            step(.char("d"), .swallow),
            step(.char("d"), .replace([.edit(.delete, .line(count: 2))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: deleteLineFixtures)
func deleteLines(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 유효 카운트는 선행 카운트와 오퍼레이터 뒤 카운트의 곱이다 — 2d3w = 6단어.
let deleteCountFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "d3w → delete over wordForward ×3 (opCount)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("3"), .swallow),
            step(.char("w"), .replace([.edit(.delete, .motion(.wordForward, count: 3))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "2d3w → 카운트 곱 6",
        startMode: .normal,
        steps: [
            step(.char("2"), .swallow),
            step(.char("d"), .swallow),
            step(.char("3"), .swallow),
            step(.char("w"), .replace([.edit(.delete, .motion(.wordForward, count: 6))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3dd → 카운트 곱이 줄 수로 (3줄 삭제)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("d"), .swallow),
            step(.char("d"), .replace([.edit(.delete, .line(count: 3))])),
        ],
        finalMode: .normal
    ),
    // 곱은 개별 1,000 클램프를 우회할 수 있어(1000×1000 ≈ 1e6) 동일 상한으로
    // 다시 클램프한다 — 모션·dd 두 소비 경로 모두 클램프된 값을 받는다.
    KeySequenceFixture(
        "9999d9999w → 곱이 1,000으로 클램프",
        startMode: .normal,
        steps: [
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("d"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("w"), .replace([.edit(.delete, .motion(.wordForward, count: 1_000))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "9999d9999d → dd 곱도 1,000으로 클램프",
        startMode: .normal,
        steps: [
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("d"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("d"), .replace([.edit(.delete, .line(count: 1_000))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: deleteCountFixtures)
func deleteCounts(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let deleteInvalidFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "d 후 Esc는 오퍼레이터 취소 — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.escape, .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "d 후 무효 키(q)는 둘 다 버리는 no-op — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("q"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    // d 뒤의 x는 오퍼레이터 문법에 없다 — invalid.
    KeySequenceFixture(
        "dx → no-op (x는 오퍼레이터 뒤에 못 온다)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("x"), .swallow),
        ],
        finalMode: .normal
    ),
    // d 뒤의 g는 dgg(linewise)를 위한 extend다 — 무효 완결 키(w)가 오면
    // 그 시점에 pending과 함께 버려지고, 그다음 키부터 정상이다.
    KeySequenceFixture(
        "dg는 extend — 무효 완결 키(w)에 폐기, 그다음 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("g"), .swallow),
            step(.char("w"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: deleteInvalidFixtures)
func deleteInvalids(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 텍스트 오브젝트 — 오퍼레이터 뒤 i/a는 Insert 진입이 아니라 스코프 접두다.
// 여기는 word 오브젝트와 스코프 경로만 — quote/pair는 `TextObjectFixtures.swift`가 담당한다.
let textObjectFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "diw → delete inner word",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("i"), .swallow),
            step(.char("w"), .replace([.edit(.delete, .textObject(.word(.inner)))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "daw → delete around word",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("a"), .swallow),
            step(.char("w"), .replace([.edit(.delete, .textObject(.word(.around)))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "di 후 Esc는 취소 — 이후 w는 단일 모션, Insert 진입 없음",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("i"), .swallow),
            step(.escape, .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    // 오브젝트 자리에 무효 키 — pending과 키를 함께 버리는 no-op.
    KeySequenceFixture(
        "diq → no-op (무효 object 키) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("i"), .swallow),
            step(.char("q"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: textObjectFixtures)
func textObjects(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

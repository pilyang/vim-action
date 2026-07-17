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

// `d`+모션 — 오퍼레이터 뒤에 valid한 모션은 charwise-safe 집합(w e $ 0 h l b ^)만.
// j/k/G는 Vim에서 linewise 범위인데 TextRange.motion엔 그 구분이 없어 어댑터가
// 의미를 복원할 수 없으므로 invalid로 이연한다.
let deleteMotionFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "dw → delete over wordForward",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("w"), .replace([.edit(.delete, .motion(.wordForward, count: 1))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "d$ → delete over lineEnd",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("$"), .replace([.edit(.delete, .motion(.lineEnd, count: 1))])),
        ],
        finalMode: .normal
    ),
    // d 뒤의 0은 카운트 슬롯(opCount)이 비어 있으므로 모션 d0이다 (0-규칙).
    KeySequenceFixture(
        "d0 → delete over lineStart",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("0"), .replace([.edit(.delete, .motion(.lineStart, count: 1))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "de → delete over wordEndForward",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("e"), .replace([.edit(.delete, .motion(.wordEndForward, count: 1))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: deleteMotionFixtures)
func deleteMotions(_ fixture: KeySequenceFixture) {
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
    // linewise 모션(dj)은 TextRange에 구분이 생길 때까지 invalid — 이연 핀.
    KeySequenceFixture(
        "dj → no-op (linewise-over-motion 이연)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("j"), .swallow),
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
    // d 뒤의 g도 invalid — dgg(linewise)는 이연 범위. 무효 시점에 pending이
    // 버려지므로 이후 w는 오퍼레이터 없는 단일 모션이다.
    KeySequenceFixture(
        "dg → no-op (g 접두는 오퍼레이터 뒤에 못 온다) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("g"), .swallow),
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
// 1차 오브젝트는 word(w)만.
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

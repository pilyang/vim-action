import Testing

@testable import VimEngine

/// Normal 모드에서 이동 키 하나 → `.replace([.move(...)])` 단건 픽스처 헬퍼.
private func motion(_ name: String, _ key: Key, _ motion: Motion) -> KeySequenceFixture {
    KeySequenceFixture(
        name,
        startMode: .normal,
        steps: [step(key, .replace([.move(motion)]))],
        finalMode: .normal
    )
}

let charMotionFixtures: [KeySequenceFixture] = [
    motion("h → charLeft", .char("h"), .charLeft),
    motion("l → charRight", .char("l"), .charRight),
    motion("j → lineDown", .char("j"), .lineDown),
    motion("k → lineUp", .char("k"), .lineUp),
]

@Test(arguments: charMotionFixtures)
func charMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let wordMotionFixtures: [KeySequenceFixture] = [
    motion("w → wordForward", .char("w"), .wordForward),
    motion("b → wordBackward", .char("b"), .wordBackward),
    motion("e → wordEndForward", .char("e"), .wordEndForward),
]

@Test(arguments: wordMotionFixtures)
func wordMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// `^`, `$`는 shift 정규화 규칙(문자에 흡수된 shift는 modifiers에 없음)대로
// Character 자체로 매칭되는지도 겸사 검증한다.
let lineMotionFixtures: [KeySequenceFixture] = [
    motion("0 → lineStart", .char("0"), .lineStart),
    motion("^ → lineFirstNonBlank", .char("^"), .lineFirstNonBlank),
    motion("$ → lineEnd", .char("$"), .lineEnd),
]

@Test(arguments: lineMotionFixtures)
func lineMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// gg 멀티키와 g-pending 경계 케이스. 규칙: g 뒤에 유효한 연속(g)만 동작하고,
// 무효 키가 오면 pending과 새 키를 함께 버리는 no-op이다 (Vim의 무효 커맨드 동작).
let documentMotionFixtures: [KeySequenceFixture] = [
    motion("G → documentEnd", .char("G"), .documentEnd),
    KeySequenceFixture(
        "gg → documentStart (첫 g는 pending으로 삼킴)",
        startMode: .normal,
        steps: [
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.move(.documentStart)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "g 후 무효 키(h)는 둘 다 no-op — pending 해제 후 h는 정상 동작",
        startMode: .normal,
        steps: [
            step(.char("g"), .swallow),
            step(.char("h"), .swallow),
            step(.char("h"), .replace([.move(.charLeft)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "g 후 Esc는 pending 취소 — 이후 gg는 정상 동작",
        startMode: .normal,
        steps: [
            step(.char("g"), .swallow),
            step(.escape, .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.move(.documentStart)])),
        ],
        finalMode: .normal
    ),
    // gi는 실제 Vim 커맨드(마지막 삽입 위치로 insert 진입)라 지원 전까지는 no-op.
    // 지원하게 되면 이 픽스처가 documentStart처럼 유효 연속으로 바뀐다.
    KeySequenceFixture(
        "g 후 i는 no-op — Insert로 전환되지 않는다",
        startMode: .normal,
        steps: [
            step(.char("g"), .swallow),
            step(.char("i"), .swallow),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: documentMotionFixtures)
func documentMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 매핑 없는 modifier 조합은 시스템 단축키 보존을 위해 통과시킨다.
let modifierGuardFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "Ctrl+h는 charLeft로 오인하지 않고 통과",
        startMode: .normal,
        steps: [step(.char("h", [.control]), .passthrough)],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Cmd+c는 시스템 단축키이므로 통과",
        startMode: .normal,
        steps: [step(.char("c", [.command]), .passthrough)],
        finalMode: .normal
    ),
]

@Test(arguments: modifierGuardFixtures)
func modifierGuards(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let insertMotionKeyFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "Insert에서 모션 키(j)는 평범한 타이핑으로 통과",
        steps: [step(.char("j"), .passthrough)],
        finalMode: .insert
    )
]

@Test(arguments: insertMotionKeyFixtures)
func insertMotionKeys(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

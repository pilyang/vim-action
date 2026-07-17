import Testing

@testable import VimEngine

/// 취소 깊이 매트릭스 — Esc(정확 매치)와 탈출 modifier 콤보를 부분 커맨드의
/// 각 깊이(카운트 입력 중 / `d` 후 / `di` 후 / `d3` 후)에서 전수 검증한다.
///
/// 규칙: 취소는 어떤 매핑보다 우선하는 cross-cutting 규칙이다.
/// - Esc → pending 전체 폐기 + swallow + Normal 유지
/// - 탈출 콤보 → pending 전체 폐기 + passthrough + Insert 전이
///
/// 각 픽스처는 취소 후 후속 키(w)로 pending이 정말 비었는지까지 확인한다.

private let escapeOnCmdOpt = VimEngine.Configuration(normalModeEscapeModifiers: [.command, .option])
private let cmdSpace = Key(.space, [.command])

/// 부분 커맨드 깊이별 진입 시퀀스 (모든 키가 swallow로 누적되는 상태).
private let pendingDepths: [(label: String, keys: [Key])] = [
    ("카운트 입력 중(3)", [.char("3")]),
    ("카운트 두 자리 입력 중(12)", [.char("1"), .char("2")]),
    ("오퍼레이터 대기(d)", [.char("d")]),
    ("스코프 대기(di)", [.char("d"), .char("i")]),
    ("오퍼레이터 카운트 입력 중(d3)", [.char("d"), .char("3")]),
    ("전체 슬롯 사용 중(2d3)", [.char("2"), .char("d"), .char("3")]),
]

let escCancellationFixtures: [KeySequenceFixture] = pendingDepths.map { depth in
    KeySequenceFixture(
        "\(depth.label) Esc → 전체 폐기, Normal 유지 — 이후 w는 단일 모션",
        startMode: .normal,
        steps: depth.keys.map { step($0, .swallow) } + [
            step(.escape, .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    )
}

@Test(arguments: escCancellationFixtures)
func escCancellations(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let comboCancellationFixtures: [KeySequenceFixture] = pendingDepths.map { depth in
    KeySequenceFixture(
        "\(depth.label) Cmd+Space → 전체 폐기, 통과하며 Insert 탈출",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: depth.keys.map { step($0, .swallow) } + [
            step(cmdSpace, .passthrough)
        ],
        finalMode: .insert
    )
}

@Test(arguments: comboCancellationFixtures)
func comboCancellations(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 탈출 옵션이 꺼져 있으면(기본) 비탈출 콤보 규칙대로 — pending은 invalid로
// 버려지되 모드는 유지된다. 취소 매트릭스의 보완 핀.
let comboCancellationOffFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "탈출 옵션 꺼짐: d 후 Cmd+Space는 invalid no-op — Normal 유지, 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(cmdSpace, .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "탈출 옵션 꺼짐: 카운트 중 비탈출 콤보(Ctrl+d)는 통과, 카운트는 버려진다",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("d", [.control]), .passthrough),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: comboCancellationOffFixtures)
func comboCancellationsOff(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

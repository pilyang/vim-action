import Testing

@testable import VimEngine

/// 취소 깊이 매트릭스 — Esc(정확 매치)와 탈출 modifier 콤보를 부분 커맨드의
/// 각 깊이(카운트 입력 중 / `d` 후 / `di` 후 / `d3` 후)에서 전수 검증한다.
///
/// 규칙: 취소는 어떤 매핑보다 우선하는 cross-cutting 규칙이다.
/// - Esc → pending이 있으면 전체 폐기 + swallow(취소 Esc가 앱 모달까지 닫는
///   부작용 방지), 없으면 passthrough(앱에 취소 전달) — 어느 쪽도 Normal 유지
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
    // change는 완결 시 Insert로 전이하므로, 취소가 전이를 유발하지 않음을 별도로 편다.
    ("오퍼레이터 대기(c)", [.char("c")]),
    ("스코프 대기(ci)", [.char("c"), .char("i")]),
    ("오퍼레이터 카운트 입력 중(d3)", [.char("d"), .char("3")]),
    ("linewise g 대기(dg)", [.char("d"), .char("g")]),
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

// pending 없는 Normal Esc는 취소할 것이 없다 — 앱으로 통과시켜 Esc 연타로
// "Normal 진입 → 앱에 취소 전달"이 가능하게 한다. Normal 유지가 핵심 신호다
// (탈출 콤보의 passthrough는 Insert 전이와 짝이다).
let escPassthroughFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "빈 상태 Esc → 통과, Normal 유지",
        startMode: .normal,
        steps: [step(.escape, .passthrough)],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "취소 Esc(삼킴) 후 연속 Esc → 두 번째부터 통과 — Esc 연타 시나리오",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.escape, .swallow),
            step(.escape, .passthrough),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "빈 상태 Ctrl+[ → Esc 동치로 통과, Normal 유지 (정규화 경유)",
        startMode: .normal,
        steps: [step(Key.char("[", [.control]), .passthrough)],
        finalMode: .normal
    ),
]

@Test(arguments: escPassthroughFixtures)
func escPassthroughs(_ fixture: KeySequenceFixture) {
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
    // Ctrl+t는 미매핑 콤보 — 매핑된 Ctrl+d 등의 동작은 CtrlComboFixtures가 핀.
    KeySequenceFixture(
        "탈출 옵션 꺼짐: 카운트 중 비탈출 콤보(Ctrl+t)는 통과, 카운트는 버려진다",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("t", [.control]), .passthrough),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: comboCancellationOffFixtures)
func comboCancellationsOff(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

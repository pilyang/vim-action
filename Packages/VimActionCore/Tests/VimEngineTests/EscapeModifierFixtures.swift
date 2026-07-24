import Testing

@testable import VimEngine

/// Normal 모드 "modifier 탈출" 옵션 픽스처.
///
/// `Configuration.normalModeEscapeModifiers`에 든 modifier를 포함한 미매핑 콤보가
/// Normal 모드에서 오면 `.passthrough` + Insert 복귀시킨다. Spotlight/Raycast 등
/// cmd/opt 단축키 직후의 텍스트 입력이 Normal 모드에 막히지 않게 하려는 옵션이다.
/// 셋에 없는 modifier나 옵션 off(빈 셋)에서는 기존 규칙(통과 + Normal 유지)을 지킨다.

/// cmd/opt를 탈출 modifier로 켠 설정.
private let escapeOnCmdOpt = VimEngine.Configuration(normalModeEscapeModifiers: [.command, .option])

let escapeModifierFixtures: [KeySequenceFixture] = [
    // on(cmd,opt) × Cmd 콤보 → Insert 탈출
    KeySequenceFixture(
        "탈출 옵션(cmd/opt) 켜진 Normal에서 Cmd+Space → 통과하며 Insert로 탈출",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: [step(.init(.space, [.command]), .passthrough)],
        finalMode: .insert
    ),
    // on(cmd,opt) × Opt 콤보(문자키) → Insert 탈출
    KeySequenceFixture(
        "탈출 옵션 켜진 Normal에서 Opt+e → 통과하며 Insert로 탈출",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: [step(.char("e", [.option]), .passthrough)],
        finalMode: .insert
    ),
    // on(cmd,opt) × Ctrl 콤보 → 셋에 없으므로 기존대로 통과 + Normal 유지
    // (Ctrl+t는 미매핑 콤보 — 매핑된 Ctrl+d 등의 동작은 CtrlComboFixtures가 핀)
    KeySequenceFixture(
        "탈출 옵션에 없는 Ctrl+t는 통과하되 Normal 유지",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: [step(.char("t", [.control]), .passthrough)],
        finalMode: .normal
    ),
    // off(기본 빈 셋) × Cmd 콤보 → 기존 동작 회귀 핀
    KeySequenceFixture(
        "탈출 옵션 꺼진 기본 설정에서 Cmd+Space는 통과하되 Normal 유지",
        startMode: .normal,
        steps: [step(.init(.space, [.command]), .passthrough)],
        finalMode: .normal
    ),
    // pending 엣지 on: g(swallow) → Cmd+Space(passthrough) → 최종 Insert
    KeySequenceFixture(
        "탈출 옵션 켜진 Normal에서 g 후 Cmd+Space → pending 버리고 통과하며 Insert로 탈출",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: [
            step(.char("g"), .swallow),
            step(.init(.space, [.command]), .passthrough),
        ],
        finalMode: .insert
    ),
    // pending 엣지 off: g(swallow) → Cmd+Space(swallow) → 최종 Normal (기존 동작 핀)
    KeySequenceFixture(
        "탈출 옵션 꺼진 기본 설정에서 g 후 Cmd+Space는 무효 연속으로 삼키고 Normal 유지",
        startMode: .normal,
        steps: [
            step(.char("g"), .swallow),
            step(.init(.space, [.command]), .swallow),
        ],
        finalMode: .normal
    ),
    // Insert 모드는 무변화 — escape 콤보가 와도 그대로 통과, 모드 유지
    KeySequenceFixture(
        "탈출 옵션이 켜져 있어도 Insert에서 Cmd+Space는 그대로 통과, 모드 무변화",
        startMode: .insert,
        configuration: escapeOnCmdOpt,
        steps: [step(.init(.space, [.command]), .passthrough)],
        finalMode: .insert
    ),
    // 수식자 붙은 Esc는 "Esc 취소" 분기(정확 매치)가 아니라 escapeCombo 판정을 탄다.
    // Esc를 base 매치로 구현하면 이 케이스가 swallow+Normal로 뒤집혀 여기서 잡힌다.
    KeySequenceFixture(
        "탈출 옵션 켜진 Normal에서 g 후 Cmd+Esc → Esc 취소가 아니라 탈출 콤보로 통과하며 Insert",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: [
            step(.char("g"), .swallow),
            step(.init(.escape, [.command]), .passthrough),
        ],
        finalMode: .insert
    ),
    // 탈출 목적 자체 확인 — 복귀 후 후속 문자 키가 타이핑으로 통과
    KeySequenceFixture(
        "탈출 옵션으로 Insert 복귀 후 후속 문자 키(a)는 타이핑으로 통과",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: [
            step(.init(.space, [.command]), .passthrough),
            step(.char("a"), .passthrough),
        ],
        finalMode: .insert
    ),
]

@Test(arguments: escapeModifierFixtures)
func escapeModifiers(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

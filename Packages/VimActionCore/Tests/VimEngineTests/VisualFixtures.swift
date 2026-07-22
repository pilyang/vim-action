import Testing

@testable import VimEngine

/// Visual 모드 픽스처 — 모션의 선택 확장(+카운트), 선택 동작 `y d x c`,
/// Normal pending과의 상호작용(3v/dv), 취소·미매핑 엣지.
///
/// 출력 계약: 모션은 `extendSelection` 반복 출력(`.move`와 같은 카운트 규칙),
/// linewise 세션의 줄 반올림은 어댑터 몫이라 char/line 모드의 모션 출력은 동일하다.
/// (decisions: 20260722_visual-mode-output-contract.md)

/// cmd/opt를 탈출 modifier로 켠 설정 (EscapeModifierFixtures와 동일).
private let escapeOnCmdOpt = VimEngine.Configuration(normalModeEscapeModifiers: [.command, .option])

let visualFixtures: [KeySequenceFixture] = [
    // 모션 → 선택 확장
    KeySequenceFixture(
        "Visual-char에서 w → 선택을 단어 앞으로 확장",
        startMode: .visualChar,
        steps: [step(.char("w"), .replace([.extendSelection(.wordForward)]))],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-line에서 j → 모션 출력은 char와 동일(줄 반올림은 어댑터 몫)",
        startMode: .visualLine,
        steps: [step(.char("j"), .replace([.extendSelection(.lineDown)]))],
        finalMode: .visualLine
    ),
    KeySequenceFixture(
        "Visual-char에서 $ → 줄 끝까지 확장",
        startMode: .visualChar,
        steps: [step(.char("$"), .replace([.extendSelection(.lineEnd)]))],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-char에서 G → 문서 끝까지 확장",
        startMode: .visualChar,
        steps: [step(.char("G"), .replace([.extendSelection(.documentEnd)]))],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-char에서 gg → 문서 시작까지 확장 (g 접두 완결)",
        startMode: .visualChar,
        steps: [
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.extendSelection(.documentStart)])),
        ],
        finalMode: .visualChar
    ),

    // 카운트 — `.move`와 같은 반복 출력 규칙
    KeySequenceFixture(
        "Visual-char에서 3j → 확장 3회 반복 출력",
        startMode: .visualChar,
        steps: [
            step(.char("3"), .swallow),
            step(.char("j"), .replace(Array(repeating: VimAction.extendSelection(.lineDown), count: 3))),
        ],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-char에서 12l → 두 자리 카운트 누적 후 12회 확장",
        startMode: .visualChar,
        steps: [
            step(.char("1"), .swallow),
            step(.char("2"), .swallow),
            step(.char("l"), .replace(Array(repeating: VimAction.extendSelection(.charRight), count: 12))),
        ],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-char에서 0은 카운트 슬롯이 비어 있으면 lineStart 모션 (0-규칙)",
        startMode: .visualChar,
        steps: [step(.char("0"), .replace([.extendSelection(.lineStart)]))],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-char에서 10j → 0이 자리값으로 누적된다 (0-규칙)",
        startMode: .visualChar,
        steps: [
            step(.char("1"), .swallow),
            step(.char("0"), .swallow),
            step(.char("j"), .replace(Array(repeating: VimAction.extendSelection(.lineDown), count: 10))),
        ],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-char에서 3gg → 카운트를 버리고 단일 확장 (Normal gg와 동일 원칙)",
        startMode: .visualChar,
        steps: [
            step(.char("3"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.extendSelection(.documentStart)])),
        ],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual-char에서 3G → 반복 출력 수용 (Normal 모션 3G와 동일한 이연)",
        startMode: .visualChar,
        steps: [
            step(.char("3"), .swallow),
            step(.char("G"), .replace(Array(repeating: VimAction.extendSelection(.documentEnd), count: 3))),
        ],
        finalMode: .visualChar
    ),

    // 선택 동작 y d x c
    KeySequenceFixture(
        "Visual-char에서 y → 선택 복사 후 Normal 복귀",
        startMode: .visualChar,
        steps: [step(.char("y"), .replace([.edit(.yank, .selection)]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual-char에서 d → 선택 삭제 후 Normal 복귀",
        startMode: .visualChar,
        steps: [step(.char("d"), .replace([.edit(.delete, .selection)]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual-char에서 x → d와 동일 출력 (x≡d)",
        startMode: .visualChar,
        steps: [step(.char("x"), .replace([.edit(.delete, .selection)]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual-char에서 c → 선택 삭제하며 Insert 진입",
        startMode: .visualChar,
        steps: [step(.char("c"), .replace([.edit(.change, .selection)]))],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "Visual-line에서 d → 출력은 char와 동일 .selection (줄 범위는 어댑터 선택 상태)",
        startMode: .visualLine,
        steps: [step(.char("d"), .replace([.edit(.delete, .selection)]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "진입부터 완결까지: v → w 확장 → y 복사 → Normal",
        startMode: .normal,
        steps: [
            step(.char("v"), .replace([.beginSelection(linewise: false)])),
            step(.char("w"), .replace([.extendSelection(.wordForward)])),
            step(.char("y"), .replace([.edit(.yank, .selection)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual에서 카운트+오퍼레이터(3d)는 invalid — 카운트는 모션에만",
        startMode: .visualChar,
        steps: [
            step(.char("3"), .swallow),
            step(.char("d"), .swallow),
        ],
        finalMode: .visualChar
    ),

    // Normal pending과의 상호작용 (decisions: 20260722_visual-entry-pending-interaction.md)
    KeySequenceFixture(
        "Normal에서 3v → 카운트를 버리고 Visual 진입 (3i와 동일 원칙)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("v"), .replace([.beginSelection(linewise: false)])),
        ],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Normal에서 dv → invalid no-op, Visual 진입하지 않음 (dq와 동일)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("v"), .swallow),
        ],
        finalMode: .normal
    ),

    // 취소·엣지
    KeySequenceFixture(
        "Visual에서 카운트 누적 중 Esc → pending 폐기 + 선택 해제 + Normal",
        startMode: .visualChar,
        steps: [
            step(.char("3"), .swallow),
            step(.escape, .replace([.clearSelection])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual에서 g 접두 후 무효 키 → 접두와 키를 함께 버리는 no-op",
        startMode: .visualChar,
        steps: [
            step(.char("g"), .swallow),
            step(.char("q"), .swallow),
            // 잔류 상태 없음 확인 — 이어지는 모션은 정상 동작.
            step(.char("w"), .replace([.extendSelection(.wordForward)])),
        ],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 탈출 콤보 → 통과하며 Insert 탈출 (clearSelection 없음 — 콤보가 선택에 작용 가능)",
        startMode: .visualChar,
        configuration: escapeOnCmdOpt,
        steps: [step(.init(.space, [.command]), .passthrough)],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "Visual에서 비탈출 modifier 콤보는 통과, 모드 유지 (시스템 단축키 보존)",
        startMode: .visualChar,
        steps: [step(.char("c", [.control]), .passthrough)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 미매핑 맨 키는 삼킴, 모드 유지",
        startMode: .visualChar,
        steps: [step(.char("q"), .swallow)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 i는 미매핑 — 삼킴 (v1엔 텍스트 오브젝트 선택 없음)",
        startMode: .visualChar,
        steps: [step(.char("i"), .swallow)],
        finalMode: .visualChar
    ),
]

@Test(arguments: visualFixtures)
func visual(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

import Testing

@testable import VimEngine

/// Normal 모드 Ctrl 콤보 픽스처 — `Ctrl-d`/`Ctrl-u`(half)·`Ctrl-f`/`Ctrl-b`(full)
/// 스크롤, `Ctrl-r`(네이티브 redo 위임), `Ctrl-[`(Esc 완전 별칭).
///
/// 출력 계약: 스크롤·redo의 카운트는 반복 출력(3u 규칙)이고, 매핑된 Ctrl 콤보는
/// 탈출 modifier 판정보다 우선한다(Normal 전용 예외 — Visual에는 매핑이 없어
/// 탈출이 이긴다). Ctrl-[는 엔진 진입부에서 Esc로 정규화되어 세 모드 전부에서
/// Esc와 동일 동작이다.
/// (decisions: 20260724_ctrl-combo-mapped-exception-cancellation.md,
/// 20260724_scroll-output-contract.md, 20260724_ctrl-bracket-escape-normalization.md)

private let escapeOnCtrl = VimEngine.Configuration(normalModeEscapeModifiers: [.control])
private let escapeOnCmdOpt = VimEngine.Configuration(normalModeEscapeModifiers: [.command, .option])

private let ctrlD = Key.char("d", [.control])
private let ctrlU = Key.char("u", [.control])
private let ctrlF = Key.char("f", [.control])
private let ctrlB = Key.char("b", [.control])
private let ctrlR = Key.char("r", [.control])
private let ctrlT = Key.char("t", [.control])
private let ctrlBracket = Key.char("[", [.control])

private let halfDown = VimAction.scroll(.halfPage, forward: true)
private let halfUp = VimAction.scroll(.halfPage, forward: false)
private let fullDown = VimAction.scroll(.fullPage, forward: true)
private let fullUp = VimAction.scroll(.fullPage, forward: false)

let ctrlComboFixtures: [KeySequenceFixture] = [
    // 기본 동작
    KeySequenceFixture(
        "Ctrl+d → half-page 아래 스크롤",
        startMode: .normal,
        steps: [step(ctrlD, .replace([halfDown]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Ctrl+u → half-page 위 스크롤",
        startMode: .normal,
        steps: [step(ctrlU, .replace([halfUp]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Ctrl+f → full-page 아래 스크롤",
        startMode: .normal,
        steps: [step(ctrlF, .replace([fullDown]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Ctrl+b → full-page 위 스크롤",
        startMode: .normal,
        steps: [step(ctrlB, .replace([fullUp]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Ctrl+r → 네이티브 redo 위임 1회",
        startMode: .normal,
        steps: [step(ctrlR, .replace([.redo]))],
        finalMode: .normal
    ),

    // 카운트 — 반복 출력 (3u 규칙)
    KeySequenceFixture(
        "3 Ctrl+d → 스크롤 반복 출력 ×3",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(ctrlD, .replace([halfDown, halfDown, halfDown])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "12 Ctrl+u → 두 자리 카운트 누적 후 반복 출력 ×12",
        startMode: .normal,
        steps: [
            step(.char("1"), .swallow),
            step(.char("2"), .swallow),
            step(ctrlU, .replace(Array(repeating: halfUp, count: 12))),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3 Ctrl+r → redo 반복 출력 ×3 (3u와 대칭)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(ctrlR, .replace([.redo, .redo, .redo])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "카운트 누적 중 Esc 후 Ctrl+d → 카운트 폐기, 단일 출력",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.escape, .swallow),
            step(ctrlD, .replace([halfDown])),
        ],
        finalMode: .normal
    ),

    // 오퍼레이터·접두 대기 중 invalid — 화이트리스트 밖 (do/du 선례), 잔류 없음
    KeySequenceFixture(
        "d Ctrl+d → invalid no-op, 잔류 없음 (후속 모션 정상)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(ctrlD, .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "d Ctrl+r → invalid no-op, 잔류 없음",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(ctrlR, .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "g Ctrl+d → 접두 대기 중 invalid no-op, 잔류 없음",
        startMode: .normal,
        steps: [
            step(.char("g"), .swallow),
            step(ctrlD, .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "di Ctrl+d → 스코프 대기 중 invalid no-op, 잔류 없음",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("i"), .swallow),
            step(ctrlD, .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),

    // 탈출 modifier에 Ctrl 설정 시 — 매핑된 콤보는 탈출 판정에서 제외 (키 단위 예외)
    KeySequenceFixture(
        "탈출 옵션(ctrl) 켜져도 매핑된 Ctrl+d는 스크롤 — 매핑이 탈출을 이긴다",
        startMode: .normal,
        configuration: escapeOnCtrl,
        steps: [step(ctrlD, .replace([halfDown]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "탈출 옵션(ctrl)에서 미매핑 Ctrl+t는 통과하며 Insert 탈출 — 탈출은 여전히 동작",
        startMode: .normal,
        configuration: escapeOnCtrl,
        steps: [step(ctrlT, .passthrough)],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "탈출 옵션(ctrl)에서 d 후 Ctrl+d → 탈출이 아니라 invalid no-op (예외는 키 단위)",
        startMode: .normal,
        configuration: escapeOnCtrl,
        steps: [
            step(.char("d"), .swallow),
            step(ctrlD, .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "탈출 옵션(cmd/opt)에서 Ctrl+d는 셋에 없으므로 그대로 스크롤",
        startMode: .normal,
        configuration: escapeOnCmdOpt,
        steps: [step(ctrlD, .replace([halfDown]))],
        finalMode: .normal
    ),

    // Ctrl-[ — 진입부 정규화로 세 모드 전부 Esc 완전 별칭
    KeySequenceFixture(
        "Insert에서 Ctrl+[ → Esc처럼 삼키며 Normal 진입",
        startMode: .insert,
        steps: [step(ctrlBracket, .swallow)],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Normal에서 d 후 Ctrl+[ → Esc 취소 — pending 폐기, 후속 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(ctrlBracket, .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual에서 Ctrl+[ → Esc처럼 선택 해제하며 Normal 복귀",
        startMode: .visualChar,
        steps: [step(ctrlBracket, .replace([.clearSelection]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "탈출 옵션(ctrl) 켜져도 Ctrl+[는 Esc 취소 — 정규화가 탈출 판정보다 선행",
        startMode: .normal,
        configuration: escapeOnCtrl,
        steps: [step(ctrlBracket, .swallow)],
        finalMode: .normal
    ),

    // Visual 범위 밖 유지 — 스크롤·redo는 Normal 전용, Visual은 미매핑 콤보 통과
    KeySequenceFixture(
        "Visual에서 Ctrl+d는 미매핑 콤보 — 통과, 모드 유지",
        startMode: .visualChar,
        steps: [step(ctrlD, .passthrough)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 Ctrl+r은 미매핑 콤보 — 통과, 모드 유지",
        startMode: .visualChar,
        steps: [step(ctrlR, .passthrough)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "탈출 옵션(ctrl)의 Visual에서 Ctrl+d는 탈출 — 매핑 예외는 Normal 스코프",
        startMode: .visualChar,
        configuration: escapeOnCtrl,
        steps: [step(ctrlD, .passthrough)],
        finalMode: .insert
    ),
]

@Test(arguments: ctrlComboFixtures)
func ctrlCombos(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

import Testing

@testable import VimEngine

/// Normal 모드 `o`/`O`(새 줄 열고 Insert), `p`/`P`(붙여넣기), `u`(네이티브 undo 위임) 픽스처.
///
/// 출력 계약: 세 키의 카운트 정책이 서로 다르다 — `3o`는 무시(표현 불가, 3i 원칙),
/// `3p`는 단일 액션의 count(한 편집 단위, 3x 규칙), `3u`는 반복 출력(`.move` 규칙).
/// (decisions: 20260723_openline-output-contract.md, 20260723_paste-output-contract.md,
/// 20260723_undo-output-contract.md)

let openPasteUndoFixtures: [KeySequenceFixture] = [
    // 기본 동작
    KeySequenceFixture(
        "o → 아래 새 줄 열며 Insert 진입",
        startMode: .normal,
        steps: [step(.char("o"), .replace([.openLine(above: false)]))],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "O → 위 새 줄 열며 Insert 진입",
        startMode: .normal,
        steps: [step(.char("O"), .replace([.openLine(above: true)]))],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "p → 커서 뒤 붙여넣기",
        startMode: .normal,
        steps: [step(.char("p"), .replace([.paste(before: false, count: 1)]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "P → 커서 앞 붙여넣기",
        startMode: .normal,
        steps: [step(.char("P"), .replace([.paste(before: true, count: 1)]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "u → 네이티브 undo 위임 1회",
        startMode: .normal,
        steps: [step(.char("u"), .replace([.undo]))],
        finalMode: .normal
    ),

    // 카운트 3정책 — 키마다 다른 규칙이 나란히 고정된다
    KeySequenceFixture(
        "3o → 카운트 무시하고 o와 동일 출력 (3i 원칙)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("o"), .replace([.openLine(above: false)])),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "3p → 단일 액션에 count 3 (한 편집 단위, 3x 규칙)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("p"), .replace([.paste(before: false, count: 3)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "12p → 두 자리 카운트 누적 후 count 12",
        startMode: .normal,
        steps: [
            step(.char("1"), .swallow),
            step(.char("2"), .swallow),
            step(.char("p"), .replace([.paste(before: false, count: 12)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3u → undo 반복 출력 ×3 (.move 규칙)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("u"), .replace([.undo, .undo, .undo])),
        ],
        finalMode: .normal
    ),

    // 오퍼레이터 대기 중 invalid — 기존 opMotions 화이트리스트가 처리, 여기서 고정만
    KeySequenceFixture(
        "do → invalid no-op, 잔류 없음 (후속 모션 정상)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("o"), .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "dp → invalid no-op, 잔류 없음",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("p"), .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "du → invalid no-op, 잔류 없음",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("u"), .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),

    // Visual 미매핑 swallow — PRD v1 Visual 어휘 밖 (o=앵커 스왑, p=선택 대체,
    // u=소문자화는 범위 밖 이연), 매핑 없는 맨 키는 삼킨다
    KeySequenceFixture(
        "Visual에서 o는 미매핑 — 삼킴, 모드 유지",
        startMode: .visualChar,
        steps: [step(.char("o"), .swallow)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 O는 미매핑 — 삼킴, 모드 유지",
        startMode: .visualChar,
        steps: [step(.char("O"), .swallow)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 p는 미매핑 — 삼킴, 모드 유지",
        startMode: .visualChar,
        steps: [step(.char("p"), .swallow)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 P는 미매핑 — 삼킴, 모드 유지",
        startMode: .visualChar,
        steps: [step(.char("P"), .swallow)],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Visual에서 u는 미매핑 — 삼킴, 모드 유지",
        startMode: .visualChar,
        steps: [step(.char("u"), .swallow)],
        finalMode: .visualChar
    ),

    // Esc 취소 상호작용 — 카운트 누적 중 Esc는 pending 폐기
    KeySequenceFixture(
        "카운트 누적 중 Esc 후 p → count 1 단일 출력",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.escape, .swallow),
            step(.char("p"), .replace([.paste(before: false, count: 1)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "카운트 누적 중 Esc 후 u → 단일 출력",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.escape, .swallow),
            step(.char("u"), .replace([.undo])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: openPasteUndoFixtures)
func openPasteUndo(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

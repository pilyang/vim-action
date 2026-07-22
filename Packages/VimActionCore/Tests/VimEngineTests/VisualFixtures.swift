import Testing

@testable import VimEngine

/// Visual 모드 픽스처 — 모션의 선택 확장(+카운트), 선택 동작 `y d x c`,
/// Normal pending과의 상호작용(3v/dv), 취소·미매핑 엣지.
///
/// 출력 계약: 모션은 `extendSelection` 반복 출력(`.move`와 같은 카운트 규칙),
/// linewise 세션의 줄 반올림은 어댑터 몫이라 char/line 모드의 모션 출력은 동일하다.
/// (decisions: 20260722_visual-mode-output-contract.md)
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
]

@Test(arguments: visualFixtures)
func visual(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

import Testing
@testable import VimEngine

/// 스켈레톤 모드 전이 픽스처. 이후 이동 키셋 픽스처도 같은 패턴으로 그룹별 파일에 추가한다.
let modeTransitionFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "Insert에서 Esc → Normal 진입, 삼킴",
        steps: [step(.escape, .swallow)],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Normal에서 i → Insert 진입, 삼킴",
        startMode: .normal,
        steps: [step(.char("i"), .swallow)],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "Insert에서 일반 문자는 통과, 모드 유지",
        steps: [step(.char("h"), .passthrough)],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "Normal에서 매핑 안 된 키는 삼키고 Normal 유지",
        startMode: .normal,
        steps: [step(.char("q"), .swallow)],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Esc → i 왕복이면 Insert로 되돌아온다",
        steps: [
            step(.escape, .swallow),
            step(.char("i"), .swallow),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "Normal에서 a → 커서 한 칸 뒤로 이동하며 Insert 진입",
        startMode: .normal,
        steps: [step(.char("a"), .replace([.move(.charRightForAppend)]))],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "Normal에서 I → 줄 첫 비공백으로 이동하며 Insert 진입",
        startMode: .normal,
        steps: [step(.char("I"), .replace([.move(.lineFirstNonBlank)]))],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "Normal에서 A → 줄 끝(마지막 문자 뒤)으로 이동하며 Insert 진입",
        startMode: .normal,
        steps: [step(.char("A"), .replace([.move(.lineEndForAppend)]))],
        finalMode: .insert
    ),
    // Visual 진입·이탈·전환 — 진입은 beginSelection(항상 앵커 리셋), 전환은
    // switchSelectionWise(앵커 유지), 이탈은 clearSelection이 명시 출력된다
    // (V의 "현재 줄 즉시 선택"과 Esc의 화면 선택 해제는 실제 동작).
    KeySequenceFixture(
        "Normal에서 v → Visual-char 진입, beginSelection(charwise)",
        startMode: .normal,
        steps: [step(.char("v"), .replace([.beginSelection(linewise: false)]))],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Normal에서 V → Visual-line 진입, beginSelection(linewise)",
        startMode: .normal,
        steps: [step(.char("V"), .replace([.beginSelection(linewise: true)]))],
        finalMode: .visualLine
    ),
    KeySequenceFixture(
        "Visual-char에서 Esc → 선택 해제하며 Normal 복귀",
        startMode: .visualChar,
        steps: [step(.escape, .replace([.clearSelection]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual-line에서 Esc → 선택 해제하며 Normal 복귀",
        startMode: .visualLine,
        steps: [step(.escape, .replace([.clearSelection]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual-char에서 v 재입력 → 선택 해제하며 Normal 복귀",
        startMode: .visualChar,
        steps: [step(.char("v"), .replace([.clearSelection]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual-line에서 V 재입력 → 선택 해제하며 Normal 복귀",
        startMode: .visualLine,
        steps: [step(.char("V"), .replace([.clearSelection]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "Visual-char에서 V → line으로 전환, switchSelectionWise(앵커 유지·wise 교체)",
        startMode: .visualChar,
        steps: [step(.char("V"), .replace([.switchSelectionWise(linewise: true)]))],
        finalMode: .visualLine
    ),
    KeySequenceFixture(
        "Visual-line에서 v → char로 전환, switchSelectionWise 출력",
        startMode: .visualLine,
        steps: [step(.char("v"), .replace([.switchSelectionWise(linewise: false)]))],
        finalMode: .visualChar
    ),
    KeySequenceFixture(
        "Insert에서 v는 일반 문자 — 통과, 모드 유지",
        steps: [step(.char("v"), .passthrough)],
        finalMode: .insert
    ),
]

@Test(arguments: modeTransitionFixtures)
func modeTransition(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

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
        steps: [step(.char("x"), .swallow)],
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
]

@Test(arguments: modeTransitionFixtures)
func modeTransition(_ fixture: KeySequenceFixture) {
    var engine = VimEngine(mode: fixture.startMode)
    for (index, step) in fixture.steps.enumerated() {
        let output = engine.handle(step.key)
        #expect(output == step.expect, "step \(index) (\(step.key)) 출력 불일치")
    }
    #expect(engine.mode == fixture.finalMode, "최종 모드 불일치")
}

import Testing

@testable import VimEngine

/// 키 시퀀스 하나를 순서대로 먹였을 때 각 단계의 기대 출력과 최종 모드를 기술하는 픽스처.
///
/// 이동 키셋 등 이후 픽스처는 이 타입을 `@Test(arguments:)`에 그대로 물리는
/// 코드 테이블(예: `MotionFixtures.swift`)로 그룹별 파일에 추가한다.
struct KeySequenceFixture: Sendable, CustomTestStringConvertible {
    /// 실패 리포트에서 픽스처를 식별하는 이름.
    let name: String
    /// 시작 모드. 생략 시 엔진 기본값(Insert).
    let startMode: Mode
    /// 주입할 엔진 설정. 생략 시 기본값(모두 off).
    let configuration: VimEngine.Configuration
    /// 각 키와 그 키를 먹인 직후의 기대 출력.
    let steps: [Step]
    /// 시퀀스를 모두 먹인 뒤의 기대 모드.
    let finalMode: Mode

    struct Step: Sendable {
        let key: Key
        let expect: EngineOutput
    }

    init(
        _ name: String,
        startMode: Mode = .insert,
        configuration: VimEngine.Configuration = .init(),
        steps: [Step],
        finalMode: Mode
    ) {
        self.name = name
        self.startMode = startMode
        self.configuration = configuration
        self.steps = steps
        self.finalMode = finalMode
    }

    var testDescription: String { name }
}

/// `[.escape → .swallow, .char("i") → .swallow]` 처럼 픽스처를 짧게 적기 위한 헬퍼.
func step(_ key: Key, _ expect: EngineOutput) -> KeySequenceFixture.Step {
    KeySequenceFixture.Step(key: key, expect: expect)
}

/// 픽스처 하나를 실행해 각 스텝의 출력과 최종 모드를 검증한다.
func expectFixture(_ fixture: KeySequenceFixture, sourceLocation: SourceLocation = #_sourceLocation) {
    var engine = VimEngine(mode: fixture.startMode, configuration: fixture.configuration)
    for (index, step) in fixture.steps.enumerated() {
        let output = engine.handle(step.key)
        #expect(output == step.expect, "step \(index) (\(step.key)) 출력 불일치", sourceLocation: sourceLocation)
    }
    #expect(engine.mode == fixture.finalMode, "최종 모드 불일치", sourceLocation: sourceLocation)
}

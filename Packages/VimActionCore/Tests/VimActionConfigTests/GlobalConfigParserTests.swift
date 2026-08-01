import Testing

@testable import VimActionConfig

/// config.yaml 한 파일의 파싱 결과. `apps`가 nil이면 파일 통째 실패를 기대한다.
struct GlobalConfigFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let yaml: String
    let apps: [String: Bool]?
    let warnings: [ConfigWarning]

    var testDescription: String { name }
}

private func fixture(
    _ name: String,
    _ yaml: String,
    apps: [String: Bool]? = [:],
    warnings: [ConfigWarning] = []
) -> GlobalConfigFixture {
    GlobalConfigFixture(name: name, yaml: yaml, apps: apps, warnings: warnings)
}

let globalConfigFixtures: [GlobalConfigFixture] = [
    fixture(
        "정상 — bundle-id별 on/off",
        """
        apps:
          com.mitchellh.ghostty: false
          com.exafunction.windsurf: true
        """,
        apps: ["com.mitchellh.ghostty": false, "com.exafunction.windsurf": true]
    ),
    fixture("빈 파일", ""),
    fixture("apps 빈 맵", "apps: {}"),
    // `apps:` 뒤에 아무것도 없는 건 편집 중인 파일의 일상적 모습이라 조용히 없는 것으로 본다.
    fixture("apps 널 섹션", "apps:"),
    fixture(
        "미지 최상위 키는 그 항목만 무시 — M5 필드 선기입 전방 호환",
        """
        strategy: auto
        apps:
          com.a: true
        """,
        apps: ["com.a": true],
        warnings: [warning("strategy", .unknownKey)]
    ),
    fixture(
        "비-bool 값은 그 항목만 무시 — 형제는 생존",
        """
        apps:
          com.a: maybe
          com.b: true
        """,
        apps: ["com.b": true],
        warnings: [warning("apps.com.a", .invalidValue("maybe"))]
    ),
    fixture(
        "apps가 맵이 아니면 통째 무시",
        """
        apps:
          - com.a
          - com.b
        """,
        warnings: [warning("apps", .invalidValue("sequence"))]
    ),
    fixture(
        "루트가 스칼라면 통째 무시",
        "hello",
        warnings: [warning("", .invalidValue("hello"))]
    ),
    // YAML 1.1 스칼라 해석을 그대로 쓴다 — 손편집 파일에서 yes/no는 자연스러운 표기다.
    fixture(
        "YAML 진리값 표기 허용",
        """
        apps:
          com.a: yes
          com.b: no
        """,
        apps: ["com.a": true, "com.b": false]
    ),
]

@Test("config.yaml 파싱", arguments: globalConfigFixtures)
func globalConfigParsing(_ fixture: GlobalConfigFixture) {
    let outcome = GlobalConfigParser.parse(fixture.yaml, file: testFile)

    #expect(outcome.value?.apps == fixture.apps)
    #expect(Set(outcome.warnings) == Set(fixture.warnings))
    #expect(outcome.error == nil)
}

@Test("파일 통째 파싱 실패는 부재 취급 + 에러 반환")
func globalConfigWholeFileFailure() {
    let outcome = GlobalConfigParser.parse("apps:\n  - x\n bad: :", file: testFile)

    #expect(outcome.value == nil)
    #expect(outcome.error?.file == testFile)
    #expect(outcome.warnings.isEmpty)
}

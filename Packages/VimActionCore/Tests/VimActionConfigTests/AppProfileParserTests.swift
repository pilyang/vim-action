import Testing
import VimEngine

@testable import VimActionConfig

private let profileFile = "profiles/com.example.app.yaml"

private func w(_ path: String, _ kind: ConfigWarning.Kind) -> ConfigWarning {
    warning(path, kind, file: profileFile)
}

/// 프로파일 한 파일의 파싱 결과. `profile`이 nil이면 파일 통째 실패를 기대한다.
struct AppProfileFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let yaml: String
    let profile: AppProfile?
    let warnings: [ConfigWarning]

    var testDescription: String { name }
}

private func fixture(
    _ name: String,
    _ yaml: String,
    _ profile: AppProfile = AppProfile(),
    warnings: [ConfigWarning] = []
) -> AppProfileFixture {
    AppProfileFixture(name: name, yaml: yaml, profile: profile, warnings: warnings)
}

let appProfileFixtures: [AppProfileFixture] = [
    fixture(
        "정상 — 필드 넷 전부",
        """
        name: Notion
        scroll:
          half_page_lines: 20
          full_page_lines: 40
        motions:
          document_end: [cmd-down]
          document_start: disabled
        actions:
          open_line: disabled
        """,
        AppProfile(
            name: "Notion",
            halfPageLines: 20,
            fullPageLines: 40,
            motions: [
                .documentEnd: .strokes([ConfigKeyStroke(.down, [.cmd])]),
                .documentStart: .disabled,
            ],
            actions: [.openLine: .disabled]
        )
    ),
    fixture("빈 파일", ""),
    fixture(
        "미지 최상위 키는 그 항목만 무시 — M5 필드 선기입 전방 호환",
        """
        per_element:
          text_area: { strategy: ax }
        motions:
          line_end: [end]
        """,
        AppProfile(motions: [.lineEnd: .strokes([ConfigKeyStroke(.end)])]),
        warnings: [w("per_element", .unknownKey)]
    ),

    // name
    fixture("name은 표시용 문자열", "name: Slack", AppProfile(name: "Slack")),
    fixture(
        "name이 맵이면 무시",
        "name: { first: Slack }",
        warnings: [w("name", .invalidValue("mapping"))]
    ),

    // scroll — 1...200 정수만. 스크롤은 카운트와 곱해지는 증폭 축이라 상한이 있다.
    fixture(
        "scroll 경계값 1·200은 유효",
        "scroll: { half_page_lines: 1, full_page_lines: 200 }",
        AppProfile(halfPageLines: 1, fullPageLines: 200)
    ),
    fixture(
        "scroll 범위 밖은 그 항목만 무시 — 형제는 생존",
        """
        scroll:
          half_page_lines: 0
          full_page_lines: 40
        """,
        AppProfile(fullPageLines: 40),
        warnings: [w("scroll.half_page_lines", .invalidValue("0"))]
    ),
    fixture(
        "scroll 상한 초과·비정수는 무시",
        """
        scroll:
          half_page_lines: 201
          full_page_lines: 20.5
        """,
        warnings: [
            w("scroll.half_page_lines", .invalidValue("201")),
            w("scroll.full_page_lines", .invalidValue("20.5")),
        ]
    ),
    fixture(
        "scroll 안의 미지 키",
        "scroll: { lines: 5 }",
        warnings: [w("scroll.lines", .unknownKey)]
    ),
    fixture(
        "scroll이 맵이 아니면 통째 무시",
        "scroll: [20, 40]",
        warnings: [w("scroll", .invalidValue("sequence"))]
    ),

    // motions
    fixture(
        "모션 시퀀스는 순서를 보존한다",
        "motions: { document_start: [cmd-up, cmd-left] }",
        AppProfile(
            motions: [
                .documentStart: .strokes([ConfigKeyStroke(.up, [.cmd]), ConfigKeyStroke(.left, [.cmd])])
            ]
        )
    ),
    fixture(
        "빈 배열은 disable이 아니라 무시 — 끄려면 disabled로 명시해야 한다",
        "motions: { document_end: [] }",
        warnings: [w("motions.document_end", .invalidValue("[]"))]
    ),
    fixture(
        "토큰 하나가 깨지면 그 모션 항목 전체를 버린다",
        "motions: { document_end: [cmd-down, Cmd-Up] }",
        warnings: [w("motions.document_end[1]", .invalidKeyStroke("Cmd-Up"))]
    ),
    fixture(
        "disabled는 소문자만",
        "motions: { document_end: Disabled }",
        warnings: [w("motions.document_end", .invalidValue("Disabled"))]
    ),
    fixture(
        "모션 값이 시퀀스도 disabled도 아니면 무시",
        "motions: { document_end: 3 }",
        warnings: [w("motions.document_end", .invalidValue("3"))]
    ),
    fixture(
        "미지 모션명",
        "motions: { teleport: [cmd-down] }",
        warnings: [w("motions.teleport", .unknownKey)]
    ),
    fixture(
        "append 전용 이름은 미지 모션명이다 — base를 재정의해야 한다",
        "motions: { char_right_for_append: [right] }",
        warnings: [w("motions.char_right_for_append", .unknownKey)]
    ),

    // actions — v1 값은 disabled만이고 시퀀스 재정의가 없다.
    fixture(
        "액션 어휘 5종",
        """
        actions:
          open_line: disabled
          paste: disabled
          undo: disabled
          redo: disabled
          scroll: disabled
        """,
        AppProfile(
            actions: [
                .openLine: .disabled, .paste: .disabled, .undo: .disabled, .redo: .disabled,
                .scroll: .disabled,
            ])
    ),
    fixture(
        "액션 시퀀스 재정의 — 자기 키 교체",
        "actions: { open_line: [shift-return] }",
        AppProfile(actions: [.openLine: .strokes([ConfigKeyStroke(.return, [.shift])])])
    ),
    fixture(
        "자기 키가 없는 scroll은 시퀀스를 받지 않는다 — 재정의는 line_down/line_up 모션 몫",
        "actions: { scroll: [page_down] }",
        warnings: [w("actions.scroll", .invalidValue("sequence"))]
    ),
    fixture(
        "scroll도 disable은 유효하다",
        "actions: { scroll: disabled }",
        AppProfile(actions: [.scroll: .disabled])
    ),
    fixture(
        "액션 값은 시퀀스이거나 disabled다",
        "actions: { open_line: enabled }",
        warnings: [w("actions.open_line", .invalidValue("enabled"))]
    ),
    fixture(
        "액션 시퀀스의 토큰 하나가 깨지면 항목 전체 폐기 — 반쯤 맞는 시퀀스 금지",
        "actions: { open_line: [shift-return, nope] }",
        warnings: [w("actions.open_line[1]", .invalidKeyStroke("nope"))]
    ),
    fixture(
        "미지 액션명",
        "actions: { teleport: disabled }",
        warnings: [w("actions.teleport", .unknownKey)]
    ),
]

@Test("프로파일 파싱", arguments: appProfileFixtures)
func appProfileParsing(_ fixture: AppProfileFixture) {
    let outcome = AppProfileParser.parse(fixture.yaml, file: profileFile)

    #expect(outcome.value == fixture.profile)
    #expect(Set(outcome.warnings) == Set(fixture.warnings))
    #expect(outcome.error == nil)
}

@Test("파일 통째 파싱 실패는 부재 취급 + 에러 반환")
func appProfileWholeFileFailure() {
    let outcome = AppProfileParser.parse("motions:\n  - x\n bad: :", file: profileFile)

    #expect(outcome.value == nil)
    #expect(outcome.error?.file == profileFile)
    #expect(outcome.warnings.isEmpty)
}

@Test("append 전용 모션은 base 모션의 재정의를 상속한다")
func appendMotionInheritsBaseOverride() {
    let strokes = ConfigOverride.strokes([ConfigKeyStroke(.end)])
    let profile = AppProfile(motions: [.lineEnd: strokes, .charRight: .disabled])

    #expect(profile.motionOverride(for: .lineEndForAppend) == strokes)
    #expect(profile.motionOverride(for: .charRightForAppend) == .disabled)
    #expect(profile.motionOverride(for: .wordForward) == nil)
}

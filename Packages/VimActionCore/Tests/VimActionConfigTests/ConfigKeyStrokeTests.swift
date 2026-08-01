import Testing

@testable import VimActionConfig

/// `[modifier-]key` 토큰 하나의 파싱 결과. nil이면 거부돼야 하는 토큰이다.
struct TokenFixture: Sendable, CustomTestStringConvertible {
    let token: String
    let expected: ConfigKeyStroke?

    var testDescription: String { "\"\(token)\"" }
}

private func ok(_ token: String, _ key: ConfigKey, _ modifiers: Set<ConfigModifier> = [])
    -> TokenFixture
{
    TokenFixture(token: token, expected: ConfigKeyStroke(key, modifiers))
}

private func rejected(_ token: String) -> TokenFixture {
    TokenFixture(token: token, expected: nil)
}

let validTokenFixtures: [TokenFixture] = [
    ok("down", .down),
    ok("page_up", .pageUp),
    ok("cmd-down", .down, [.cmd]),
    ok("shift-cmd-down", .down, [.shift, .cmd]),
    ok("opt-ctrl-tab", .tab, [.opt, .ctrl]),
    ok("cmd-opt-ctrl-shift-return", .return, [.cmd, .opt, .ctrl, .shift]),
    // modifier 중복은 집합이 흡수한다 — 오타는 아니지만 의미가 갈리지 않는다.
    ok("cmd-cmd-down", .down, [.cmd]),
]

/// 대소문자 관용이 없다는 것이 계약이다 — `Cmd-Down`은 미지 키워드와 같은 취급.
let nonLowercaseTokenFixtures: [TokenFixture] = [
    rejected("Cmd-Down"),
    rejected("DOWN"),
    rejected("Page_Up"),
    rejected("cmd-Down"),
]

let malformedTokenFixtures: [TokenFixture] = [
    rejected(""),
    rejected("cmd-"),
    rejected("-down"),
    rejected("cmd--down"),
    rejected("cmd_down"),  // 구분자는 `-`
    rejected("page-up"),  // 키 이름 안의 구분자는 `_`
    rejected("down-cmd"),  // 키는 항상 마지막
    rejected("cmd"),  // modifier만
]

let unknownVocabularyTokenFixtures: [TokenFixture] = [
    rejected("hyper-down"),
    rejected("super-tab"),
    rejected("a"),
    rejected("cmd-z"),  // 문자 키는 레이아웃 의존이라 v1 제외
    rejected("f1"),
]

@Test("유효 토큰", arguments: validTokenFixtures)
func validTokens(_ fixture: TokenFixture) {
    #expect(ConfigKeyStroke(token: fixture.token) == fixture.expected)
}

@Test("비소문자 토큰은 거부", arguments: nonLowercaseTokenFixtures)
func nonLowercaseTokens(_ fixture: TokenFixture) {
    #expect(ConfigKeyStroke(token: fixture.token) == nil)
}

@Test("형식 오류 토큰은 거부", arguments: malformedTokenFixtures)
func malformedTokens(_ fixture: TokenFixture) {
    #expect(ConfigKeyStroke(token: fixture.token) == nil)
}

@Test("미지 어휘 토큰은 거부", arguments: unknownVocabularyTokenFixtures)
func unknownVocabularyTokens(_ fixture: TokenFixture) {
    #expect(ConfigKeyStroke(token: fixture.token) == nil)
}

/// 키 이름 11종이 전부 자기 raw value로 파싱된다 — 키를 추가하고 이름을 빼먹으면 여기서 깨진다.
@Test("키 이름 v1 전수", arguments: ConfigKey.allCases)
func everyKeyNameParses(_ key: ConfigKey) {
    #expect(ConfigKeyStroke(token: key.rawValue) == ConfigKeyStroke(key))
}

@Test("modifier 순서는 무관하다")
func modifierOrderIsIrrelevant() {
    #expect(ConfigKeyStroke(token: "cmd-shift-down") == ConfigKeyStroke(token: "shift-cmd-down"))
}

@Test("v1 어휘 크기는 키 11종·modifier 4종이다")
func vocabularySize() {
    #expect(ConfigKey.allCases.count == 11)
    #expect(ConfigModifier.allCases.count == 4)
}

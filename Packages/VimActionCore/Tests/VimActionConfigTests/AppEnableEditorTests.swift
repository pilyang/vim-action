import Testing

@testable import VimActionConfig

/// 번들 `VimAction/BundledConfig/config.yaml`의 실물 — 헤더 주석·섹션 주석·후행 주석이
/// 전부 들어 있어, 편집이 사용자 파일의 서식을 건드리지 않는지를 실전 형태로 검증한다.
private let bundledConfig = """
    # VimAction — per-app on/off (bundle id -> bool map).
    # Apps not listed here are on by default. To find an app's bundle id:
    #   osascript -e 'id of app "Slack"'
    apps:
      # Terminals with their own Vim keybindings — double interpretation breaks both.
      com.mitchellh.ghostty: false
      # Editors that usually have a Vim extension.
      com.microsoft.VSCode: false
      com.todesktop.230313mzl4w4u92: false # Cursor

    """

/// 값 토큰만 갈아 끼우는 경로 — 나머지 바이트가 한 글자도 바뀌면 안 된다.
struct AppEnableValueReplacementTests {
    @Test("기존 항목은 값 토큰만 바뀐다")
    func replacesValueToken() {
        let yaml = """
            apps:
              com.a: true
              com.b: false

            """

        #expect(
            settingAppEnabled(in: yaml, bundleID: "com.a", enabled: false) == """
                apps:
                  com.a: false
                  com.b: false

                """)
    }

    @Test("후행 주석·들여쓰기·파일 안의 다른 주석이 전부 보존된다")
    func preservesCommentsAndIndentation() {
        let edited = settingAppEnabled(
            in: bundledConfig, bundleID: "com.todesktop.230313mzl4w4u92", enabled: true)

        #expect(
            edited
                == bundledConfig.replacingLine(
                    "  com.todesktop.230313mzl4w4u92: false # Cursor",
                    with: "  com.todesktop.230313mzl4w4u92: true # Cursor"))
    }

    @Test("값 앞뒤 공백도 원문 그대로 둔다")
    func preservesSpacingAroundValue() {
        #expect(
            settingAppEnabled(in: "apps:\n  com.a:   false   # note\n", bundleID: "com.a", enabled: true)
                == "apps:\n  com.a:   true   # note\n")
    }

    @Test("값이 비어 있던 줄은 값이 채워진다")
    func fillsInMissingValue() {
        #expect(
            settingAppEnabled(in: "apps:\n  com.a:\n", bundleID: "com.a", enabled: false)
                == "apps:\n  com.a: false\n")
        #expect(
            settingAppEnabled(in: "apps:\n  com.a: # note\n", bundleID: "com.a", enabled: false)
                == "apps:\n  com.a: false # note\n")
    }

    @Test("이미 같은 값이면 텍스트가 한 글자도 바뀌지 않는다")
    func isIdempotent() {
        #expect(settingAppEnabled(in: bundledConfig, bundleID: "com.microsoft.VSCode", enabled: false) == bundledConfig)
    }
}

/// 항목이 없을 때의 삽입 경로.
struct AppEnableInsertionTests {
    @Test("블록의 마지막 항목 뒤에 삽입하고 들여쓰기를 상속한다")
    func insertsAfterLastEntry() {
        let yaml = """
            apps:
                com.a: false
                com.b: true
            """

        #expect(
            settingAppEnabled(in: yaml, bundleID: "com.new", enabled: false) == """
                apps:
                    com.a: false
                    com.b: true
                    com.new: false
                """)
    }

    @Test("블록이 비어 있으면 2칸 들여쓰기로 첫 항목이 된다")
    func insertsIntoEmptyBlock() {
        #expect(
            settingAppEnabled(in: "apps:\n", bundleID: "com.a", enabled: false)
                == "apps:\n  com.a: false\n")
    }

    @Test("빈 줄·주석 줄은 블록을 끊지 않는다 — 삽입은 마지막 항목 뒤다")
    func blankAndCommentLinesDoNotEndTheBlock() {
        let yaml = """
            apps:
              com.a: false

              # 다음 앱은 나중에
              com.b: true
            # 파일 끝 주석
            """

        #expect(
            settingAppEnabled(in: yaml, bundleID: "com.new", enabled: false) == """
                apps:
                  com.a: false

                  # 다음 앱은 나중에
                  com.b: true
                  com.new: false
                # 파일 끝 주석
                """)
    }

    @Test("주석 안의 유사 항목 줄은 매칭되지 않는다")
    func commentedOutEntryIsNotAMatch() {
        let yaml = """
            apps:
              # com.a: false
              com.b: true

            """

        #expect(
            settingAppEnabled(in: yaml, bundleID: "com.a", enabled: false) == """
                apps:
                  # com.a: false
                  com.b: true
                  com.a: false

                """)
    }

    @Test("apps 뒤에 다른 최상위 키가 있어도 블록 안에 삽입한다")
    func insertsBeforeNextTopLevelKey() {
        let yaml = """
            apps:
              com.a: false
            other:
              x: 1

            """

        #expect(
            settingAppEnabled(in: yaml, bundleID: "com.new", enabled: true) == """
                apps:
                  com.a: false
                  com.new: true
                other:
                  x: 1

                """)
    }
}

/// `apps:` 키 자체가 없을 때 — 파일 끝에 블록을 추가한다.
struct AppEnableBlockAppendTests {
    @Test("apps 키가 없으면 파일 끝에 블록을 추가한다 — 기존 내용은 그대로")
    func appendsBlockWhenAppsIsMissing() {
        let yaml = """
            # 내 설정
            other: 1

            """

        #expect(
            settingAppEnabled(in: yaml, bundleID: "com.a", enabled: false) == """
                # 내 설정
                other: 1

                apps:
                  com.a: false

                """)
    }

    @Test("빈 파일이면 블록만 남는다")
    func appendsBlockToEmptyFile() {
        #expect(settingAppEnabled(in: "", bundleID: "com.a", enabled: false) == "apps:\n  com.a: false")
        #expect(settingAppEnabled(in: "\n", bundleID: "com.a", enabled: false) == "apps:\n  com.a: false\n")
    }

    @Test("주석뿐인 파일 뒤에도 블록이 붙는다")
    func appendsAfterCommentOnlyFile() {
        #expect(
            settingAppEnabled(in: "# 아직 아무것도 없음\n", bundleID: "com.a", enabled: true)
                == "# 아직 아무것도 없음\n\napps:\n  com.a: true\n")
    }
}

/// `nil` = "안전하게 손대지 않음". 호출자는 파일 열기로 폴백한다.
struct AppEnableRefusalTests {
    @Test("중복 키가 있는 파일은 손대지 않는다")
    func refusesDuplicateKeys() {
        #expect(
            settingAppEnabled(in: "apps:\n  com.a: false\n  com.a: true\n", bundleID: "com.b", enabled: false)
                == nil)
        #expect(
            settingAppEnabled(in: "apps:\n  com.a: false\napps:\n  com.b: true\n", bundleID: "com.a", enabled: true)
                == nil)
    }

    @Test("인용이 필요한 bundle id는 손대지 않는다", arguments: [
        "com.a b", "has:colon", "#hash", "", "- dash", "id#note", "\"quoted\"",
    ])
    func refusesBundleIDsNeedingQuotes(_ bundleID: String) {
        #expect(settingAppEnabled(in: "apps:\n  com.a: false\n", bundleID: bundleID, enabled: false) == nil)
    }

    @Test("flow 형태 apps는 손대지 않는다 — 줄을 끼워 넣을 수 없다")
    func refusesFlowMapping() {
        #expect(settingAppEnabled(in: "apps: {}\n", bundleID: "com.a", enabled: false) == nil)
        #expect(
            settingAppEnabled(in: "apps: {com.a: false}\n", bundleID: "com.a", enabled: true) == nil)
    }

    @Test("이미 무효한 파일은 손대지 않는다 — 고칠 대상이 아니라 사용자가 열어 봐야 할 파일이다")
    func refusesAlreadyBrokenFile() {
        #expect(settingAppEnabled(in: "apps: [broken\n", bundleID: "com.a", enabled: false) == nil)
    }
}

/// 편집 결과를 실제 파서로 되읽어 의미를 단언한다 — 순수 함수의 자가검증과 같은 계약이지만
/// 여기서는 **의도한 값이 나오는지**(자가검증은 "의도와 다르면 nil인지")를 본다.
struct AppEnableRoundTripTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let yaml: String
        let bundleID: String
        let enabled: Bool

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "기존 항목 교체", yaml: "apps:\n  com.a: true\n", bundleID: "com.a", enabled: false),
        Case(name: "형제 옆에 신규 삽입", yaml: "apps:\n  com.a: true\n", bundleID: "com.b", enabled: false),
        Case(name: "빈 블록", yaml: "apps:\n", bundleID: "com.a", enabled: false),
        Case(name: "apps 키 부재", yaml: "other: 1\n", bundleID: "com.a", enabled: false),
        Case(name: "빈 파일", yaml: "", bundleID: "com.a", enabled: true),
        Case(name: "번들 config 교체", yaml: bundledConfig, bundleID: "com.microsoft.VSCode", enabled: true),
        Case(name: "번들 config 삽입", yaml: bundledConfig, bundleID: "com.tinyspeck.slackmacgap", enabled: false),
    ]

    @Test("편집 결과는 GlobalConfigParser로 의도대로 읽힌다", arguments: cases)
    func roundTripsThroughTheParser(_ testCase: Case) throws {
        let edited = try #require(
            settingAppEnabled(in: testCase.yaml, bundleID: testCase.bundleID, enabled: testCase.enabled))
        let before = GlobalConfigParser.parse(testCase.yaml, file: testFile)
        let after = GlobalConfigParser.parse(edited, file: testFile)

        #expect(after.error == nil)
        // 형제 항목은 하나도 바뀌지 않고, 대상만 의도한 값이 된다.
        var expected = before.value?.apps ?? [:]
        expected[testCase.bundleID] = testCase.enabled
        #expect(after.value?.apps == expected)
    }

    @Test("후행 개행 유무가 보존된다 — 교체·삽입·블록 추가 전부")
    func preservesTrailingNewline() {
        for (yaml, bundleID) in [
            ("apps:\n  com.a: true", "com.a"),  // 값 교체
            ("apps:\n  com.a: true", "com.b"),  // 마지막 항목 뒤 삽입
            ("other: 1", "com.a"),  // 파일 끝 블록 추가
        ] {
            #expect(
                settingAppEnabled(in: yaml, bundleID: bundleID, enabled: false)?.hasSuffix("\n")
                    == false, "원문에 후행 개행이 없으면 결과에도 없다")
            #expect(
                settingAppEnabled(in: yaml + "\n", bundleID: bundleID, enabled: false)?
                    .hasSuffix("\n") == true, "있으면 그대로 있다")
        }
    }
}

extension String {
    /// 픽스처 단언용 — 딱 한 줄만 바뀌었음을 표현한다.
    fileprivate func replacingLine(_ line: String, with replacement: String) -> String {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) == line ? replacement : String($0) }
            .joined(separator: "\n")
    }
}

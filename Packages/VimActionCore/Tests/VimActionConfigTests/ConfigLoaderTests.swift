import Testing
import VimEngine

@testable import VimActionConfig

private let configPath = "/config/vim-action/config.yaml"
private let profilesDirectory = "/config/vim-action/profiles"

private func load(_ fileSystem: InMemoryFileSystem) -> ConfigLoadResult {
    ConfigLoader(
        configPath: configPath,
        profilesDirectory: profilesDirectory,
        fileSystem: fileSystem.loaderFileSystem
    ).load()
}

private let slackProfilePath = "\(profilesDirectory)/com.tinyspeck.slackmacgap.yaml"
private let notionProfilePath = "\(profilesDirectory)/notion.id.yaml"

@Test("config.yaml과 프로파일을 함께 읽는다")
func loadsConfigAndProfiles() {
    let result = load(
        InMemoryFileSystem(files: [
            configPath: "apps: { com.a: false }",
            slackProfilePath: "actions: { open_line: disabled }",
            notionProfilePath: "motions: { document_start: disabled }",
        ])
    )

    #expect(result.snapshot.global.apps == ["com.a": false])
    #expect(result.snapshot.profiles.keys.sorted() == ["com.tinyspeck.slackmacgap", "notion.id"])
    #expect(result.snapshot.profiles["com.tinyspeck.slackmacgap"]?.actions == [.openLine: .disabled])
    #expect(result.snapshot.profiles["notion.id"]?.motionOverride(for: .documentStart) == .disabled)
    #expect(result.warnings.isEmpty)
    #expect(result.errors.isEmpty)
}

@Test("파일이 하나도 없으면 빈 스냅샷")
func loadsNothingWhenFilesAreAbsent() {
    let result = load(InMemoryFileSystem())

    #expect(result.snapshot == ConfigSnapshot())
    #expect(result.warnings.isEmpty)
    #expect(result.errors.isEmpty)
}

@Test("config.yaml만 없어도 프로파일은 읽힌다")
func loadsProfilesWithoutConfig() {
    let result = load(InMemoryFileSystem(files: [slackProfilePath: "name: Slack"]))

    #expect(result.snapshot.global.apps.isEmpty)
    #expect(result.snapshot.profiles["com.tinyspeck.slackmacgap"]?.name == "Slack")
}

@Test("bundle-id는 파일명에서 .yaml만 떼고 대소문자를 보존한다")
func derivesBundleIDFromFileName() {
    let result = load(InMemoryFileSystem(files: ["\(profilesDirectory)/com.Foo.Bar.yaml": "name: Foo"]))

    #expect(result.snapshot.profiles.keys.sorted() == ["com.Foo.Bar"])
}

@Test("프로파일 디렉터리의 .yaml 아닌 항목은 조용히 건너뛴다")
func skipsNonYAMLEntries() {
    let result = load(
        InMemoryFileSystem(files: [
            "\(profilesDirectory)/README.md": "# 참고",
            "\(profilesDirectory)/notes.txt": "메모",
            "\(profilesDirectory)/com.a.yml": "name: 확장자가 다름",
            slackProfilePath: "name: Slack",
        ])
    )

    #expect(result.snapshot.profiles.keys.sorted() == ["com.tinyspeck.slackmacgap"])
    #expect(result.warnings.isEmpty)
    #expect(result.errors.isEmpty)
}

/// 설정 오류가 Vim 레이어를 통째로 죽이지 않는다는 불변식의 로더 쪽 이행.
@Test("깨진 프로파일 하나가 나머지를 죽이지 않는다")
func brokenProfileDoesNotKillOthers() {
    let result = load(
        InMemoryFileSystem(files: [
            configPath: "apps: { com.a: true }",
            slackProfilePath: "motions:\n  - x\n bad: :",
            notionProfilePath: "name: Notion",
        ])
    )

    #expect(result.snapshot.global.apps == ["com.a": true])
    #expect(result.snapshot.profiles.keys.sorted() == ["notion.id"])
    #expect(result.errors.map(\.file) == [slackProfilePath])
}

@Test("깨진 config.yaml은 부재 취급 — 프로파일은 살아남는다")
func brokenConfigIsTreatedAsAbsent() {
    let result = load(
        InMemoryFileSystem(files: [
            configPath: "apps:\n  - x\n bad: :",
            slackProfilePath: "name: Slack",
        ])
    )

    #expect(result.snapshot.global.apps.isEmpty)
    #expect(result.snapshot.profiles["com.tinyspeck.slackmacgap"]?.name == "Slack")
    #expect(result.errors.map(\.file) == [configPath])
}

@Test("경고에는 그 항목이 나온 파일 경로가 실린다")
func warningsCarryTheirFilePath() {
    let result = load(
        InMemoryFileSystem(files: [
            configPath: "strategy: auto",
            slackProfilePath: "motions: { document_end: [Cmd-Up] }",
        ])
    )

    #expect(
        Set(result.warnings) == [
            ConfigWarning(file: configPath, path: "strategy", kind: .unknownKey),
            ConfigWarning(
                file: slackProfilePath,
                path: "motions.document_end[0]",
                kind: .invalidKeyStroke("Cmd-Up")
            ),
        ]
    )
}

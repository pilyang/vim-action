import Testing

@testable import VimActionConfig

private let root = "/config/vim-action"
private let configPath = "\(root)/config.yaml"
private let profilesDirectory = "\(root)/profiles"
private let slackPath = "\(profilesDirectory)/com.tinyspeck.slackmacgap.yaml"

private let bundledConfig = "apps: { com.microsoft.VSCode: false }"
private let bundledProfiles = ["com.tinyspeck.slackmacgap": "actions: { open_line: disabled }"]

private func seed(_ fileSystem: InMemoryFileSystem) -> [String: ConfigSeeder.Outcome] {
    ConfigSeeder(
        configPath: configPath,
        profilesDirectory: profilesDirectory,
        fileSystem: fileSystem.seederFileSystem
    ).seed(config: bundledConfig, profiles: bundledProfiles)
}

@Test("파일이 없으면 전부 복사한다")
func seedsMissingFiles() {
    let fileSystem = InMemoryFileSystem()

    let outcomes = seed(fileSystem)

    #expect(outcomes == [configPath: .written, slackPath: .written])
    #expect(fileSystem.files[configPath] == bundledConfig)
    #expect(fileSystem.files[slackPath] == bundledProfiles.values.first)
}

/// "이미 있으면 그대로 유지"가 이 계층의 핵심 계약이다 — 사용자가 고친 내용을 절대 덮지 않는다.
@Test("이미 있는 파일은 내용을 보지 않고 그대로 둔다")
func keepsExistingFilesUntouched() {
    let userEdited = "apps: { com.microsoft.VSCode: true }  # 내가 되켰다"
    let fileSystem = InMemoryFileSystem(files: [configPath: userEdited])

    let outcomes = seed(fileSystem)

    #expect(outcomes == [configPath: .skippedExisting, slackPath: .written])
    #expect(fileSystem.files[configPath] == userEdited)
}

@Test("두 번째 시딩은 아무것도 바꾸지 않는다")
func seedingIsIdempotent() {
    let fileSystem = InMemoryFileSystem()

    _ = seed(fileSystem)
    let outcomes = seed(fileSystem)

    #expect(outcomes == [configPath: .skippedExisting, slackPath: .skippedExisting])
}

@Test("쓰기 전에 상위 디렉터리를 만든다")
func createsParentDirectories() {
    let fileSystem = InMemoryFileSystem()

    _ = seed(fileSystem)

    #expect(fileSystem.directories == [root, profilesDirectory])
}

/// 쓰기 실패는 throw가 아니라 값이다 — 시딩 실패가 앱 시작을 막으면 안 된다.
@Test("쓰기 실패는 그 파일만 failed로 보고한다")
func reportsWriteFailurePerFile() {
    let fileSystem = InMemoryFileSystem()
    fileSystem.unwritablePaths = [configPath]

    let outcomes = seed(fileSystem)

    #expect(outcomes == [configPath: .failed, slackPath: .written])
    #expect(fileSystem.files[slackPath] != nil)
}

@Test("동봉할 내용이 없으면 아무것도 하지 않는다")
func seedsNothingWithoutBundledContent() {
    let fileSystem = InMemoryFileSystem()

    let outcomes = ConfigSeeder(
        configPath: configPath,
        profilesDirectory: profilesDirectory,
        fileSystem: fileSystem.seederFileSystem
    ).seed(config: nil, profiles: [:])

    #expect(outcomes.isEmpty)
    #expect(fileSystem.files.isEmpty)
    #expect(fileSystem.directories.isEmpty)
}

import Foundation
import Testing
import VimEngine

@testable import VimActionConfig

/// 설정 계층 소스가 지켜야 할 import 불변식.
///
/// 타깃 의존성 선언(빌드 시스템)이 1차 방어이고, 이 테스트가 2차 방어다.
enum ConfigSourceGuard {
    /// 파싱·병합은 플랫폼 무관이다. **Foundation까지 막는 것이 핵심** — Foundation이 없으면
    /// `FileManager`·`Bundle`에 손이 닿지 않아, 주입 seam이 파일시스템의 유일한 입구가 된다.
    static let forbiddenImports = [
        "Foundation", "AppKit", "Cocoa", "ApplicationServices", "CoreGraphics",
        "Carbon", "SwiftUI", "UIKit", "IOKit",
    ]

    /// 이 테스트 파일(`#filePath`) 기준 패키지 루트.
    static func packageRoot(from testFile: String) -> URL {
        URL(fileURLWithPath: testFile)  // .../Tests/VimActionConfigTests/ConfigInvariantTests.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func swiftFiles(in directory: URL) throws -> [URL] {
        let enumerator = try #require(
            FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil),
            "소스 디렉터리를 열거할 수 없음: \(directory.path)"
        )
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "소스 디렉터리에서 .swift 파일을 찾지 못함: \(directory.path)")
        return files
    }

    static func imports(_ source: String, _ module: String) -> Bool {
        source
            .split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import \(module)") }
    }
}

@Test("설정 소스는 플랫폼 프레임워크를 import하지 않는다")
func configSourcesHaveNoPlatformImports() throws {
    let sources = ConfigSourceGuard.packageRoot(from: #filePath)
        .appendingPathComponent("Sources/VimActionConfig")

    for file in try ConfigSourceGuard.swiftFiles(in: sources) {
        let source = try String(contentsOf: file, encoding: .utf8)
        for module in ConfigSourceGuard.forbiddenImports {
            #expect(
                !ConfigSourceGuard.imports(source, module),
                "\(file.lastPathComponent)가 금지된 프레임워크를 import함: \(module)"
            )
        }
    }
}

/// Yams 의존은 `VimActionConfig` 타깃 밖으로 나가지 않는다는 불변식.
@Test("Yams는 엔진으로 새지 않는다")
func yamsStaysOutOfTheEngine() throws {
    let sources = ConfigSourceGuard.packageRoot(from: #filePath)
        .appendingPathComponent("Sources/VimEngine")

    for file in try ConfigSourceGuard.swiftFiles(in: sources) {
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(
            !ConfigSourceGuard.imports(source, "Yams"),
            "\(file.lastPathComponent)가 Yams를 import함 — 파서 의존이 엔진으로 샜다"
        )
    }
}

/// 현실적인 설정 한 벌이 경고·에러 0건으로 읽힌다 — 과민한 `unknownKey`를 잡는 회귀.
@Test("골든 픽스처는 진단 0건으로 읽힌다")
func goldenFixtureLoadsCleanly() {
    let configPath = "/config/vim-action/config.yaml"
    let profilesDirectory = "/config/vim-action/profiles"
    let fileSystem = InMemoryFileSystem(files: [
        configPath: """
            apps:
              com.mitchellh.ghostty: false
              com.microsoft.VSCode: false
              com.exafunction.windsurf: true
            """,
        "\(profilesDirectory)/com.tinyspeck.slackmacgap.yaml": """
            name: Slack
            actions:
              open_line: disabled
            """,
        "\(profilesDirectory)/notion.id.yaml": """
            name: Notion
            scroll:
              half_page_lines: 20
              full_page_lines: 40
            motions:
              document_start: disabled
              document_end: [cmd-down]
            """,
    ])

    let result = ConfigLoader(
        configPath: configPath,
        profilesDirectory: profilesDirectory,
        fileSystem: fileSystem.loaderFileSystem
    ).load()

    #expect(result.warnings.isEmpty)
    #expect(result.errors.isEmpty)
    #expect(result.snapshot.global.apps.count == 3)

    let notion = result.snapshot.profiles["notion.id"]
    #expect(notion?.halfPageLines == 20)
    #expect(notion?.motionOverride(for: .documentEnd) == .strokes([ConfigKeyStroke(.down, [.cmd])]))
    #expect(result.snapshot.profiles["com.tinyspeck.slackmacgap"]?.disabledActions == [.openLine])
}

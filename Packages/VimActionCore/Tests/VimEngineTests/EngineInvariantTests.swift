import Foundation
import Testing

/// 엔진 소스는 macOS 프레임워크를 import하면 안 된다는 불변식을 테스트로도 지킨다.
///
/// 타깃 의존성을 선언하지 않는 것(빌드 시스템)이 1차 방어이고, 이 테스트가 2차 방어다.
/// 누군가 `.target`에 `AppKit`을 링크하거나 조건부 import를 넣어도 여기서 잡힌다.
enum EngineSourceGuard {
    /// 엔진에 들어오면 안 되는 macOS/그래픽/AX 프레임워크.
    static let forbiddenImports = [
        "AppKit", "Cocoa", "ApplicationServices", "CoreGraphics",
        "Carbon", "SwiftUI", "UIKit", "IOKit",
    ]

    /// 이 테스트 파일(`#filePath`) 기준으로 `Sources/VimEngine` 디렉터리를 찾는다.
    static func sourcesDirectory(from testFile: String) -> URL {
        URL(fileURLWithPath: testFile)  // .../Tests/VimEngineTests/EngineInvariantTests.swift
            .deletingLastPathComponent()  // .../Tests/VimEngineTests
            .deletingLastPathComponent()  // .../Tests
            .deletingLastPathComponent()  // 패키지 루트
            .appendingPathComponent("Sources/VimEngine")
    }
}

@Test
func engineSourcesHaveNoMacOSImports() throws {
    let sourcesDir = EngineSourceGuard.sourcesDirectory(from: #filePath)

    // 하위 폴더로 소스를 나눠도 불변식이 계속 지켜지도록 재귀적으로 열거한다.
    let enumerator = try #require(
        FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil),
        "엔진 소스 디렉터리를 열거할 수 없음: \(sourcesDir.path)"
    )
    let files = enumerator
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }

    #expect(!files.isEmpty, "엔진 소스 디렉터리에서 .swift 파일을 찾지 못함: \(sourcesDir.path)")

    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        for framework in EngineSourceGuard.forbiddenImports {
            let hasImport =
                source
                .split(separator: "\n")
                .contains {
                    $0.trimmingCharacters(in: .whitespaces).hasPrefix("import \(framework)")
                }
            #expect(!hasImport, "\(file.lastPathComponent)가 금지된 프레임워크를 import함: \(framework)")
        }
    }
}

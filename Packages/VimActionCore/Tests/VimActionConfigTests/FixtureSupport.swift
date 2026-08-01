import Testing

@testable import VimActionConfig

/// 파서 테스트가 쓰는 가짜 파일 경로. 실제 `~/.config`는 어떤 테스트도 건드리지 않는다.
let testFile = "config.yaml"

func warning(_ path: String, _ kind: ConfigWarning.Kind, file: String = testFile) -> ConfigWarning {
    ConfigWarning(file: file, path: path, kind: kind)
}

/// 로더·시더 테스트가 주입하는 인메모리 파일시스템.
///
/// 테스트는 이것만 쓴다 — `FileManager`도 실제 `~/.config`도 등장하지 않는다.
/// (테스트는 단일 스레드에서 돌고 seam 클로저가 `@Sendable`이라 `@unchecked`로 둔다.)
final class InMemoryFileSystem: @unchecked Sendable {
    /// 절대 경로 → 내용.
    var files: [String: String]
    /// 존재하는 디렉터리 경로. 시더가 만든 것도 여기 쌓인다.
    var directories: Set<String>
    /// 쓰기를 실패시킬 경로 (쓰기 실패 경로 테스트용).
    var unwritablePaths: Set<String> = []

    init(files: [String: String] = [:], directories: Set<String> = []) {
        self.files = files
        self.directories = directories
    }

    var loaderFileSystem: ConfigLoader.FileSystem {
        ConfigLoader.FileSystem(
            readFile: { [self] path in files[path] },
            listDirectory: { [self] directory in
                files.keys
                    .filter { $0.hasPrefix(directory + "/") }
                    .map { String($0.dropFirst(directory.count + 1)) }
                    .filter { !$0.contains("/") }
            }
        )
    }

    var seederFileSystem: ConfigSeeder.FileSystem {
        ConfigSeeder.FileSystem(
            fileExists: { [self] path in files[path] != nil },
            createDirectory: { [self] path in
                directories.insert(path)
                return true
            },
            writeFile: { [self] path, contents in
                guard !unwritablePaths.contains(path) else { return false }
                files[path] = contents
                return true
            }
        )
    }
}

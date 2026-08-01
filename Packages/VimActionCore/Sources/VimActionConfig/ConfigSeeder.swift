/// 번들 기본값을 사용자 설정 디렉터리에 **초기값으로 복사**한다.
///
/// 번들 기본값은 사용자 파일 아래에 깔리는 계층이 아니다 — 없는 파일만 채우고, **이미 있으면
/// 내용을 보지 않고 그대로 둔다**. 그래서 사용자는 기본값 항목을 덮는 게 아니라 지울 수 있다.
///
/// 대가: 이후 버전이 기존 파일 *안의* 항목을 갱신하지 못한다(새로 추가되는 프로파일 *파일*은
/// 파일 단위 시딩으로 들어온다).
///
/// `Bundle`도 `FileManager`도 모른다 — 동봉 내용은 문자열로 주입받고 쓰기는 seam으로 한다.
public struct ConfigSeeder: Sendable {
    /// 쓰기 seam. 테스트는 인메모리 구현을 주입해 실제 `~/.config`를 건드리지 않는다.
    public struct FileSystem: Sendable {
        public var fileExists: @Sendable (String) -> Bool
        /// 중간 디렉터리까지 만든다. 이미 있으면 성공으로 친다.
        public var createDirectory: @Sendable (String) -> Bool
        public var writeFile: @Sendable (String, String) -> Bool

        public init(
            fileExists: @escaping @Sendable (String) -> Bool,
            createDirectory: @escaping @Sendable (String) -> Bool,
            writeFile: @escaping @Sendable (String, String) -> Bool
        ) {
            self.fileExists = fileExists
            self.createDirectory = createDirectory
            self.writeFile = writeFile
        }
    }

    public enum Outcome: Hashable, Sendable {
        case written
        /// 이미 있어서 건드리지 않았다 — 정상 경로다.
        case skippedExisting
        /// 디렉터리 생성이나 쓰기가 실패했다. 시딩 실패가 앱 시작을 막으면 안 되므로 값으로 돌린다.
        case failed
    }

    private let configPath: String
    private let profilesDirectory: String
    private let fileSystem: FileSystem

    public init(configPath: String, profilesDirectory: String, fileSystem: FileSystem) {
        self.configPath = configPath
        self.profilesDirectory = profilesDirectory
        self.fileSystem = fileSystem
    }

    /// 동봉 내용을 시딩하고 경로별 결과를 돌려준다. 로깅은 소비자의 몫이다.
    ///
    /// - Parameters:
    ///   - config: 번들 `config.yaml` 내용.
    ///   - profiles: bundle-id → 번들 프로파일 YAML.
    public func seed(config: String?, profiles: [String: String]) -> [String: Outcome] {
        var outcomes: [String: Outcome] = [:]

        if let config {
            outcomes[configPath] = seedFile(at: configPath, contents: config)
        }
        for (bundleID, yaml) in profiles {
            let path = "\(profilesDirectory)/\(bundleID).yaml"
            outcomes[path] = seedFile(at: path, contents: yaml)
        }

        return outcomes
    }

    private func seedFile(at path: String, contents: String) -> Outcome {
        guard !fileSystem.fileExists(path) else { return .skippedExisting }
        guard let directory = Self.parentDirectory(of: path),
            fileSystem.createDirectory(directory)
        else { return .failed }
        return fileSystem.writeFile(path, contents) ? .written : .failed
    }

    private static func parentDirectory(of path: String) -> String? {
        guard let separator = path.lastIndex(of: "/") else { return nil }
        return String(path[path.startIndex..<separator])
    }
}

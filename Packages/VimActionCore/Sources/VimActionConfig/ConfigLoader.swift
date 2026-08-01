/// 파싱이 끝난 설정 스냅샷.
///
/// 병합은 없다 — 사용자 파일이 곧 최종값이고, 번들 기본값은 시딩된 초기 내용일 뿐이다.
public struct ConfigSnapshot: Hashable, Sendable {
    public let global: GlobalConfig
    /// bundle-id → 그 앱의 프로파일.
    public let profiles: [String: AppProfile]

    public init(global: GlobalConfig = GlobalConfig(), profiles: [String: AppProfile] = [:]) {
        self.global = global
        self.profiles = profiles
    }
}

public struct ConfigLoadResult: Hashable, Sendable {
    public let snapshot: ConfigSnapshot
    /// 항목 단위로 무시된 것들. 로깅은 소비자의 몫이다.
    public let warnings: [ConfigWarning]
    /// 통째 파싱에 실패한 파일들 — 스냅샷에서는 없는 것으로 취급됐다.
    public let errors: [ConfigError]
}

/// 설정 파일을 읽어 스냅샷을 만든다.
///
/// `Bundle`도 `FileManager`도 모른다 — 파일 접근은 주입된 클로저 seam으로만 한다.
public struct ConfigLoader: Sendable {
    /// 읽기 seam. 테스트는 인메모리 구현을 주입해 실제 `~/.config`를 건드리지 않는다.
    public struct FileSystem: Sendable {
        /// 경로의 텍스트. 없거나 읽을 수 없으면 nil (권한 문제 로깅은 앱 몫).
        public var readFile: @Sendable (String) -> String?
        /// 디렉터리 안의 파일 **이름** 목록. 디렉터리가 없으면 빈 배열.
        public var listDirectory: @Sendable (String) -> [String]

        public init(
            readFile: @escaping @Sendable (String) -> String?,
            listDirectory: @escaping @Sendable (String) -> [String]
        ) {
            self.readFile = readFile
            self.listDirectory = listDirectory
        }
    }

    private let configPath: String
    private let profilesDirectory: String
    private let fileSystem: FileSystem

    public init(configPath: String, profilesDirectory: String, fileSystem: FileSystem) {
        self.configPath = configPath
        self.profilesDirectory = profilesDirectory
        self.fileSystem = fileSystem
    }

    /// 한 번 읽고 파싱한다. 핫 리로드는 이걸 다시 부르는 것이다.
    public func load() -> ConfigLoadResult {
        var warnings: [ConfigWarning] = []
        var errors: [ConfigError] = []

        var global = GlobalConfig()
        if let yaml = fileSystem.readFile(configPath) {
            let outcome = GlobalConfigParser.parse(yaml, file: configPath)
            global = outcome.value ?? GlobalConfig()
            warnings += outcome.warnings
            if let error = outcome.error { errors.append(error) }
        }

        var profiles: [String: AppProfile] = [:]
        for fileName in fileSystem.listDirectory(profilesDirectory) {
            guard let bundleID = Self.bundleID(fromFileName: fileName) else { continue }
            let path = "\(profilesDirectory)/\(fileName)"
            guard let yaml = fileSystem.readFile(path) else { continue }

            let outcome = AppProfileParser.parse(yaml, file: path)
            // 통째 실패한 프로파일은 그 앱만 없는 것이 된다 — 나머지 앱은 영향받지 않는다.
            if let profile = outcome.value { profiles[bundleID] = profile }
            warnings += outcome.warnings
            if let error = outcome.error { errors.append(error) }
        }

        return ConfigLoadResult(
            snapshot: ConfigSnapshot(global: global, profiles: profiles),
            warnings: warnings,
            errors: errors
        )
    }

    /// 프로파일 파일명 → bundle-id. `.yaml`이 아닌 항목은 프로파일이 아니다(조용히 건너뛴다).
    private static func bundleID(fromFileName fileName: String) -> String? {
        let suffix = ".yaml"
        guard fileName.hasSuffix(suffix), fileName.count > suffix.count else { return nil }
        return String(fileName.dropLast(suffix.count))
    }
}

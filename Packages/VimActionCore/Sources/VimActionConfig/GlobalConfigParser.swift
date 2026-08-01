import Yams

/// `config.yaml` 한 파일을 읽는다.
///
/// Codable을 쓰지 않는 이유: 항목 하나가 잘못됐을 때 **그 항목만** 버리고 나머지를 살려야 하는데,
/// Codable은 파일 단위 실패만 표현한다.
enum GlobalConfigParser {
    static func parse(_ yaml: String, file: String) -> ParseOutcome<GlobalConfig> {
        let collector = WarningCollector(file: file)

        let root: Node?
        switch composeRoot(yaml, file: file) {
        case .success(let node): root = node
        case .failure(let error): return .failed(error)
        }
        guard let root else { return .parsed(GlobalConfig(), []) }

        var apps: [String: Bool] = [:]
        forEachEntry(of: root, at: "", collector) { key, value, path in
            guard key == "apps" else { return false }  // strategy·per_element 등 M5 필드가 여기로 접힌다
            forEachEntry(of: value, at: path, collector) { bundleID, value, path in
                if let enabled = boolValue(of: value, at: path, collector) {
                    apps[bundleID] = enabled
                }
                return true  // bundle-id는 자유 키라 미지 키가 없다
            }
            return true
        }

        return .parsed(GlobalConfig(apps: apps), collector.warnings)
    }
}

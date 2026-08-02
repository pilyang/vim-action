import VimEngine
import Yams

/// `profiles/<bundle-id>.yaml` 한 파일을 읽는다.
enum AppProfileParser {
    /// 유효한 scroll 값의 범위. 스크롤은 줄 수 × 카운트로 곱해지는 증폭 축이라 상한이 있다.
    static let scrollLineRange = 1...200

    /// disable을 뜻하는 매핑 값. 소문자만 유효하다(대소문자 관용 없음).
    private static let disabledKeyword = "disabled"

    static func parse(_ yaml: String, file: String) -> ParseOutcome<AppProfile> {
        let collector = WarningCollector(file: file)

        let root: Node?
        switch composeRoot(yaml, file: file) {
        case .success(let node): root = node
        case .failure(let error): return .failed(error)
        }
        guard let root else { return .parsed(AppProfile(), []) }

        var name: String?
        var halfPageLines: Int?
        var fullPageLines: Int?
        var motions: [Motion: ConfigOverride] = [:]
        var actions: [ConfigAction: ConfigOverride] = [:]

        forEachEntry(of: root, at: "", collector) { key, value, path in
            switch key {
            case "name":
                name = stringValue(of: value, at: path, collector)
            case "scroll":
                forEachEntry(of: value, at: path, collector) { key, value, path in
                    switch key {
                    case "half_page_lines":
                        halfPageLines = intValue(
                            of: value, at: path, in: scrollLineRange, collector)
                    case "full_page_lines":
                        fullPageLines = intValue(
                            of: value, at: path, in: scrollLineRange, collector)
                    default:
                        return false
                    }
                    return true
                }
            case "motions":
                forEachEntry(of: value, at: path, collector) { name, value, path in
                    // append 전용 이름은 여기 없다 — base 모션 재정의를 상속하므로 미지 이름이다.
                    guard let motion = MotionVocabulary.byName[name] else { return false }
                    if let override = override(of: value, at: path, collector) {
                        motions[motion] = override
                    }
                    return true
                }
            case "actions":
                forEachEntry(of: value, at: path, collector) { name, value, path in
                    guard let action = ConfigAction(rawValue: name) else { return false }
                    guard let override = override(of: value, at: path, collector) else {
                        return true
                    }
                    // 자기 키가 없는 액션(`scroll`)의 시퀀스는 교체할 대상이 없다 — 미지
                    // 값과 같은 warn+무시로 접는다. disable은 모든 액션에서 유효하다.
                    if case .strokes = override, !action.hasOwnKey {
                        collector.warn(path, .invalidValue(describe(value)))
                        return true
                    }
                    actions[action] = override
                    return true
                }
            default:
                return false  // strategy·per_element 등 M5 필드가 여기로 접힌다
            }
            return true
        }

        let profile = AppProfile(
            name: name,
            halfPageLines: halfPageLines,
            fullPageLines: fullPageLines,
            motions: motions,
            actions: actions
        )
        return .parsed(profile, collector.warnings)
    }

    /// `motions:`·`actions:` 값 — 시퀀스이거나 `disabled`다. 스칼라를 먼저 갈라야 하는 이유:
    /// Yams의 `Node.string`은 어떤 스칼라에도 non-nil이라 "문자열인가"로는 구분되지 않는다.
    private static func override(
        of node: Node, at path: String, _ collector: WarningCollector
    ) -> ConfigOverride? {
        if case .scalar = node {
            return isDisabled(node, at: path, collector) ? .disabled : nil
        }
        return keyStrokes(of: node, at: path, collector).map(ConfigOverride.strokes)
    }

    /// 값이 `disabled` 키워드인가. 아니면 경고 후 false.
    private static func isDisabled(
        _ node: Node, at path: String, _ collector: WarningCollector
    ) -> Bool {
        guard case .scalar(let scalar) = node, scalar.string == disabledKeyword else {
            collector.warn(path, .invalidValue(describe(node)))
            return false
        }
        return true
    }
}

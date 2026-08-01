import Yams

/// 파일 하나의 파싱 결과. `value == nil`이면 통째 파싱 실패 — 그 파일은 없는 것으로 취급된다.
struct ParseOutcome<Value> {
    let value: Value?
    let warnings: [ConfigWarning]
    let error: ConfigError?

    static func parsed(_ value: Value, _ warnings: [ConfigWarning]) -> ParseOutcome {
        ParseOutcome(value: value, warnings: warnings, error: nil)
    }

    static func failed(_ error: ConfigError) -> ParseOutcome {
        ParseOutcome(value: nil, warnings: [], error: error)
    }
}

/// 파싱 중 경고를 모으는 수집기.
///
/// **참조 타입인 것이 의도적이다** — 값 타입 + `inout`이면 `forEachEntry`에 넘긴 수집기를
/// 그 클로저 안에서 다시 건드리게 되어 배타적 접근 위반이 난다.
final class WarningCollector {
    let file: String
    private(set) var warnings: [ConfigWarning] = []

    init(file: String) {
        self.file = file
    }

    func warn(_ path: String, _ kind: ConfigWarning.Kind) {
        warnings.append(ConfigWarning(file: file, path: path, kind: kind))
    }
}

/// YAML 텍스트를 루트 노드로. 빈 문서는 `nil` 노드, 통째 실패는 `ConfigError`다.
func composeRoot(_ yaml: String, file: String) -> Result<Node?, ConfigError> {
    do {
        return .success(try Yams.compose(yaml: yaml))
    } catch {
        return .failure(ConfigError(file: file, message: "\(error)"))
    }
}

/// 경고 메시지에 실을 값의 원문. 스칼라는 그 텍스트, 그 밖은 종류 이름이다.
func describe(_ node: Node) -> String {
    switch node {
    case .scalar(let scalar): scalar.string
    case .sequence: "sequence"
    case .mapping: "mapping"
    default: "unsupported"  // 앵커/별칭 등 — v1 스키마가 쓰지 않는 노드 종류
    }
}

/// 값이 비어 있는 키(`apps:` 뒤에 아무것도 없는 형태)인가. 편집 중인 파일의 일상적 모습이라
/// 오류가 아니라 "없음"으로 본다.
private func isNull(_ node: Node) -> Bool {
    if case .scalar(let scalar) = node { return scalar.string.isEmpty || node.null != nil }
    return false
}

/// 매핑 노드를 순회한다. 두 파서의 모든 반복이 이 하나를 탄다.
///
/// - 널이면 아무 엔트리도 돌리지 않는다(경고 없음).
/// - 매핑이 아니면 `invalidValue` 경고 하나로 접는다.
/// - `handle`이 `false`를 돌려준 키는 `unknownKey` 경고가 된다 — 고정 필드의 미지 키든
///   미지 모션명·액션명이든 같은 처리이고, 구분은 `path`가 한다.
/// - `handle`의 세 번째 인자는 이어 붙인 자식 경로다. 파서가 문자열 조립을 하지 않는다.
func forEachEntry(
    of node: Node,
    at path: String,
    _ warnings: WarningCollector,
    _ handle: (_ key: String, _ value: Node, _ childPath: String) -> Bool
) {
    guard !isNull(node) else { return }
    guard let mapping = node.mapping else {
        warnings.warn(path, .invalidValue(describe(node)))
        return
    }

    for (keyNode, value) in mapping {
        guard case .scalar(let keyScalar) = keyNode else {
            warnings.warn(path, .invalidValue(describe(keyNode)))
            continue
        }
        let key = keyScalar.string
        let childPath = path.isEmpty ? key : "\(path).\(key)"
        if !handle(key, value, childPath) {
            warnings.warn(childPath, .unknownKey)
        }
    }
}

/// 문자열 스칼라. 스칼라가 아니면 경고 후 nil.
func stringValue(of node: Node, at path: String, _ warnings: WarningCollector) -> String? {
    guard case .scalar(let scalar) = node else {
        warnings.warn(path, .invalidValue(describe(node)))
        return nil
    }
    return scalar.string
}

/// 진리값. YAML 1.1 해석을 그대로 쓴다(`yes`/`no`도 유효).
func boolValue(of node: Node, at path: String, _ warnings: WarningCollector) -> Bool? {
    guard let value = node.bool else {
        warnings.warn(path, .invalidValue(describe(node)))
        return nil
    }
    return value
}

/// 범위 안의 정수. `20.5`·`true` 같은 값이 새지 않도록 `node.int`가 아니라 원문에서 직접 읽는다.
func intValue(
    of node: Node, at path: String, in range: ClosedRange<Int>, _ warnings: WarningCollector
) -> Int? {
    guard case .scalar(let scalar) = node, let value = Int(scalar.string), range.contains(value)
    else {
        warnings.warn(path, .invalidValue(describe(node)))
        return nil
    }
    return value
}

/// 키 스트로크 시퀀스. 빈 배열·비스칼라 원소·토큰 실패는 전부 경고 후 **항목 전체 폐기**(nil)다 —
/// 반쯤 맞는 시퀀스를 만들면 "지원 ⟹ 빈 시퀀스 아님" 매퍼 불변식이 흔들린다.
func keyStrokes(of node: Node, at path: String, _ warnings: WarningCollector) -> [ConfigKeyStroke]?
{
    guard let sequence = node.sequence else {
        warnings.warn(path, .invalidValue(describe(node)))
        return nil
    }
    guard !sequence.isEmpty else {
        // 빈 배열은 disable이 아니다 — 끄려는 의도는 `disabled`로 명시해야 한다.
        warnings.warn(path, .invalidValue("[]"))
        return nil
    }

    var strokes: [ConfigKeyStroke] = []
    for (index, element) in sequence.enumerated() {
        let elementPath = "\(path)[\(index)]"
        guard case .scalar(let scalar) = element else {
            warnings.warn(elementPath, .invalidValue(describe(element)))
            return nil
        }
        guard let stroke = ConfigKeyStroke(token: scalar.string) else {
            warnings.warn(elementPath, .invalidKeyStroke(scalar.string))
            return nil
        }
        strokes.append(stroke)
    }
    return strokes
}

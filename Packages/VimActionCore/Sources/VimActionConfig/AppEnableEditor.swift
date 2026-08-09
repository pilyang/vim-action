/// `config.yaml`에서 앱 하나의 on/off만 바꾼 새 텍스트를 만든다.
///
/// **재직렬화(Yams dump)를 하지 않는다** — 파싱→수정→덤프는 사용자의 주석·키 순서·서식을
/// 통째로 날린다. 대신 라인 단위 텍스트 편집만 한다: 값 토큰 교체 / 한 줄 삽입 / 블록 추가.
///
/// - Returns: 바뀐 전체 텍스트. **`nil`은 실패가 아니라 "안전하게 손대지 않음"**이고,
///   호출자는 파일을 열어 사용자가 직접 고치게 폴백한다.
///
/// 이 편집이 중복 키를 만들면 Yams `compose`가 던져 config.yaml이 **통째로 무효**가 되고,
/// 그 순간 사용자가 off 해둔 앱이 전부 켜진다. 그래서 조금이라도 애매하면 `nil`이고,
/// 마지막에 결과를 실제로 파싱해 의미가 의도대로인지 **증명한 뒤에만** 돌려준다.
public func settingAppEnabled(in yaml: String, bundleID: String, enabled: Bool) -> String? {
    // 인용이 필요한 문자가 섞이면 우리가 만드는 줄이 우리 의도와 다른 키가 된다.
    guard isPlainKey(bundleID) else { return nil }
    // 원본이 이미 무효면 손대지 않는다 — 고칠 대상이 아니라 사용자가 열어 봐야 할 파일이다.
    guard let before = GlobalConfigParser.parse(yaml, file: "").value else { return nil }

    guard let edited = editingAppsEntry(yaml, bundleID: bundleID, enabled: enabled) else {
        return nil
    }

    // 자가검증: 중복 키 생성·엉뚱한 블록 삽입·들여쓰기 파손·형제 항목 훼손이 전부 여기서 걸린다.
    var expected = before.apps
    expected[bundleID] = enabled
    guard let after = GlobalConfigParser.parse(edited, file: "").value, after.apps == expected
    else { return nil }
    return edited
}

/// 텍스트 편집만 — 의미 검증은 호출자(`settingAppEnabled`)가 한다.
private func editingAppsEntry(_ yaml: String, bundleID: String, enabled: Bool) -> String? {
    let hadTrailingNewline = yaml.hasSuffix("\n")
    var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if hadTrailingNewline { lines.removeLast() }
    let value = enabled ? "true" : "false"

    // 최상위 `apps:` 줄. 주석 줄은 `keyLine`이 걸러내므로 `# com.a: false`는 매칭되지 않는다.
    let appsLines = lines.indices.filter { index in
        guard let key = keyLine(lines[index]) else { return false }
        return key.indent == 0 && key.name == "apps"
    }
    guard appsLines.count <= 1 else { return nil }  // 이미 중복 키 — 파일이 통째로 무효다
    guard let appsIndex = appsLines.first else {
        return joined(appendingAppsBlock(to: lines, entry: "\(bundleID): \(value)"), hadTrailingNewline)
    }
    // 블록 형태여야 한 줄을 끼워 넣을 수 있다 — `apps: {}` 같은 flow 형태는 손대지 않는다.
    guard let appsKey = keyLine(lines[appsIndex]),
        valueParts(after: appsKey.colon, in: lines[appsIndex]).token.isEmpty
    else { return nil }

    // apps 블록 = 다음 줄부터 들여쓰기가 더 깊은 줄들. 빈 줄·주석 줄은 블록을 끊지 않는다.
    var entryIndent: Int?
    var lastEntry: Int?
    var matches: [(line: Int, colon: String.Index)] = []
    var index = appsIndex + 1
    while index < lines.count {
        let line = lines[index]
        let indent = leadingSpaces(of: line).count
        let rest = line.dropFirst(indent)
        if rest.isEmpty || rest.first == "#" {
            index += 1
            continue
        }
        guard indent > 0 else { break }  // 다음 최상위 키
        // 항목 들여쓰기는 블록의 첫 항목에서 상속한다 — 더 깊은 줄은 항목이 아니다.
        if let key = keyLine(line), key.indent == (entryIndent ?? key.indent) {
            entryIndent = key.indent
            lastEntry = index
            if key.name == bundleID { matches.append((index, key.colon)) }
        }
        index += 1
    }

    // 중복 키는 손대지 않는다 — 그 파일은 이미 통째로 무효다.
    guard matches.count <= 1 else { return nil }
    if let match = matches.first {
        lines[match.line] = replacingValue(in: lines[match.line], colon: match.colon, with: value)
    } else {
        // 마지막 **항목** 뒤에 넣는다(블록 뒤 주석 뒤가 아니라) — 다음 최상위 키에 딸린
        // 주석을 넘어가지 않는다.
        let indent = String(repeating: " ", count: entryIndent ?? 2)
        lines.insert("\(indent)\(bundleID): \(value)", at: (lastEntry ?? appsIndex) + 1)
    }
    return joined(lines, hadTrailingNewline)
}

private func appendingAppsBlock(to lines: [String], entry: String) -> [String] {
    var out = lines
    if out.contains(where: { !isBlank($0) }) {
        // 기존 내용과 새 블록 사이에 빈 줄 하나.
        if let last = out.last, !isBlank(last) { out.append("") }
    } else {
        out = []  // 빈 파일 — 남은 빈 줄을 블록으로 대체한다(새 파일이 빈 줄로 시작하지 않게)
    }
    out.append("apps:")
    out.append("  \(entry)")
    return out
}

private func joined(_ lines: [String], _ trailingNewline: Bool) -> String {
    lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
}

// MARK: - 라인 파싱 (Foundation 없이 — 이 타깃의 불변식)

/// `key: value` 형태의 줄. 빈 줄·주석 줄·`:`이 없는 줄은 `nil`이다.
private struct KeyLine {
    let indent: Int
    let name: String
    /// `:` 위치 — 값 토큰 교체가 이 뒤만 건드린다.
    let colon: String.Index
}

private func keyLine(_ line: String) -> KeyLine? {
    let indent = leadingSpaces(of: line).count
    let rest = line.dropFirst(indent)
    guard let first = rest.first, first != "#" else { return nil }
    guard let colon = rest.firstIndex(of: ":") else { return nil }
    return KeyLine(
        indent: indent,
        name: unquoted(trimmingTrailingSpaces(rest[rest.startIndex..<colon])),
        colon: colon)
}

/// `:` 뒤를 (값 앞 공백, 값 토큰, 값 뒤 공백, 후행 주석)으로 쪼갠다. 넷을 그대로 이어 붙이면
/// 원문이 복원되므로, 값만 갈아 끼우면 들여쓰기·주석이 보존된다.
private struct ValueParts {
    let leading: Substring
    let token: Substring
    let trailingSpaces: Substring
    let comment: Substring
}

private func valueParts(after colon: String.Index, in line: String) -> ValueParts {
    let after = line[line.index(after: colon)...]
    // YAML 주석은 앞에 공백이 있어야 시작한다 — `key:#x`의 `#x`는 주석이 아니라 값이다.
    var commentStart = after.endIndex
    var previous: Character = ":"
    var index = after.startIndex
    while index < after.endIndex {
        let character = after[index]
        if character == "#", previous == " " || previous == "\t" {
            commentStart = index
            break
        }
        previous = character
        index = after.index(after: index)
    }

    let head = after[after.startIndex..<commentStart]
    let leading = head.prefix(while: { $0 == " " || $0 == "\t" })
    let token = trimmingTrailingSpaces(head[leading.endIndex...])
    return ValueParts(
        leading: leading,
        token: token,
        trailingSpaces: head[token.endIndex...],
        comment: after[commentStart...])
}

private func replacingValue(in line: String, colon: String.Index, with value: String) -> String {
    let parts = valueParts(after: colon, in: line)
    let head = line[line.startIndex...colon]
    guard !parts.token.isEmpty else {
        // 값이 비어 있던 줄(`com.a:`) — 주석이 있으면 사이에 공백 하나가 필요하다.
        return "\(head) \(value)\(parts.comment.isEmpty ? "" : " \(parts.comment)")"
    }
    return "\(head)\(parts.leading)\(value)\(parts.trailingSpaces)\(parts.comment)"
}

private func leadingSpaces(of line: String) -> Substring {
    line.prefix(while: { $0 == " " })
}

private func isBlank(_ line: String) -> Bool {
    line.allSatisfy { $0 == " " || $0 == "\t" }
}

private func trimmingTrailingSpaces(_ text: Substring) -> Substring {
    var end = text.endIndex
    while end > text.startIndex {
        let previous = text.index(before: end)
        guard text[previous] == " " || text[previous] == "\t" else { break }
        end = previous
    }
    return text[text.startIndex..<end]
}

private func unquoted(_ text: Substring) -> String {
    guard let first = text.first, first == "\"" || first == "'", text.count >= 2,
        text.last == first
    else { return String(text) }
    return String(text.dropFirst().dropLast())
}

/// 인용 없이 그대로 YAML 키로 쓸 수 있는가. 실제 bundle id는 전부 통과하고, `:`·`#`·공백·
/// 선행 인디케이터가 섞인 문자열은 여기서 막힌다.
private func isPlainKey(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return text.allSatisfy { character in
        character.isASCII
            && (character.isLetter || character.isNumber || character == "." || character == "-"
                || character == "_")
    }
}

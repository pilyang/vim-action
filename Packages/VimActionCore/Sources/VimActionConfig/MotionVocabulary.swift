import VimEngine

/// 프로파일 `motions:`의 모션 이름 어휘.
///
/// 이름은 `Motion` 케이스에서 파생한 소문자 snake_case이며, **자동 변환이 아니라 명시적 표**다 —
/// 케이스가 늘면 컴파일러가 여기서 멈춰 "이 모션을 사용자에게 노출할 것인가"를 결정하게 만든다.
enum MotionVocabulary {
    /// 설정 어휘에 노출되는 이름. append 전용 2종은 노출하지 않으므로 nil이다.
    static func name(for motion: Motion) -> String? {
        switch motion {
        case .charLeft: "char_left"
        case .charRight: "char_right"
        case .lineUp: "line_up"
        case .lineDown: "line_down"
        case .wordForward: "word_forward"
        case .wordBackward: "word_backward"
        case .wordEndForward: "word_end_forward"
        case .lineStart: "line_start"
        case .lineFirstNonBlank: "line_first_non_blank"
        case .lineEnd: "line_end"
        case .documentStart: "document_start"
        case .documentEnd: "document_end"
        // a/A 전용 케이스는 사용자 조절축이 아니라 어댑터의 줄 끝 시맨틱 구분용이다.
        // base 모션 재정의를 `overrideKey(for:)`로 상속한다.
        case .charRightForAppend, .lineEndForAppend: nil
        }
    }

    /// 이름 → 모션 역조회. 여기 없는 이름은 미지 모션명(warn+무시)이다.
    static let byName: [String: Motion] = Motion.allCases.reduce(into: [:]) { table, motion in
        if let name = name(for: motion) { table[name] = motion }
    }

    /// 재정의를 찾을 때 쓸 키. append 전용 모션은 base 모션의 재정의·disable을 상속한다 —
    /// 사용자 관점에서 `$`와 `A`의 줄 끝은 같은 개념이다.
    static func overrideKey(for motion: Motion) -> Motion {
        switch motion {
        case .charRightForAppend: .charRight
        case .lineEndForAppend: .lineEnd
        default: motion
        }
    }
}

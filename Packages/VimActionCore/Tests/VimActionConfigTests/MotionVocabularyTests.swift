import Testing
import VimEngine

@testable import VimActionConfig

/// 설정 어휘에 노출되지 않는 모션 — append 전용 2종은 base 모션을 따라간다.
private let appendOnlyMotions: [Motion] = [.charRightForAppend, .lineEndForAppend]

/// 어휘 전체 스냅샷. 이름이 바뀌면 사용자 파일이 깨지므로 목록 자체가 계약이다.
@Test("모션 이름 목록 스냅샷")
func motionNameSnapshot() {
    #expect(
        MotionVocabulary.byName.keys.sorted() == [
            "char_left",
            "char_right",
            "document_end",
            "document_start",
            "line_down",
            "line_end",
            "line_first_non_blank",
            "line_start",
            "line_up",
            "word_backward",
            "word_end_forward",
            "word_forward",
        ]
    )
}

/// 케이스가 늘면 이름을 주든 append처럼 명시적으로 빼든 결정하게 만든다.
@Test("append 2종을 뺀 모든 모션이 어휘에 있다")
func vocabularyCoversEveryNonAppendMotion() {
    #expect(MotionVocabulary.byName.count == Motion.allCases.count - appendOnlyMotions.count)
}

@Test("이름 왕복", arguments: Motion.allCases)
func nameRoundTrip(_ motion: Motion) {
    guard let name = MotionVocabulary.name(for: motion) else {
        #expect(appendOnlyMotions.contains(motion), "이름이 없는 모션은 append 전용 2종뿐이어야 한다")
        return
    }
    #expect(MotionVocabulary.byName[name] == motion)
}

@Test("append 전용 모션은 어휘에 노출되지 않는다", arguments: appendOnlyMotions)
func appendMotionsAreNotInVocabulary(_ motion: Motion) {
    #expect(MotionVocabulary.name(for: motion) == nil)
}

@Test("append 이름은 미지 모션명이다")
func appendMotionNamesAreUnknown() {
    #expect(MotionVocabulary.byName["char_right_for_append"] == nil)
    #expect(MotionVocabulary.byName["line_end_for_append"] == nil)
}

/// 재정의 조회의 단일 지점 — a/A는 `char_right`/`line_end`의 재정의를 그대로 상속한다.
@Test("append 전용 모션은 base 모션의 재정의를 상속한다")
func appendMotionsInheritBaseOverride() {
    #expect(MotionVocabulary.overrideKey(for: .charRightForAppend) == .charRight)
    #expect(MotionVocabulary.overrideKey(for: .lineEndForAppend) == .lineEnd)
}

@Test("그 밖의 모션은 자기 자신이 조회 키다", arguments: Motion.allCases)
func nonAppendMotionsAreTheirOwnOverrideKey(_ motion: Motion) {
    guard !appendOnlyMotions.contains(motion) else { return }
    #expect(MotionVocabulary.overrideKey(for: motion) == motion)
}

@Test("이름은 전부 소문자 snake_case다")
func namesAreLowercaseSnakeCase() {
    for name in MotionVocabulary.byName.keys {
        #expect(name.allSatisfy { $0.isLowercase || $0 == "_" }, "\(name)이 소문자 snake_case가 아님")
    }
}

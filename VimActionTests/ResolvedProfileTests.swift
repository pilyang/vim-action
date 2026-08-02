//
//  ResolvedProfileTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimActionConfig
import VimEngine
@testable import VimAction

/// 설정 표기(`ConfigKeyStroke`) → 실행 키(`KeyStroke`) 변환 골든.
struct KeyStrokeConversionFixture: CustomTestStringConvertible {
    let config: ConfigKeyStroke
    let expected: KeyStroke

    init(_ key: ConfigKey, _ expected: KeyStroke, modifiers: Set<ConfigModifier> = []) {
        config = ConfigKeyStroke(key, modifiers)
        self.expected = expected
    }

    var testDescription: String { "\(config.key.rawValue)+\(config.modifiers.count)modifiers" }
}

/// 키 11종 전부 — 변환 switch가 exhaustive라 케이스 추가는 컴파일러가 강제하고,
/// 여기서는 값이 맞는지를 고정한다.
let keyStrokeConversionFixtures: [KeyStrokeConversionFixture] = [
    .init(.left, KeyStroke(kVK_LeftArrow)),
    .init(.right, KeyStroke(kVK_RightArrow)),
    .init(.up, KeyStroke(kVK_UpArrow)),
    .init(.down, KeyStroke(kVK_DownArrow)),
    .init(.return, KeyStroke(kVK_Return)),
    .init(.escape, KeyStroke(kVK_Escape)),
    .init(.tab, KeyStroke(kVK_Tab)),
    .init(.home, KeyStroke(kVK_Home)),
    .init(.end, KeyStroke(kVK_End)),
    .init(.pageUp, KeyStroke(kVK_PageUp)),
    .init(.pageDown, KeyStroke(kVK_PageDown)),
    // 수정자 4종 + 조합 — 순서 무관 집합이 플래그 합집합이 된다.
    .init(.down, KeyStroke(kVK_DownArrow, [.maskCommand]), modifiers: [.cmd]),
    .init(.right, KeyStroke(kVK_RightArrow, [.maskAlternate]), modifiers: [.opt]),
    .init(.up, KeyStroke(kVK_UpArrow, [.maskControl]), modifiers: [.ctrl]),
    .init(.left, KeyStroke(kVK_LeftArrow, [.maskShift]), modifiers: [.shift]),
    .init(.end, KeyStroke(kVK_End, [.maskCommand, .maskShift]), modifiers: [.cmd, .shift]),
]

struct ResolvedProfileTests {
    @Test("설정 키 토큰이 실행 키코드·플래그로 변환된다", arguments: keyStrokeConversionFixtures)
    func convertsConfigKeyStroke(_ fixture: KeyStrokeConversionFixture) {
        #expect(KeyStroke(fixture.config) == fixture.expected)
    }

    @Test("시퀀스 재정의는 로드 시 KeyStroke로 변환돼 담긴다")
    func bakesStrokeOverrides() {
        let profile = ResolvedProfile(
            AppProfile(motions: [.documentEnd: .strokes([ConfigKeyStroke(.end, [.cmd])])]))
        #expect(profile.motionOverrides[.documentEnd] == .strokes([KeyStroke(kVK_End, [.maskCommand])]))
        #expect(profile.motionOverrides[.documentStart] == nil, "재정의 없는 모션은 항목이 없다")
    }

    @Test("disabled 재정의가 그대로 담긴다")
    func bakesDisabledOverrides() {
        let profile = ResolvedProfile(AppProfile(motions: [.documentStart: .disabled]))
        #expect(profile.motionOverrides[.documentStart] == .disabled)
    }

    /// append 전용 모션(a/A)은 설정 어휘에 없다 — base 모션(`char_right`/`line_end`)의
    /// 재정의·disable을 베이킹 시점에 상속해야 어댑터 조회가 상속을 다시 알 필요가 없다.
    @Test("append 전용 모션이 base 모션의 재정의를 상속한다")
    func appendMotionsInheritBaseOverrides() {
        let profile = ResolvedProfile(
            AppProfile(motions: [
                .charRight: .strokes([ConfigKeyStroke(.right, [.cmd])]),
                .lineEnd: .disabled,
            ]))
        #expect(
            profile.motionOverrides[.charRightForAppend]
                == .strokes([KeyStroke(kVK_RightArrow, [.maskCommand])]))
        #expect(profile.motionOverrides[.lineEndForAppend] == .disabled)
    }

    @Test("scroll·이름·액션 disable이 그대로 전달된다")
    func carriesScalarFields() {
        let profile = ResolvedProfile(
            AppProfile(
                name: "Slack", halfPageLines: 12, fullPageLines: 24,
                actions: [.openLine: .disabled]))
        #expect(profile.name == "Slack")
        #expect(profile.halfPageLines == 12)
        #expect(profile.fullPageLines == 24)
        #expect(profile.actionOverrides == [.openLine: .disabled])
    }

    /// 매퍼가 보는 창구는 이름 붙인 프로퍼티다 — 여기서 `ConfigAction`이 실행 계층으로
    /// 새지 않는다. disable이 `nil`로 접히는 것도 계약이다(어댑터가 앞에서 걸러낸다).
    @Test("액션 자신의 키 재정의는 이름 붙인 프로퍼티로 노출된다")
    func exposesActionKeyOverrides() {
        let profile = ResolvedProfile(
            AppProfile(actions: [
                .openLine: .strokes([ConfigKeyStroke(.return, [.shift])]),
                .undo: .disabled,
            ]))

        #expect(profile.newLineStrokes == [KeyStroke(kVK_Return, [.maskShift])])
        #expect(profile.undoStrokes == nil, "disable은 매퍼까지 오지 않는다")
        #expect(profile.pasteStrokes == nil)
        #expect(profile.redoStrokes == nil)
    }

    @Test(".empty는 아무 재정의도 없다 — 모든 매퍼가 내장 테이블 그대로다")
    func emptyHasNoOverrides() {
        #expect(ResolvedProfile.empty.motionOverrides.isEmpty)
        #expect(ResolvedProfile.empty.actionOverrides.isEmpty)
        #expect(ResolvedProfile.empty.newLineStrokes == nil)
        #expect(ResolvedProfile.empty.halfPageLines == nil)
        #expect(ResolvedProfile.empty.fullPageLines == nil)
    }
}

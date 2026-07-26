//
//  MotionKeyMapperTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine
@testable import VimAction

/// 매핑 계약 결정 문서(`20260726_motion-keystroke-mapping-contract.md`)의 매핑표 한 행.
/// **이 픽스처가 곧 계약이다** — 표가 바뀌면 여기가 먼저 바뀐다.
struct MotionMappingFixture: Sendable, CustomTestStringConvertible {
    var motion: Motion
    var expected: [KeyStroke]

    init(_ motion: Motion, _ expected: [KeyStroke]) {
        self.motion = motion
        self.expected = expected
    }

    var testDescription: String { "\(motion)" }
}

/// 매핑표 전체(근사 3건 포함). 화살표 키코드는 레이아웃 무관 고정값이라
/// QWERTY 조건이 필요 없다.
let motionMappingFixtures: [MotionMappingFixture] = [
    .init(.charLeft, [KeyStroke(kVK_LeftArrow)]),
    .init(.charRight, [KeyStroke(kVK_RightArrow)]),
    .init(.lineUp, [KeyStroke(kVK_UpArrow)]),
    .init(.lineDown, [KeyStroke(kVK_DownArrow)]),
    // 근사 — "다음 단어 시작"이 macOS에 없어 e와 동일 취급.
    .init(.wordForward, [KeyStroke(kVK_RightArrow, [.maskAlternate])]),
    .init(.wordBackward, [KeyStroke(kVK_LeftArrow, [.maskAlternate])]),
    .init(.wordEndForward, [KeyStroke(kVK_RightArrow, [.maskAlternate])]),
    .init(.lineStart, [KeyStroke(kVK_LeftArrow, [.maskCommand])]),
    // 근사 — 첫 비공백 개념이 macOS에 없어 0과 동일 취급.
    .init(.lineFirstNonBlank, [KeyStroke(kVK_LeftArrow, [.maskCommand])]),
    .init(.lineEnd, [KeyStroke(kVK_RightArrow, [.maskCommand])]),
    .init(.documentStart, [KeyStroke(kVK_UpArrow, [.maskCommand])]),
    .init(.documentEnd, [KeyStroke(kVK_DownArrow, [.maskCommand])]),
    // 캐럿 모델에서 l·$와의 구분이 자연 소멸 — 케이스는 AX 어댑터용으로 유지된다.
    .init(.charRightForAppend, [KeyStroke(kVK_RightArrow)]),
    .init(.lineEndForAppend, [KeyStroke(kVK_RightArrow, [.maskCommand])]),
]

struct MotionKeyMapperTests {
    @Test("매핑표 골든 — 모션이 계약대로 키스트로크가 된다", arguments: motionMappingFixtures)
    func mapsMotionAsContracted(_ fixture: MotionMappingFixture) {
        #expect(MotionKeyMapper.keyStrokes(for: fixture.motion) == fixture.expected, "\(fixture.motion)")
    }

    /// 매퍼의 switch가 컴파일러 강제로 전 케이스를 덮으므로, 여기서는 **픽스처 쪽**이
    /// 뒤처지지 않는지를 지킨다 — Motion에 케이스가 늘면 매퍼는 컴파일 에러로,
    /// 골든 표는 이 개수 단언으로 드러난다.
    @Test("매핑표가 Motion 전 케이스(14개)를 중복 없이 덮는다")
    func goldenTableCoversEveryMotion() {
        #expect(motionMappingFixtures.count == 14)
        #expect(Set(motionMappingFixtures.map(\.motion)).count == motionMappingFixtures.count)
    }

    /// 모션은 반드시 실행 가능한 형태로 매핑된다 — 빈 배열은 "조용히 아무것도 안 함"이라
    /// 미지원 스킵과 구분되지 않는다.
    @Test("어떤 모션도 빈 시퀀스로 매핑되지 않는다", arguments: motionMappingFixtures)
    func neverMapsToEmptySequence(_ fixture: MotionMappingFixture) {
        #expect(!MotionKeyMapper.keyStrokes(for: fixture.motion).isEmpty)
    }
}

//
//  EventTapDecisionTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import CoreGraphics
import Testing
import VimEngine
@testable import VimAction

/// 합성 keyDown 한 번의 입력 (virtualKey + flags).
struct KeyStroke: Sendable {
    var virtualKey: CGKeyCode
    var flags: CGEventFlags

    init(_ virtualKey: Int, _ flags: CGEventFlags = []) {
        self.virtualKey = CGKeyCode(virtualKey)
        self.flags = flags
    }
}

/// 키 시퀀스 → 마지막 키의 처리 결과(통과 여부)와 최종 모드 픽스처.
///
/// 엔진은 컨트롤러 내부라 상태를 직접 주입할 수 없다 — Normal 진입도 Esc 이벤트로
/// 유도한다. 검증은 반환값(nil/non-nil)과 `mode`까지만 한다: actions 내용은 엔진
/// 테스트의 몫이고, 여기 결합하면 엔진 출력 확장 때마다 앱 테스트가 함께 깨진다.
struct EventTapDecisionFixture: Sendable, CustomTestStringConvertible {
    var name: String
    var sequence: [KeyStroke]
    var lastKeyPassesThrough: Bool
    var finalMode: Mode

    init(_ name: String, _ sequence: [KeyStroke], passesThrough: Bool, finalMode: Mode) {
        self.name = name
        self.sequence = sequence
        self.lastKeyPassesThrough = passesThrough
        self.finalMode = finalMode
    }

    var testDescription: String { name }
}

/// 레이아웃과 무관하게 성립하는 케이스 — 특수키(keycode 매칭)만 사용한다.
let layoutInvariantDecisionFixtures: [EventTapDecisionFixture] = [
    .init(
        "Insert: Space 통과",
        [KeyStroke(kVK_Space)],
        passesThrough: true, finalMode: .insert
    ),
    .init(
        "Insert: Esc 삼킴 + Normal 전이",
        [KeyStroke(kVK_Escape)],
        passesThrough: false, finalMode: .normal
    ),
    .init(
        "Normal: Cmd+Space 통과 + Insert 복귀 (escape 콤보 기본 on)",
        [KeyStroke(kVK_Escape), KeyStroke(kVK_Space, [.maskCommand])],
        passesThrough: true, finalMode: .insert
    ),
]

/// 문자 키 케이스 — keycode↔문자 짝이 QWERTY 계열 레이아웃에서만 성립한다.
let qwertyDecisionFixtures: [EventTapDecisionFixture] = [
    .init(
        "Insert: 문자 j 통과",
        [KeyStroke(kVK_ANSI_J)],
        passesThrough: true, finalMode: .insert
    ),
    .init(
        "Normal: h 삼킴 (replace — 실행은 다음 마일스톤)",
        [KeyStroke(kVK_Escape), KeyStroke(kVK_ANSI_H)],
        passesThrough: false, finalMode: .normal
    ),
    .init(
        "Normal: i 삼킴 + Insert 전이",
        [KeyStroke(kVK_Escape), KeyStroke(kVK_ANSI_I)],
        passesThrough: false, finalMode: .insert
    ),
    .init(
        "Normal: 미매핑 q 삼킴",
        [KeyStroke(kVK_Escape), KeyStroke(kVK_ANSI_Q)],
        passesThrough: false, finalMode: .normal
    ),
]

@MainActor
struct EventTapDecisionTests {
    @Test("키 시퀀스 → 결정·모드 — 레이아웃 불변", arguments: layoutInvariantDecisionFixtures)
    func decideLayoutInvariant(_ fixture: EventTapDecisionFixture) throws {
        try assertDecision(fixture)
    }

    @Test(
        "키 시퀀스 → 결정·모드 — QWERTY 문자",
        .enabled("keycode↔문자 기대값이 QWERTY 계열 레이아웃에서만 성립한다") {
            await isQwertyLayout()
        },
        arguments: qwertyDecisionFixtures
    )
    func decideQwerty(_ fixture: EventTapDecisionFixture) throws {
        try assertDecision(fixture)
    }

    private func assertDecision(_ fixture: EventTapDecisionFixture) throws {
        // 탭 설치와 무관한 순수 메서드 경로 — startIfPermitted를 호출하지 않는다.
        // 임시 suite 주입: .standard는 실기기 사용으로 영속된 설정이 새어 든다.
        try withTemporaryDefaults { defaults in
            let controller = EventTapController(defaults: defaults)
            var lastResult: Unmanaged<CGEvent>?
            for stroke in fixture.sequence {
                let event = try #require(
                    CGEvent(keyboardEventSource: nil, virtualKey: stroke.virtualKey, keyDown: true),
                    "합성 CGEvent 생성 실패: \(fixture.name)"
                )
                event.flags = stroke.flags
                lastResult = controller.handleKeyDown(event)
            }
            #expect((lastResult != nil) == fixture.lastKeyPassesThrough, "\(fixture.name)")
            #expect(controller.mode == fixture.finalMode, "\(fixture.name)")
        }
    }
}

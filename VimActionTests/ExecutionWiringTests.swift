//
//  ExecutionWiringTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import Foundation
import Testing
import VimEngine
@testable import VimAction

/// 앱 게이트와 실행 배선 — 탭 콜백이 무엇을 통과시키고 무엇을 실행 큐로 넘기는가.
///
/// 실행 sink를 가로채는 것이 핵심이다: 프로덕션 기본 sink는 XCTest 하위에서 no-op이지만
/// (그냥 두면 테스트가 개발자 머신에 실제 화살표 키를 주입한다), 배선을 **관측**하려면
/// 자체 sink가 필요하다. 게이트도 격리된 `NotificationCenter`로 주입해 실제 최전면 앱이
/// 판정에 새어 들지 않게 한다.
@MainActor
struct ExecutionWiringTests {
    private static func gate(frontmost: String?) -> FrontmostAppGate {
        FrontmostAppGate(notificationCenter: NotificationCenter(), frontmostBundleID: frontmost)
    }

    /// 게이트가 걸린 앱에서는 VimAction이 존재하지 않는 것처럼 동작한다 — Esc조차 통과하고
    /// 엔진은 키를 보지 못하므로 모드가 **동결**된다. 그리고 그 앱에서 나오면 그대로 재개된다
    /// (앱별 모드 기억은 M4 이후 주제라, 여기서는 "이전 상태 그대로"가 계약이다).
    @Test("게이트 중에는 통과 + 모드 동결, 해제되면 재개")
    func gatedInputPassesThroughAndFreezesMode() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var dispatched: [[VimAction]] = []
            let gate = Self.gate(frontmost: "com.mitchellh.ghostty")
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: gate,
                dispatchActions: { dispatched.append($0) })

            // `#expect`에 코멘트를 붙이면 매크로 확장 안의 `try`가 처리되지 않아, 이벤트
            // 생성은 항상 문장으로 뺀다.
            let gatedEscape = try keyDown(kVK_Escape)
            #expect(controller.handleKeyDown(gatedEscape) != nil, "게이트 중 Esc는 통과")
            #expect(controller.mode == .insert, "엔진이 키를 보지 않으므로 모드 동결")
            #expect(dispatched.isEmpty)

            gate.update(bundleID: "com.apple.TextEdit")

            let escape = try keyDown(kVK_Escape)
            #expect(controller.handleKeyDown(escape) == nil, "해제 후 Esc는 삼킴")
            #expect(controller.mode == .normal)
        }
    }

    /// `.replace`의 배선 — 콜백은 원본을 삼키고(nil) actions를 실행 sink로 넘긴다.
    /// 여기서 검증하는 것은 "무엇이 넘어가는가"까지다: CGEvent 변환은 어댑터 테스트,
    /// 큐 홉 자체는 실기기 GREEN의 몫이다.
    @Test(
        "Normal 모션은 삼킨 뒤 actions를 실행 sink로 넘긴다",
        .enabled("keycode↔문자 기대값이 QWERTY 계열 레이아웃에서만 성립한다") {
            await isQwertyLayout()
        }
    )
    func replaceDispatchesActions() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var dispatched: [[VimAction]] = []
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: Self.gate(frontmost: "com.apple.TextEdit"),
                dispatchActions: { dispatched.append($0) })
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입

            let motionKey = try keyDown(kVK_ANSI_H)
            #expect(controller.handleKeyDown(motionKey) == nil, "원본 h는 삼킴")

            #expect(dispatched == [[.move(.charLeft)]])
        }
    }

    /// 게이트가 걸린 앱에서는 모션 키도 실행되지 않는다 — 삼킨 뒤 실행만 막는 "죽은 키"가
    /// 아니라, 애초에 엔진에 닿지 않아 원본 h가 그대로 앱에 전달된다.
    @Test(
        "게이트 중 모션 키는 원본이 통과하고 sink는 조용하다",
        .enabled("keycode↔문자 기대값이 QWERTY 계열 레이아웃에서만 성립한다") {
            await isQwertyLayout()
        }
    )
    func gatedMotionKeyIsNotDispatched() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var dispatched: [[VimAction]] = []
            let gate = Self.gate(frontmost: "com.apple.TextEdit")
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: gate,
                dispatchActions: { dispatched.append($0) })
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입
            gate.update(bundleID: "com.mitchellh.ghostty")

            #expect(controller.handleKeyDown(try keyDown(kVK_ANSI_H)) != nil)
            #expect(dispatched.isEmpty)
        }
    }

    /// 통과(Insert 타이핑)·삼킴(모드 전환)에는 실행할 것이 없다 — sink가 불리면 빈 시퀀스
    /// 게시가 매 키 입력마다 큐를 왕복한다.
    @Test("passthrough·swallow는 실행 sink를 부르지 않는다")
    func nonReplaceDecisionsDoNotDispatch() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var dispatched: [[VimAction]] = []
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: Self.gate(frontmost: "com.apple.TextEdit"),
                dispatchActions: { dispatched.append($0) })

            let space = try keyDown(kVK_Space)
            let escape = try keyDown(kVK_Escape)
            #expect(controller.handleKeyDown(space) != nil, "Insert 타이핑은 통과")
            #expect(controller.handleKeyDown(escape) == nil, "Esc는 삼킴")

            #expect(dispatched.isEmpty)
        }
    }

    /// 마스터 토글 off는 번역 전에 전부 통과한다 — 실행 경로가 붙은 뒤에도 off가 실제로
    /// 출력까지 끊는지 고정한다 (off가 통과만 하고 실행이 남으면 최악의 조합이다).
    @Test("토글 off 중에는 실행 sink를 부르지 않는다")
    func disabledInterceptionDoesNotDispatch() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var dispatched: [[VimAction]] = []
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: Self.gate(frontmost: "com.apple.TextEdit"),
                dispatchActions: { dispatched.append($0) })
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입
            controller.isInterceptionEnabled = false

            #expect(controller.handleKeyDown(try keyDown(kVK_Escape)) != nil)
            #expect(dispatched.isEmpty)
        }
    }
}

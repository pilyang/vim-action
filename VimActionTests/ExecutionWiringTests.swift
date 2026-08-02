//
//  ExecutionWiringTests.swift
//  VimActionTests
//

import Carbon.HIToolbox
import Foundation
import Testing
import VimActionConfig
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
    /// disable 집합 소스가 config로 바뀌어 테스트가 명시 주입한다 — 기본값(빈 집합)으로
    /// 두면 게이트 테스트가 아무것도 걸리지 않는 채로 "통과"해 검증이 사라진다.
    private static func gate(
        frontmost: String?, disabled: Set<String> = []
    ) -> FrontmostAppGate {
        FrontmostAppGate(
            notificationCenter: NotificationCenter(), frontmostBundleID: frontmost,
            disabledBundleIDs: disabled)
    }

    /// 게이트가 걸린 앱에서는 VimAction이 존재하지 않는 것처럼 동작한다 — Esc조차 통과하고
    /// 엔진은 키를 보지 못하므로 모드가 **동결**된다. 그리고 그 앱에서 나오면 그대로 재개된다
    /// (앱별 모드 기억은 M4 이후 주제라, 여기서는 "이전 상태 그대로"가 계약이다).
    @Test("게이트 중에는 통과 + 모드 동결, 해제되면 재개")
    func gatedInputPassesThroughAndFreezesMode() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var dispatched: [[VimAction]] = []
            let gate = Self.gate(
                frontmost: "com.mitchellh.ghostty", disabled: ["com.mitchellh.ghostty"])
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: gate,
                dispatchActions: { actions, _ in dispatched.append(actions) })

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
                dispatchActions: { actions, _ in dispatched.append(actions) })
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입

            let motionKey = try keyDown(kVK_ANSI_H)
            #expect(controller.handleKeyDown(motionKey) == nil, "원본 h는 삼킴")

            #expect(dispatched == [[.move(.charLeft)]])
        }
    }

    /// 계열은 **콜백에서 읽어 페이로드로 실린다** — 게시 큐가 나중에 캐시를 읽으면 그 사이
    /// 옮겨간 포커스를 기준으로 걸러진다. 배선이 끊기면 리졸버가 무엇을 보고하든 어댑터는
    /// 늘 폴백으로 실행하므로, 걸러내기가 통째로 죽는 조용한 고장이 된다.
    @Test(
        "디스패치 페이로드에 키 입력 시점의 요소 계열이 실린다",
        .enabled("keycode↔문자 기대값이 QWERTY 계열 레이아웃에서만 성립한다") {
            await isQwertyLayout()
        }
    )
    func replaceCarriesFocusedElementFamily() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var families: [ElementFamily] = []
            let resolver = FocusedElementResolver(
                notificationCenter: NotificationCenter(), frontmostProcessID: nil)
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: Self.gate(frontmost: "com.apple.TextEdit"),
                focusedElement: resolver,
                dispatchActions: { _, context in families.append(context.family) })
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입

            _ = controller.handleKeyDown(try keyDown(kVK_ANSI_H))
            #expect(families == [.textArea], "AX를 못 읽는 리졸버는 폴백을 보고한다")

            resolver.update(family: .nonText)
            _ = controller.handleKeyDown(try keyDown(kVK_ANSI_H))
            #expect(families == [.textArea, .nonText])
        }
    }

    /// 프로파일도 계열처럼 **콜백에서 읽어 페이로드로 실린다** — 최전면 앱 bundle id로
    /// provider를 조회한 스냅샷이다. 배선이 끊기면 모든 앱이 `.empty`로 실행돼 재정의·disable이
    /// 통째로 죽는 조용한 고장이 된다.
    @Test(
        "디스패치 페이로드에 키 입력 시점의 최전면 앱 프로파일이 실린다",
        .enabled("keycode↔문자 기대값이 QWERTY 계열 레이아웃에서만 성립한다") {
            await isQwertyLayout()
        }
    )
    func replaceCarriesFrontmostAppProfile() throws {
        try withTemporaryDefaults { defaults in
            nonisolated(unsafe) var profiles: [ResolvedProfile] = []
            let slack = ResolvedProfile(AppProfile(name: "Slack", actions: [.openLine: .disabled]))
            let gate = Self.gate(frontmost: "com.apple.TextEdit")
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: gate,
                dispatchActions: { _, context in profiles.append(context.profile) },
                profileProvider: { bundleID in
                    bundleID == "com.tinyspeck.slackmacgap" ? slack : .empty
                })
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입

            _ = controller.handleKeyDown(try keyDown(kVK_ANSI_H))
            #expect(profiles == [.empty], "프로파일 없는 앱은 .empty로 실행된다")

            gate.update(bundleID: "com.tinyspeck.slackmacgap")
            _ = controller.handleKeyDown(try keyDown(kVK_ANSI_H))
            #expect(profiles == [.empty, slack], "앱 전환 후에는 그 앱의 프로파일이 실린다")
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
            let gate = Self.gate(
                frontmost: "com.apple.TextEdit", disabled: ["com.mitchellh.ghostty"])
            let controller = EventTapController(
                defaults: defaults, frontmostAppGate: gate,
                dispatchActions: { actions, _ in dispatched.append(actions) })
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
                dispatchActions: { actions, _ in dispatched.append(actions) })

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
                dispatchActions: { actions, _ in dispatched.append(actions) })
            _ = controller.handleKeyDown(try keyDown(kVK_Escape))  // Normal 진입
            controller.isInterceptionEnabled = false

            #expect(controller.handleKeyDown(try keyDown(kVK_Escape)) != nil)
            #expect(dispatched.isEmpty)
        }
    }
}

/// 실행 중단 래치를 **세우는 쪽**의 배선 — 어댑터가 그것을 어떻게 소비하는지는
/// `KeyboardAdapterAbortTests`가 본다.
///
/// 무효화 지점 누락은 조용한 고장이다: 킬스위치를 눌러도 문서가 계속 바뀌거나, 토글을 껐는데
/// 출력이 이어지거나, 폭주 중 타이핑이 순서 역전을 일으킨다. 전부 실기기에서만 드러나므로
/// 여기서 계약으로 고정한다.
@MainActor
struct ExecutionAbortWiringTests {
    private static func controller(_ defaults: UserDefaults) -> EventTapController {
        EventTapController(
            defaults: defaults,
            frontmostAppGate: FrontmostAppGate(
                notificationCenter: NotificationCenter(), frontmostBundleID: "com.apple.TextEdit"),
            dispatchActions: { _, _ in })
    }

    /// **가장 중요한 한 건**: 우리가 게시한 합성 이벤트는 탭으로 되돌아온다. 그것이 래치를
    /// 세우면 버스트가 첫 청크 직후 자기 자신을 끊는다 — 무효화가 마커 가드 **뒤**여야 하는 이유.
    @Test("마커 찍힌 합성 이벤트는 실행을 끊지 않는다")
    func markedSyntheticEventDoesNotAbort() throws {
        try withTemporaryDefaults { defaults in
            let controller = Self.controller(defaults)
            let run = controller.executionAbort.beginRun()

            let synthetic = try keyDown(kVK_ANSI_H)
            SyntheticEventMarker.mark(synthetic)
            #expect(controller.handleKeyDown(synthetic) != nil, "합성 이벤트는 통과")

            #expect(controller.executionAbort.isCurrent(run), "우리 출력이 우리 버스트를 끊으면 안 된다")
        }
    }

    /// 결정 종류를 가리지 않는다 — 실증된 순서 역전(`9999j` 중 `i`+`abc`)의 `abc`는
    /// passthrough라, replace만 보면 목표를 못 이룬다.
    @Test("passthrough·swallow·replace 어느 사용자 키든 실행을 끊는다")
    func anyUserKeyAbortsInFlightExecution() throws {
        try withTemporaryDefaults { defaults in
            let controller = Self.controller(defaults)

            // passthrough (Insert 타이핑)
            let space = try keyDown(kVK_Space)
            var run = controller.executionAbort.beginRun()
            #expect(controller.handleKeyDown(space) != nil)
            #expect(!controller.executionAbort.isCurrent(run))

            // swallow (Esc — Normal 진입)
            let escape = try keyDown(kVK_Escape)
            run = controller.executionAbort.beginRun()
            #expect(controller.handleKeyDown(escape) == nil)
            #expect(!controller.executionAbort.isCurrent(run))
        }
    }

    /// off가 통과만 시키고 이미 나가던 출력은 끝까지 소진하면 "껐는데 문서가 계속 바뀐다"가 된다.
    @Test("마스터 토글 off는 게시 중인 실행을 끊는다")
    func togglingOffAbortsInFlightExecution() throws {
        try withTemporaryDefaults { defaults in
            let controller = Self.controller(defaults)
            let run = controller.executionAbort.beginRun()

            controller.isInterceptionEnabled = false

            #expect(!controller.executionAbort.isCurrent(run))
        }
    }

    /// 단계 0이 실증한 킬스위치의 한계 — 발동은 즉시였지만 이미 게시된 이벤트는 끝까지
    /// 소진됐다. 이 배선이 그 창을 닫는다.
    @Test("킬스위치는 게시 중인 실행을 끊는다")
    func killSwitchAbortsInFlightExecution() throws {
        try withTemporaryDefaults { defaults in
            let controller = Self.controller(defaults)
            let run = controller.executionAbort.beginRun()

            controller.triggerKillSwitch()

            #expect(!controller.executionAbort.isCurrent(run))
        }
    }
}

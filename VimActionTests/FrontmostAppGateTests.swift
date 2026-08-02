//
//  FrontmostAppGateTests.swift
//  VimActionTests
//

import Foundation
import Testing
@testable import VimAction

/// 판정 소스는 이제 `config.yaml`의 `apps` 맵이다 — 테스트는 집합을 직접 주입한다.
private let ghosttyOnly: Set<String> = ["com.mitchellh.ghostty"]

/// 격리된 `NotificationCenter`를 주입해 라이브 `NSWorkspace` 구독을 피한다 — 실제 최전면
/// 앱(= 테스트를 돌린 터미널)이 판정에 새어 들면 머신 상태 의존 실패가 된다.
@MainActor
private func makeGate(frontmost: String?, disabled: Set<String> = ghosttyOnly) -> FrontmostAppGate {
    FrontmostAppGate(
        notificationCenter: NotificationCenter(), frontmostBundleID: frontmost,
        disabledBundleIDs: disabled)
}

@MainActor
struct FrontmostAppGateTests {
    @Test("disable 목록의 앱만 게이트에 걸린다")
    func onlyDisabledBundleIDsMatch() {
        #expect(FrontmostAppGate.isDisabled("com.mitchellh.ghostty", disabledBundleIDs: ghosttyOnly))
        #expect(!FrontmostAppGate.isDisabled("com.apple.TextEdit", disabledBundleIDs: ghosttyOnly))
        // 부분 일치로 번지지 않는다 — 정확 일치만.
        #expect(
            !FrontmostAppGate.isDisabled(
                "com.mitchellh.ghostty.helper", disabledBundleIDs: ghosttyOnly))
    }

    /// 최전면 앱 미확인은 **통과**다 — 게이트는 확실히 disable 앱일 때만 개입한다.
    /// (실패 시 최전면을 못 읽는 순간 가로채기가 조용히 죽는다.)
    @Test("bundleID 없음은 게이트에 걸리지 않는다")
    func unknownFrontmostAppPassesThrough() {
        #expect(!FrontmostAppGate.isDisabled(nil, disabledBundleIDs: ghosttyOnly))
        #expect(!makeGate(frontmost: nil).isFrontmostAppDisabled)
    }

    /// 설정 로드 전(기본값)의 게이트는 비어 있다 — 아무 앱도 걸리지 않는다.
    @Test("disable 집합 기본값(빈 집합)은 모든 앱을 통과시킨다")
    func emptyDefaultSetPassesEverything() {
        #expect(!makeGate(frontmost: "com.mitchellh.ghostty", disabled: []).isFrontmostAppDisabled)
    }

    /// 시드가 필요한 이유: LSUIElement 앱이라 실행이 최전면을 바꾸지 않는다 — disable 앱이
    /// 최전면인 채로 앱을 켜면 다음 앱 전환까지 알림이 오지 않는다.
    @Test("init 시드가 판정에 즉시 반영된다")
    func seedAppliesImmediately() {
        #expect(makeGate(frontmost: "com.mitchellh.ghostty").isFrontmostAppDisabled)
        #expect(!makeGate(frontmost: "com.apple.TextEdit").isFrontmostAppDisabled)
    }

    @Test("update가 게이트를 양방향으로 전환한다")
    func updateFlipsGateBothWays() {
        let gate = makeGate(frontmost: "com.apple.TextEdit")

        gate.update(bundleID: "com.mitchellh.ghostty")
        #expect(gate.frontmostBundleID == "com.mitchellh.ghostty")
        #expect(gate.isFrontmostAppDisabled)

        gate.update(bundleID: "com.apple.TextEdit")
        #expect(!gate.isFrontmostAppDisabled)
    }

    /// 리로드 경로 — 최전면 앱이 그대로인 채 disable 집합만 바뀌어도 게이트가 즉시 뒤집힌다.
    /// (config.yaml 편집 → Reload Config가 앱 전환 없이 반영되는 계약.)
    @Test("disable 집합 갱신이 앱 전환 없이 게이트를 뒤집는다")
    func updatingDisabledSetFlipsGateInPlace() {
        let gate = makeGate(frontmost: "com.apple.TextEdit", disabled: [])
        #expect(!gate.isFrontmostAppDisabled)

        gate.update(disabledBundleIDs: ["com.apple.TextEdit"])
        #expect(gate.isFrontmostAppDisabled)

        gate.update(disabledBundleIDs: [])
        #expect(!gate.isFrontmostAppDisabled)
    }
}

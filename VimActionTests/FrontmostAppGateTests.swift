//
//  FrontmostAppGateTests.swift
//  VimActionTests
//

import Foundation
import Testing
@testable import VimAction

/// 판정 소스는 이제 `config.yaml`의 `apps` 맵이다 — 테스트는 집합을 직접 주입한다.
private let ghosttyOnly: Set<String> = ["com.mitchellh.ghostty"]

/// 자기 자신 — `Bundle.main`을 쓰지 않고 주입한다(TEST_HOST가 앱 프로세스라 머신 의존이 된다).
private let selfID = "dev.pilyang.VimAction"

/// 격리된 `NotificationCenter`를 주입해 라이브 `NSWorkspace` 구독을 피한다 — 실제 최전면
/// 앱(= 테스트를 돌린 터미널)이 판정에 새어 들면 머신 상태 의존 실패가 된다.
@MainActor
private func makeGate(frontmost: String?, disabled: Set<String> = ghosttyOnly) -> FrontmostAppGate {
    FrontmostAppGate(
        notificationCenter: NotificationCenter(), frontmostBundleID: frontmost,
        disabledBundleIDs: disabled, selfBundleID: selfID)
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

/// 메뉴바 편의 기능이 겨누는 "마지막 비자신 앱" 캐시. 메뉴를 여는 행위 자체가 VimAction을
/// 최전면으로 만들 수 있어, 최전면 캐시로는 대상 앱을 가리킬 수 없다.
@MainActor
struct FrontmostAppNonSelfCacheTests {
    @Test("nil과 자기 자신은 직전 값을 유지하고, 다른 앱만 캐시를 바꾼다")
    func nonSelfDerivation() {
        let derive = FrontmostAppGate.nonSelfBundleID
        #expect(derive("com.apple.TextEdit", selfID, "com.slack.old") == "com.apple.TextEdit")
        // "지금은 알 수 없다"이지 "대상이 없어졌다"가 아니다 — 지우면 메뉴가 대상을 잃는다.
        #expect(derive(nil, selfID, "com.slack.old") == "com.slack.old")
        #expect(derive(selfID, selfID, "com.slack.old") == "com.slack.old")
        #expect(derive(selfID, selfID, nil) == nil)
        // selfBundleID를 못 읽는 환경에서는 걸러낼 자신이 없으니 전부 대상이다.
        #expect(derive(selfID, nil, nil) == selfID)
    }

    /// 이 PR의 핵심 회귀 가드 — 메뉴 클릭·리로드 실패 알림의 `NSApp.activate`가
    /// 대상 앱 정보를 지워 버리는 것을 막는다.
    @Test("자기 자신의 활성화는 비자신 캐시를 덮지 않는다")
    func selfActivationKeepsTarget() {
        let gate = makeGate(frontmost: "com.apple.TextEdit")

        gate.update(bundleID: selfID)
        #expect(gate.frontmostBundleID == selfID, "최전면 캐시는 사실대로 자기 자신이다")
        #expect(gate.lastNonSelfBundleID == "com.apple.TextEdit")

        gate.update(bundleID: "com.apple.TextEdit")
        #expect(gate.lastNonSelfBundleID == "com.apple.TextEdit")
    }

    @Test("최전면 미확인(nil)은 비자신 캐시를 지우지 않는다")
    func unknownFrontmostKeepsTarget() {
        let gate = makeGate(frontmost: "com.apple.TextEdit")

        gate.update(bundleID: nil)
        #expect(gate.lastNonSelfBundleID == "com.apple.TextEdit")
    }

    @Test("init 시드가 비자신 캐시에 반영된다 — 자기 자신 시드는 비어 있다")
    func seedFillsCache() {
        #expect(makeGate(frontmost: "com.apple.TextEdit").lastNonSelfBundleID == "com.apple.TextEdit")
        #expect(makeGate(frontmost: selfID).lastNonSelfBundleID == nil)
        #expect(makeGate(frontmost: nil).lastNonSelfBundleID == nil)
    }

    /// `update`의 동등성 early-return 뒤에서 캐시를 갱신해도 되는 근거(파생이 멱등)를
    /// 못 박는다 — 가드 앞으로 옮기고 싶어지는 지점이다.
    @Test("같은 값 재통지가 캐시를 어긋내지 않는다")
    func repeatedNotificationsAreIdempotent() {
        let gate = makeGate(frontmost: "com.apple.TextEdit")

        gate.update(bundleID: selfID)
        gate.update(bundleID: selfID)
        #expect(gate.lastNonSelfBundleID == "com.apple.TextEdit")

        gate.update(bundleID: "com.apple.Safari")
        gate.update(bundleID: "com.apple.Safari")
        #expect(gate.lastNonSelfBundleID == "com.apple.Safari")
    }

    /// 캐시는 메뉴 전용이다 — 판정에 새어 들면 다른 앱으로 갔는데 disable이 따라온다.
    @Test("비자신 캐시는 게이트 판정에 쓰이지 않는다")
    func cacheDoesNotLeakIntoGate() {
        let gate = makeGate(frontmost: "com.mitchellh.ghostty")
        #expect(gate.isFrontmostAppDisabled)

        gate.update(bundleID: selfID)
        #expect(gate.lastNonSelfBundleID == "com.mitchellh.ghostty")
        #expect(!gate.isFrontmostAppDisabled, "판정은 최전면(자기 자신)만 본다")
    }
}

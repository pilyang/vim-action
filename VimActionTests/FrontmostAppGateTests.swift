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
/// 앱(= 테스트를 돌린 터미널)이 판정에 새어 들면 머신 상태 의존 실패가 된다. 시드 기본값은
/// inert(nil)라 pid를 생략해도 머신 상태를 읽지 않는다 — 여기서는 단언에 쓸 값을 넣는다.
@MainActor
private func makeGate(
    frontmost: String?, frontmostPID: pid_t? = nil, disabled: Set<String> = ghosttyOnly
) -> FrontmostAppGate {
    FrontmostAppGate(
        notificationCenter: NotificationCenter(), frontmostBundleID: frontmost,
        frontmostProcessID: frontmostPID, disabledBundleIDs: disabled, selfBundleID: selfID)
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
    @Test("nil과 자기 자신은 직전 짝을 유지하고, 다른 앱만 캐시를 바꾼다")
    func nonSelfDerivation() {
        func derive(
            _ bundleID: String?, _ processID: pid_t?, _ selfBundleID: String?,
            _ previous: (bundleID: String?, processID: pid_t?)
        ) -> (bundleID: String?, processID: pid_t?) {
            FrontmostAppGate.nonSelfTarget(
                bundleID: bundleID, processID: processID, selfBundleID: selfBundleID,
                previous: previous)
        }
        let old: (bundleID: String?, processID: pid_t?) = ("com.slack.old", 100)
        #expect(derive("com.apple.TextEdit", 7, selfID, old) == ("com.apple.TextEdit", 7))
        // "지금은 알 수 없다"이지 "대상이 없어졌다"가 아니다 — 지우면 메뉴가 대상을 잃는다.
        #expect(derive(nil, nil, selfID, old) == old)
        #expect(derive(selfID, 55, selfID, old) == old)
        #expect(derive(selfID, 55, selfID, (nil, nil)) == (nil, nil))
        // selfBundleID를 못 읽는 환경에서는 걸러낼 자신이 없으니 전부 대상이다.
        #expect(derive(selfID, 55, nil, (nil, nil)) == (selfID, 55))
        // 같은 번들의 재실행 — 번들은 그대로여도 pid는 새 값으로 갈린다 (짝 갱신의 존재 이유).
        #expect(derive("com.slack.old", 200, selfID, old) == ("com.slack.old", 200))
    }

    /// 이 PR의 핵심 회귀 가드 — 메뉴 클릭·리로드 실패 알림의 `NSApp.activate`가
    /// 대상 앱 정보를 지워 버리는 것을 막는다. pid도 같은 짝으로 유지된다 — 메뉴의
    /// "Strategy:" 줄이 이 pid로 판정을 조회한다.
    @Test("자기 자신의 활성화는 비자신 캐시를 덮지 않는다")
    func selfActivationKeepsTarget() {
        let gate = makeGate(frontmost: "com.apple.TextEdit")
        gate.update(bundleID: "com.apple.TextEdit", processID: 7)

        gate.update(bundleID: selfID, processID: 99)
        #expect(gate.frontmostBundleID == selfID, "최전면 캐시는 사실대로 자기 자신이다")
        #expect(gate.lastNonSelfBundleID == "com.apple.TextEdit")
        #expect(gate.lastNonSelfProcessID == 7, "자기 pid가 판정 조회 키를 덮으면 오표시다")

        gate.update(bundleID: "com.apple.TextEdit", processID: 7)
        #expect(gate.lastNonSelfBundleID == "com.apple.TextEdit")
        #expect(gate.lastNonSelfProcessID == 7)
    }

    /// 같은 번들 ID의 재실행(새 pid)은 최전면 캐시 기준 무변화라 dedupe 가드에 걸린다 —
    /// 짝 갱신이 가드 **앞**인 이유. 함께 걸러지면 메뉴 판정 조회가 죽은 pid로 남는다.
    @Test("같은 번들의 새 pid가 비자신 짝을 갱신한다")
    func sameBundleNewProcessIDUpdatesPair() {
        let gate = makeGate(frontmost: nil)
        gate.update(bundleID: "com.apple.TextEdit", processID: 7)
        #expect(gate.lastNonSelfProcessID == 7)

        gate.update(bundleID: "com.apple.TextEdit", processID: 8)
        #expect(gate.lastNonSelfProcessID == 8, "재실행된 앱의 pid가 반영돼야 한다")
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

    /// 시드도 짝이다 — pid를 주입하지 않은 시드가 실제 최전면 앱의 pid로 채워지면
    /// "주입한 번들 + 터미널 pid"라는 머신 의존 어긋난 짝이 된다 (파일 헤더가 금지한 부류).
    @Test("시드 짝 — 주입한 pid만 실리고, 미주입은 비어 있다")
    func seedPairsBundleWithInjectedPID() {
        let seeded = makeGate(frontmost: "com.apple.TextEdit", frontmostPID: 7)
        #expect(seeded.lastNonSelfBundleID == "com.apple.TextEdit")
        #expect(seeded.lastNonSelfProcessID == 7)

        #expect(
            makeGate(frontmost: "com.apple.TextEdit").lastNonSelfProcessID == nil,
            "pid 미주입 시드가 머신의 최전면 pid를 읽으면 안 된다")
        #expect(makeGate(frontmost: selfID, frontmostPID: 55).lastNonSelfProcessID == nil)
    }

    /// 짝 갱신이 dedupe 가드 **앞**에 있어도 재통지가 캐시를 어긋내지 않는다 — 파생이
    /// 멱등이고 동등성 검사가 재대입(@Observable 발화 포함)을 걸러낸다.
    @Test("같은 값 재통지가 캐시를 어긋내지 않는다")
    func repeatedNotificationsAreIdempotent() {
        let gate = makeGate(frontmost: "com.apple.TextEdit")

        gate.update(bundleID: selfID)
        gate.update(bundleID: selfID)
        #expect(gate.lastNonSelfBundleID == "com.apple.TextEdit")

        gate.update(bundleID: "com.apple.Safari", processID: 9)
        gate.update(bundleID: "com.apple.Safari", processID: 9)
        #expect(gate.lastNonSelfBundleID == "com.apple.Safari")
        #expect(gate.lastNonSelfProcessID == 9)
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

    /// 표시 축과 판정 축이 **동시에 갈리는** 자리를 못 박는다 — 메뉴바 아이콘을 클릭해
    /// VimAction이 최전면이 된 순간이 그 자리다. 표시가 판정 축을 보면 이때
    /// 인디케이터가 사라져 메뉴의 'Disable for This App' 체크마크와 어긋난다.
    @Test("자기 자신이 최전면이어도 표시 축은 대상 앱의 disable을 유지한다")
    func targetAxisHoldsWhileGateAxisReleases() {
        let gate = makeGate(frontmost: "com.mitchellh.ghostty")
        #expect(gate.isTargetAppDisabled)

        gate.update(bundleID: selfID)
        #expect(gate.isTargetAppDisabled, "표시는 비자신 캐시(=대상 앱)를 본다")
        #expect(!gate.isFrontmostAppDisabled, "판정은 최전면(자기 자신)을 본다")

        // 진짜로 다른 앱에 가면 둘 다 풀린다.
        gate.update(bundleID: "com.apple.TextEdit")
        #expect(!gate.isTargetAppDisabled)
        #expect(!gate.isFrontmostAppDisabled)
    }

    /// 대상 앱을 모르면 표시하지 않는다 — 순수 판정의 nil 통과 규칙이 표시 축에도 그대로다.
    @Test("대상 앱 미확인은 표시 축에도 걸리지 않는다")
    func unknownTargetIsNotDisabled() {
        #expect(!makeGate(frontmost: nil).isTargetAppDisabled)
        #expect(!makeGate(frontmost: selfID).isTargetAppDisabled)
    }
}

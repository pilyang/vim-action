//
//  AXWriteOutcomeTests.swift
//  VimActionTests
//

import ApplicationServices
import Foundation
import Testing

@testable import VimAction

// MARK: - 분류표

/// `AXError` 분류표 한 행. **이 표가 곧 계약이다** — 분류가 바뀌면 여기가 먼저 바뀐다.
/// `AXError`는 `CustomStringConvertible`이 아니라(raw는 `-25204` 같은 정수) 이름을 손으로 싣는다.
struct AXWriteOutcomeFixture: Sendable, CustomTestStringConvertible {
    var name: String
    var error: AXError
    var expected: AXWriteOutcome

    var testDescription: String { name }
}

/// **`AXError` 전 16케이스.** SDK `AXError.h` 기준 — `kAXErrorSuccess`(0) + `-25200`~`-25214`.
/// 전수성 자체가 이 표의 요점이다: 새 코드가 조용히 "보고"로 흘러들지 않게 하는 것이
/// default-deny 화이트리스트의 존재 이유이므로, 표에서 빠진 코드가 있으면 그 보장이 깨진다.
private let axWriteOutcomeFixtures: [AXWriteOutcomeFixture] = [
    .init(name: "success", error: .success, expected: .success),

    // 유일한 보고 케이스. 헤더상 "시스템 오류"라 정상 사용에서 도달 불가하다.
    .init(name: "failure", error: .failure, expected: .failure),

    // 관측 전용 — 사전 경계 검증을 통과한 뒤의 거부라 오프셋 공간 불일치 신호다.
    .init(name: "illegalArgument", error: .illegalArgument, expected: .illegalArgument),

    // 미지원 스킵 — 앱의 정적 성질("미지원 ≠ 실패").
    .init(name: "attributeUnsupported", error: .attributeUnsupported, expected: .unsupportedSkip),
    .init(name: "notImplemented", error: .notImplemented, expected: .unsupportedSkip),
    .init(
        name: "parameterizedAttributeUnsupported", error: .parameterizedAttributeUnsupported,
        expected: .unsupportedSkip),
    .init(name: "noValue", error: .noValue, expected: .unsupportedSkip),

    // 경합 스킵 — `.cannotComplete`는 "성공 + 응답 유실"과 구분 불가라 보고로 올리지 않는다.
    .init(name: "invalidUIElement", error: .invalidUIElement, expected: .contentionSkip),
    .init(name: "cannotComplete", error: .cannotComplete, expected: .contentionSkip),

    // 권한 회수 — 복구는 `AccessibilityPermissionMonitor`(1초 폴링) 전담.
    .init(name: "apiDisabled", error: .apiDisabled, expected: .apiDisabled),

    // 쓰기 호출에서 도달 불가한 알려진 코드 — 미보고 스킵 + error 로그(미지 코드와 같은 클래스).
    .init(name: "actionUnsupported", error: .actionUnsupported, expected: .unexpected),
    .init(name: "notEnoughPrecision", error: .notEnoughPrecision, expected: .unexpected),
    .init(
        name: "invalidUIElementObserver", error: .invalidUIElementObserver, expected: .unexpected),
    .init(name: "notificationUnsupported", error: .notificationUnsupported, expected: .unexpected),
    .init(
        name: "notificationAlreadyRegistered", error: .notificationAlreadyRegistered,
        expected: .unexpected),
    .init(
        name: "notificationNotRegistered", error: .notificationNotRegistered, expected: .unexpected),
]

/// AX 쓰기 결과 분류의 계약 — **default-deny 화이트리스트**
/// (`20260808_ax-write-failure-whitelist-no-fallback.md`)를 전수 스윕으로 고정한다.
/// `AXWriterTests`가 "코드가 통로에서 접히지 않고 도착한다"를 고정하고, 여기서 그 도착한
/// 코드가 어느 소비자 행동으로 가는지가 닫힌다.
struct AXWriteOutcomeClassificationTests {
    /// 표가 손으로 유지되는 대가를 여기서 치른다 — `AXError`는 `CaseIterable`이 아니라
    /// `Set(T.allCases)` 비교(`MotionKeyMapperTests` 관례)를 쓸 수 없다.
    @Test("표가 AXError 16케이스를 중복 없이 덮는다")
    func tableCoversEveryKnownErrorCode() {
        #expect(axWriteOutcomeFixtures.count == 16)
        #expect(Set(axWriteOutcomeFixtures.map(\.error)).count == 16, "중복 행")
    }

    /// 반대 방향의 전수성 — 선언만 되고 어느 코드도 도달하지 못하는 의미 클래스가 없다.
    /// (있다면 소비자가 죽은 분기를 들고 있다는 뜻이다.)
    @Test("의미 클래스 전부가 표에서 도달된다")
    func everyOutcomeClassIsReachable() {
        #expect(Set(axWriteOutcomeFixtures.map(\.expected)) == Set(AXWriteOutcome.allCases))
    }

    /// **화이트리스트의 폭을 직접 고정한다.** D1 구간의 보고는 `.failure` 하나뿐이며, 표의 다른
    /// 행이 보고로 옮겨오면 여기서 걸린다 — 조용한 보고 확대가 이 결정이 막으려는 것 자체다.
    @Test("실패 보고로 분류되는 코드는 정확히 하나다")
    func exactlyOneCodeIsReported() {
        let reported = axWriteOutcomeFixtures.filter { $0.expected == .failure }
        #expect(reported.count == 1)
        #expect(reported.first?.error == .failure)
    }

    @Test("분류표대로 접는다", arguments: axWriteOutcomeFixtures)
    func classifyFollowsTheTable(_ fixture: AXWriteOutcomeFixture) {
        #expect(AXWriteOutcome.classify(fixture.error) == fixture.expected, "\(fixture.name)")
    }
}

// MARK: - 사전 경계 검증

/// 쓰기 전 우리 쪽 경계 검증의 계약 — **감지 가능한 우리 버그를 AX에 보내지 않는다**.
/// 여기서 걸린 것은 보고가 아니라 스킵이며(쓰기 시도 자체가 없다), 통과한 뒤의 앱 거부만
/// `.illegalArgument` 관측 대상이 된다. `ViewportProvenTests`와 같은 형태의 표 검증이다.
struct AXWriteProvenRangeTests {
    @Test("문서 안에 들어가는 범위·캐럿은 그대로 통과한다")
    func rangesInsideTheDocumentPass() {
        // 빈 문서의 캐럿 — 길이 0이 걸러지지 않는 것이 계약이다(모션이 전부 이 형태다).
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: 0, length: 0), characterCount: 0)
                == NSRange(location: 0, length: 0))
        // upperBound == characterCount (경계 통과)
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: 3, length: 2), characterCount: 5)
                == NSRange(location: 3, length: 2))
        // 문서 끝 캐럿 — 마지막 글자 "뒤"는 유효한 캐럿 자리다.
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: 5, length: 0), characterCount: 5)
                == NSRange(location: 5, length: 0))
    }

    @Test("문서 밖으로 넘치는 범위는 거부한다")
    func rangesPastTheDocumentAreRejected() {
        // upperBound == characterCount + 1 (경계 1 차이)
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: 3, length: 3), characterCount: 5)
                == nil)
        // 끝 너머 캐럿
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: 6, length: 0), characterCount: 5)
                == nil)
    }

    /// 결정 문서 문언(`0 ≤ location && upperBound ≤ characterCount`)만으로는 음수 length가
    /// 통과한다(5 + (−3) = 2 ≤ 10). 같은 default-deny의 연장으로 막고, 뺄셈 우선 가드가
    /// `NSNotFound` 같은 값의 오버플로 트랩까지 함께 닫는 것을 여기서 고정한다.
    @Test("말이 안 되는 입력은 트랩 없이 거부한다")
    func nonsensicalInputsAreRejectedWithoutTrapping() {
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: -1, length: 0), characterCount: 5)
                == nil, "음수 location")
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: 5, length: -3), characterCount: 10)
                == nil, "음수 length")
        #expect(
            AXWriteOutcome.provenWriteRange(
                NSRange(location: NSNotFound, length: 0), characterCount: 5) == nil,
            "NSNotFound — location + length가 오버플로하면 안 된다")
        #expect(
            AXWriteOutcome.provenWriteRange(NSRange(location: 0, length: 1), characterCount: -1)
                == nil, "앱이 음수 characterCount를 보고")
    }
}

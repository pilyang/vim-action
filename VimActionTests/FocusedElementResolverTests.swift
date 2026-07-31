//
//  FocusedElementResolverTests.swift
//  VimActionTests
//

import Foundation
import Testing
@testable import VimAction

/// 격리된 `NotificationCenter` + `nil` pid를 주입해 라이브 `NSWorkspace` 구독과 AX 호출을
/// 둘 다 피한다 — 실제 최전면 앱(= 테스트를 돌린 터미널)이 판정에 새어 들면 머신 상태 의존
/// 실패가 되고, AX 옵저버는 유닛 테스트에서 만들 수 없다 (`FrontmostAppGateTests`와 같은 규칙).
@MainActor
private func makeResolver() -> FocusedElementResolver {
    FocusedElementResolver(notificationCenter: NotificationCenter(), frontmostProcessID: nil)
}

/// 실측 분류표 한 행 — **이 표가 곧 계약이다**. 값은 2026-08-01 실기기 서베이에서 왔다
/// (`20260801_element-family-classification-table.md`).
struct ClassificationFixture: Sendable, CustomTestStringConvertible {
    var app: String
    var role: String?
    var subrole: String?
    var exposesSelectedTextRange: Bool
    var expected: ElementFamily

    init(
        _ app: String, _ role: String?, _ subrole: String?, _ exposesSelectedTextRange: Bool,
        _ expected: ElementFamily
    ) {
        self.app = app
        self.role = role
        self.subrole = subrole
        self.exposesSelectedTextRange = exposesSelectedTextRange
        self.expected = expected
    }

    var testDescription: String { app }
}

/// 실측된 앱 6종. Finder가 이 표의 요점이다 — role만 보면 `AXGroup`이라 Chromium·Electron의
/// 편집 영역과 구별되지 않지만, 속성 노출로는 깨끗하게 갈린다.
private let surveyedFixtures: [ClassificationFixture] = [
    .init("TextEdit 문서 본문", "AXTextArea", nil, true, .textArea),
    .init("Notion 블록 본문", "AXTextArea", "AXApplicationGroup", true, .textArea),
    .init("Slack 컴포저", "AXTextArea", nil, true, .textArea),
    .init("Chrome 주소창", "AXTextField", nil, true, .textField),
    .init("Finder 리스트", "AXGroup", nil, false, .nonText),
    // VS Code는 포커스 요소 자체를 보고하지 않는다(AXError=-25212) — 리졸버가 AX 단계에서
    // 폴백하므로 이 함수에는 애초에 도달하지 않지만, 폴백 값이 무엇인지는 아래 별도 테스트가 고정한다.
]

/// 실측되지 않았지만 계약이 규정하는 행 — "확실한 보고에만 걸러낸다"의 경계.
private let boundaryFixtures: [ClassificationFixture] = [
    .init("미지 role + 텍스트 범위 있음", "AXSomeFutureRole", nil, true, .textArea),
    .init("role 없음 + 텍스트 범위 있음", nil, nil, true, .textArea),
    .init("검색창 subrole", "AXTextArea", "AXSearchField", true, .textField),
    .init("비밀번호 필드 subrole", "AXTextArea", "AXSecureTextField", true, .textField),
    // 범위를 노출하지 않으면 role이 무엇이든 비텍스트다 — 애매한 role도 예외가 아니다.
    .init("미지 role + 텍스트 범위 없음", "AXSomeFutureRole", nil, false, .nonText),
    .init("role 없음 + 텍스트 범위 없음", nil, nil, false, .nonText),
]

@MainActor
struct FocusedElementResolverTests {
    @Test("실측 분류표 골든", arguments: surveyedFixtures)
    func classifiesSurveyedApps(_ fixture: ClassificationFixture) {
        let actual = FocusedElementResolver.family(
            role: fixture.role, subrole: fixture.subrole,
            exposesSelectedTextRange: fixture.exposesSelectedTextRange)
        #expect(actual == fixture.expected, "\(fixture.app)")
    }

    @Test("경계 규칙 — 확실한 보고에만 걸러낸다", arguments: boundaryFixtures)
    func classifiesBoundaryCases(_ fixture: ClassificationFixture) {
        let actual = FocusedElementResolver.family(
            role: fixture.role, subrole: fixture.subrole,
            exposesSelectedTextRange: fixture.exposesSelectedTextRange)
        #expect(actual == fixture.expected, "\(fixture.app)")
    }

    /// 텍스트/비텍스트를 가르는 것은 role이 **아니라** 속성 노출이라는 계약.
    ///
    /// Finder는 리스트에 포커스가 있어도 `AXGroup`을 보고하는데, 그 role은 Chromium·Electron이
    /// 편집 가능한 영역에도 붙인다. role 화이트리스트로 갔으면 Finder를 못 걸러내거나
    /// (`AXGroup`을 텍스트로 두면) 웹 앱 전체를 죽였을 것이다(비텍스트로 두면).
    @Test("같은 role이라도 텍스트 범위 노출 여부로 갈린다")
    func selectedTextRangeIsTheDiscriminator() {
        let asText = FocusedElementResolver.family(
            role: "AXGroup", subrole: nil, exposesSelectedTextRange: true)
        let asNonText = FocusedElementResolver.family(
            role: "AXGroup", subrole: nil, exposesSelectedTextRange: false)
        #expect(asText == .textArea)
        #expect(asNonText == .nonText)
    }

    /// AX가 아무 말도 못 하는 앱(VS Code 실측)에서 리졸버가 무엇을 보고하는가.
    /// 초기값이 곧 폴백이며, 이것이 `.nonText`가 되면 AX 부실 앱에서 Vim 레이어가 통째로 죽는다.
    @Test("AX를 읽지 못하면 폴백은 textArea")
    func fallbackIsTextArea() {
        #expect(makeResolver().family == .textArea)
    }

    @Test("update가 계열을 양방향으로 전환한다")
    func updateFlipsFamilyBothWays() {
        let resolver = makeResolver()

        resolver.update(family: .nonText)
        #expect(resolver.family == .nonText)

        resolver.update(family: .textField)
        #expect(resolver.family == .textField)

        resolver.update(family: .textArea)
        #expect(resolver.family == .textArea)
    }
}

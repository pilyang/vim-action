//
//  ViewportReader.swift
//  VimAction
//

import ApplicationServices
import Foundation

/// 포커스 요소의 **뷰포트 표시 줄 수**를 읽는 리더 — 스크롤 근사(15/30)를 정확화하는 입력이다.
///
/// `FocusedTextReader`와 별개의 프리미티브다: 그쪽은 캐럿 ±256 창의 텍스트이고, 이쪽은
/// `AXVisibleCharacterRange` 양 끝의 `AXLineForIndex` 줄 번호 차다. 반환이 텍스트가 아니라
/// **줄 수 하나(`Int`)**인 것이 계약이다 — 변환이 리더 안에 닫혀 소비자(매퍼)는 읽기 방법을
/// 모른다. `AXLineForIndex`의 "line"은 **표시 줄**(시각 줄)인데, 그것이 오히려 옳은 단위다:
/// 스크롤은 `↓`/`↑` 화살표 반복이고 화살표도 시각 줄을 걷는다 — 소프트 랩 문단에서 개행
/// 세기는 6× 과소가 실측됐다(120 표시 줄 창에서 논리 줄 20). 결정 20260803의
/// `AXLineForIndex` 기각은 논리 줄이 필요한 자리(linewise 편집)에 관한 것이라 충돌하지 않는다.
///
/// 주입 seam인 이유는 `FocusedTextReader`와 같다 — 실제 AX를 읽으면 골든 테스트가
/// 실기기 권한과 개발자 머신의 포커스 상태에 따라 갈린다.
nonisolated struct ViewportReader: Sendable {
    private let readViewportLines: @Sendable (pid_t) -> Int?

    init(read: @escaping @Sendable (pid_t) -> Int? = ViewportReader.readViaAccessibility) {
        self.readViewportLines = read
    }

    /// 실패는 전부 `nil` 하나다 — 아래 프로덕션 구현의 계약과 같다.
    func read(processID: pid_t) -> Int? { readViewportLines(processID) }

    /// 프로덕션 구현. 어느 단계에서 실패하든 `nil`이며(속성 미지원·파라미터화 미지원·타임아웃)
    /// 에러코드로 갈라지지 않는다 — 소비자가 할 일은 하나뿐이다: 정확화를 포기하고 현행
    /// 폴백 사다리(프로파일 → 코드 상수 15/30)로 간다.
    ///
    /// **문서 전체 가시는 뷰포트 증명 실패로 본다** (`visible.length >= characterCount` → `nil`).
    /// Notion이 visible을 문서 전체로 오보하는 것이 실측됐고(198줄 — 한 화면일 수 없다),
    /// 줄 수 클램프만으로는 실패 방향이 "과다 스크롤"이라 위험하다. 정말 문서 전체가 보이는
    /// 짧은 문서도 함께 폴백되지만, 그런 문서에서는 화살표가 문서 끝에서 포화해 스크롤
    /// 정밀도가 애초에 의미 없다 — 놓치는 방향이라 안전하다.
    @Sendable
    static func readViaAccessibility(processID: pid_t) -> Int? {
        guard let element = AXRead.focusedElement(ofProcess: processID),
            let raw = copyRange(element, kAXVisibleCharacterRangeAttribute),
            let characterCount = AXRead.copyValue(element, kAXNumberOfCharactersAttribute) as? Int,
            let visible = provenViewport(raw, characterCount: characterCount),
            let firstLine = lineForIndex(element, visible.location),
            let lastLine = lineForIndex(element, visible.location + visible.length - 1),
            firstLine <= lastLine
        else {
            return nil
        }
        return lastLine - firstLine + 1
    }

    /// 읽은 visible 범위가 **뷰포트로 증명되는가** — 문서 전체 가시(`length >= characterCount`)와
    /// 문서와 아귀가 안 맞는 보고는 전부 `nil`(읽기 실패와 같은 편)이다. 순수 함수로 뽑아 둔
    /// 것은 `FocusedTextReader.window(around:)`와 같은 이유다 — Notion 오보 가드가 표로
    /// 검증되고, AX 호출 자체는 실기기 몫으로 남는다.
    static func provenViewport(_ visible: NSRange, characterCount: Int) -> NSRange? {
        guard visible.location >= 0, visible.length > 0,
            visible.length < characterCount,
            visible.location + visible.length <= characterCount
        else {
            return nil
        }
        return visible
    }

    private static func copyRange(_ element: AXUIElement, _ attribute: String) -> NSRange? {
        guard let value = AXRead.copyValue(element, attribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// `AXLineForIndex`는 **파라미터화 속성**이라 전용 API를 쓴다 (`AXStringForRange`와 같다).
    private static func lineForIndex(_ element: AXUIElement, _ index: Int) -> Int? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXLineForIndexParameterizedAttribute as CFString, index as CFNumber,
                &value) == .success
        else {
            return nil
        }
        return value as? Int
    }
}

/// `execute` **1회 동안**의 뷰포트 줄 수 — 처음 물을 때 읽고 그 뒤로는 기억한다.
///
/// `FocusedTextSnapshot`과 형태는 동형이되 **수명이 다르다: 액션마다가 아니라 execute당
/// 1회다.** 그쪽 계약("액션마다 새로")의 사유는 앞 액션이 캐럿을 옮겨 실행 직전 값만
/// 정확하다는 것인데, 뷰포트 **높이**는 버스트 중 불변이다 — 스크롤로 뷰가 움직여도 창
/// 크기는 그대로다. 액션별 재읽기는 정확도 이득 0에 비용만 곱한다(카운트 스크롤은 엔진이
/// 액션 복제로 풀므로 최악 33회 × 타임아웃 50ms).
nonisolated final class ViewportSnapshot {
    private let processID: pid_t?
    private let reader: ViewportReader
    /// 이중 옵셔널이 memo 여부와 읽기 실패를 가른다 — 바깥 `nil`은 "아직 안 읽었다",
    /// 안쪽 `nil`은 "읽었는데 실패했다"다. **실패도 기억한다** (`FocusedTextSnapshot`과 같은
    /// 이유 — 타임아웃 앱에서 물음 수만큼 캡을 물지 않게).
    private var cached: Int??

    init(processID: pid_t?, reader: ViewportReader) {
        self.processID = processID
        self.reader = reader
    }

    /// 읽기 실패·타임아웃·pid 없음이 전부 같은 `nil`이다 — 소비자의 폴백이 하나뿐이라
    /// 구분할 이유가 없다.
    func value() -> Int? {
        if let cached { return cached }
        let value = processID.flatMap { reader.read(processID: $0) }
        cached = .some(value)
        return value
    }
}

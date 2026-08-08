//
//  FocusedTextReader.swift
//  VimAction
//

import ApplicationServices
import Foundation

/// 디스패치 경로가 읽은 **캐럿 주변 스냅샷** — 무상태 시퀀스를 정확화하는 입력이다.
///
/// 문서 전체(`AXValue`)는 담지 않는다: 필요한 것은 캐럿 주변 텍스트와 문서 길이뿐인데
/// 전체 읽기는 비용이 문서 크기에 비례한다 (실측 100만자 TextEdit 3.5~5.3ms vs 창 읽기는
/// 크기 무관 ~0.2ms — `20260802_dispatch-read-on-posting-queue.md` ③).
nonisolated struct FocusedText: Equatable, Sendable {
    /// `AXSelectedTextRange`. 길이 0이면 캐럿, 아니면 선택 범위다.
    var selection: NSRange
    /// `AXNumberOfCharacters` — 문서 끝 포화(마지막 줄 `dgg`, 마지막 단어 `dw`) 판정용.
    var characterCount: Int
    /// 캐럿 주변 창의 텍스트 (`AXStringForRange`).
    var window: String
    /// `window`가 문서에서 차지하는 절대 범위. **이것이 있어야 절대↔상대 오프셋 변환이 된다** —
    /// 소비자는 `selection.location - windowRange.location`으로 창 안의 캐럿 위치를 얻는다.
    var windowRange: NSRange
}

/// 포커스 요소의 캐럿 주변을 읽는 리더 — **게시 직렬 큐 위에서만** 불린다.
///
/// 주입 seam인 이유는 `ActionExecutor(postEvent:)`·`PasteWiseResolver(readClipboard:)`와 같다:
/// 실제 AX를 읽으면 골든 테스트가 실기기 권한과 개발자 머신의 포커스 상태에 따라 갈린다.
nonisolated struct FocusedTextReader: Sendable {
    /// 캐럿 양옆으로 읽는 문자 수. 소비자가 필요로 하는 것은 단어·줄 경계라 이 반경이면
    /// 충분하고, 창 읽기 비용은 실측상 크기와 무관해서(~0.2ms) 여유를 크게 잡아도 공짜다.
    static let windowRadius = 256

    /// **AX 쓰기 경로 전용 반경.** keyboard 경로의 256과 갈린 이유는 소비자가 다르기 때문이다:
    /// 정확화는 캐럿 ±몇 자의 술어만 물어 256이 남고, AX 오프셋 계층은 논리 줄 전체(소프트 랩
    /// 문단 = Notion 블록)를 창 안에 들여야 `dd`·`0`·`$`가 증명된다.
    ///
    /// 확대가 keyboard에서 기각됐던 사유 셋 중 둘(원자 그룹 폭증·낡은 읽기의 오프셋 비례 파괴)이
    /// AX에서 소멸하고, 비용은 실측상 창 크기와 무관하다 — 8192단위 웜 p50이 TextEdit 0.37ms·
    /// Notion 0.26ms로 현행 512 창과 사실상 동일했다(세션 1 실측). 고정 상수라 "문서 크기 비례
    /// 읽기 금지" 불변식과도 충돌하지 않는다
    /// (`20260808_ax-offset-layer-window-logical-lines.md`).
    static let axWindowRadius = 4096

    private let readFocusedText: @Sendable (pid_t) -> FocusedText?

    init(
        read: @escaping @Sendable (pid_t) -> FocusedText? = { readViaAccessibility(processID: $0) }
    ) {
        self.readFocusedText = read
    }

    /// 실패는 전부 `nil` 하나다 — 아래 프로덕션 구현의 계약과 같다.
    func read(processID: pid_t) -> FocusedText? { readFocusedText(processID) }

    /// 프로덕션 구현. **어느 단계에서 실패하든 `nil`이며 에러코드로 갈라지지 않는다** —
    /// `attrUnsupported`(비텍스트 요소)든 `noValue`(Slack·VS Code처럼 포커스 요소 미노출)든
    /// `cannotComplete`(타임아웃)든 소비자가 할 일은 하나뿐이기 때문이다: 정확화를 포기하고
    /// 현행 무상태 시퀀스로 실행한다. 스킵도, `reportExecutionFailure` 대상도 아니다 —
    /// 읽기는 정확화의 입력이지 실행이 아니다 (`20260802_dispatch-read-on-posting-queue.md` ④).
    @Sendable
    static func readViaAccessibility(processID: pid_t) -> FocusedText? {
        guard let element = AXRead.focusedElement(ofProcess: processID) else { return nil }
        return read(element, radius: windowRadius)
    }

    /// 요소가 이미 있을 때의 본체 — 위에서 획득 단계만 뺀 것이다.
    ///
    /// **AX 쓰기 경로가 여기로 들어온다.** 오프셋을 계산한 읽기와 뒤따르는 쓰기가 **같은 요소
    /// 핸들**을 써야 `AXWriter`의 요소 수신 계약(그 타입 doc)이 성립한다 — 리더가 pid로 요소를
    /// 다시 획득하면 그 사이 포커스가 옮겨간 경우 한 요소로 계산한 범위를 다른 요소에 쓰는
    /// 창이 열리고, 그것이 요소 획득 API를 `AXWriter`에 두지 않은 이유 그 자체다.
    static func read(_ element: AXUIElement, radius: Int) -> FocusedText? {
        guard let selection = copyRange(element, kAXSelectedTextRangeAttribute),
            let characterCount = AXRead.copyValue(element, kAXNumberOfCharactersAttribute) as? Int,
            let windowRange = window(
                around: selection, characterCount: characterCount, radius: radius)
        else {
            return nil
        }
        guard let window = copyString(element, forRange: windowRange) else { return nil }
        return FocusedText(
            selection: selection, characterCount: characterCount, window: window,
            windowRange: windowRange)
    }

    /// 캐럿(또는 선택) 양옆 `radius`를 문서 경계로 clamp한 범위.
    /// 범위가 문서와 아귀가 맞지 않으면(음수 위치, 문서 밖 선택) `nil` — 읽기 실패와 같은 편이다.
    static func window(
        around selection: NSRange, characterCount: Int, radius: Int = FocusedTextReader.windowRadius
    ) -> NSRange? {
        guard selection.location >= 0, selection.length >= 0, characterCount >= 0 else {
            return nil
        }
        let start = max(0, selection.location - radius)
        let end = min(characterCount, selection.location + selection.length + radius)
        guard start <= end else { return nil }
        return NSRange(location: start, length: end - start)
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

    /// `AXStringForRange`는 **파라미터화 속성**이라 전용 API를 쓴다.
    ///
    /// 빈 범위(빈 문서·빈 검색창)에서 AX를 부르지 않고 곧장 `""`를 내는 것은 에러 분기가
    /// 아니다 — 답을 이미 아는 왕복을 생략하는 것이고, 그것이 없으면 빈 문서가 읽기 실패로
    /// 잘못 집계돼 정확화가 필요 없는 자리에서 폴백이 발동한다.
    private static func copyString(_ element: AXUIElement, forRange range: NSRange) -> String? {
        guard range.length > 0 else { return "" }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value)
                == .success
        else {
            return nil
        }
        return value as? String
    }
}

/// 액션 **1건 동안**의 캐럿 주변 텍스트 — 처음 물을 때 읽고 그 뒤로는 기억한다.
///
/// **액션마다 새로 만드는 것이 계약이다.** 계열·프로파일 스냅샷과 시점 요구가 정반대다:
/// 그쪽은 키 입력 시점 값이 유일하게 일관되지만, 선택 범위는 같은 버스트의 앞 액션이 캐럿을
/// 옮기므로 **실행 직전 값만 정확하다**. 그래서 읽기는 콜백 선읽기가 아니라 소비 지점의
/// lazy이며, 한 액션 안에서는 1회로 접는다 (Notion에서 읽기 1회가 7ms다).
nonisolated final class FocusedTextSnapshot {
    /// 읽기 대상 pid. 노출하는 이유는 Visual 앵커의 자가 검증이다 — 읽은 pid와 검증하는
    /// pid가 **같은 값임을 구조로 보장**한다 (따로 나르면 두 값이 어긋날 자리가 생긴다).
    let processID: pid_t?
    private let reader: FocusedTextReader
    /// 이중 옵셔널이 memo 여부와 읽기 실패를 가른다 — 바깥 `nil`은 "아직 안 읽었다",
    /// 안쪽 `nil`은 "읽었는데 실패했다"다. **실패도 기억하는 것이 요점이다**: 한 액션 안에서
    /// 여러 번 물어도 실패한 AX 왕복을 되풀이하지 않는다 (Notion 타임아웃이면 매번 50ms다).
    private var cached: FocusedText??

    init(processID: pid_t?, reader: FocusedTextReader) {
        self.processID = processID
        self.reader = reader
    }

    /// 읽기 실패·타임아웃·pid 없음이 전부 같은 `nil`이다 — 소비자의 폴백이 하나뿐이라
    /// 구분할 이유가 없다.
    func value() -> FocusedText? {
        if let cached { return cached }
        let value = processID.flatMap { reader.read(processID: $0) }
        cached = .some(value)
        return value
    }
}

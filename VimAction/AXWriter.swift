//
//  AXWriter.swift
//  VimAction
//

import ApplicationServices
import Foundation

/// **AX 속성 쓰기의 단일 통로.** `AXUIElementSetAttributeValue`를 부르는 유일한 자리다.
///
/// 출력 통로 불변식은 프리미티브마다 하나다 — 합성 이벤트 게시는 `ActionExecutor`,
/// AX 속성 쓰기는 여기, `NSPasteboard` 쓰기는 `PasteWiseResolver`/`Clipboard`. 감사
/// 가능성은 "타입 1개"가 아니라 **"프리미티브당 소유자 1개"** 에서 나오기 때문이다:
/// CGEvent 감사는 `post(tap:)` 호출자가 `ActionExecutor` 외 0건임을 확인하는 것이고,
/// AX 쓰기 감사는 `SetAttributeValue` 호출자가 이 타입 외 0건임을 확인하는 것이다.
///
/// **`ActionExecutor`에 넣지 않은 이유는 마커다.** 그 타입의 존재 이유는 게시 직전
/// 마킹 강제인데, AX 쓰기는 탭으로 되돌아오지 않아 마커·무한 루프 개념 자체가 없다.
/// 마커 없는 쓰기를 마커 타입에 넣으면 "이 타입을 거치면 마커가 찍힌다"가 거짓이 되고
/// AX 쓰기에도 마커가 관여한다는 오독이 생긴다.
///
/// 격리는 읽기 seam 2종(`FocusedTextReader`·`ViewportReader`)과 같다 — 쓰기는 게시
/// 직렬 큐에서만 일어나므로 이 값은 큐를 건너간다. 클로저의 비-`Sendable` 파라미터
/// (`AXUIElement`·`CFTypeRef`)는 **같은 격리 안에서** 넘어가므로 crossing이 아니다
/// (`ActionExecutor`의 `@Sendable (CGEvent) -> Void`와 같은 형태).
///
/// 주입 seam인 이유도 읽기 쪽과 같다 — 실제 AX에 쓰면 테스트가 실기기 권한과 개발자
/// 머신의 포커스 상태에 의존하고, 무엇보다 **개발자의 실제 문서를 편집한다**.
nonisolated struct AXWriter: Sendable {
    private let setAttributeValue: @Sendable (AXUIElement, String, CFTypeRef) -> AXError

    init(
        write: @escaping @Sendable (AXUIElement, String, CFTypeRef) -> AXError = AXWriter
            .writeViaAccessibility
    ) {
        self.setAttributeValue = write
    }

    /// **`AXError`는 raw로 나간다 — 분류는 이 타입의 책임이 아니다.**
    ///
    /// 읽기 seam이 실패를 전부 `nil` 하나로 접는 것은 소비자 폴백이 하나뿐이라서였다
    /// (정확화를 포기하고 무상태 시퀀스로 간다). 쓰기는 소비자 행동이 갈린다 — 미지원
    /// 스킵과 실패 보고가 다른 경로이고, 그 판정은 default-deny 화이트리스트라 어댑터의
    /// 순수 함수가 표로 검증한다 (`20260808_ax-write-failure-whitelist-no-fallback.md`).
    /// 여기서 분류·로깅·보고를 하면 그 표가 통로 안에 숨어 테스트할 수 없게 된다.
    ///
    /// **요소는 pid가 아니라 `AXUIElement`로 받는다.** 읽기(오프셋 계산)와 쓰기가 같은
    /// 요소 핸들을 써야, 그 사이 포커스가 옮겨간 경우 엉뚱한 요소에 계산된 범위를 써
    /// 넣는 창이 구조적으로 닫힌다. 요소 획득 API를 이 타입에 두지 않는 것이 그 계약의
    /// 나머지 절반이다 — 요소는 반드시 `AXRead.focusedElement`에서 오고, 50ms 단일
    /// 메시징 타임아웃이 그 고리로 쓰기 경로에도 상속된다.
    func write(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        setAttributeValue(element, attribute, value)
    }

    /// `AXSelectedTextRange`에 범위(길이 0이면 캐럿)를 쓴다 — **유일한 편의 메서드**다.
    ///
    /// AX 어댑터의 실행 수단이 범위/캐럿 쓰기 하나뿐이라 지금 필요한 포장이 이것뿐이다
    /// (텍스트 쓰기 `AXSelectedText`는 미채택 — 클립보드를 채우는 주체가 앱이어야 리치
    /// 클립보드와 앱 undo 스택 등록이 보존된다). 다른 속성 쓰기 포장은 필요해질 때 얹는다.
    ///
    /// `NSRange`를 받는 것은 읽기 seam의 거울이다 — 그쪽 `copyRange`가 `CFRange`를
    /// `NSRange`로 좁혀 내보내므로 쓰기는 반대로 넓혀 받는다. 소비자(오프셋 계층)가
    /// 다루는 값이 전부 `NSRange`(`FocusedText.selection`·`windowRange`)라 변환이 통로
    /// 안에 닫힌다.
    ///
    /// `AXValueCreate` 실패는 `.failure`로 접는다. 유효한 `CFRange`에서 실질적으로
    /// 불가능하지만 옵셔널이라 분기가 필요하고, AX 호출이 나가지 않았어도 "실행을
    /// 시도했는데 깨졌다"에 해당하므로 실보고 대상 코드가 정직한 매핑이다.
    func writeSelectedTextRange(_ element: AXUIElement, _ range: NSRange) -> AXError {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return .failure }
        return write(element, kAXSelectedTextRangeAttribute, value)
    }

    /// 프로덕션 구현. 메시징 타임아웃은 여기서 걸지 않는다 — 요소가 `AXRead.focusedElement`를
    /// 거쳐 오면서 이미 설정된 상태로 도착한다(그것이 요소 획득을 이 타입에 두지 않는 이유다).
    @Sendable
    static func writeViaAccessibility(
        _ element: AXUIElement, _ attribute: String, _ value: CFTypeRef
    ) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
}

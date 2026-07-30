//
//  Clipboard.swift
//  VimAction
//

import AppKit

/// 시스템 클립보드 읽기 — v1은 레지스터가 없고 이것이 무명 레지스터다.
///
/// `nonisolated`인 이유는 호출 위치다: `KeyboardAdapter`의 기본 인수로 들어가고 게시 직렬 큐
/// 위에서 실행된다. 프로젝트 기본 격리가 `MainActor`라 그냥 두면 기본 인수 식(nonisolated
/// 컨텍스트에서 평가된다)에 놓을 수 없다 — `EventTapController`의 주입 기본값이 `nil`인 것과
/// 같은 제약이다.
///
/// 메인 밖에서 `NSPasteboard`를 만지는 근거는 `EventTapController`의 `defaults`와 같은
/// 부류다: SDK에 `Sendable`·`@MainActor` 표시가 없고(헤더 확인), 문서상 스레드 안전한
/// 타입이다. 읽기는 **`p` 입력에만** 발생하는 IPC 왕복이라 게시를 잠깐 늦출 뿐이고
/// 탭 콜백에는 영향이 없다(콜백 경량 불변식).
nonisolated enum Clipboard {
    /// 클립보드 텍스트의 붙여넣기 단위. 붙여넣을 텍스트가 없으면 `nil`이다 —
    /// 이미지·파일 URL만 있는 클립보드가 여기 해당한다.
    ///
    /// 판정 자체는 순수 함수 `PasteWise(clipboardText:)`가 하고 여기서는 읽기만 한다.
    static func pasteWise() -> PasteWise? {
        PasteWise(clipboardText: NSPasteboard.general.string(forType: .string))
    }
}

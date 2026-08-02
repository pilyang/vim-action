//
//  Clipboard.swift
//  VimAction
//

import AppKit

/// 시스템 클립보드 접근 — v1은 레지스터가 없고 이것이 무명 레지스터다.
/// 읽기는 붙여넣기 경로가, 쓰기는 메뉴의 'Copy Bundle ID' 하나가 쓴다.
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

    /// 클립보드가 바뀔 때마다 증가하는 카운터. 누가 썼는지가 아니라 **몇 번 쓰였는지**만
    /// 알려주므로 "그 사이에 우리 편집 말고 다른 쓰기가 있었나"를 판정하는 데 쓴다.
    static func changeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    /// 클립보드 쓰기 — 메뉴의 'Copy Bundle ID'가 유일한 호출자다(메인 스레드).
    ///
    /// `changeCount`가 오르므로 그 순간 `PasteWiseResolver`의 줄 단위 기억은 델타-1 규칙을
    /// 벗어나 버려지고 실제 클립보드 내용을 따른다 — 클립보드가 더는 우리 편집 결과가
    /// 아니니 옳은 동작이고, 그 규칙 자체는 `KeyboardAdapterTests`가 이미 고정하고 있다.
    static func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 붙여넣을 단위를 정한다 — **우리가 방금 게시한 줄 단위 편집은 추론할 필요가 없다.**
///
/// 끝 개행 휴리스틱은 앱에 따라 틀린다: Notion은 블록 하나를 잘라내도 끝 개행을 붙이지
/// 않아 줄 단위 내용이 charwise로 오판되고, 그러면 `p`가 줄 중간을 쪼갠다(실측으로 확인 —
/// 같은 `yy`가 TextEdit에서는 개행으로 끝나고 Notion에서는 아니다). 우리가 낸 `dd`·`yy`는
/// 우리가 줄 단위인 걸 알고 있으므로 휴리스틱을 거치지 않는다
/// (`20260730_paste-wise-from-our-own-edit.md`).
///
/// **게시 직렬 큐가 이 인스턴스를 단독 소유한다** — `KeyboardAdapter.execute`가 그 큐 위에서만
/// 불리므로 상태 접근이 직렬화된다. `@unchecked Sendable`은 컴파일러가 못 보는 그 사실의
/// 표현이며, `EventTapController`의 `nonisolated(unsafe) let defaults`와 같은 부류의 근거다.
nonisolated final class PasteWiseResolver: @unchecked Sendable {
    private let readClipboard: @Sendable () -> PasteWise?
    private let readChangeCount: @Sendable () -> Int

    /// 줄 단위 편집을 게시한 시점의 `changeCount`. 대상 앱은 잘라내기/복사를 **비동기로**
    /// 처리하므로 여기 담기는 값은 클립보드가 쓰이기 **이전** 것이다.
    private var recorded: (beforeWrite: Int, wise: PasteWise)?

    init(
        readClipboard: @escaping @Sendable () -> PasteWise? = { Clipboard.pasteWise() },
        readChangeCount: @escaping @Sendable () -> Int = { Clipboard.changeCount() }
    ) {
        self.readClipboard = readClipboard
        self.readChangeCount = readChangeCount
    }

    /// 줄 단위 편집(`dd`·`yy`·`dj`·`dG` 등)을 게시했다고 기록한다.
    func recordLinewiseEdit() {
        recorded = (readChangeCount(), .linewise)
    }

    /// 붙여넣을 단위. 붙여넣을 텍스트가 아예 없으면 `nil`이다.
    func resolve() -> PasteWise? {
        // 텍스트 유무 판정은 언제나 클립보드가 갖는다 — 기억이 있다는 이유로 빈 클립보드에
        // 접두만 게시하면 "붙여넣기 없이 캐럿만 움직이는" 조용한 오동작이 된다.
        guard let heuristic = readClipboard() else { return nil }
        // 정확히 1 늘었을 때만 그 쓰기가 우리 편집의 결과다. 아직 안 늘었으면(비동기 처리가
        // 끝나지 않았거나 잘라낼 것이 없었으면) 클립보드는 여전히 **이전** 내용이고,
        // 2 이상 늘었으면 그 사이 다른 쓰기가 끼어들어 기억이 내용을 설명하지 못한다.
        if let recorded, readChangeCount() == recorded.beforeWrite + 1 { return recorded.wise }
        return heuristic
    }
}

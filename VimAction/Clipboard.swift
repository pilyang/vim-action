//
//  Clipboard.swift
//  VimAction
//

import AppKit
import os

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
    /// `changeCount`가 오르므로 그 순간 `PasteWiseResolver`의 wise 기억은 델타-1 규칙을
    /// 벗어나 버려지고 실제 클립보드 내용을 따른다 — 클립보드가 더는 우리 편집 결과가
    /// 아니니 옳은 동작이고, 그 규칙 자체는 `KeyboardAdapterTests`가 이미 고정하고 있다.
    static func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 붙여넣을 단위를 정한다 — **우리가 방금 게시한 편집은 추론할 필요가 없다.**
///
/// 끝 개행 휴리스틱은 앱에 따라 틀린다: Notion은 블록 하나를 잘라내도 끝 개행을 붙이지
/// 않아 줄 단위 내용이 charwise로 오판되고, 그러면 `p`가 줄 중간을 쪼갠다(실측으로 확인 —
/// 같은 `yy`가 TextEdit에서는 개행으로 끝나고 Notion에서는 아니다). 반대 방향도 있다 —
/// 줄 끝 `x`가 개행을 잘라내면 charwise 내용이 개행으로 끝나 linewise로 오판된다.
/// 클립보드를 쓰는 편집(delete·change는 `Cmd-X`, yank는 `Cmd-C`)은 전부 우리가 낸
/// 것이라 내용의 wise를 우리가 알고 있으므로 휴리스틱을 거치지 않는다
/// (`20260730_paste-wise-from-our-own-edit.md`). 휴리스틱은 외부 복사 전담이다.
///
/// **게시 직렬 큐가 이 인스턴스를 단독 소유한다** — `KeyboardAdapter.execute`가 그 큐 위에서만
/// 불리므로 상태 접근이 직렬화된다. `@unchecked Sendable`은 컴파일러가 못 보는 그 사실의
/// 표현이며, `EventTapController`의 `nonisolated(unsafe) let defaults`와 같은 부류의 근거다.
nonisolated final class PasteWiseResolver: @unchecked Sendable {
    private let readClipboard: @Sendable () -> PasteWise?
    private let readChangeCount: @Sendable () -> Int

    /// 편집을 게시한 시점의 `changeCount`와 그 내용의 wise. 대상 앱은 잘라내기/복사를
    /// **비동기로** 처리하므로 여기 담기는 값은 클립보드가 쓰이기 **이전** 것이다.
    private var recorded: (beforeWrite: Int, wise: PasteWise)?

    /// Visual 세션의 현재 wise — 어댑터가 **게시가 확정된** `beginSelection`·
    /// `switchSelectionWise`의 값만 note한다. 스킵된 전환(`V`→`v` 폴백)은 화면 선택이
    /// 그대로라 여기 반영되지 않는 것이 내용 진실이다. "begin = 리셋"(엔진 계약)은
    /// `forgetSelectionWise`가 **게이트와 무관하게** 코드로 복원한다 — note가 게시 확정에
    /// 게이팅되므로, 걸러진 begin(`.nonText`·`.unresolved`) 뒤의 `.selection` 편집이
    /// 이전 세션의 wise를 소비하는 구멍이 망각 없이는 남는다.
    private var selectionWise: PasteWise?

    init(
        readClipboard: @escaping @Sendable () -> PasteWise? = { Clipboard.pasteWise() },
        readChangeCount: @escaping @Sendable () -> Int = { Clipboard.changeCount() }
    ) {
        self.readClipboard = readClipboard
        self.readChangeCount = readChangeCount
    }

    /// 클립보드를 쓰는 편집(`dd`·`dw`·`cc` 등)을 게시했다고 그 내용의 wise와 함께 기록한다.
    func recordEdit(_ wise: PasteWise) {
        recorded = (readChangeCount(), wise)
    }

    /// 게시가 확정된 Visual 진입·전환의 wise를 note한다 — `.selection` 편집의 내용 wise는
    /// 범위가 아니라 세션이 정하기 때문이다.
    func noteSelectionWise(_ wise: PasteWise) {
        selectionWise = wise
    }

    /// 새 Visual 세션의 시작 — 옛 세션의 wise를 잊는다. `beginSelection` **액션마다**,
    /// 게이트·게시 확정과 무관하게 불린다: 기록이 아니라 망각이라 오염 방향이 없고
    /// (틀려봐야 휴리스틱 폴백), 걸러진 begin이 note를 못 남겨도 옛 값만은 반드시 죽어야
    /// 뒤의 `.selection` 편집이 이전 세션의 wise로 기록되지 않는다.
    func forgetSelectionWise() {
        selectionWise = nil
    }

    /// `.selection` 편집(Visual `d`/`y`/`c`)의 기록 — note해 둔 세션 wise를 쓴다.
    /// 미상이면(begin 없이 온 편집) 기록하지 않는다: 기록할 근거가 없고, 휴리스틱 폴백이
    /// 보수 방향이다 — 이 잘라내기가 올린 changeCount는 델타-1 규칙이 옛 기억도 무효화한다.
    func recordSelectionEdit() {
        guard let selectionWise else { return }
        recordEdit(selectionWise)
    }

    /// 붙여넣을 단위. 붙여넣을 텍스트가 아예 없으면 `nil`이다.
    func resolve() -> PasteWise? {
        // 텍스트 유무 판정은 언제나 클립보드가 갖는다 — 기억이 있다는 이유로 빈 클립보드에
        // 접두만 게시하면 "붙여넣기 없이 캐럿만 움직이는" 조용한 오동작이 된다.
        guard let heuristic = readClipboard() else { return nil }
        // 정확히 1 늘었을 때만 그 쓰기가 우리 편집의 결과다. 아직 안 늘었으면(비동기 처리가
        // 끝나지 않았거나 잘라낼 것이 없었으면) 클립보드는 여전히 **이전** 내용이고,
        // 2 이상 늘었으면 그 사이 다른 쓰기가 끼어들어 기억이 내용을 설명하지 못한다.
        if let recorded {
            let delta = readChangeCount() - recorded.beforeWrite
            if delta == 1 {
                #if DEBUG
                // 판정 출처 관측 — 도그푸딩에서 "기억 대 휴리스틱"과 델타를 화면과 대조하는
                // 유일한 수단이다 (앱의 패스트보드 쓰기 횟수는 여기서만 보인다).
                Logger.eventTap.debug(
                    "paste wise \(String(describing: recorded.wise), privacy: .public) — 기억 (델타 1)"
                )
                #endif
                return recorded.wise
            }
            #if DEBUG
            Logger.eventTap.debug(
                "paste wise \(String(describing: heuristic), privacy: .public) — 휴리스틱 (기억 델타 \(delta, privacy: .public))"
            )
            #endif
            return heuristic
        }
        #if DEBUG
        Logger.eventTap.debug(
            "paste wise \(String(describing: heuristic), privacy: .public) — 휴리스틱 (기억 없음)")
        #endif
        return heuristic
    }
}

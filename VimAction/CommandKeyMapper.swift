//
//  CommandKeyMapper.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import VimEngine

/// 붙여넣기 단위 — Vim 레지스터의 charwise/linewise에 해당한다.
///
/// v1은 레지스터가 없고 시스템 클립보드가 무명 레지스터다. 우리가 방금 게시한 편집이라면
/// wise를 우리가 알고 있고(`PasteWiseResolver`), **외부에서 복사된 내용만** 아래 끝 개행
/// 휴리스틱으로 추론한다 (`20260730_paste-wise-trailing-newline-heuristic.md`,
/// `20260730_paste-wise-from-our-own-edit.md`).
nonisolated enum PasteWise: Equatable, Sendable {
    case charwise
    case linewise

    /// 클립보드 텍스트 → wise. 붙여넣을 텍스트가 없으면 `nil`이다.
    ///
    /// `NSPasteboard` 읽기와 분리된 순수 함수인 것이 요점이다 — 판정은 여기서 테이블로
    /// 검증하고, 패스트보드 접근은 `Clipboard`가 어댑터 쪽에서 담당한다.
    ///
    /// `isNewline`은 `\n` 외에 `\r`·`\u{2028}` 등도 잡는다 — 의도한 것이다. 어느 줄
    /// 종결자로 끝나든 "줄 단위로 복사된 것"이라는 신호는 같다.
    init?(clipboardText text: String?) {
        guard let text, !text.isEmpty else { return nil }
        self = text.last?.isNewline == true ? .linewise : .charwise
    }
}

/// 네이티브 명령 위임 계열의 액션 → 합성 키스트로크 시퀀스.
/// `MotionKeyMapper`·`EditKeyMapper`·`VisualKeyMapper`와 같은 순수 함수다.
///
/// 이 매퍼가 맡는 다섯 액션(`o`/`O`, `p`/`P`, `u`, `Ctrl-r`, 스크롤)의 공통점은
/// **앱의 네이티브 명령·키에 그대로 위임한다**는 것이다 — 모션의 캐럿 이동이나 편집의
/// "선택 후 오퍼레이터"와 달리 우리가 의미를 조립하지 않는다. 그래서 위치를 잡는 접두만
/// 모션 매핑을 재사용하고, 끝은 항상 명령 키 한 종류다
/// (`20260730_command-key-mapper-scope.md`).
///
/// 반환 `nil`은 **미지원**(스킵+로그)이다. 네 매퍼 공통으로 "지원 ⟹ 빈 시퀀스 아님"이
/// 불변식이라, 게시할 것이 없는 경우는 `nil`로만 표현한다.
nonisolated enum CommandKeyMapper {
    /// `.openLine` / `.undo` / `.redo` / `.scroll`. 붙여넣기는 클립보드 판정이 필요해
    /// `pasteStrokeGroups(before:count:wise:family:profile:)`로 갈라져 있다.
    ///
    /// 프로파일의 모션 재정의·disable은 위치 접두(`move`)를 통해 여기에도 전파된다 —
    /// disable된 모션을 접두로 쓰는 액션은 통째로 `nil`(정직한 스킵)이 된다.
    static func keyStrokes(
        for action: VimAction, family: ElementFamily, profile: ResolvedProfile = .empty
    ) -> [KeyStroke]? {
        switch action {
        case .openLine(let above):
            // **여기가 계열이 실제로 시퀀스를 가르는 유일한 자리다.** 단일행 필드에서 `Return`은
            // 줄을 만드는 대신 대개 **submit**이라(폼 전송·주소창 이동) 되돌릴 수 없다.
            // 엔진은 이미 Insert로 전이한 뒤라 "줄 없이 Insert"라는 불일치가 남지만, 그 실패
            // 모드는 Esc 한 번으로 끝나 무해하다 (`20260801_textfield-edit-sequences-scrapped.md`).
            guard family != .textField else { return nil }
            return above ? openAbove(profile) : openBelow(profile)

        case .undo:
            return profile.undoStrokes ?? [undoKey]

        case .redo:
            return profile.redoStrokes ?? [redoKey]

        case .scroll(let extent, let forward):
            // macOS에는 **캐럿을 한 뷰포트만큼 옮기는 키 프리미티브가 없다**. PageUp/PageDown은
            // 뷰만 옮기고 캐럿을 두고 가며, Vim 레이어는 모든 키가 모션이라 다음 키 한 번에
            // 스크롤이 통째로 되돌아온다(실측). Vim의 `Ctrl-d`/`Ctrl-f`는 본래 **커서 이동**이므로
            // 화살표 반복으로 근사한다 (`20260730_scroll-arrow-repetition.md`).
            guard let line = move(forward ? .lineDown : .lineUp, profile) else { return nil }
            return repeated(line, lineCount(for: extent, profile))

        default:
            // `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다.
            return nil
        }
    }

    /// `p`/`P` — 위치 접두는 **1회만**, `Cmd-V`만 count만큼 반복한다. 붙여넣기 후 캐럿이
    /// 삽입된 텍스트 끝에 남으므로 연타가 그대로 이어붙는다.
    ///
    /// 다른 매퍼와 달리 **원자 그룹으로 갈라서** 낸다. `.paste`는 액션 **1개** 안에서 카운트가
    /// 곱해지는 유일한 액션이라(`1000p` = `Cmd-V` 1,000타) 통짜로 내면 실행 중단 래치가
    /// 파고들 틈이 없다. 가를 수 없는 것은 `접두 + 첫 Cmd-V` 하나뿐이다 — 접두만 게시되고
    /// 끊기면 "붙여넣기 없이 캐럿만 움직이는" 조용한 오동작이 된다. 그 뒤의 `Cmd-V`는 각각
    /// 독립이라 어디서 끊겨도 "덜 붙여넣음"으로 끝난다.
    ///
    /// 매핑 자체는 그대로다 — 평탄화하면 이전과 같은 시퀀스다.
    /// 이 붙여넣기가 캐럿 주변 읽기를 묻는가 — 어댑터가 읽을지 정하는 술어다
    /// (`EditKeyMapper.consultsFocusedText`와 같은 자리). charwise `p`만 줄 끝 증명을
    /// 위해 묻고, `P`·linewise는 읽기 없이도 접두가 정확하므로 AX 왕복이 0건 유지된다.
    static func pasteConsultsFocusedText(before: Bool, wise: PasteWise) -> Bool {
        !before && wise == .charwise
    }

    static func pasteStrokeGroups(
        before: Bool, count: Int, wise: PasteWise, family: ElementFamily,
        profile: ResolvedProfile = .empty, text: FocusedText? = nil
    ) -> [[KeyStroke]]? {
        // 엔진은 count 1 이상만 낸다(0은 `0` 모션 규칙이 선점한다). 그래도 가드가 있는 이유는
        // 접두만 남은 시퀀스가 "붙여넣기 없이 캐럿만 움직인다"는 조용한 오동작이기 때문이다.
        guard count >= 1, let prefix = prefix(before: before, wise: wise, profile: profile, text: text)
        else { return nil }
        let paste = profile.pasteStrokes ?? [pasteKey]
        return [prefix + paste]
            + Array(repeating: paste, count: count - 1)
    }

    /// 붙여넣기 지점으로 캐럿을 옮기는 접두. `P`(before)는 Vim에서 캐럿 위치가 곧 삽입점이라
    /// charwise에서 접두가 없다. `nil`은 접두 모션이 프로파일에서 disable된 경우다 —
    /// 접두 없이 `Cmd-V`만 내면 위치가 틀린 채 붙으므로 붙여넣기 전체를 접는다.
    private static func prefix(
        before: Bool, wise: PasteWise, profile: ResolvedProfile, text: FocusedText?
    ) -> [KeyStroke]? {
        switch (wise, before) {
        case (.charwise, true):
            return []

        case (.charwise, false):
            // **줄 끝이 증명되면 접두가 없다** — Vim 커서는 줄 끝을 넘지 못하므로(마지막 글자
            // 위) "커서 뒤"가 곧 지금 캐럿 자리다. `→`를 내면 다음 줄 시작으로 포화해 붙여넣기가
            // 줄을 넘는다 (도그푸딩 실측 — 줄 끝 `xp`가 글자를 다음 줄로 보냈다). 편집 정확화와
            // 같은 줄 끝 Vim 커서 모델이고, 빈 줄·문서 끝도 같은 판정에 덮인다. 살아 있는 선택은
            // 출발점을 증명할 수 없어 제외한다 (정확화 표의 공통 발동 조건).
            if let text, text.selection.length == 0, text.isAtLineEnd { return [] }
            // 캐럿은 문자 **사이**이고 Vim의 커서는 문자 **위**라, "커서 문자 뒤"는 한 칸 오른쪽이다.
            return move(.charRight, profile)

        case (.linewise, true):
            return move(.lineStart, profile)

        case (.linewise, false):
            // 다음 줄 시작으로. 꼬리 `Cmd-←`는 멱등 보정자다 — 내부 줄에서는 이미 줄 시작이라
            // no-op이고, **마지막 줄에서는 `→`가 포화**하므로 그것이 없으면 `Cmd-V`가 마지막
            // 줄에 내용을 이어붙이고 개행을 남긴다(기존 텍스트 훼손). 보정자가 있으면 최악이
            // "`p`가 `P`로 퇴행"(한 줄 위, 구조는 온전)이다.
            guard let lineEnd = move(.lineEnd, profile),
                let charRight = move(.charRight, profile),
                let lineStart = move(.lineStart, profile)
            else { return nil }
            return lineEnd + charRight + lineStart
        }
    }

    /// `o` — 줄 끝으로 간 뒤 개행. 엔진이 이미 Insert로 전이했으므로 뒤에 붙일 키가 없다.
    private static func openBelow(_ profile: ResolvedProfile) -> [KeyStroke]? {
        guard let lineEnd = move(.lineEnd, profile) else { return nil }
        return lineEnd + newLine(profile)
    }

    /// `O` — 줄 시작에서 개행해 현재 줄을 아래로 밀고, 새로 생긴 빈 줄로 올라간다.
    ///
    /// `↑, Cmd-→, Return`이 아닌 이유는 **첫 줄**이다 — 거기서는 `↑`가 no-op이라 조용히
    /// `o`로 퇴행한다(`O`를 가장 많이 쓰는 자리에서 틀린다). 이 순서는 첫 줄에서도 맞는다
    /// (`20260730_openline-return-sequence.md`).
    private static func openAbove(_ profile: ResolvedProfile) -> [KeyStroke]? {
        guard let lineStart = move(.lineStart, profile), let lineUp = move(.lineUp, profile)
        else { return nil }
        return lineStart + newLine(profile) + lineUp
    }

    /// 줄을 만드는 키 — 앱마다 다르다. Slack처럼 `Return`이 전송인 앱은 `Shift-Return`이
    /// 줄바꿈이므로 프로파일이 이 키만 갈아끼운다(위치 접두는 그대로 모션을 탄다).
    private static func newLine(_ profile: ResolvedProfile) -> [KeyStroke] {
        profile.newLineStrokes ?? [returnKey]
    }

    /// 스크롤 1회가 옮길 줄 수. 뷰포트 높이를 모르는 상태의 **근사값**이다 — 실제 높이는
    /// 요소 리졸버가 AX(`AXVisibleCharacterRange`)로 읽을 수 있게 되는 M5에서 정확해지고,
    /// 그전까지는 M4 프로파일의 조절값이 된다.
    private static let halfPageLines = 15
    private static let fullPageLines = 30

    /// 프로파일 재정의가 있으면 그것, 없으면 코드 상수 — 프로파일은 "값 없음"만 표현하고
    /// 기본값 15/30은 여기 남는다.
    private static func lineCount(
        for extent: VimAction.ScrollExtent, _ profile: ResolvedProfile
    ) -> Int {
        extent == .halfPage
            ? profile.halfPageLines ?? halfPageLines
            : profile.fullPageLines ?? fullPageLines
    }

    /// 모션 스트로크 그대로 — 위치를 잡는 접두에 쓴다. `EditKeyMapper`와 같은 재사용이라
    /// 모션 매핑이 개선되거나 프로파일이 재정의하면 이 시퀀스들이 함께 따라온다.
    private static func move(_ motion: Motion, _ profile: ResolvedProfile) -> [KeyStroke]? {
        MotionKeyMapper.keyStrokes(for: motion, profile: profile)
    }

    private static func repeated(_ strokes: [KeyStroke], _ count: Int) -> [KeyStroke] {
        Array(repeating: strokes, count: count).flatMap { $0 }
    }

    /// `Return`은 화살표처럼 레이아웃 무관 고정 키코드다.
    private static let returnKey = KeyStroke(kVK_Return)

    /// 명령 단축키는 ANSI 키코드라 QWERTY 계열을 가정한다
    /// (`20260727_operator-key-ansi-layout-assumption.md`). **`Cmd-Z`는 그 가정의 위험 등급이
    /// 다르다** — AZERTY에서 이 자리는 `w`라 `u`가 `Cmd-W`(창 닫기)로 나간다
    /// (`20260730_cmd-z-ansi-layout-escalation.md`).
    private static let pasteKey = KeyStroke(kVK_ANSI_V, [.maskCommand])
    private static let undoKey = KeyStroke(kVK_ANSI_Z, [.maskCommand])
    private static let redoKey = KeyStroke(kVK_ANSI_Z, [.maskShift, .maskCommand])
}

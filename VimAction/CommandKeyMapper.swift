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
    /// `pasteStrokes(before:count:wise:family:)`로 갈라져 있다.
    static func keyStrokes(for action: VimAction, family: ElementFamily) -> [KeyStroke]? {
        switch action {
        case .openLine(let above):
            return above ? openAbove : openBelow

        case .undo:
            return [undoKey]

        case .redo:
            return [redoKey]

        case .scroll(let extent, let forward):
            // macOS에는 **캐럿을 한 뷰포트만큼 옮기는 키 프리미티브가 없다**. PageUp/PageDown은
            // 뷰만 옮기고 캐럿을 두고 가며, Vim 레이어는 모든 키가 모션이라 다음 키 한 번에
            // 스크롤이 통째로 되돌아온다(실측). Vim의 `Ctrl-d`/`Ctrl-f`는 본래 **커서 이동**이므로
            // 화살표 반복으로 근사한다 (`20260730_scroll-arrow-repetition.md`).
            return repeated(move(forward ? .lineDown : .lineUp), lineCount(for: extent))

        default:
            // `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다.
            return nil
        }
    }

    /// `p`/`P` — 위치 접두는 **1회만**, `Cmd-V`만 count만큼 반복한다. 붙여넣기 후 캐럿이
    /// 삽입된 텍스트 끝에 남으므로 연타가 그대로 이어붙는다.
    static func pasteStrokes(
        before: Bool, count: Int, wise: PasteWise, family: ElementFamily
    ) -> [KeyStroke]? {
        // 엔진은 count 1 이상만 낸다(0은 `0` 모션 규칙이 선점한다). 그래도 가드가 있는 이유는
        // 접두만 남은 시퀀스가 "붙여넣기 없이 캐럿만 움직인다"는 조용한 오동작이기 때문이다.
        guard count >= 1 else { return nil }
        return prefix(before: before, wise: wise) + Array(repeating: pasteKey, count: count)
    }

    /// 붙여넣기 지점으로 캐럿을 옮기는 접두. `P`(before)는 Vim에서 캐럿 위치가 곧 삽입점이라
    /// charwise에서 접두가 없다.
    private static func prefix(before: Bool, wise: PasteWise) -> [KeyStroke] {
        switch (wise, before) {
        case (.charwise, true):
            return []

        case (.charwise, false):
            // 캐럿은 문자 **사이**이고 Vim의 커서는 문자 **위**라, "커서 문자 뒤"는 한 칸 오른쪽이다.
            return move(.charRight)

        case (.linewise, true):
            return move(.lineStart)

        case (.linewise, false):
            // 다음 줄 시작으로. 꼬리 `Cmd-←`는 멱등 보정자다 — 내부 줄에서는 이미 줄 시작이라
            // no-op이고, **마지막 줄에서는 `→`가 포화**하므로 그것이 없으면 `Cmd-V`가 마지막
            // 줄에 내용을 이어붙이고 개행을 남긴다(기존 텍스트 훼손). 보정자가 있으면 최악이
            // "`p`가 `P`로 퇴행"(한 줄 위, 구조는 온전)이다.
            return move(.lineEnd) + move(.charRight) + move(.lineStart)
        }
    }

    /// `o` — 줄 끝으로 간 뒤 개행. 엔진이 이미 Insert로 전이했으므로 뒤에 붙일 키가 없다.
    private static let openBelow = move(.lineEnd) + [returnKey]

    /// `O` — 줄 시작에서 개행해 현재 줄을 아래로 밀고, 새로 생긴 빈 줄로 올라간다.
    ///
    /// `↑, Cmd-→, Return`이 아닌 이유는 **첫 줄**이다 — 거기서는 `↑`가 no-op이라 조용히
    /// `o`로 퇴행한다(`O`를 가장 많이 쓰는 자리에서 틀린다). 이 순서는 첫 줄에서도 맞는다
    /// (`20260730_openline-return-sequence.md`).
    private static let openAbove = move(.lineStart) + [returnKey] + move(.lineUp)

    /// 스크롤 1회가 옮길 줄 수. 뷰포트 높이를 모르는 상태의 **근사값**이다 — 실제 높이는
    /// 요소 리졸버가 AX(`AXVisibleCharacterRange`)로 읽을 수 있게 되는 M5에서 정확해지고,
    /// 그전까지는 M4 프로파일의 조절값이 된다.
    private static let halfPageLines = 15
    private static let fullPageLines = 30

    private static func lineCount(for extent: VimAction.ScrollExtent) -> Int {
        extent == .halfPage ? halfPageLines : fullPageLines
    }

    /// 모션 스트로크 그대로 — 위치를 잡는 접두에 쓴다. `EditKeyMapper`와 같은 재사용이라
    /// 모션 매핑이 개선되면 이 시퀀스들이 함께 따라온다.
    private static func move(_ motion: Motion) -> [KeyStroke] {
        MotionKeyMapper.keyStrokes(for: motion)
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

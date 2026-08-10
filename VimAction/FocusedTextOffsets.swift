//
//  FocusedTextOffsets.swift
//  VimAction
//

import Foundation
import VimEngine

/// **AX 쓰기 경로의 오프셋 산출** — 캐럿 주변 창(`FocusedText`)에서 모션의 목표 절대 오프셋을
/// 계산하는 순수 함수 계층이다.
///
/// `FocusedTextAnalysis`의 extension으로 얹지 않고 별도 이름공간인 것이 계약이다: **런 클래스가
/// 갈린다.** Analysis는 비ASCII를 `other`로 두어 런이 길게 세어지고 정확화가 **포기**하는 쪽으로
/// 떨어지지만(그쪽의 보수 방향), 여기서는 비ASCII가 `keyword`여야 CJK 문서의 `w`·`b`·`e`가
/// 성립한다. 같은 extension에 `runClass`가 둘 공존하면 호출부가 조용히 잘못 고른다
/// (`20260808_ax-offset-layer-window-logical-lines.md`).
///
/// **UTF-16 배관은 공유한다** — 절대↔창 상대 변환과 `window.utf16.count == windowRange.length`
/// 가드는 `FocusedText.offsetInWindow`를 그대로 쓴다.
///
/// **스캔은 `Character`(grapheme cluster) 단위다.** Analysis가 UTF-16 단위인 것과 갈리는데,
/// 이유가 이 계층의 안전 규칙 그 자체다: 산출이 항상 grapheme 경계 위여야 하고(서로게이트 쌍
/// 한가운데 쓰기를 Notion은 무보정으로 받는다는 세션 1 실측 — 이 불변식이 유일한 방어선이다),
/// 줄 종결자 `\r\n`이 Swift에서 한 `Character`라 떠돌이 `\r`가 원천 소거된다. Analysis 쪽은
/// "캐럿 ±1자 술어"라 단위를 바꿀 이유가 없었다.
///
/// **읽기는 분기의 근거이지 스트로크 수의 근거가 아니다** 불변식은 여기 적용되지 않는다 —
/// 그것은 keyboard 경로 전용이고(낡은 읽기 창), AX는 읽기·쓰기가 같은 큐에서 동기라 그 창이
/// 구조적으로 없으며 오프셋이 실행 수단 그 자체다.
nonisolated enum FocusedTextOffsets {
    /// 모션 1건의 산출 — `EditKeyMapper.Refinement`·`VisualKeyMapper.Refinement` 동형의 3상태다.
    ///
    /// 2상태로 뭉치면 "무동작이 정답"인 자리(첫 줄 `k`, 줄 끝 `l`)가 keyboard로 위임돼 실제로
    /// 캐럿이 움직인다 — 정직한 스킵과 위임은 반드시 갈려야 한다.
    enum Target: Equatable, Sendable {
        /// Vim 자체가 무효 — 그 액션만 정직한 스킵이다(게시도 쓰기도 없다).
        case invalid
        /// 증명된 목표 **절대 UTF-16 오프셋** — AX 캐럿 쓰기로 간다.
        case caret(Int)
        /// 창이 답하지 못했다 — keyboard 위임. 쓰기 시도 **전**이라 이중 실행이 원리적으로
        /// 불가하며, 쓰기 시도 **후** 실패의 폴백 금지와는 별개 축이다.
        case unproven
    }

    /// 구간 1건의 산출 — `Target`과 동형 3상태다.
    enum Span: Equatable, Sendable {
        /// Vim 자체가 무효 — 그 액션만 정직한 스킵이다.
        case invalid
        /// 증명된 **절대 UTF-16 범위** — AX 범위 쓰기로 간다.
        case range(NSRange)
        /// 창이 답하지 못했다 — keyboard 위임.
        case unproven
    }

    /// Visual 산출 1건 — 범위와 **상태 재수립 재료**를 함께 낸다.
    ///
    /// `Span`을 쓰지 않는 것이 계약이다: Visual은 매 액션이 세션 상태를 갱신하는 유일한 어휘라
    /// 범위만으로는 다음 상태를 세울 수 없다. 전환은 **논리 앵커 자체가 이동하고**(`v`→`V`의 새
    /// 앵커는 앵커 줄 시작이라 후진형에서는 범위 한가운데다), charwise `j`/`k`는 **희망 열**을
    /// 물려받는다. `side`·`pinnedEnd`는 범위와 앵커에서 도출되므로 여기 싣지 않는다
    /// (`VisualAnchorState.moved(to:anchor:column:)`).
    enum Selection: Equatable, Sendable {
        /// Vim 자체가 무효(범위 무변화 포함) — 그 액션만 정직한 스킵이다.
        case invalid
        /// 증명된 **절대 UTF-16 범위** + 새 논리 앵커 + 새 희망 열(`nil` = 모름).
        case range(NSRange, anchor: Int, column: Int?)
        /// 창이 답하지 못했다. Normal 경로와 달리 **AX Visual 세션에서는 위임이 아니라 스킵**
        /// 이다 — AX가 쓴 범위 위의 무상태 시퀀스는 파괴 방향 동전 던지기다.
        case unproven
    }

    /// 희망 열의 **줄 끝 고정** — Vim curswant MAXCOL의 대응이다. `$` 뒤의 `j`/`k`는 줄 길이와
    /// 무관하게 줄 끝(종결자)에 붙는 것이 실측이고, 산술이 항상 `min` 우선이라 오버플로가 없다.
    static let lineEndColumn = Int.max

    /// 삽입 위치 1건의 산출. **`.invalid`가 없다** — `o`·`O`·`p`·`P`는 Vim에서 무효인 자리가
    /// 없기 때문이다. 이것이 `Span`과 타입을 가른 이유이기도 하다: `Target`/`Span`은 "목표 ==
    /// 현재 캐럿"을 `.invalid`로 접는데, 줄 끝에서 `o`는 목표 == 캐럿이면서 유효하다. 같은
    /// 타입을 쓰면 접는 헬퍼를 재사용하는 순간 `o`가 조용히 죽는다.
    enum Insertion: Equatable, Sendable {
        /// 증명된 삽입 캐럿.
        case at(Int)
        /// **마지막 줄(뒤 개행 없음)의 linewise `p`** — 문서 끝 캐럿에 쓰고 게시 그룹이
        /// `[Return, Cmd-V]`여야 한다. naive 문서 끝 캐럿 + `Cmd-V`는 마지막 줄에 이어붙는
        /// 병합 훼손이 실측됐고, 캐럿 쓰기만으로는 구분 개행을 만들 수 없다
        /// (`20260808_last-line-linewise-paste-return-synthesis.md`).
        case appendingLine(Int)
        case unproven
    }

    /// 단어를 가르는 런 클래스. **비ASCII는 전부 `keyword`** 다 — `FocusedText.RunClass`와
    /// 정반대이며 그것이 이 타입이 별도 이름공간인 이유다(위 doc). 개행은 어느 런에도 속하지
    /// 않는 종결자라 이 타입으로 표현하지 않는다.
    enum RunClass: Equatable, Sendable {
        case blank
        case keyword
        case punctuation
    }

    /// 모션의 목표 캐럿 오프셋.
    ///
    /// `j`/`k`(`.lineUp`/`.lineDown`)는 **여기 오지 않는다** — 오프셋 대입이 희망 열(desired
    /// column)을 잃어 위임이 확정이다. 방어적으로 `.unproven`을 돌려준다(호출자가 실수로
    /// 넘겨도 현행 동작으로 떨어진다).
    static func caretTarget(for motion: Motion, in text: FocusedText) -> Target {
        // 살아 있는 선택 위에서는 "캐럿이 어디인가"가 애매하다 — Normal 모션의 전제가 아니므로
        // 증명하지 않는다 (정확화 표가 `selection.length == 0`만 다루는 것과 같은 규칙).
        guard text.selection.length == 0 else { return .unproven }

        switch motion {
        case .lineUp, .lineDown:
            return .unproven
        case .documentStart:
            // 상수 끝점이라 창과 무관하게 증명된다.
            return moved(from: text.selection.location, to: 0)
        case .documentEnd:
            return moved(from: text.selection.location, to: text.characterCount)
        default:
            break
        }

        guard let window = Window(text) else { return .unproven }
        switch motion {
        case .charLeft:
            return window.result(window.charLeft())
        case .charRight, .charRightForAppend:
            // 캐럿 모델에서 `l`과 `a`의 목표는 같다 — "마지막 글자 위 vs 뒤"의 구분은 블록
            // 커서 모델에서만 존재하고, 이 프로젝트는 줄 끝 어휘 셋 밖에서는 캐럿 모델이다.
            return window.result(window.charRight())
        case .wordForward:
            return window.result(window.wordForward())
        case .wordBackward:
            return window.result(window.wordBackward())
        case .wordEndForward:
            return window.result(window.wordEndForward())
        case .lineStart:
            return window.result(window.lineStart())
        case .lineFirstNonBlank:
            return window.result(window.lineFirstNonBlank())
        case .lineEnd, .lineEndForAppend:
            // `$`와 `A`도 캐럿 모델에서 같은 자리다 (위 `l`/`a`와 같은 이유).
            return window.result(window.lineEnd())
        case .lineUp, .lineDown, .documentStart, .documentEnd:
            return .unproven  // 위에서 처리됨 — 도달하지 않는다.
        }
    }

    /// 절대 오프셋 목표를 3상태로 접는다 — **목표 == 현재 캐럿이면 `.invalid`** 다.
    /// no-op을 굳이 AX로 왕복시킬 이유가 없고, 화면 결과가 정직한 스킵과 같다.
    private static func moved(from caret: Int, to target: Int) -> Target {
        target == caret ? .invalid : .caret(target)
    }

    // MARK: - 편집 범위

    /// `.edit(op, range)`의 범위 — AX 범위 쓰기가 겨냥할 절대 구간이다.
    ///
    /// 답은 `EditKeyMapper`의 정확화 표와 같아야 한다(수단만 다르다). 표가 **침묵하는** 자리
    /// 셋은 keyboard가 창을 못 물어봐서 비워 둔 곳이라 Vim 시맨틱을 따른다 — 마지막 줄
    /// linewise의 앞 개행 흡수, 줄 끝 단어 `dw`의 개행 미포함, linewise 카운트 클램프
    /// (전부 실측 확인, `20260809_ax-span-vim-exact-where-table-is-silent.md`).
    ///
    /// 살아 있는 선택 위에서는 출발점을 증명할 수 없어 전부 `.unproven`이다 — 정확화 표의
    /// 공통 발동 조건과 같은 규칙이고, `.selection`(Visual 편집)이 여기로 오면 위임 결과가
    /// 정확히 `Cmd-X`/`Cmd-C` 1타라 의미까지 맞는다.
    static func editSpan(
        for op: VimAction.Operator, range: VimAction.TextRange, in text: FocusedText
    ) -> Span {
        guard text.selection.length == 0, let window = Window(text) else { return .unproven }
        switch range {
        case .motion(let motion, let count):
            // `cw` 리타깃은 `EditKeyMapper.retargeted`와 같은 자리에서 한 번만 일어나야
            // 판정과 실행이 갈라지지 않는다. 카운트 2 이상은 표와 같이 `e` 반복이다.
            if op == .change, motion == .wordForward {
                return count == 1 ? window.changeWordSpan() : window.motionSpan(.wordEndForward, count)
            }
            return window.motionSpan(motion, count)

        case .line(let count):
            // `dd`의 모션 성분은 "아래 count−1줄"이다 — count 1은 모션이 없어 항상 유효하다.
            return window.linewiseSpan(above: 0, below: count - 1, op: op)

        case .linewiseMotion(.lineDown, let count):
            return window.linewiseSpan(above: 0, below: count, op: op)

        case .linewiseMotion(.lineUp, let count):
            return window.linewiseSpan(above: count, below: 0, op: op)

        case .linewiseMotion(.documentStart, _):
            return window.spanToDocumentStart(op: op)

        case .linewiseMotion(.documentEnd, _):
            return window.spanToDocumentEnd(op: op)

        case .textObject(.word(.inner)):
            return window.innerWordSpan()

        default:
            // `.selection`·`aw`·따옴표·괄호쌍 — 위임(= 현행 keyboard 경로 그대로).
            // `TextRange`에 exhaustive switch를 걸지 않는 것이 엔진 케이스 추가에 견디는 계약이다.
            return .unproven
        }
    }

    // MARK: - 하이브리드 삽입 위치

    /// `o`/`O`의 삽입 캐럿 — 줄 끝 / 줄 시작. 게시 `Return`(과 `O`의 복귀)은 매퍼 몫이다.
    ///
    /// **`Span`을 쓰지 않는 것이 계약이다**: 이미 줄 끝인 캐럿에서도 `o`는 유효하므로
    /// "목표 == 캐럿 ⟹ 무효" 접기를 지나면 안 된다.
    static func openLineInsertion(above: Bool, in text: FocusedText) -> Insertion {
        guard text.selection.length == 0, let window = Window(text) else { return .unproven }
        return window.insertion(above ? window.lineStart() : window.lineEnd())
    }

    /// `p`/`P`의 삽입 캐럿. wise별 규칙은 `CommandKeyMapper.prefix(before:wise:profile:text:)`의
    /// 접두와 같은 자리를 겨냥한다 — charwise `p`는 한 글자 오른쪽이되 **줄 끝이면 캐럿
    /// 그대로**이고(Vim 커서는 마지막 글자 위), linewise `p`는 다음 줄 시작이되 마지막 줄이면
    /// `.appendingLine`이다.
    static func pasteInsertion(before: Bool, wise: PasteWise, in text: FocusedText) -> Insertion {
        guard text.selection.length == 0, let window = Window(text) else { return .unproven }
        switch (wise, before) {
        case (.charwise, true):
            // Vim에서 `P`의 삽입점은 캐럿 그 자리다 — 접두가 없는 것과 같은 이유.
            return .at(text.selection.location)
        case (.charwise, false):
            return window.charwisePasteAfter()
        case (.linewise, true):
            return window.insertion(window.lineStart())
        case (.linewise, false):
            return window.linewisePasteAfter()
        }
    }

    // MARK: - Visual 범위

    /// `v`/`V` 진입의 선택 범위 — `v`는 캐럿이 놓인 글자 하나(inclusive), `V`는 캐럿 논리 줄
    /// 전체(종결자 포함)다.
    ///
    /// **진입에는 Vim 무효가 없다** — 빈 줄처럼 잡을 글자가 없는 자리는 `.invalid`가 아니라
    /// `.unproven`(keyboard 폴백)으로 강등한다. 진입을 스킵하면 엔진은 이미 Visual로 전이한
    /// 뒤라 화면과 모드가 어긋난다.
    static func visualEntrySelection(linewise: Bool, in text: FocusedText) -> Selection {
        guard text.selection.length == 0, let window = Window(text) else { return .unproven }
        let selection = linewise ? window.linewiseEntry() : window.charwiseEntry()
        if case .invalid = selection { return .unproven }
        return selection
    }

    /// `extendSelection(motion)`의 새 선택 범위 — 논리 앵커 A와 포커스 끝에서 계산한다.
    ///
    /// 포커스 끝 도출(`side`)이 범위 산술의 일부라 상태를 통째로 받는다 — 어댑터가 도출하면
    /// 그 규칙이 두 곳에 생긴다. `pinnedEnd`·pid 검증은 호출자(`VisualAnchorTracker`) 몫이다.
    static func visualExtendSelection(
        for motion: Motion, anchor: VisualAnchorState, in text: FocusedText
    ) -> Selection {
        guard text.selection.length > 0, let window = Window(text) else { return .unproven }
        let selection: Selection
        switch anchor.wise {
        case .linewise:
            // `V` 세션의 charwise 모션 8종은 Vim에서 범위가 안 바뀐다 — 무게시가 정확 동작이다
            // (`20260804_visual-linewise-motion-range-noop.md`). 희망 열도 그대로 남아
            // `V`→`v` 복원의 열이 실제 Vim 커서 열과 일치한다.
            guard !isCharwiseMotion(motion) else { return .invalid }
            selection = window.linewiseExtension(motion, anchor: anchor, in: text)
        case .charwise:
            selection = window.charwiseExtension(motion, anchor: anchor, in: text)
        }
        // 계산 결과가 지금 선택 그대로면 Vim에서도 범위 무변화다 — 무게시가 정확 동작이고,
        // 굳이 같은 범위를 AX로 다시 쓸 이유가 없다 (줄 끝 `vl`·문서 끝 `Vj`가 여기로 온다).
        // 그 액션의 희망 열 갱신도 함께 버려진다 — 이미 줄 끝인 캐럿의 `v$`가 그 자리이며,
        // 무게시 자리에 상태만 남기려면 케이스가 하나 더 필요해 수용한다.
        if case .range(let range, _, _) = selection, range == text.selection { return .invalid }
        return selection
    }

    /// `switchSelectionWise(linewise:)`의 새 선택 범위 — `v`↔`V` 양방향이다.
    ///
    /// keyboard 경로가 `V`→`v`를 조건부로만 지원하는 이유(포커스 열이 창으로 증명되지 않는다)는
    /// AX에 없다: `V` 진입이 원래 캐럿 P를 **정확히** 읽어 두고 포커스 줄 시작도 창이 답하므로
    /// 열이 추정이 아니라 뺄셈이다. 남는 증명 실패(P 미상 — ⑥으로 만들어진 세션은 아니다,
    /// 창이 줄 경계에 못 닿음)만 `.unproven`이며 AX 세션에서는 정직한 스킵이 된다.
    static func visualSwitchSelection(
        toLinewise: Bool, anchor: VisualAnchorState, in text: FocusedText
    ) -> Selection {
        guard text.selection.length > 0, let window = Window(text) else { return .unproven }
        return toLinewise
            ? window.roundedToLines(anchor: anchor, in: text)
            : window.restoredToCharacters(anchor: anchor, in: text)
    }

    /// `V` 세션에서 범위를 바꾸지 못하는 모션들.
    private static func isCharwiseMotion(_ motion: Motion) -> Bool {
        switch motion {
        case .charLeft, .charRight, .charRightForAppend, .wordForward, .wordBackward,
            .wordEndForward, .lineStart, .lineFirstNonBlank, .lineEnd, .lineEndForAppend:
            return true
        case .lineUp, .lineDown, .documentStart, .documentEnd:
            return false
        }
    }

    /// 창 안 스캔의 좌표계 — `Character` 인덱스와 절대 UTF-16 오프셋의 대응표다.
    ///
    /// 인덱스는 **문자 사이 위치**라 `0...characters.count` 범위이고, `offsets[i]`가 그 위치의
    /// 절대 오프셋이다(마지막 원소는 창 끝). 산출이 이 배열의 원소로만 나오는 것이 "항상
    /// grapheme 경계 위" 불변식의 구현이다.
    private struct Window {
        /// 스캔 결과 — 인덱스이거나, 창이 답하지 못했거나, Vim 무효다.
        enum Step {
            case index(Int)
            case invalid
            case unproven
        }

        let characters: [Character]
        let offsets: [Int]
        /// 캐럿의 문자 인덱스. 캐럿이 grapheme 경계 위가 아니면 창을 만들지 않는다(아래 init).
        let caret: Int
        /// 문서 전체 길이 — `G`·`dG`·마지막 줄 판정의 **상수 끝점**이다. 창 밖이어도 항상
        /// 유효한 경계라, 이 값 덕에 `dgg`/`dG`가 문서 규모와 무관하게 증명된다.
        let characterCount: Int
        let reachesDocumentStart: Bool
        let reachesDocumentEnd: Bool

        init?(_ text: FocusedText) {
            // 창 길이 일치 가드와 범위 확인은 Analysis와 공유한다 — 통과했다는 것 자체가
            // "이 창을 근거로 써도 된다"의 증명이라 반환된 상대 오프셋은 여기서 쓰지 않는다.
            guard text.offsetInWindow(text.selection.location) != nil else { return nil }

            var characters: [Character] = []
            var offsets: [Int] = []
            var cursor = 0
            characters.reserveCapacity(text.window.count)
            offsets.reserveCapacity(text.window.count + 1)
            for character in text.window {
                offsets.append(text.windowRange.location + cursor)
                characters.append(character)
                cursor += character.utf16.count
            }
            offsets.append(text.windowRange.location + cursor)

            // 캐럿이 경계 위가 아니면(서로게이트 쌍 한가운데 등) 이 창으로는 아무것도 증명하지
            // 않는다 — 보정해서 진행하면 "정확하게 엉뚱한 자리"를 쓴다.
            guard let caret = offsets.firstIndex(of: text.selection.location) else { return nil }

            self.characters = characters
            self.offsets = offsets
            self.caret = caret
            self.characterCount = text.characterCount
            self.reachesDocumentStart = text.windowRange.location == 0
            self.reachesDocumentEnd = text.windowRange.upperBound == text.characterCount
        }

        var count: Int { characters.count }

        /// 절대 오프셋 → 문자 인덱스. **경계 위가 아니면 `nil`** 이다 — 산출이 `offsets`
        /// 원소만 경유한다는 불변식의 유일한 조회 창구다.
        func index(of offset: Int) -> Int? { offsets.firstIndex(of: offset) }

        /// 절대 오프셋 두 개 → `Span`. 호출자는 양 끝이 `offsets`의 원소이거나 문서 경계
        /// 상수(`0`·`characterCount`)임을 보장한다. **비면 `.invalid`** — 0폭 편집은
        /// 오퍼레이터만 나가는 조용한 오동작이라 여기서 접는다.
        static func span(from lower: Int, to upper: Int) -> Span {
            guard lower < upper else { return .invalid }
            return .range(NSRange(location: lower, length: upper - lower))
        }

        /// 인덱스 스텝을 삽입 위치로. `Span`과 달리 **접지 않는다**(위 `Insertion` doc).
        func insertion(_ step: Step) -> Insertion {
            guard case .index(let index) = step else { return .unproven }
            return .at(offsets[index])
        }

        func result(_ step: Step) -> Target {
            switch step {
            case .invalid: return .invalid
            case .unproven: return .unproven
            case .index(let index):
                return index == caret ? .invalid : .caret(offsets[index])
            }
        }

        // MARK: 문자 술어

        /// 줄 종결자 — `\r\n`(Swift에서 한 `Character`)·`\n`·`\r`·U+2028·U+2029.
        /// `\n` 단독 스캔은 `\r\n` 문서에서 떠돌이 `\r`를 남긴다.
        static func isLineTerminator(_ character: Character) -> Bool {
            switch character {
            case "\r\n", "\n", "\r", "\u{2028}", "\u{2029}": return true
            default: return false
            }
        }

        /// 줄 안의 공백 — 종결자는 여기 들어가지 않는다.
        static func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }

        /// 런 클래스. 종결자는 어느 런에도 속하지 않아 `nil`이다.
        static func runClass(_ character: Character) -> RunClass? {
            if isLineTerminator(character) { return nil }
            if isBlank(character) { return .blank }
            guard let ascii = character.asciiValue else {
                // **비ASCII는 전부 keyword** — CJK 문서의 `w`가 성립하는 지점이다.
                return .keyword
            }
            let isKeyword =
                (ascii >= 0x30 && ascii <= 0x39) || (ascii >= 0x41 && ascii <= 0x5A)
                || (ascii >= 0x61 && ascii <= 0x7A) || ascii == 0x5F
            return isKeyword ? .keyword : .punctuation
        }

        func isTerminator(at index: Int) -> Bool {
            index >= 0 && index < count && Self.isLineTerminator(characters[index])
        }

        // MARK: 모션

        // 무인자 형태는 캐럿에서 출발하는 얇은 위임이다 — Visual 확장은 캐럿이 아니라
        // **포커스 끝**에서 같은 모션을 적용해야 해서 `from:` 형태가 본체다.

        /// `h` — 줄 시작(문서 시작 포함)에서는 Vim이 no-op이다.
        func charLeft() -> Step { charLeft(from: caret) }

        func charLeft(from index: Int) -> Step {
            if index == 0 { return reachesDocumentStart ? .invalid : .unproven }
            if isTerminator(at: index - 1) { return .invalid }
            return .index(index - 1)
        }

        /// `l`·`a` — 줄 끝(문서 끝 포함)에서는 Vim이 no-op이다.
        func charRight() -> Step { charRight(from: caret) }

        func charRight(from index: Int) -> Step {
            if index == count { return reachesDocumentEnd ? .invalid : .unproven }
            if isTerminator(at: index) { return .invalid }
            return .index(index + 1)
        }

        /// `0` — 현재 논리 줄의 시작.
        func lineStart() -> Step { lineStartIndex(from: caret) }

        /// `$`·`A` — 현재 논리 줄의 끝(종결자 앞, 마지막 줄이면 문서 끝).
        func lineEnd() -> Step { lineEndIndex(from: caret) }

        /// `^` — 줄 시작부터 첫 비공백. 줄이 전부 공백이면 줄 끝이다(Vim과 같다).
        func lineFirstNonBlank() -> Step { lineFirstNonBlank(from: caret) }

        func lineFirstNonBlank(from origin: Int) -> Step {
            let start = lineStartIndex(from: origin)
            guard case .index(let index0) = start else { return start }
            var index = index0
            while index < count, !Self.isLineTerminator(characters[index]),
                Self.isBlank(characters[index])
            {
                index += 1
            }
            // 창 끝에서 멈췄다면 그 줄이 정말 거기서 끝나는지 알 수 없다.
            if index == count, !reachesDocumentEnd { return .unproven }
            return .index(index)
        }

        /// `w` — 현재 런을 지나 공백·개행을 건너뛴 다음 단어의 시작. 빈 줄도 정지 지점이다.
        func wordForward() -> Step { wordForward(from: caret) }

        func wordForward(from origin: Int) -> Step {
            if origin == count { return reachesDocumentEnd ? .invalid : .unproven }
            var index = origin
            // 비공백 위에서는 그 런의 끝까지 먼저 나간다.
            if let own = Self.runClass(characters[index]), own != .blank {
                while index < count, Self.runClass(characters[index]) == own { index += 1 }
                if index == count, !reachesDocumentEnd { return .unproven }
            }
            // 공백·개행 건너뛰기 — 개행 뒤에 곧바로 개행이 오면 그 빈 줄이 정지 지점이다.
            while index < count {
                let character = characters[index]
                if !Self.isLineTerminator(character), !Self.isBlank(character) { break }
                if Self.isLineTerminator(character), isTerminator(at: index + 1) {
                    return .index(index + 1)
                }
                index += 1
            }
            if index == count, !reachesDocumentEnd { return .unproven }
            return .index(index)
        }

        /// `b` — 뒤쪽 공백·개행을 건너뛴 다음 그 런의 시작.
        func wordBackward() -> Step { wordBackward(from: caret) }

        func wordBackward(from origin: Int) -> Step {
            if origin == 0 { return reachesDocumentStart ? .invalid : .unproven }
            var index = origin - 1
            while index >= 0 {
                let character = characters[index]
                if !Self.isLineTerminator(character), !Self.isBlank(character) { break }
                // 빈 줄(종결자 바로 앞이 또 종결자)은 `w`와 대칭으로 정지 지점이다.
                if Self.isLineTerminator(character), index > 0, isTerminator(at: index - 1),
                    index < origin
                {
                    return .index(index)
                }
                index -= 1
            }
            if index < 0 { return reachesDocumentStart ? .index(0) : .unproven }
            guard let own = Self.runClass(characters[index]) else { return .unproven }
            while index > 0, Self.runClass(characters[index - 1]) == own { index -= 1 }
            // 런이 창 왼쪽 끝에 닿았다면 더 왼쪽으로 이어질 수 있다.
            if index == 0, !reachesDocumentStart { return .unproven }
            return .index(index)
        }

        /// `e` — 단어 마지막 글자 **뒤**(캐럿 모델 = `Opt-→` 자리). 이미 그 자리에 커서가 있으면
        /// (= 캐럿이 런의 마지막 글자 위) Vim처럼 다음 단어의 끝으로 뛴다.
        func wordEndForward() -> Step { wordEndForward(from: caret) }

        func wordEndForward(from origin: Int) -> Step {
            if origin == count { return reachesDocumentEnd ? .invalid : .unproven }
            var index = origin
            // 런 안쪽이면 이 런의 끝, 단 마지막 글자 위면 다음 런으로 넘어간다.
            if let own = Self.runClass(characters[index]), own != .blank {
                var end = index
                while end < count, Self.runClass(characters[end]) == own { end += 1 }
                if end == count, !reachesDocumentEnd { return .unproven }
                if end > origin + 1 { return .index(end) }
                index = end
            }
            // 공백·개행을 건너뛴 다음 런의 끝.
            while index < count,
                Self.isLineTerminator(characters[index]) || Self.isBlank(characters[index])
            {
                index += 1
            }
            if index == count { return reachesDocumentEnd ? .index(count) : .unproven }
            guard let next = Self.runClass(characters[index]) else { return .unproven }
            while index < count, Self.runClass(characters[index]) == next { index += 1 }
            if index == count, !reachesDocumentEnd { return .unproven }
            return .index(index)
        }

        /// 모션 1스텝을 임의 원점에서 — Visual 확장이 포커스 끝에서 같은 표를 쓰기 위한 창구다.
        private func step(_ motion: Motion, from origin: Int) -> Step {
            switch motion {
            case .charLeft: return charLeft(from: origin)
            case .charRight, .charRightForAppend: return charRight(from: origin)
            case .wordForward: return wordForward(from: origin)
            case .wordBackward: return wordBackward(from: origin)
            case .wordEndForward: return wordEndForward(from: origin)
            case .lineStart: return lineStartIndex(from: origin)
            case .lineFirstNonBlank: return lineFirstNonBlank(from: origin)
            case .lineEnd, .lineEndForAppend: return lineEndIndex(from: origin)
            case .documentStart: return reachesDocumentStart ? .index(0) : .unproven
            case .documentEnd: return reachesDocumentEnd ? .index(count) : .unproven
            case .lineUp, .lineDown: return .unproven
            }
        }

        // MARK: 편집 범위

        /// `.motion` 범위 — 캐럿과 목표 사이. 특례가 없는 모션은 스텝 반복 + 클램프다.
        func motionSpan(_ motion: Motion, _ count: Int) -> Span {
            switch motion {
            case .charRight:
                return charRightSpan(count)
            case .charLeft:
                return charLeftSpan(count)
            case .wordForward:
                return wordForwardSpan(count)
            case .wordEndForward, .wordBackward:
                return repeatedSpan(count) { step(motion, from: $0) }
            case .lineStart, .lineEnd, .lineFirstNonBlank:
                // 멱등이라 카운트를 무시한다 — keyboard도 같은 스트로크의 반복이라 답이 같다.
                return repeatedSpan(1) { step(motion, from: $0) }
            case .documentStart:
                return Self.span(from: 0, to: offsets[caret])
            case .documentEnd:
                return Self.span(from: offsets[caret], to: characterCount)
            case .lineUp, .lineDown, .charRightForAppend, .lineEndForAppend:
                // 줄 모션은 `.linewiseMotion`으로만 오고, append 2종은 편집 범위에 오지 않는다.
                return .unproven
            }
        }

        /// 스텝을 `count`회 적용하고 캐럿과의 구간을 낸다.
        ///
        /// **클램프가 Vim 동작이다** — 남은 것이 카운트보다 적으면 있는 만큼 간다(실측:
        /// 2자 남은 자리의 `d5l`은 2자, 위가 1줄인 `5dk`는 1줄+현재 줄). 한 칸도 못 가는
        /// 경우만 무효이며, 그 판정은 `span(from:to:)`의 "비면 `.invalid`"가 대신한다.
        private func repeatedSpan(_ count: Int, _ step: (Int) -> Step) -> Span {
            var index = caret
            for _ in 0..<max(count, 1) {
                switch step(index) {
                case .unproven: return .unproven
                case .invalid: return boundedSpan(index)
                case .index(let next):
                    if next == index { return boundedSpan(index) }
                    index = next
                }
            }
            return boundedSpan(index)
        }

        /// 캐럿과 도달 인덱스 사이 — 방향 무관이고, 같으면 `.invalid`(Vim no-op)다.
        private func boundedSpan(_ index: Int) -> Span {
            Self.span(from: offsets[min(index, caret)], to: offsets[max(index, caret)])
        }

        /// `x`·`dl` — 줄 끝은 블록 커서 모델(엣지 1: 마지막 글자를 지운다), 그 외는 줄에
        /// 남은 글자 수로 클램프한다. 빈 줄에는 지울 글자가 없어 무효다.
        private func charRightSpan(_ count: Int) -> Span {
            var index = caret
            while index - caret < count, index < self.count, !isTerminator(at: index) { index += 1 }
            // 카운트를 못 채운 채 창 끝에서 멈췄다면 그 줄이 정말 거기서 끝나는지 알 수 없다.
            if index == self.count, index - caret < count, !reachesDocumentEnd { return .unproven }
            if index > caret { return Self.span(from: offsets[caret], to: offsets[index]) }
            guard case .index(let start) = lineStartIndex(from: caret) else { return .unproven }
            return caret > start ? Self.span(from: offsets[caret - 1], to: offsets[caret]) : .invalid
        }

        /// `dh`·`X` — 엣지 1의 대칭이되 **방향은 뒤집지 않는다**. Vim의 `h`는 앞 줄로 넘어가지
        /// 않으므로 줄 시작에서는 그냥 무효다(문서 시작도 그 특수 경우).
        private func charLeftSpan(_ count: Int) -> Span {
            var index = caret
            while caret - index < count, index > 0, !isTerminator(at: index - 1) { index -= 1 }
            if index == 0, caret - index < count, !reachesDocumentStart { return .unproven }
            return Self.span(from: offsets[index], to: offsets[caret])
        }

        /// `dw` — 마지막으로 지나간 단어가 줄에서 끝나면 **개행을 넘지 않는다**. Vim 실측:
        /// `"foo bar\nbaz"`의 `bar`에서 `dw`는 `bar`만 지우고, 뒤 공백이 있으면 줄 끝까지
        /// 지운다. 카운트가 있으면 마지막 스텝에만 걸린다(`d2w`는 줄을 넘는다 — 실측).
        private func wordForwardSpan(_ count: Int) -> Span {
            var index = caret
            for _ in 0..<max(count, 1) {
                switch wordForward(from: index) {
                case .unproven: return .unproven
                case .invalid: return clampedForwardSpan(index)
                case .index(let next):
                    if next == index { return clampedForwardSpan(index) }
                    index = next
                }
            }
            return clampedForwardSpan(index)
        }

        /// 목표 직전이 (줄 안 공백을 건너뛰면) 줄 종결자면 그 종결자 앞으로 되돌린다.
        private func clampedForwardSpan(_ target: Int) -> Span {
            var scan = target - 1
            while scan >= 0, Self.isBlank(characters[scan]) { scan -= 1 }
            let end = scan >= 0 && isTerminator(at: scan) ? scan : target
            return Self.span(from: offsets[caret], to: offsets[end])
        }

        /// `cw` — Vim은 **커서가 놓인 런의 끝까지만** 바꾼다(공백 위면 그 공백 런만).
        /// 캐럿이 줄 끝이면 커서는 마지막 글자 위이므로 그 한 글자다.
        /// `EditKeyMapper.changeWordRefinement`와 같은 답이며, 진짜 `ce`·`de`는 여기 오지 않는다.
        func changeWordSpan() -> Span {
            if caret < count, !isTerminator(at: caret) {
                guard let own = Self.runClass(characters[caret]) else { return .unproven }
                var end = caret
                while end < count, Self.runClass(characters[end]) == own { end += 1 }
                if end == count, !reachesDocumentEnd { return .unproven }
                return Self.span(from: offsets[caret], to: offsets[end])
            }
            if caret == count, !reachesDocumentEnd { return .unproven }
            // 줄 끝(문서 끝 포함) — 직전 글자 하나. 빈 줄·빈 문서면 바꿀 글자가 없다.
            guard caret > 0, !isTerminator(at: caret - 1) else { return .invalid }
            return Self.span(from: offsets[caret - 1], to: offsets[caret])
        }

        /// `iw` — 캐럿이 놓인 런 전체. 줄 끝이면 직전 글자의 런이다(줄 끝 커서 모델).
        /// 2자 이상의 공백·구두점 런까지 정확해져 무상태 시퀀스의 마지막 엣지가 닫힌다.
        func innerWordSpan() -> Span {
            var index = caret
            if index == count || isTerminator(at: index) {
                if index == count, !reachesDocumentEnd { return .unproven }
                guard index > 0, !isTerminator(at: index - 1) else { return .invalid }
                index -= 1
            }
            guard let own = Self.runClass(characters[index]) else { return .invalid }
            var lower = index
            while lower > 0, Self.runClass(characters[lower - 1]) == own { lower -= 1 }
            if lower == 0, !reachesDocumentStart { return .unproven }
            var upper = index + 1
            while upper < count, Self.runClass(characters[upper]) == own { upper += 1 }
            if upper == count, !reachesDocumentEnd { return .unproven }
            return Self.span(from: offsets[lower], to: offsets[upper])
        }

        /// 논리 줄 범위 — 위 `above`줄 + 현재 줄 + 아래 `below`줄.
        ///
        /// **모션 성분이 한 줄도 못 가면 무효**이고 그 외에는 클램프다(Vim 실측: 마지막 줄의
        /// `dj`·`2dd`는 무동작, 남은 줄이 카운트보다 적은 `5dk`·`9dd`는 있는 만큼).
        func linewiseSpan(above: Int, below: Int, op: VimAction.Operator) -> Span {
            guard case .index(var first) = lineStartIndex(from: caret) else { return .unproven }
            var moved = 0
            while moved < above, first > 0 {
                guard case .index(let previous) = lineStartIndex(from: first - 1) else {
                    return .unproven
                }
                first = previous
                moved += 1
            }
            if moved < above, first == 0, !reachesDocumentStart { return .unproven }
            if above > 0, moved == 0 { return .invalid }

            guard case .index(var last) = lineEndIndex(from: caret) else { return .unproven }
            moved = 0
            while moved < below, last < count {
                guard case .index(let next) = lineEndIndex(from: last + 1) else { return .unproven }
                last = next
                moved += 1
            }
            if below > 0, moved == 0 { return .invalid }
            return spanOverLines(from: first, lastLineEnd: last, op: op)
        }

        /// `dgg`/`ygg`/`cgg` — 문서 시작부터 현재 줄까지. 시작이 상수 0이라 창과 무관하게 선다.
        func spanToDocumentStart(op: VimAction.Operator) -> Span {
            guard case .index(let end) = lineEndIndex(from: caret) else { return .unproven }
            guard op != .change else { return Self.span(from: 0, to: offsets[end]) }
            return Self.span(from: 0, to: end < count ? offsets[end + 1] : characterCount)
        }

        /// `dG`/`yG`/`cG` — 현재 줄부터 문서 끝까지. 끝이 상수라 창과 무관하게 선다.
        /// delete와 change가 같은 답인 것은 문서 끝에 반올림할 종결자가 없어서다.
        func spanToDocumentEnd(op: VimAction.Operator) -> Span {
            guard case .index(let start) = lineStartIndex(from: caret) else { return .unproven }
            return Self.span(from: offsets[start], to: characterCount)
        }

        /// 줄 시작 ~ 마지막 줄 끝을 오퍼레이터 반올림으로 구간화한다.
        ///
        /// delete·yank는 마지막 줄의 종결자를 포함하고, change는 줄을 남긴다(`cc`).
        ///
        /// **종결자 없이 문서가 끝나면 앞 개행을 흡수하지 않는다** — 그러면 빈 줄이 안 남아
        /// Vim의 버퍼 시맨틱과 같아지지만, 우리 레지스터는 OS 클립보드의 **생 텍스트**라
        /// 잘라낸 내용이 `"\n마지막줄"`이 된다(구분자가 앞에 붙는다). Vim의 레지스터는
        /// 구조체(linewise 플래그 + 줄 텍스트)라 이 문제가 없지만 우리는 그 모양을 표현할 수
        /// 없고, 그 클립보드는 이어지는 `p`(빈 줄 하나 추가)·외부 앱 붙여넣기·wise 휴리스틱
        /// (끝 글자만 보므로 charwise로 오판) 전부에서 틀린다. 빈 줄 1개가 남는 편차를 택한다
        /// (keyboard와 같은 답, `20260809_no-leading-newline-absorb-clipboard-is-the-register.md`).
        private func spanOverLines(
            from first: Int, lastLineEnd last: Int, op: VimAction.Operator
        ) -> Span {
            guard op != .change else {
                return Self.span(from: offsets[first], to: offsets[last])
            }
            if last < count { return Self.span(from: offsets[first], to: offsets[last + 1]) }
            return Self.span(from: offsets[first], to: characterCount)
        }

        /// 문서가 줄 종결자 없이 끝나는가 — **증명 못 하면 `false`** 다(= 개행을 합성하지 않음
        /// = keyboard 패리티). 창이 문서 끝에 닿지 않으면 알 수 없는 사실이다.
        private var endsWithoutTerminator: Bool {
            reachesDocumentEnd && count > 0 && !isTerminator(at: count - 1)
        }

        // MARK: 하이브리드 삽입 위치

        /// charwise `p` — 한 글자 오른쪽. **줄 끝이면 캐럿 그대로**다: Vim 커서는 마지막 글자
        /// 위라 "커서 뒤"가 곧 지금 캐럿이고, 한 칸 밀면 붙여넣기가 다음 줄로 넘어간다.
        func charwisePasteAfter() -> Insertion {
            if caret == count { return reachesDocumentEnd ? .at(offsets[caret]) : .unproven }
            if isTerminator(at: caret) { return .at(offsets[caret]) }
            return .at(offsets[caret + 1])
        }

        /// linewise `p` — 다음 줄 시작. 마지막 줄(뒤 개행 없음)이면 구분 개행이 없어
        /// `.appendingLine`이다(문서 끝 캐럿 + 게시 `Return`).
        ///
        /// **종결자를 못 찾은 채 문서 끝에 닿은 것은 두 모양을 뭉친다** — 문서가 종결자로
        /// 끝나면 캐럿은 마지막 종결자 **뒤**(빈 마지막 줄)이고 구분 개행이 이미 있으므로 그
        /// 자리가 곧 삽입점이다. 거기서 `Return`을 합성하면 빈 줄이 하나 더 생겨 keyboard
        /// 경로보다 나빠진다(`"l1\nl2\n"`의 마지막 줄 `dd` 뒤 `p`가 정확히 이 자리다).
        func linewisePasteAfter() -> Insertion {
            guard case .index(let end) = lineEndIndex(from: caret) else { return .unproven }
            if end < count { return .at(offsets[end + 1]) }
            return endsWithoutTerminator ? .appendingLine(characterCount) : .at(characterCount)
        }

        // MARK: Visual 범위

        /// `v` 진입 — 캐럿이 놓인 글자 하나(inclusive). 줄 끝이면 Vim 커서는 마지막 글자 위라
        /// 그 글자이고, 빈 줄은 잡을 글자가 없어 무효(호출자가 `.unproven`으로 강등)다.
        func charwiseEntry() -> Selection {
            let focus: Int
            if caret < count, !isTerminator(at: caret) {
                focus = caret
            } else if caret == count, !reachesDocumentEnd {
                return .unproven
            } else {
                guard caret > 0, !isTerminator(at: caret - 1) else { return .invalid }
                focus = caret - 1
            }
            return selection(
                Self.span(from: offsets[focus], to: offsets[inclusiveEnd(focus)]),
                anchor: offsets[focus], column: focusColumn(at: focus))
        }

        /// `V` 진입 — 캐럿 논리 줄 전체(종결자 포함, 마지막 줄이면 문서 끝까지).
        ///
        /// 열은 `charwiseEntry`와 **같은 함수**로 센다 — 절대 오프셋 뺄셈은 UTF-16 델타라
        /// 이모지 앞의 캐럿에서 열이 부풀고(그 값이 `V`→`v` 복원의 포커스가 된다), grapheme
        /// 경계 불변식은 결과가 `offsets` 원소이기만 하면 통과시켜 못 잡는다. 이 값이 `V`→`v`
        /// 복원의 포커스 열이고, ⑤가 `V` 세션의 열 이동을 전부 스킵하므로 Vim 커서 열과
        /// 실제로 일치한다(실측 `llVjv`).
        func linewiseEntry() -> Selection {
            guard case .range(let range) = lineSpan(from: caret, to: caret) else {
                return .unproven
            }
            return .range(range, anchor: range.location, column: focusColumn(at: caret))
        }

        /// charwise 확장 — 포커스 **글자** 위에서 모션을 적용하고 앵커와 합친다.
        ///
        /// 포커스가 선택 끝이 아니라 그 한 글자 왼쪽인 것이 요점이다: Vim 커서는 선택된
        /// 마지막 글자 **위**에 있고, `l`이 선택을 한 글자 넓히려면 거기서 출발해야 한다.
        func charwiseExtension(
            _ motion: Motion, anchor: VisualAnchorState, in text: FocusedText
        ) -> Selection {
            guard let anchorIndex = index(of: anchor.anchor) else { return .unproven }
            // 절대 모션은 끝점이 상수라 포커스도 창도 필요 없다.
            switch motion {
            case .documentStart:
                return selection(
                    Self.span(from: 0, to: offsets[inclusiveEnd(anchorIndex)]),
                    anchor: anchor.anchor, column: 0)
            case .documentEnd:
                // 착지가 문서 끝이라 열을 세려면 마지막 줄 시작이 필요한데 창이 거기 못 닿는다 —
                // 모르는 것은 모른다고 남긴다(이어지는 `j`/`k`가 정직하게 스킵된다).
                return selection(
                    Self.span(from: offsets[anchorIndex], to: characterCount),
                    anchor: anchor.anchor, column: nil)
            default:
                break
            }
            guard let focus = focusIndex(anchor: anchor, in: text) else { return .unproven }
            let moved: Step
            /// `j`/`k`만 값이 있다 — 물려받는 희망 열이다.
            let inherited: Int?
            switch motion {
            case .lineUp, .lineDown:
                // **`j`/`k`가 위임이 아닌 것이 AX charwise 세션의 차이다.** 위임 사유(희망 열
                // 소실)를 상태가 열을 들어 없앤다. 모르면 근사하지 않고 정직하게 스킵한다.
                guard let desired = anchor.desiredColumn else { return .unproven }
                moved = movedFocus(from: focus, down: motion == .lineDown, column: desired)
                inherited = desired
            default:
                moved = step(motion, from: focus)
                inherited = nil
            }
            switch moved {
            case .unproven: return .unproven
            case .invalid: return .invalid
            case .index(let target):
                // **커서 자리로 정규화하는 것이 먼저다.** `e`의 목표는 캐럿 모델에서 "마지막
                // 글자 **뒤**"라 커서는 그 한 칸 왼쪽이고, 방향 판정과 후진 하한이 그것을
                // 되돌리지 않으면 후진형 `ve`가 커서 글자를 선택에서 빠뜨린다(전진형만 `end`
                // 보정으로 우연히 맞았다).
                let focusTarget = Self.landsPastCharacter(motion) ? target - 1 : target
                let column: Int?
                if let inherited {
                    column = inherited
                } else if Self.sticksToLineEnd(motion) {
                    column = FocusedTextOffsets.lineEndColumn
                } else {
                    column = focusColumn(at: focusTarget)
                }
                return selection(
                    spanBetween(anchorIndex, focusTarget), anchor: anchor.anchor, column: column)
            }
        }

        /// 캐럿 모델에서 목표가 커서 자리가 아니라 **그 다음**인 모션 — `e` 하나다.
        ///
        /// `$`가 여기 없는 것이 Vim 실측이다: 비-마지막 줄의 `v$`는 레지스터가 `"abcdef\n"`
        /// (개행 포함)이라 커서가 종결자 **위**이고, 그래서 아래 `inclusiveEnd`를 지난다.
        private static func landsPastCharacter(_ motion: Motion) -> Bool {
            motion == .wordEndForward
        }

        /// 앵커와 포커스를 잇는 inclusive 범위 — **큰 쪽 끝을 한 글자 더 문다.**
        ///
        /// 확장과 `V`→`v` 복원이 같은 함수를 지나는 것이 계약이다: 방향 판정과 끝 보정이
        /// 한 몸이라 갈라 두면 한쪽만 고쳐지는 자리다(후진형 `ve`가 정확히 그랬다).
        private func spanBetween(_ anchor: Int, _ focus: Int) -> Span {
            anchor <= focus
                ? Self.span(from: offsets[anchor], to: offsets[inclusiveEnd(focus)])
                : Self.span(from: offsets[focus], to: offsets[inclusiveEnd(anchor)])
        }

        /// 이후 `j`/`k`가 줄 길이와 무관하게 줄 끝에 붙는 모션 — Vim curswant MAXCOL이다
        /// (실측 `v$j`가 다음 줄의 개행까지 문다).
        private static func sticksToLineEnd(_ motion: Motion) -> Bool {
            motion == .lineEnd || motion == .lineEndForAppend
        }

        /// linewise 확장 — 포커스 **줄**을 옮기고 앵커 줄과 합친다. 희망 열은 그대로 물려
        /// `V`→`v` 복원의 원천으로 남는다.
        ///
        /// `j`/`k`가 여기서는 위임이 아니다: 위임 사유가 희망 열 소실인데 `V` 세션에는 열이
        /// 없어 사유 자체가 성립하지 않는다.
        func linewiseExtension(
            _ motion: Motion, anchor: VisualAnchorState, in text: FocusedText
        ) -> Selection {
            selection(
                linewiseExtendSpan(motion, anchor: anchor, in: text), anchor: anchor.anchor,
                column: anchor.desiredColumn)
        }

        /// ⑥ `v`→`V` — 선택이 걸친 논리 줄 전체. 새 논리 앵커는 **앵커 줄 시작**이라 범위의
        /// 끝점이 아니다(후진형에서는 범위 한가운데다) — `Selection`이 앵커를 함께 내는 이유다.
        func roundedToLines(anchor: VisualAnchorState, in text: FocusedText) -> Selection {
            guard anchor.wise == .charwise, let anchorIndex = index(of: anchor.anchor),
                let focus = focusIndex(anchor: anchor, in: text),
                case .index(let anchorLine) = lineStartIndex(from: anchorIndex)
            else { return .unproven }
            return selection(
                lineSpan(from: anchorIndex, to: focus), anchor: offsets[anchorLine],
                column: anchor.desiredColumn)
        }

        /// ⑦ `V`→`v` — 원래 캐럿 P와 포커스 줄의 희망 열을 잇는다. Vim은 `V` 세션에서도 커서
        /// 열을 보존하므로 열이 곧 포커스이고(실측 `llVjv`·`llvjVv`), keyboard ⑦의 열 근사·
        /// 상한 32·페이싱이 전부 필요 없다(범위 1회 쓰기).
        func restoredToCharacters(anchor: VisualAnchorState, in text: FocusedText) -> Selection {
            guard anchor.wise == .linewise, let caret = anchor.originalCaret,
                let column = anchor.desiredColumn, let caretIndex = index(of: caret),
                let focusLine = focusIndex(anchor: anchor, in: text),
                case .index(let lineStart) = lineStartIndex(from: focusLine),
                case .index(let focus) = focusOnLine(start: lineStart, column: column)
            else { return .unproven }
            return selection(spanBetween(caretIndex, focus), anchor: caret, column: column)
        }

        /// `Span` + 상태 재료 → `Selection`. 범위가 아닌 결과는 그대로 옮긴다.
        private func selection(_ span: Span, anchor: Int, column: Int?) -> Selection {
            switch span {
            case .invalid: return .invalid
            case .unproven: return .unproven
            case .range(let range): return .range(range, anchor: anchor, column: column)
            }
        }

        /// 포커스의 **열**(줄 시작으로부터의 문자 수) — 희망 열의 원천이다. 줄 시작이 창 밖이면
        /// `nil`(모름)이고, 그때 이어지는 `j`/`k`는 정직한 스킵이 된다.
        private func focusColumn(at index: Int) -> Int? {
            guard case .index(let start) = lineStartIndex(from: index) else { return nil }
            return index - start
        }

        /// charwise `j`/`k` — 희망 열을 물려 한 줄 위/아래로. Vim은 짧은 줄을 지나도 열을
        /// 복원하므로(실측 `4lvjj`) 이 이동은 열을 바꾸지 않는다.
        private func movedFocus(from origin: Int, down: Bool, column: Int) -> Step {
            switch movedLine(from: origin, down: down) {
            case .invalid: return .invalid
            case .unproven: return .unproven
            case .index(let start): return focusOnLine(start: start, column: column)
            }
        }

        /// 줄 시작 + 희망 열. 열이 줄을 넘으면 **종결자 위**에 선다 — 짧은 줄로 내려온 `vj`가
        /// 그 줄의 개행까지 물어 `d`가 줄을 병합하는 것이 Vim 실측이다(`llvjd` → `abghi`).
        private func focusOnLine(start: Int, column: Int) -> Step {
            guard case .index(let end) = lineEndIndex(from: start) else { return .unproven }
            return .index(start + min(column, end - start))
        }

        private func linewiseExtendSpan(
            _ motion: Motion, anchor: VisualAnchorState, in text: FocusedText
        ) -> Span {
            guard let anchorIndex = index(of: anchor.anchor) else { return .unproven }
            switch motion {
            case .documentStart:
                guard case .index(let end) = lineEndIndex(from: anchorIndex) else {
                    return .unproven
                }
                return Self.span(from: 0, to: end < count ? offsets[end + 1] : characterCount)
            case .documentEnd:
                guard case .index(let start) = lineStartIndex(from: anchorIndex) else {
                    return .unproven
                }
                return Self.span(from: offsets[start], to: characterCount)
            case .lineDown, .lineUp:
                guard let focus = focusIndex(anchor: anchor, in: text) else { return .unproven }
                switch movedLine(from: focus, down: motion == .lineDown) {
                case .unproven: return .unproven
                case .invalid: return .invalid
                case .index(let line): return lineSpan(from: line, to: anchorIndex)
                }
            default:
                // charwise 모션은 호출자가 먼저 걸러낸다.
                return .invalid
            }
        }

        /// 앵커 상태가 가리키는 포커스 위치. 전진형(`.left`)의 선택 끝은 포커스 글자(또는
        /// 포커스 줄의 종결자) **다음**이라 한 칸 되돌린다 — charwise·linewise 공통이다.
        private func focusIndex(anchor: VisualAnchorState, in text: FocusedText) -> Int? {
            switch anchor.side {
            case .left:
                guard let end = index(of: text.selection.upperBound), end > 0 else { return nil }
                return end - 1
            case .right:
                return index(of: text.selection.location)
            }
        }

        /// 포커스 **글자 다음** — **종결자 위의 포커스도 문다.**
        ///
        /// Vim 실측이 근거다: 비-마지막 줄의 `v$`는 레지스터가 `"abcdef\n"`(len 7)이고, 열보다
        /// 짧은 줄로 내려온 `vj`도 그 줄의 개행까지 물어 `d`가 줄을 병합한다. 커서가 줄 끝에
        /// 가상으로 서는 자리이며(curswant ≥ 줄 길이), 문서 끝에는 물 것이 없어 그대로다.
        private func inclusiveEnd(_ index: Int) -> Int { min(index + 1, count) }

        /// 한 줄 위/아래의 줄 시작. 못 가면 `.invalid`(Vim no-op), 창 밖이면 `.unproven`.
        private func movedLine(from origin: Int, down: Bool) -> Step {
            if down {
                guard case .index(let end) = lineEndIndex(from: origin) else { return .unproven }
                guard end < count else { return .invalid }
                return lineStartIndex(from: end + 1)
            }
            guard case .index(let start) = lineStartIndex(from: origin) else { return .unproven }
            guard start > 0 else { return .invalid }
            return lineStartIndex(from: start - 1)
        }

        /// 두 위치가 걸친 논리 줄 전체(마지막 줄의 종결자 포함).
        private func lineSpan(from a: Int, to b: Int) -> Span {
            guard case .index(let start) = lineStartIndex(from: min(a, b)),
                case .index(let end) = lineEndIndex(from: max(a, b))
            else { return .unproven }
            return Self.span(
                from: offsets[start], to: end < count ? offsets[end + 1] : characterCount)
        }

        // MARK: 줄 경계

        private func lineStartIndex(from index: Int) -> Step {
            var scan = index
            while scan > 0 {
                if isTerminator(at: scan - 1) { return .index(scan) }
                scan -= 1
            }
            return reachesDocumentStart ? .index(0) : .unproven
        }

        private func lineEndIndex(from index: Int) -> Step {
            var scan = index
            while scan < count {
                if isTerminator(at: scan) { return .index(scan) }
                scan += 1
            }
            return reachesDocumentEnd ? .index(count) : .unproven
        }
    }
}

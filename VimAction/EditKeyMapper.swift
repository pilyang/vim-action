//
//  EditKeyMapper.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import VimEngine

/// `.edit(Operator, TextRange)` → 합성 키스트로크 시퀀스. `MotionKeyMapper`와 같은 순수 함수이며,
/// CGEvent 변환은 매퍼 밖 게시 직렬 큐 위에서 한다.
///
/// 거의 모든 편집은 한 형태다: **범위를 Shift+모션으로 선택한 뒤 오퍼레이터 1타**.
/// 선택 스트로크는 모션 매핑의 재사용으로 전부 나오므로(`select(_:)`), `w`·`^`의 3타 조합도
/// 추가 규칙 없이 선택 확장으로 성립한다.
///
/// 예외는 Visual의 `.selection` 하나다 — 화면에 선택이 이미 있어 선택 시퀀스가 없고,
/// yank의 collapse도 엔진이 뒤이어 내는 `clearSelection`이 전담한다
/// (`20260728_visual-clear-selection-collapse-left.md`).
///
/// 반환 `nil`은 두 뜻이다: **이 계열에서 미지원**, 또는 **읽기가 증명한 무효**(Vim에서
/// no-op인 조합). 어댑터가 `text: nil`로 되물어 둘을 가르고(`classifyEdit`), 어느 쪽이든
/// 실패가 아니라 스킵+로그다. "빈 배열"과 구분되어야 무로그 삼킴이 생기지 않는다.
///
/// `text`(캐럿 주변 읽기)는 **정확화의 입력일 뿐 실행 조건이 아니다** — `nil`이거나 창이
/// 근거를 못 대면 아래의 무상태 시퀀스가 그대로 나간다. 정확화가 갈리는 것은 읽기 **성공**
/// 경로뿐이고, 그 갈림은 전부 `Refinement`를 거친다.
///
/// 프로파일의 모션 재정의·disable은 `MotionKeyMapper` 조회(`move`/`select`)를 통해 그대로
/// 전파된다 — disable된 모션이 시퀀스의 어느 조각에든 나타나면 `guard let`이 nil을 위로
/// 올려 **편집 전체가** 정직한 스킵이 된다 (부분 시퀀스는 파괴적 실행이라 금지).
nonisolated enum EditKeyMapper {
    static func keyStrokes(
        for op: VimAction.Operator,
        range: VimAction.TextRange,
        family: ElementFamily,
        profile: ResolvedProfile = .empty,
        text: FocusedText? = nil
    ) -> [KeyStroke]? {
        // 계열 판정이 **가장 먼저**다 — `.selection` 조기 반환보다 앞이어야 한다. 뒤에 두면
        // 비텍스트에서도 살아 있는 선택에 `Cmd-X`가 나가는데, Finder에서 그것은 파일 이동이다.
        switch family {
        case .textArea, .textField:
            // **의도된 수렴이다** — TextField 전용 시퀀스를 만들지 않는다. 단일행 필드에서는
            // TextArea 시퀀스가 저절로 같은 결과로 수렴하고(주소창에서 `Shift-↓`는 끝까지
            // 선택된다), 전용 분기는 role 오보고 시 여러 줄 검색창의 `dd` 1줄 삭제를 전체
            // 삭제로 개악한다 (`20260801_textfield-edit-sequences-scrapped.md`).
            break

        case .nonText, .unresolved:
            // 어댑터 게이트가 먼저 걸러 실제로는 도달하지 않는다. 봉쇄를 남기는 것은 게이트를
            // 매퍼로 옮기려는 미래의 변경에 대한 안전판이다
            // (`20260801_non-text-filter-keeps-motion-and-scroll.md`). `.unresolved`가 같은
            // 편인 이유는 게이트와 같다 — 모르는 동안의 편집은 보류다
            // (`20260801_unresolved-window-after-app-switch.md`).
            return nil
        }
        // `.selection`은 계열 분기 **밖**이다: 이미 있는 선택에 대한 `Cmd-X`/`Cmd-C`는
        // TextField에서도 같고, 무엇보다 `apply(_:)`가 yank에 무조건 붙이는 `←`를 피해야 한다.
        if case .selection = range {
            return op == .yank ? [copy] : [cut]
        }
        guard let selection = textAreaSelection(op, range, profile, text),
            let operatorStrokes = apply(op, profile)
        else { return nil }
        return selection + operatorStrokes
    }

    /// 이 범위가 캐럿 주변 읽기를 묻는가 — **묻지 않으면 AX 왕복도 없다**(읽기는 lazy다).
    ///
    /// 어댑터가 이 값을 보고 읽을지 정하므로, 범위 표가 어댑터로 복사되지 않는다. 아래
    /// 정확화와 한 쌍이며, 둘이 갈라지지 않음(= 묻지 않는 범위에서는 `text`가 시퀀스를 바꾸지
    /// 못함)을 테스트가 고정한다 — 갈라지면 정확화가 코드에 있는 채로 영원히 죽는다.
    ///
    /// **넓히는 것은 공짜가 아니다**: 여기 들어오는 범위는 액션마다 AX 왕복 1회를 문다
    /// (Notion 실측 ~7ms). 그래서 `.line`(`dd`)과 `.linewiseMotion(.lineDown)`(`dj`)은 빠져
    /// 있다 — 소프트 랩 논리 줄은 이 읽기로 해소되지 않아 물을 이유가 없다.
    static func consultsFocusedText(_ range: VimAction.TextRange) -> Bool {
        switch range {
        case .motion:
            return true
        case .linewiseMotion(.lineUp, _):  // 엣지 2 — 첫 줄 `dk`
            return true
        case .linewiseMotion(.documentStart, _):  // 엣지 4 — 마지막 줄 `dgg`
            return true
        case .textObject(.word(.inner)):  // 캐럿이 놓인 단어 런
            return true
        default:
            return false
        }
    }

    /// 읽기가 무상태 시퀀스에 대해 증명한 것.
    ///
    /// **`unproven`이 기본값이라는 것이 계약이다** — 모션이나 케이스가 늘어도 증명을 명시적으로
    /// 세우기 전까지는 현행 동작이고, 조용한 억제나 조용한 재조립이 생기지 않는다.
    private enum Refinement {
        /// Vim에서 무효인 조합 — 편집 전체가 정직한 스킵이 된다(선택 스트로크도 나가지 않는다).
        case invalid
        /// 더 정확한 선택 시퀀스. 오퍼레이터 접미는 호출자가 그대로 붙인다.
        case selection([KeyStroke])
        /// 증명하지 못했다 — 현행 무상태 시퀀스로 간다.
        case unproven
    }

    /// `.motion` 범위의 정확화 — 수용 엣지 1·3·5와 `^`가 여기서 갈린다.
    ///
    /// 살아 있는 선택(`length > 0`)이 있으면 전부 `unproven`이다: 우리가 만들 선택이 어디서
    /// 출발할지 증명할 수 없고, 그 선택 자체가 우리가 비동기로 배달한 합성 이벤트의 결과라
    /// 읽기가 낡았을 가능성이 가장 높은 자리다.
    private static func motionRefinement(
        _ motion: Motion, _ isChangeWord: Bool, _ count: Int, _ profile: ResolvedProfile,
        _ text: FocusedText
    ) -> Refinement {
        guard text.selection.length == 0 else { return .unproven }
        switch motion {
        case .charRight:
            return charRightRefinement(count, profile, text)

        case .charLeft:
            return charLeftRefinement(count, profile, text)

        case .wordForward:
            // 엣지 3 — 다음 단어 시작이 없으면 3타(`Opt-→ ×2, Opt-←`)의 마지막 후퇴가 앵커를
            // 지나쳐 **캐럿 왼쪽**을 잡는다. 남은 것이 현재 단어뿐이니 Vim의 `w`도 그 단어
            // 끝에서 멈추고, 그것이 곧 `e`의 1타다 — 카운트와 무관하다(남은 단어가 없으므로).
            //
            // 오프셋만큼 `Shift-→`를 내는 대안을 쓰지 않은 것은 의도다: **읽기는 분기의 근거이지
            // 스트로크 수의 근거가 아니다.** 위치 상대적인 1타는 읽기가 낡아도 반전되지 않는다.
            guard text.provesNoWordStartAhead, let strokes = select(.wordEndForward, profile) else {
                return .unproven
            }
            return .selection(strokes)

        case .wordEndForward:
            if isChangeWord, count == 1 {
                return changeWordRefinement(profile, text)
            }
            // 문서 끝에서 `Opt-→`는 움직이지 않는다 — 0폭이라 오퍼레이터만 나간다.
            return text.isAtDocumentEnd ? .invalid : .unproven

        case .wordBackward:
            return text.isAtDocumentStart ? .invalid : .unproven

        case .lineEnd:
            return text.isAtLineEnd ? .invalid : .unproven

        case .lineStart:
            return text.isAtLineStart ? .invalid : .unproven

        case .lineFirstNonBlank:
            // 전부 공백인 줄에서는 `false`다 — 그 줄의 `^`는 no-op이 아니라 다음 줄까지
            // 넘어가는 별건의 오동작이라, 여기서 억제하면 진짜 편집을 삼킨다.
            return text.isAtLineFirstNonBlank ? .invalid : .unproven

        default:
            return .unproven
        }
    }

    /// 전진 charwise(`x`·`dl`)의 줄 경계 — 수용 엣지 1.
    ///
    /// 줄 끝에서 `Shift-→`는 0폭이 아니라 **개행을 집어** 줄을 병합한다. Vim의 커서는 문자
    /// 위에 있어 그 자리가 곧 "마지막 글자 위"이므로, `x`는 그 글자를 지운다 — 그래서 여기
    /// 한 자리에서만 선택 방향을 뒤집는다. **이 모델 채택을 다른 모션으로 넓히지 않는다**
    /// (`dh`는 아래에서 계속 캐럿 모델이다). 줄이 비어 있으면 지울 글자가 없어 무효다.
    ///
    /// 줄 끝이 아니면 남은 글자 수로 clamp만 한다 — `min`이 카운트로 막혀 있어, 읽기가
    /// 낡았을 때의 최악이 현행 동작(개행까지 집기)을 넘지 않는다.
    private static func charRightRefinement(
        _ count: Int, _ profile: ResolvedProfile, _ text: FocusedText
    ) -> Refinement {
        guard let remaining = text.charactersToLineEnd else { return .unproven }
        guard remaining == 0 else {
            guard remaining < count, let stroke = select(.charRight, profile) else {
                return .unproven
            }
            return .selection(repeated(stroke, remaining))
        }
        guard let before = text.charactersToLineStart else { return .unproven }
        guard before > 0 else { return .invalid }
        guard let stroke = select(.charLeft, profile) else { return .unproven }
        return .selection(stroke)
    }

    /// 후진 charwise(`dh`·`X`)의 줄 경계 — 엣지 1의 대칭이되 **방향은 뒤집지 않는다**.
    /// Vim의 `h`는 앞 줄로 넘어가지 않으므로 줄 시작에서는 그냥 무효다(문서 시작도 그 특수 경우).
    private static func charLeftRefinement(
        _ count: Int, _ profile: ResolvedProfile, _ text: FocusedText
    ) -> Refinement {
        guard let remaining = text.charactersToLineStart else { return .unproven }
        guard remaining > 0 else { return .invalid }
        guard remaining < count, let stroke = select(.charLeft, profile) else { return .unproven }
        return .selection(repeated(stroke, remaining))
    }

    /// `cw` 특례의 정확화 — Vim의 `cw`는 **커서가 놓인 런의 끝까지만** 바꾼다.
    ///
    /// `Shift-Opt-→` 1타는 커서가 런 중간일 때만 그 자리에 맞는다. 커서가 런의 **마지막 글자**
    /// 위면 macOS는 다음 단어 끝까지 건너뛰는데 Vim이 바꾸는 것은 그 한 글자뿐이고, 공백 위면
    /// Vim은 다음 단어 시작까지(= 남은 공백만) 바꾼다 — 두 경우 모두 런의 마지막 글자에서
    /// `Shift-→` 1타로 정확해진다.
    ///
    /// 캐럿이 줄 끝이면 Vim 커서는 그 줄 마지막 글자 위이므로 방향이 뒤집혀 `Shift-←`다.
    /// 이 자리가 문서 끝이면 세션 1의 0폭 억제를 덮어쓴다 — 엣지 1에서 문서 끝 `x`가 억제에서
    /// 재조립으로 바뀐 것과 같은 논리이고, 남는 무효는 **빈 문서**뿐이다.
    ///
    /// **진짜 `ce`·`de`는 여기 들어오지 않는다**: Vim의 `e`는 단어 끝에서 다음 단어 끝으로
    /// 뛰므로 현행 `Shift-Opt-→`가 그쪽에서는 옳다. 그래서 리타깃 여부가 판정에 실린다.
    private static func changeWordRefinement(
        _ profile: ResolvedProfile, _ text: FocusedText
    ) -> Refinement {
        if text.caretIsAtRunEnd, let stroke = select(.charRight, profile) {
            return .selection(stroke)
        }
        if text.runClassBeforeLineEnd != nil, let stroke = select(.charLeft, profile) {
            return .selection(stroke)
        }
        return text.isAtDocumentEnd ? .invalid : .unproven
    }

    /// `iw`의 정확화 — **무효는 내지 않는다**(Vim에서 `iw`가 무효인 자리가 없다).
    ///
    /// 런이 1자면 그 1자가 곧 범위다(공백 1칸·1자 구두점·1자 단어). 캐럿이 줄 끝이면 Vim
    /// 커서는 마지막 글자 위이고, 그 글자가 키워드일 때만 `Shift-Opt-←`가 그 단어 시작으로
    /// 정확히 되돌아간다 — 구두점 런에서는 macOS가 앞 단어까지 넘어가 증명이 서지 않는다.
    private static func innerWordRefinement(
        _ profile: ResolvedProfile, _ text: FocusedText
    ) -> Refinement {
        guard text.selection.length == 0 else { return .unproven }
        if text.caretRunIsSingleCharacter, let stroke = select(.charRight, profile) {
            return .selection(stroke)
        }
        if text.runClassBeforeLineEnd == .keyword, let stroke = select(.wordBackward, profile) {
            return .selection(stroke)
        }
        return .unproven
    }

    /// `.linewiseMotion` 범위의 정확화 — 수용 엣지 2·4.
    private static func linewiseRefinement(
        _ motion: Motion, _ count: Int, _ op: VimAction.Operator, _ profile: ResolvedProfile,
        _ text: FocusedText
    ) -> Refinement {
        guard text.selection.length == 0 else { return .unproven }
        switch motion {
        case .lineUp:
            // 엣지 2 — 위로 갈 줄이 카운트보다 적으면 Vim은 명령 전체를 무효로 친다. 현행
            // 시퀀스는 `↑`가 문서 시작에서 포화한 채 아래로 확장해 **아래 줄을 지운다**.
            guard let above = text.linesAboveCaret else { return .unproven }
            return above < count ? .invalid : .unproven

        case .documentStart where op != .change:
            // 엣지 4 — 마지막 줄에서는 선행 `↓`가 줄 끝으로 포화해 `Cmd-←`가 같은 줄로 되돌아오고,
            // 그래서 마지막 줄이 범위에서 빠진다. `cgg`가 이미 쓰는 "줄 끝에서 위로"가 그 자리의
            // 정답이다 — 새 스트로크 조합이 아니라 기존 조합의 재사용이다.
            guard text.isOnLastLine, let lineEnd = move(.lineEnd, profile),
                let selection = select(.documentStart, profile)
            else { return .unproven }
            return .selection(lineEnd + selection)

        default:
            return .unproven
        }
    }

    /// `cw` 특례 — Vim의 cw는 ce처럼 단어 **끝**까지만 바꾼다 (엔진이 이연한 어댑터 몫).
    /// 선택 시퀀스와 포화 판정이 **같은 함수를 거치는 것이 요점**이다: 한쪽만 리타깃하면
    /// `cw`의 판정이 실제로 나갈 시퀀스와 다른 모션을 보게 된다.
    ///
    /// 리타깃 여부를 함께 돌려주는 것은 `cw`와 진짜 `ce`가 **런 끝에서 갈리기** 때문이다 —
    /// 같은 `wordEndForward`를 받고도 정확화가 달라야 하므로, 그 사실을 여기 말고 다른 데서
    /// 다시 계산하면 두 곳이 갈라진다.
    private static func retargeted(
        _ motion: Motion, for op: VimAction.Operator
    ) -> (motion: Motion, isChangeWord: Bool) {
        guard op == .change, motion == .wordForward else { return (motion, false) }
        return (.wordEndForward, true)
    }

    /// 범위 → 선택 스트로크 (TextArea 계열).
    ///
    /// 정확화는 **범위별로 한 갈래씩**만 얹힌다: 읽기가 증명하면 그 시퀀스를, 아니면 아래의
    /// 무상태 시퀀스를 그대로 쓴다. `consultsFocusedText`가 거짓인 범위에는 `text`를 보는
    /// 자리 자체가 없어야 한다 — 어댑터가 그런 범위에서는 읽지도 않기 때문이다.
    private static func textAreaSelection(
        _ op: VimAction.Operator, _ range: VimAction.TextRange, _ profile: ResolvedProfile,
        _ text: FocusedText?
    ) -> [KeyStroke]? {
        switch range {
        case .motion(let motion, let count):
            let target = retargeted(motion, for: op)
            if let text {
                switch motionRefinement(
                    target.motion, target.isChangeWord, count, profile, text)
                {
                case .invalid: return nil
                case .selection(let strokes): return strokes
                case .unproven: break
                }
            }
            guard let selection = select(target.motion, profile) else { return nil }
            return repeated(selection, count)

        case .line(let count):
            guard let lineStart = move(.lineStart, profile),
                let lines = extendLines(count, op, profile)
            else { return nil }
            return lineStart + lines

        case .linewiseMotion(let motion, let count):
            if let text {
                switch linewiseRefinement(motion, count, op, profile, text) {
                case .invalid: return nil
                case .selection(let strokes): return strokes
                case .unproven: break
                }
            }
            return linewiseMotionSelection(motion, count, op, profile)

        case .textObject(.word(.inner)):
            if let text {
                switch innerWordRefinement(profile, text) {
                case .invalid: return nil
                case .selection(let strokes): return strokes
                case .unproven: break
                }
            }
            // 근사 — 단어 끝을 지나친 뒤 시작으로 복귀해 앵커를 잡고 끝까지 선택한다
            // (`^`와 같은 패턴). 물러나기만 하면 캐럿이 단어 시작일 때 앞 단어를 잡는다.
            // 남는 수용 엣지: 캐럿이 **2자 이상의** 공백·구두점 런 위면 다음 단어를 잡는다
            // (Vim은 그 런). 1자 런과 줄 끝은 위 정확화가 해소한다.
            guard let overshoot = move(.wordEndForward, profile),
                let back = move(.wordBackward, profile),
                let selection = select(.wordEndForward, profile)
            else { return nil }
            return overshoot + back + selection

        default:
            // aw·따옴표·괄호쌍 오브젝트(M5 AX) — 미지원. (`.selection`은 호출자가 먼저 처리한다.)
            // `TextRange`에 exhaustive switch를 걸지 않는 것이 엔진 케이스 추가에 견디는 계약이다.
            return nil
        }
    }

    /// 줄 단위 모션 범위. 절대 모션은 문서 경계에서 비대칭이다: `gg`는 다음 줄 시작에서 위로
    /// 잡아 현재 줄의 개행까지 정확히 가져가지만, `G`는 마지막 줄 아래에 개행이 없어 빈 줄이
    /// 하나 남는다 — Keyboard 전략은 문서 상태를 읽지 못해 감지가 불가하므로 수용한다.
    private static func linewiseMotionSelection(
        _ motion: Motion, _ count: Int, _ op: VimAction.Operator, _ profile: ResolvedProfile
    ) -> [KeyStroke]? {
        switch motion {
        case .lineDown:
            // `dj`는 현재 줄 + 아래 count줄.
            guard let lineStart = move(.lineStart, profile),
                let lines = extendLines(count + 1, op, profile)
            else { return nil }
            return lineStart + lines

        case .lineUp:
            // `dk`는 위 count줄 + 현재 줄 — 맨 위 줄로 올라가 시작점을 잡은 뒤 아래로 확장한다.
            guard let lineStart = move(.lineStart, profile),
                let lineUp = move(.lineUp, profile),
                let lines = extendLines(count + 1, op, profile)
            else { return nil }
            return lineStart + repeated(lineUp, count) + lineStart + lines

        case .documentEnd:
            // delete/change가 같은 시퀀스다 — 남는 빈 줄이 change에서는 곧 정답이다.
            guard let lineStart = move(.lineStart, profile),
                let selection = select(.documentEnd, profile)
            else { return nil }
            return lineStart + selection

        case .documentStart:
            if op == .change {
                guard let lineEnd = move(.lineEnd, profile),
                    let selection = select(.documentStart, profile)
                else { return nil }
                return lineEnd + selection
            }
            guard let lineStart = move(.lineStart, profile),
                let lineDown = move(.lineDown, profile),
                let selection = select(.documentStart, profile)
            else { return nil }
            return lineStart + lineDown + lineStart + selection

        default:
            return nil
        }
    }

    /// linewise 범위의 줄 확장. delete/yank는 개행을 포함해 줄을 통째로 가져가고,
    /// change는 마지막 확장만 줄 끝으로 바꿔 줄 자체는 남긴다 (Vim의 `cc`).
    private static func extendLines(
        _ lines: Int, _ op: VimAction.Operator, _ profile: ResolvedProfile
    ) -> [KeyStroke]? {
        guard let lineDown = select(.lineDown, profile) else { return nil }
        guard op == .change else { return repeated(lineDown, lines) }
        guard let lineEnd = select(.lineEnd, profile) else { return nil }
        return repeated(lineDown, lines - 1) + lineEnd
    }

    /// 선택 후의 오퍼레이터 1타. `change`도 잘라내기다 — 엔진이 이미 Insert로 전이했으므로
    /// 뒤에 붙일 키가 없고, 클립보드에 실리는 것이 v1의 "시스템 클립보드 = 무명 레지스터"
    /// 설계(`p`와의 정합)와도 맞는다. yank만 선택을 소비하지 않아 collapse가 뒤따른다.
    ///
    /// `.selection`은 이 경로를 타지 않는다 — collapse를 `clearSelection`이 전담하므로
    /// 여기서 `←`를 또 붙이면 캐럿이 한 칸 더 밀린다.
    private static func apply(
        _ op: VimAction.Operator, _ profile: ResolvedProfile
    ) -> [KeyStroke]? {
        switch op {
        case .delete, .change:
            return [cut]
        case .yank:
            // 왼쪽 끝으로 붙임 = Vim의 "범위 시작으로 이동". 전진·후진·linewise 공통이다.
            // `char_left` 재정의·disable이 여기에도 미치는 것은 의도다 — collapse 역시
            // "이 앱에서 왼쪽 한 칸"이라는 같은 모션이다.
            guard let collapse = move(.charLeft, profile) else { return nil }
            return [copy] + collapse
        }
    }

    /// 모션 스트로크 그대로 — 선택 **시작점**을 잡는 접두에 쓴다.
    private static func move(_ motion: Motion, _ profile: ResolvedProfile) -> [KeyStroke]? {
        MotionKeyMapper.keyStrokes(for: motion, profile: profile)
    }

    /// 모션을 선택 확장으로 바꾼다 — Visual의 선택 확장과 같은 변환을 공유한다.
    private static func select(_ motion: Motion, _ profile: ResolvedProfile) -> [KeyStroke]? {
        MotionKeyMapper.selectionStrokes(for: motion, profile: profile)
    }

    /// 카운트는 엔진이 두 카운트의 곱으로 접어 전달한다 — 여기서는 반복만 한다.
    private static func repeated(_ strokes: [KeyStroke], _ count: Int) -> [KeyStroke] {
        count > 0 ? Array(repeating: strokes, count: count).flatMap { $0 } : []
    }

    /// 오퍼레이터 키만은 ANSI 키코드다 — 화살표와 달리 레이아웃 의존적이라 QWERTY 계열을
    /// 가정한다 (`20260727_operator-key-ansi-layout-assumption.md`).
    private static let cut = KeyStroke(kVK_ANSI_X, [.maskCommand])
    private static let copy = KeyStroke(kVK_ANSI_C, [.maskCommand])
}

//
//  EditKeyMapper.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import VimActionConfig
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
/// 반환 `nil`은 **이 계열에서 미지원**이라는 뜻이다 — 실패가 아니라 어댑터의 스킵+로그 대상이며,
/// "빈 배열"과 구분되어야 무로그 삼킴이 생기지 않는다.
///
/// 프로파일의 모션 재정의·disable은 `MotionKeyMapper` 조회(`move`/`select`)를 통해 그대로
/// 전파된다 — disable된 모션이 시퀀스의 어느 조각에든 나타나면 `guard let`이 nil을 위로
/// 올려 **편집 전체가** 정직한 스킵이 된다 (부분 시퀀스는 파괴적 실행이라 금지).
nonisolated enum EditKeyMapper {
    static func keyStrokes(
        for op: VimAction.Operator,
        range: VimAction.TextRange,
        family: ElementFamily,
        profile: ResolvedProfile = .empty
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
        guard let selection = textAreaSelection(op, range, profile),
            let operatorStrokes = apply(op, profile)
        else { return nil }
        return selection + operatorStrokes
    }

    /// 범위 → 선택 스트로크 (TextArea 계열).
    private static func textAreaSelection(
        _ op: VimAction.Operator, _ range: VimAction.TextRange, _ profile: ResolvedProfile
    ) -> [KeyStroke]? {
        switch range {
        case .motion(let motion, let count):
            // `cw` 특례 — Vim의 cw는 ce처럼 단어 **끝**까지만 바꾼다 (엔진이 이연한 어댑터 몫).
            let target =
                (op == .change && motion == .wordForward) ? Motion.wordEndForward : motion
            guard let selection = select(target, profile) else { return nil }
            return repeated(selection, count)

        case .line(let count):
            guard let lineStart = move(.lineStart, profile),
                let lines = extendLines(count, op, profile)
            else { return nil }
            return lineStart + lines

        case .linewiseMotion(let motion, let count):
            return linewiseMotionSelection(motion, count, op, profile)

        case .textObject(.word(.inner)):
            // 근사 — 단어 끝을 지나친 뒤 시작으로 복귀해 앵커를 잡고 끝까지 선택한다
            // (`^`와 같은 패턴). 물러나기만 하면 캐럿이 단어 시작일 때 앞 단어를 잡는다.
            // 수용 엣지: 캐럿이 단어 뒤 공백 위면 다음 단어를 잡는다 (Vim은 공백 런).
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

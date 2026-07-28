//
//  EditKeyMapper.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import VimEngine

/// 리졸버가 보고하는 요소 계열 — 같은 편집이라도 계열마다 다른 키 시퀀스가 필요하다
/// (예: `delete(.line)`이 TextArea에서는 줄 선택 후 잘라내기, TextField에서는 `Cmd-A, Delete`).
///
/// 지금은 TextArea 하나뿐이다. 리졸버(focusedRole 캐시)가 붙기 전까지 어댑터가 고정 주입하지만,
/// 테이블 키를 처음부터 `(action, family)`로 둬 계열이 늘 때 시퀀스 표만 확장되게 한다.
nonisolated enum ElementFamily: Sendable {
    case textArea
}

/// `.edit(Operator, TextRange)` → 합성 키스트로크 시퀀스. `MotionKeyMapper`와 같은 순수 함수이며,
/// CGEvent 변환은 매퍼 밖 게시 직렬 큐 위에서 한다.
///
/// 모든 편집은 한 형태다: **범위를 Shift+모션으로 선택한 뒤 오퍼레이터 1타**.
/// 선택 스트로크는 모션 매핑의 재사용으로 전부 나오므로(`select(_:)`), `w`·`^`의 3타 조합도
/// 추가 규칙 없이 선택 확장으로 성립한다.
///
/// 반환 `nil`은 **이 계열에서 미지원**이라는 뜻이다 — 실패가 아니라 어댑터의 스킵+로그 대상이며,
/// "빈 배열"과 구분되어야 무로그 삼킴이 생기지 않는다.
nonisolated enum EditKeyMapper {
    static func keyStrokes(
        for op: VimAction.Operator,
        range: VimAction.TextRange,
        family: ElementFamily
    ) -> [KeyStroke]? {
        switch family {
        case .textArea:
            guard let selection = textAreaSelection(op, range) else { return nil }
            return selection + apply(op)
        }
    }

    /// 범위 → 선택 스트로크 (TextArea 계열).
    private static func textAreaSelection(
        _ op: VimAction.Operator, _ range: VimAction.TextRange
    ) -> [KeyStroke]? {
        switch range {
        case .motion(let motion, let count):
            // `cw` 특례 — Vim의 cw는 ce처럼 단어 **끝**까지만 바꾼다 (엔진이 이연한 어댑터 몫).
            let target =
                (op == .change && motion == .wordForward) ? Motion.wordEndForward : motion
            return repeated(select(target), count)

        case .line(let count):
            return move(.lineStart) + extendLines(count, op)

        case .linewiseMotion(let motion, let count):
            return linewiseMotionSelection(motion, count, op)

        case .textObject(.word(.inner)):
            // 근사 — 단어 끝을 지나친 뒤 시작으로 복귀해 앵커를 잡고 끝까지 선택한다
            // (`^`와 같은 패턴). 물러나기만 하면 캐럿이 단어 시작일 때 앞 단어를 잡는다.
            // 수용 엣지: 캐럿이 단어 뒤 공백 위면 다음 단어를 잡는다 (Vim은 공백 런).
            return move(.wordEndForward) + move(.wordBackward) + select(.wordEndForward)

        default:
            // Visual `.selection`(단계 2), aw·따옴표·괄호쌍 오브젝트(M5 AX) — 미지원.
            // `TextRange`에 exhaustive switch를 걸지 않는 것이 엔진 케이스 추가에 견디는 계약이다.
            return nil
        }
    }

    /// 줄 단위 모션 범위. 절대 모션은 문서 경계에서 비대칭이다: `gg`는 다음 줄 시작에서 위로
    /// 잡아 현재 줄의 개행까지 정확히 가져가지만, `G`는 마지막 줄 아래에 개행이 없어 빈 줄이
    /// 하나 남는다 — Keyboard 전략은 문서 상태를 읽지 못해 감지가 불가하므로 수용한다.
    private static func linewiseMotionSelection(
        _ motion: Motion, _ count: Int, _ op: VimAction.Operator
    ) -> [KeyStroke]? {
        switch motion {
        case .lineDown:
            // `dj`는 현재 줄 + 아래 count줄.
            return move(.lineStart) + extendLines(count + 1, op)

        case .lineUp:
            // `dk`는 위 count줄 + 현재 줄 — 맨 위 줄로 올라가 시작점을 잡은 뒤 아래로 확장한다.
            return move(.lineStart) + repeated(move(.lineUp), count) + move(.lineStart)
                + extendLines(count + 1, op)

        case .documentEnd:
            // delete/change가 같은 시퀀스다 — 남는 빈 줄이 change에서는 곧 정답이다.
            return move(.lineStart) + select(.documentEnd)

        case .documentStart:
            return op == .change
                ? move(.lineEnd) + select(.documentStart)
                : move(.lineStart) + move(.lineDown) + move(.lineStart) + select(.documentStart)

        default:
            return nil
        }
    }

    /// linewise 범위의 줄 확장. delete/yank는 개행을 포함해 줄을 통째로 가져가고,
    /// change는 마지막 확장만 줄 끝으로 바꿔 줄 자체는 남긴다 (Vim의 `cc`).
    private static func extendLines(_ lines: Int, _ op: VimAction.Operator) -> [KeyStroke] {
        guard op == .change else { return repeated(select(.lineDown), lines) }
        return repeated(select(.lineDown), lines - 1) + select(.lineEnd)
    }

    /// 선택 후의 오퍼레이터 1타. `change`도 잘라내기다 — 엔진이 이미 Insert로 전이했으므로
    /// 뒤에 붙일 키가 없고, 클립보드에 실리는 것이 v1의 "시스템 클립보드 = 무명 레지스터"
    /// 설계(`p`와의 정합)와도 맞는다. yank만 선택을 소비하지 않아 collapse가 뒤따른다.
    private static func apply(_ op: VimAction.Operator) -> [KeyStroke] {
        switch op {
        case .delete, .change:
            return [cut]
        case .yank:
            // 왼쪽 끝으로 붙임 = Vim의 "범위 시작으로 이동". 전진·후진·linewise 공통이다.
            return [copy] + move(.charLeft)
        }
    }

    /// 모션 스트로크 그대로 — 선택 **시작점**을 잡는 접두에 쓴다.
    private static func move(_ motion: Motion) -> [KeyStroke] {
        MotionKeyMapper.keyStrokes(for: motion)
    }

    /// 모션을 선택 확장으로 바꾼다. 3타 조합(`w`·`^`)도 앵커가 고정된 채 엔드포인트만
    /// 캐럿처럼 움직이므로 그대로 성립한다 — 그래서 편집 시퀀스에 모션별 특례가 없다.
    private static func select(_ motion: Motion) -> [KeyStroke] {
        MotionKeyMapper.keyStrokes(for: motion).map {
            KeyStroke(Int($0.keyCode), $0.flags.union(.maskShift))
        }
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

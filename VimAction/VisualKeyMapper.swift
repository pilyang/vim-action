//
//  VisualKeyMapper.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import VimEngine

/// Visual 선택 **세션**(진입·확장·wise 전환·이탈) → 합성 키스트로크 시퀀스.
/// `MotionKeyMapper`·`EditKeyMapper`와 같은 순수 함수다.
///
/// 세션 동작만 담당하고, 선택에 오퍼레이터를 적용하는 `.edit(op, .selection)`은
/// `EditKeyMapper`의 몫이다 — 그쪽이 `Cmd-X`/`Cmd-C` 상수와 "오퍼레이터 키로 끝난다"는
/// 불변식을 이미 들고 있다.
///
/// **어댑터는 wise 상태를 들지 않는다**: `extendSelection`은 모션 매핑에 Shift를 얹는 것이
/// 전부이며, linewise 세션의 줄 반올림은 적용하지 않는다. 엔진이 문서화한
/// "범위는 어댑터 상태" 계약으로부터의 의도적 이탈이고, 수용 편차는 결정 문서에 표로 있다
/// (`20260728_visual-extend-stateless-no-linewise-rounding.md`).
///
/// 반환 `nil`은 **미지원**(스킵+로그)이다. 이 매퍼는 빈 배열을 반환하지 않는다 —
/// 세 매퍼 공통으로 "지원 ⟹ 빈 시퀀스 아님"이 불변식이라, 게시할 것이 없는 경우도
/// `nil`(정직한 스킵)이거나 실제 스트로크이거나 둘 중 하나다.
nonisolated enum VisualKeyMapper {
    /// `family`는 아직 쓰이지 않지만 시그니처에 처음부터 둔다 — Visual은 모션과 달리 계열
    /// 불변이 아니다(TextField의 `V`는 `Cmd-←, Shift-↓`가 아니라 `Cmd-A`여야 한다).
    /// 단계 3의 리졸버가 붙을 때 시퀀스 표만 늘리면 되게 하는 것이 이 자리의 목적이다.
    static func keyStrokes(for action: VimAction, family: ElementFamily) -> [KeyStroke]? {
        switch action {
        case .beginSelection(let linewise):
            return linewise ? enterLinewise : enterCharwise

        case .extendSelection(let motion):
            return MotionKeyMapper.selectionStrokes(for: motion)

        case .switchSelectionWise(let linewise):
            // `V`→`v`는 미지원이다 — 줄 반올림은 원래 엔드포인트를 파괴하므로 되돌릴 역연산이
            // 없다. 게시가 없다는 점은 무게시와 같지만, `nil`이라야 스킵 로그에 잡혀
            // 단계 4의 "무로그 삼킴 없음" 판정에 드러난다.
            return linewise ? roundFocusToLine : nil

        case .clearSelection:
            return [collapseLeft]

        default:
            // `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다.
            return nil
        }
    }

    /// `v` — Vim의 charwise Visual은 inclusive라 진입 시점에 커서 문자가 이미 잡혀 있다.
    /// 무게시로 두면 `vd`·`vy`가 빈 선택에 오퍼레이터를 날려 무동작이 되고, 이탈 시
    /// `clearSelection`의 `←`가 접을 선택을 못 찾아 캐럿을 왼쪽으로 표류시킨다
    /// (`20260728_visual-charwise-entry-inclusive-selection.md`).
    private static let enterCharwise = [KeyStroke(kVK_RightArrow, [.maskShift])]

    /// `V` — 현재 줄을 개행까지 통째로. `dd`의 선택 접두와 같은 시퀀스다
    /// (`20260727_linewise-newline-rounding.md`의 delete/yank 반올림과 일관).
    private static let enterLinewise = [
        KeyStroke(kVK_LeftArrow, [.maskCommand]),
        KeyStroke(kVK_DownArrow, [.maskShift]),
    ]

    /// `v`→`V` — 포커스를 다음 줄 시작까지 밀어 **포커스 줄만** 개행까지 포함시킨다.
    /// 앵커는 앱에 박혀 있어 손댈 수 없다(수용 편차). `Shift-↓` 단독이 아닌 이유는 포커스가
    /// 임의의 열에 있기 때문이다 — `↓`는 열을 보존하므로 다음 줄 중간에 떨어진다.
    private static let roundFocusToLine = [
        KeyStroke(kVK_DownArrow, [.maskShift]),
        KeyStroke(kVK_LeftArrow, [.maskShift, .maskCommand]),
    ]

    /// 선택을 왼쪽 끝(= 범위 시작)으로 접는다 — Normal 편집의 yank collapse와 단일 규칙이다
    /// (`20260728_visual-clear-selection-collapse-left.md`).
    private static let collapseLeft = KeyStroke(kVK_LeftArrow)
}

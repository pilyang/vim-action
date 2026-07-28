//
//  MotionKeyMapper.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import VimEngine

/// 합성할 키 한 타 — `(keyCode, flags)`만 담는 값 타입.
///
/// `CGEvent`가 아닌 것이 핵심이다: `CGEvent`는 비-`Sendable`이라 게시 직렬 큐 위에서만
/// 만들 수 있으므로, 매핑 로직은 이벤트 없이 표현·테스트하고 변환은 어댑터가 큐 위에서 한다.
nonisolated struct KeyStroke: Equatable, Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    init(_ keyCode: Int, _ flags: CGEventFlags = []) {
        self.keyCode = CGKeyCode(keyCode)
        self.flags = flags
    }
}

/// `Motion` → 합성 키스트로크 시퀀스. macOS 텍스트 시스템의 표준 캐럿 이동 단축키로
/// 매핑하는 순수 함수다 (화살표 키코드는 레이아웃 무관 고정값이라 레이아웃 이슈가 없다).
///
/// **반환이 배열인 것이 계약이다** — 모션 1개를 키스트로크 N개 조합으로 실행하는 개선
/// (예: `w`를 `Opt-→ Opt-→ Opt-←` 3타로)이 이 테이블의 원소 교체만으로 되게 한다.
/// 어댑터·실행기·테스트는 그대로다.
///
/// Keyboard 전략은 캐럿(문자 사이) 모델이라 macOS에 프리미티브가 없는 곳은 조합·수렴으로
/// 처리한다: `wordForward`·`lineFirstNonBlank`는 3타 조합(단어 끝을 지나친 뒤 시작 복귀),
/// append 전용 모션은 `charRight`·`lineEnd`와 자연 수렴. 정확한 의미는 AX 어댑터의 몫이다
/// (`20260726_motion-keystroke-mapping-contract.md`,
/// `20260726_word-forward-first-nonblank-multi-stroke.md`).
nonisolated enum MotionKeyMapper {
    static func keyStrokes(for motion: Motion) -> [KeyStroke] {
        switch motion {
        case .charLeft:
            return [KeyStroke(kVK_LeftArrow)]
        case .charRight:
            return [KeyStroke(kVK_RightArrow)]
        case .lineUp:
            return [KeyStroke(kVK_UpArrow)]
        case .lineDown:
            return [KeyStroke(kVK_DownArrow)]
        case .wordForward:
            // "다음 단어 시작"이 macOS에 없어 단어 끝을 지나친 뒤 시작으로 복귀
            // (`20260726_word-forward-first-nonblank-multi-stroke.md` — 수용 엣지 포함).
            return [
                KeyStroke(kVK_RightArrow, [.maskAlternate]),
                KeyStroke(kVK_RightArrow, [.maskAlternate]),
                KeyStroke(kVK_LeftArrow, [.maskAlternate]),
            ]
        case .wordBackward:
            return [KeyStroke(kVK_LeftArrow, [.maskAlternate])]
        case .wordEndForward:
            return [KeyStroke(kVK_RightArrow, [.maskAlternate])]
        case .lineStart:
            return [KeyStroke(kVK_LeftArrow, [.maskCommand])]
        case .lineFirstNonBlank:
            // 첫 비공백 개념이 macOS에 없어 줄 시작 → 첫 단어 끝 → 그 시작으로 복귀.
            return [
                KeyStroke(kVK_LeftArrow, [.maskCommand]),
                KeyStroke(kVK_RightArrow, [.maskAlternate]),
                KeyStroke(kVK_LeftArrow, [.maskAlternate]),
            ]
        case .lineEnd:
            return [KeyStroke(kVK_RightArrow, [.maskCommand])]
        case .documentStart:
            return [KeyStroke(kVK_UpArrow, [.maskCommand])]
        case .documentEnd:
            return [KeyStroke(kVK_DownArrow, [.maskCommand])]
        case .charRightForAppend:
            return [KeyStroke(kVK_RightArrow)]
        case .lineEndForAppend:
            return [KeyStroke(kVK_RightArrow, [.maskCommand])]
        }
    }

    /// 같은 모션을 **선택 확장**으로 바꾼다 — 스트로크마다 Shift를 얹는다.
    ///
    /// 앵커는 고정된 채 엔드포인트만 캐럿처럼 움직이므로 `w`·`^`의 3타 조합도 특례 없이
    /// 그대로 성립한다(중간 위치는 관측되지 않는다). 편집의 범위 선택과 Visual의 선택 확장이
    /// 둘 다 이 함수를 쓰는 것이 레이어링의 핵심이다 — **모션 매핑이 개선되면 양쪽이 자동으로
    /// 따라온다**.
    static func selectionStrokes(for motion: Motion) -> [KeyStroke] {
        keyStrokes(for: motion).map { KeyStroke(Int($0.keyCode), $0.flags.union(.maskShift)) }
    }
}

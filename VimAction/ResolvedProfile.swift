//
//  ResolvedProfile.swift
//  VimAction
//

import Carbon.HIToolbox
import CoreGraphics
import VimActionConfig
import VimEngine

/// 실행 경로가 소비하는 프로파일 — `AppProfile`을 **로드 시 1회** 변환해 둔다
/// (`ConfigKeyStroke` → `KeyStroke` 변환을 디스패치마다 하지 않는다).
///
/// `Sendable` 값인 것이 계약이다: 키 입력 시점에 메인에서 스냅샷으로 읽혀
/// 게시 직렬 큐를 건넌다 (`DispatchContext`).
nonisolated struct ResolvedProfile: Equatable, Sendable {
    /// `ConfigOverride`의 앱측 대응 — 시퀀스는 이미 `KeyStroke`다.
    enum Override: Equatable, Sendable {
        /// 키 시퀀스 통째 교체 — 파서 불변식("지원 ⟹ 빈 시퀀스 아님")으로 항상 1개 이상.
        case strokes([KeyStroke])
        /// 이 항목을 쓰는 어휘 전부가 정직한 스킵.
        case disabled

        init(_ override: ConfigOverride) {
            switch override {
            case .strokes(let strokes): self = .strokes(strokes.map(KeyStroke.init))
            case .disabled: self = .disabled
            }
        }
    }

    let name: String?
    /// 이 앱에 **사용자가 선언한** 전략 — 실행 판정이 보는 값은 이것이 아니라 판정과 함께
    /// 접은 실효 전략(`DispatchContext.effectiveStrategy`)이다. 여기 원본이 남는 이유는
    /// `.auto` 유래인지가 관측(전략 출처 라벨)의 재료이기 때문이다.
    ///
    /// **`ProfileStrategy`를 앱측 타입으로 다시 선언하지 않는다.** `Override`가 다시 선언된
    /// 것은 `ConfigKeyStroke`를 `KeyStroke`로 번역해야 해서였는데, 전략은 번역할 것이 없는
    /// 순수 열거값이고 `ConfigAction`이 이미 그대로 통과한다.
    let strategy: ProfileStrategy
    /// keyboard 실행의 요소 계열 — `.forceText`면 걸러내기를 우회한다. 같은 이유로 앱측 타입을
    /// 다시 선언하지 않는다. **소비처는 PR-D2 세션 4가 만든다**(치환은 keyboard 실행 쪽만).
    let keyboardFamily: KeyboardFamily
    /// 스크롤 줄 수 재정의 — 명시값은 AX 뷰포트 정확값보다 **우선**하며 그 extent는 읽기
    /// 자체가 생략된다. `nil`이면 AX 뷰포트를 시도하고, 그것도 실패하면 `CommandKeyMapper`의
    /// 코드 상수(15/30)다 (`20260806_scroll-line-count-priority-ladder.md`).
    let halfPageLines: Int?
    let fullPageLines: Int?
    let motionOverrides: [Motion: Override]
    let actionOverrides: [ConfigAction: Override]

    /// 재정의 없음 — 모든 매퍼가 내장 테이블 그대로 동작한다. 매퍼 기본값이자, 어댑터가
    /// "이 스킵이 프로파일 때문인가"를 가르는 **builtIn 재조회 센티널**이다.
    ///
    /// **번들 기본 전략(`AppProfile.defaultStrategy`)을 따르지 않는다** — 그 축은 프로파일
    /// 부재를 뜻하는 `noProfile`이 맡는다. 여기 실린 `.keyboard`는 "전략 미지정"이 아니라
    /// "이 값은 전략을 말하지 않는다"에 가깝고, 매퍼는 전략을 보지 않으므로 무해하다.
    static let empty = ResolvedProfile()

    /// 프로파일 **파일이 없는** 앱 — 빈 프로파일 파일과 같은 값이다. `AppProfile()`을 통과시켜
    /// 파서 기본값과 **같은 상수**에서 전략을 받는다(기본값이 두 곳으로 갈리지 않는다 —
    /// `20260813_bundled-default-strategy-auto-flip-gated.md`).
    static let noProfile = ResolvedProfile(AppProfile())

    private init() {
        name = nil
        strategy = .keyboard
        keyboardFamily = .keyMapping
        halfPageLines = nil
        fullPageLines = nil
        motionOverrides = [:]
        actionOverrides = [:]
    }

    init(_ profile: AppProfile) {
        name = profile.name
        strategy = profile.strategy
        keyboardFamily = profile.keyboardFamily
        halfPageLines = profile.halfPageLines
        fullPageLines = profile.fullPageLines
        // append 전용 모션(a/A)의 base 상속은 `motionOverride(for:)` 안에 있다 — 패키지
        // 내부 어휘 테이블에 접근할 수 없으므로 전 케이스를 이 공개 API로 베이킹한다.
        var overrides: [Motion: Override] = [:]
        for motion in Motion.allCases {
            if let override = profile.motionOverride(for: motion) {
                overrides[motion] = Override(override)
            }
        }
        motionOverrides = overrides
        actionOverrides = profile.actions.mapValues(Override.init)
    }

    /// 액션 **자신의 키** 재정의 — `nil`이면 매퍼가 내장 상수를 쓴다. `.disabled`도 여기서는
    /// `nil`로 접힌다: 어댑터가 매핑 조회보다 앞에서 걸러내므로 매퍼까지 오지 않는다.
    ///
    /// 이름 붙인 프로퍼티인 것이 계약이다 — 매퍼는 설정 어휘(`ConfigAction`)를 모르고,
    /// `ResolvedProfile`이 설정↔실행의 유일한 번역 지점으로 남는다.
    var newLineStrokes: [KeyStroke]? { strokes(for: .openLine) }

    /// 줄을 만드는 키가 **사용자 지시로 꺼져 있는가.** `newLineStrokes`의 `nil`이 "재정의
    /// 없음"과 "disable" 둘을 뭉치므로, 기본 `Return`으로 fail-open 하면 안 되는 자리가 따로
    /// 묻는다 — 마지막 줄 linewise `p`의 개행 합성이 그 자리다(`.openLine`은 어댑터가 매핑
    /// 조회보다 앞에서 걸러내지만 `.paste`는 그 게이트를 지나지 않는다).
    var newLineDisabled: Bool { actionOverrides[.openLine] == .disabled }
    var pasteStrokes: [KeyStroke]? { strokes(for: .paste) }
    var undoStrokes: [KeyStroke]? { strokes(for: .undo) }
    var redoStrokes: [KeyStroke]? { strokes(for: .redo) }

    private func strokes(for action: ConfigAction) -> [KeyStroke]? {
        guard case .strokes(let strokes) = actionOverrides[action] else { return nil }
        return strokes
    }
}

// `nonisolated`는 필수 — 프로젝트 기본 격리(MainActor)가 확장 멤버에도 적용되므로,
// 그냥 두면 이 init이 MainActor에 묶여 위 `strokes.map(KeyStroke.init)`이 격리 경고가 된다.
nonisolated extension KeyStroke {
    /// 설정 표기(플랫폼 중립) → 실행 키 한 타. 화살표·기능 키는 레이아웃 무관 고정
    /// 키코드라 문자 키 같은 레이아웃 이슈가 없다 (설정 어휘가 v1에서 문자 키를
    /// 제외한 이유이기도 하다).
    ///
    /// 두 switch 모두 **의도적으로 exhaustive다** — 설정 어휘가 자라면 컴파일러가
    /// 여기 플랫폼 매핑 결정을 강제한다 ("VimAction에 exhaustive switch 금지" 계약과
    /// 반대 방향인 것이 맞다).
    init(_ stroke: ConfigKeyStroke) {
        let keyCode: Int
        switch stroke.key {
        case .left: keyCode = kVK_LeftArrow
        case .right: keyCode = kVK_RightArrow
        case .up: keyCode = kVK_UpArrow
        case .down: keyCode = kVK_DownArrow
        case .return: keyCode = kVK_Return
        case .escape: keyCode = kVK_Escape
        case .tab: keyCode = kVK_Tab
        case .home: keyCode = kVK_Home
        case .end: keyCode = kVK_End
        case .pageUp: keyCode = kVK_PageUp
        case .pageDown: keyCode = kVK_PageDown
        }

        var flags: CGEventFlags = []
        for modifier in stroke.modifiers {
            switch modifier {
            case .cmd: flags.insert(.maskCommand)
            case .opt: flags.insert(.maskAlternate)
            case .ctrl: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }

        self.init(keyCode, flags)
    }
}

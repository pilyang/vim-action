import VimEngine

/// `profiles/<bundle-id>.yaml` — 특수 앱의 동작 고도화 전용. 필드 여섯, `enabled` 없음
/// (앱별 on/off는 `config.yaml`이 단일 소유한다).
///
/// **`strategy`·`keyboardFamily`를 뺀 모든 필드가 옵셔널이거나 빈 컬렉션이다** — 스크롤 기본값
/// 15/30 같은 코드 상수는 앱이 갖고, 이 계층은 "값 없음"만 표현한다. 둘만 기본값을 드는 것은
/// "미지정"이 값 없음이 아니라 **결정된 기본 동작**이기 때문이다.
public struct AppProfile: Hashable, Sendable {
    /// 번들 기본 전략 — 프로파일이 **없거나** `strategy`를 안 쓴 앱이 무엇으로 도는가.
    ///
    /// **단일 상수인 것이 계약이다.** 기본값이 실제로는 두 곳이라 — 파서 기본값(파일은 있는데
    /// 필드 없음)과 앱측 프로파일 부재 경로(`ResolvedProfile.noProfile`) — 한쪽만 바꾸면 두
    /// 경우의 동작이 갈린다. `keyboard` → `auto` 전환은 PR-D2 마지막 단계의 별도 커밋이며
    /// 도그푸딩 게이트 뒤다 (`20260813_bundled-default-strategy-auto-flip-gated.md`).
    public static let defaultStrategy: ProfileStrategy = .keyboard

    /// 표시용 이름.
    public let name: String?
    /// 이 앱의 실행 전략. 미지정이면 `defaultStrategy`다.
    public let strategy: ProfileStrategy
    /// keyboard 실행의 요소 계열. 미지정이면 `.keyMapping`이라 동작 diff가 0이다.
    public let keyboardFamily: KeyboardFamily
    /// 뷰포트에 맞춘 스크롤 줄 수 재정의 (유효 1...200).
    public let halfPageLines: Int?
    public let fullPageLines: Int?
    /// 모션 단위 재정의·disable. 조회는 `motionOverride(for:)`로 한다.
    public let motions: [Motion: ConfigOverride]
    /// 명령 계열 재정의·disable. 시퀀스는 **그 액션 자신의 키**(o/O의 Return, p의 Cmd-V 등)를
    /// 교체하며, 위치를 잡는 모션 접두는 `motions`가 계속 소유한다.
    public let actions: [ConfigAction: ConfigOverride]

    public init(
        name: String? = nil,
        strategy: ProfileStrategy = defaultStrategy,
        keyboardFamily: KeyboardFamily = .keyMapping,
        halfPageLines: Int? = nil,
        fullPageLines: Int? = nil,
        motions: [Motion: ConfigOverride] = [:],
        actions: [ConfigAction: ConfigOverride] = [:]
    ) {
        self.name = name
        self.strategy = strategy
        self.keyboardFamily = keyboardFamily
        self.halfPageLines = halfPageLines
        self.fullPageLines = fullPageLines
        self.motions = motions
        self.actions = actions
    }

    /// 모션 재정의 조회의 **단일 지점**.
    ///
    /// append 전용 모션(a/A)은 어휘에 없고 base 모션(`char_right`/`line_end`)의 재정의·disable을
    /// 여기서 상속한다 — 사용자 관점에서 `$`와 `A`의 줄 끝은 같은 개념이다.
    public func motionOverride(for motion: Motion) -> ConfigOverride? {
        motions[MotionVocabulary.overrideKey(for: motion)]
    }
}

/// `motions:`·`actions:` 값 — 시퀀스 재정의 또는 disable. 두 섹션이 값 문법과 강건성
/// 규칙을 공유하므로 타입도 하나다. 교체 대상만 다르다: 모션은 그 모션의 시퀀스,
/// 액션은 그 액션 **자신의 키**다.
public enum ConfigOverride: Hashable, Sendable {
    /// 키 시퀀스 통째 교체. **항상 1개 이상**이다 — 빈 배열은 파서가 걸러낸다
    /// ("지원 ⟹ 빈 시퀀스 아님" 매퍼 불변식 보호).
    case strokes([ConfigKeyStroke])
    /// 이 항목을 쓰는 어휘 전부(모션이면 `G`·`dG`·`vG`)가 정직한 스킵이 된다 —
    /// 매퍼 `nil` 경로와 같다.
    case disabled
}

/// `strategy:` 값 — 이 앱의 액션을 무엇으로 실행하는가.
///
/// 어휘는 `20260712_ax-keyboard-strategy-dispatch.md`에서 정해졌고, `auto`는 PR-D2에서
/// 정식 파싱으로 들어왔다 (`20260813_auto-parsing-in-d2.md`).
public enum ProfileStrategy: String, Hashable, Sendable, CaseIterable {
    /// AX 범위/캐럿 쓰기로 실행한다. 지원하지 않는 액션은 keyboard로 위임된다(위임 표).
    case accessibility
    /// 합성 키 이벤트로 실행한다.
    case keyboard
    /// 프로브 판정에 맡긴다 — trusted면 accessibility, pending·untrusted면 keyboard다.
    ///
    /// **실행 계층에는 이 값이 도달하지 않는다**: 콜백이 판정과 함께 실효 전략으로 접어
    /// (`effectiveStrategy(_:verdict:)`) `DispatchContext`에 싣고, 어댑터는 접힌 값만 본다.
    /// 판정 계층·수명은 architecture `strategy-dispatch.md`의 auto 프로브 섹션이 SSOT다.
    case auto
}

/// `keyboard_family:` 값 — keyboard 실행이 요소를 인식하는가, 우회하는가.
///
/// **자동 감지로는 절대 선택되지 않는 명시 전용 축이다** — force-text는 비텍스트 UI에서 편집을
/// 봉쇄하는 걸러내기 층을 버리는 수단이라(Finder에서 `dd`가 파일을 지우는 것을 막는 층),
/// 리졸버 오보 1건이 파괴적 시퀀스로 승격된다
/// (`20260813_force-text-keyboard-family-substitution.md`).
///
/// 치환의 적용 범위는 **keyboard 실행 쪽뿐**이다(걸러내기 게이트·매퍼 호출·매퍼 내부 `.nonText`
/// 봉쇄·하이브리드 위임분이 같은 치환값을 본다). AX 분기의 계열 판정은 원본 계열을 유지한다.
/// 치환 자리는 `KeyboardAdapter.mapping` 진입부 **한 곳**이다.
public enum KeyboardFamily: String, Hashable, Sendable, CaseIterable {
    /// 요소 계열을 인식해 시퀀스를 고르고 위험 어휘를 걸러낸다 — 기본값이자 선호 폴백.
    case keyMapping = "key_mapping"
    /// 요소 감지를 우회하고 항상 TextArea 시퀀스를 낸다 — 최후 수단.
    case forceText = "force_text"
}

/// `actions:` 어휘 v1 5종 — `VimAction` 케이스 파생.
public enum ConfigAction: String, Hashable, Sendable, CaseIterable {
    case openLine = "open_line"
    case paste
    case undo
    case redo
    case scroll

    /// 시퀀스 재정의가 의미를 갖는가 — 그 액션이 자기 키를 갖는가와 같다.
    /// `scroll`만 아니다: 게시하는 스트로크가 곧 `line_down`/`line_up` 모션이라 재정의는
    /// `motions` 몫이고, "줄 수만큼 반복"이라는 카운트 단위와도 충돌한다.
    var hasOwnKey: Bool { self != .scroll }
}

import VimEngine

/// `profiles/<bundle-id>.yaml` — 특수 앱의 동작 고도화 전용. 필드 넷, `enabled` 없음
/// (앱별 on/off는 `config.yaml`이 단일 소유한다).
///
/// **모든 필드가 옵셔널이거나 빈 컬렉션이다** — 스크롤 기본값 15/30 같은 코드 상수는 앱이 갖고,
/// 이 계층은 "값 없음"만 표현한다.
public struct AppProfile: Hashable, Sendable {
    /// 표시용 이름.
    public let name: String?
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
        halfPageLines: Int? = nil,
        fullPageLines: Int? = nil,
        motions: [Motion: ConfigOverride] = [:],
        actions: [ConfigAction: ConfigOverride] = [:]
    ) {
        self.name = name
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

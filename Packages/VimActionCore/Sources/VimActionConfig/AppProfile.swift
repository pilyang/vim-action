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
    public let motions: [Motion: MotionOverride]
    /// 명령 계열 disable. v1 값이 `disabled`뿐이라 집합으로 충분하다.
    public let disabledActions: Set<ConfigAction>

    public init(
        name: String? = nil,
        halfPageLines: Int? = nil,
        fullPageLines: Int? = nil,
        motions: [Motion: MotionOverride] = [:],
        disabledActions: Set<ConfigAction> = []
    ) {
        self.name = name
        self.halfPageLines = halfPageLines
        self.fullPageLines = fullPageLines
        self.motions = motions
        self.disabledActions = disabledActions
    }

    /// 모션 재정의 조회의 **단일 지점**.
    ///
    /// append 전용 모션(a/A)은 어휘에 없고 base 모션(`char_right`/`line_end`)의 재정의·disable을
    /// 여기서 상속한다 — 사용자 관점에서 `$`와 `A`의 줄 끝은 같은 개념이다.
    public func motionOverride(for motion: Motion) -> MotionOverride? {
        motions[MotionVocabulary.overrideKey(for: motion)]
    }
}

/// `motions:` 값 — 시퀀스 재정의 또는 disable.
public enum MotionOverride: Hashable, Sendable {
    /// 키 시퀀스 통째 교체. **항상 1개 이상**이다 — 빈 배열은 파서가 걸러낸다
    /// ("지원 ⟹ 빈 시퀀스 아님" 매퍼 불변식 보호).
    case strokes([ConfigKeyStroke])
    /// 이 모션을 쓰는 어휘 전부(`G`·`dG`·`vG`)가 정직한 스킵이 된다 — 매퍼 `nil` 경로와 같다.
    case disabled
}

/// `actions:` 어휘 v1 5종 — `VimAction` 케이스 파생.
public enum ConfigAction: String, Hashable, Sendable, CaseIterable {
    case openLine = "open_line"
    case paste
    case undo
    case redo
    case scroll
}

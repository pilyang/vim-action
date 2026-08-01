/// `config.yaml` — 앱별 on/off를 **단일 소유**한다. 프로파일에는 `enabled` 필드가 없다.
public struct GlobalConfig: Hashable, Sendable {
    /// bundle-id → 개입 on/off. **여기 없는 앱은 없는 것**이고, 기본값 판단은 소비자(앱 게이트)의 몫이다.
    public let apps: [String: Bool]

    public init(apps: [String: Bool] = [:]) {
        self.apps = apps
    }
}

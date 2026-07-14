extension VimEngine {
    /// 엔진의 동작을 튜닝하는 주입 설정. 엔진 기본값은 모두 off(빈 셋)이며,
    /// 앱 계층이 사용자 설정을 이 값으로 번역해 `VimEngine.init`에 주입한다.
    public struct Configuration: Sendable {
        /// Normal 모드에서 이 modifier 중 하나라도 포함한 미매핑 콤보가 오면
        /// Insert로 탈출시킨다. Spotlight/Raycast 등 cmd/opt 단축키 직후의 텍스트
        /// 입력이 Normal 모드에 막히지 않게 하려는 옵션이다. 빈 셋이면 기존 동작 유지.
        public var normalModeEscapeModifiers: Set<Key.Modifier>

        public init(normalModeEscapeModifiers: Set<Key.Modifier> = []) {
            self.normalModeEscapeModifiers = normalModeEscapeModifiers
        }
    }
}

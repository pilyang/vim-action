/// 설정 항목 하나가 무시됐다는 경고.
///
/// **로그가 아니라 값으로 반환한다** — 이 패키지는 os.log를 모르고, 로깅은 소비자(앱)의 몫이다.
public struct ConfigWarning: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// 스키마에 없는 키. 미지 모션명·액션명도 여기다 — 어느 쪽인지는 `path`가 말한다.
        /// 남은 M5 필드(`per_element`)가 미리 적혀 있어도 이 경로로 접힌다(전방 호환).
        case unknownKey
        /// 타입 불일치·범위 밖·빈 시퀀스. 연관값은 문제가 된 원문.
        case invalidValue(String)
        /// `[modifier-]key` 토큰 파싱 실패. 연관값은 원문 토큰(`Cmd-Down` 등).
        case invalidKeyStroke(String)
    }

    /// 경고가 난 파일 경로.
    public let file: String
    /// 항목 경로 — `apps.com.foo`, `scroll.half_page_lines`, `motions.document_end[1]`.
    /// 빈 문자열이면 파일 최상위다.
    public let path: String
    public let kind: Kind

    public init(file: String, path: String, kind: Kind) {
        self.file = file
        self.path = path
        self.kind = kind
    }
}

/// 파일 통째 파싱 실패. 그 파일은 **없는 것으로 취급**되고 이 값이 함께 반환된다.
///
/// "직전 유효 설정 유지"는 이 값을 받는 쪽(핫 리로드)의 정책이지 이 계층의 책임이 아니다.
public struct ConfigError: Hashable, Sendable, Error {
    public let file: String
    /// Yams가 준 오류 설명.
    public let message: String

    public init(file: String, message: String) {
        self.file = file
        self.message = message
    }
}

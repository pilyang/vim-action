/// 엔진이 생산하는 추상 동작. "무엇을 해야 하는가"만 표현하고
/// "어떻게 실행하는가"(AX 호출인지 키 합성인지)는 전략 어댑터의 몫이다.
public enum VimAction: Hashable, Sendable {
    case move(Motion)
    case edit(Operator, TextRange)
    /// Visual 선택 세션 시작 — 앵커를 현재 캐럿으로 설정한다. `linewise`(V 진입)면
    /// 현재 줄 전체를 즉시 선택한다. 세션 활성 중 다시 받으면(v↔V 전환) 앵커를
    /// 유지한 채 wise만 교체·재적용한다. 앵커·실제 범위는 어댑터 상태다.
    case beginSelection(linewise: Bool)
    /// Visual에서의 모션 — 이동이 아니라 선택 확장이다. 카운트는 `.move`와 같은
    /// 반복 출력. linewise 세션에서의 줄 반올림은 wise를 아는 어댑터의 실행 규칙이다.
    case extendSelection(Motion)
    /// Visual 이탈 — 화면의 선택을 해제(collapse)한다.
    case clearSelection

    /// 편집 오퍼레이터의 종류. 적용 범위는 `TextRange`가 함께 나른다.
    public enum Operator: Hashable, Sendable {
        case delete
        /// 범위를 지우고 입력을 시작한다 — 엔진이 완결 시 Insert로 전이한다.
        case change
        case yank
    }

    /// 오퍼레이터가 적용될 범위.
    public enum TextRange: Hashable, Sendable {
        /// 커서에서 모션을 count회 적용한 지점까지 — 한 편집 단위다 (`d3w`는
        /// move 3회 반복이 아니라 3단어를 한 번에 지우는 범위).
        case motion(Motion, count: Int)
        /// 커서가 놓인 텍스트 오브젝트 — `diw`/`daw`.
        case textObject(TextObject)
        /// 현재 줄부터 count줄 — `dd`, `2dd`.
        case line(count: Int)
        /// 줄 단위 모션 범위 — `dj`(현재+아래 줄), `dG`(현재부터 마지막 줄까지).
        /// 총 몇 줄인지의 해석은 어댑터 몫이다. 절대 모션(G/gg)은 항상 count 1로만
        /// 나온다 — 카운트가 붙으면 엔진이 invalid로 이연한다.
        case linewiseMotion(Motion, count: Int)
        /// 현재 선택 영역 — Visual의 `y d x c`. 실제 범위는 어댑터가 유지하는
        /// 선택 상태에서 온다.
        case selection
    }

    /// 텍스트 오브젝트. 경계의 실제 의미(단어의 정의, 주변 공백 포함 범위,
    /// 따옴표 안/포함, 괄호 중첩 처리)는 어댑터가 정하며, 엔진은 종류와 스코프만 낸다.
    public enum TextObject: Hashable, Sendable {
        case word(Scope)
        /// 따옴표 오브젝트 — `ci"`/`da'`/``yi` ``.
        case quote(Quote, Scope)
        /// 괄호쌍 오브젝트 — `ci(`/`da[`/`yiB`. 여닫이 어느 쪽 키로 완결해도 같은 kind다.
        case pair(Pair, Scope)

        public enum Quote: Hashable, Sendable {
            case double
            case single
            case backtick
        }

        public enum Pair: Hashable, Sendable {
            case paren
            case bracket
            case brace
            case angle
        }

        /// `i`(inner: 오브젝트 본체만) / `a`(around: 주변 공백 포함).
        public enum Scope: Hashable, Sendable {
            case inner
            case around
        }
    }
}

/// 커서 이동의 종류. 단어 경계·줄 경계의 실제 의미(어디까지가 단어인가 등)는
/// 어댑터가 정하며, 엔진은 추상 케이스만 낸다.
public enum Motion: Hashable, Sendable {
    case charLeft
    case charRight
    case lineUp
    case lineDown
    case wordForward
    case wordBackward
    case wordEndForward
    case lineStart
    case lineFirstNonBlank
    case lineEnd
    case documentStart
    case documentEnd
    /// `a` 전용. Vim에서 `l`(charRight)은 줄 끝 문자 위에서 멈추지만 append는
    /// 마지막 문자 뒤까지 가야 하므로, 어댑터가 구분할 수 있게 별도 케이스로 둔다.
    case charRightForAppend
    /// `A` 전용. `$`(lineEnd)는 마지막 문자 위, `A`는 마지막 문자 뒤 — 위와 같은 이유.
    case lineEndForAppend
}

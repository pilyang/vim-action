//
//  AXWriteOutcome.swift
//  VimAction
//

import ApplicationServices
import Foundation

/// AX 쓰기 1회의 결과를 **소비자 행동 단위의 의미 클래스**로 분류한 값 — `AXWriter`가 raw로
/// 내보낸 `AXError`가 여기서 갈린다.
///
/// 분류는 **default-deny 화이트리스트**다 (`20260808_ax-write-failure-whitelist-no-fallback.md`).
/// 순수 AX 경로에서 "보고"와 "스킵"은 사용자 가시 결과가 같으므로(둘 다 무동작) 유일한 판단
/// 기준은 "이 코드가 **우리 실행 코드의 고장**을 가리키는가"이고, 그렇다고 증명된 코드만
/// 보고 쪽에 올라온다. 새 코드가 조용히 보고로 흘러드는 경로는 두지 않는다.
///
/// **이 타입의 함수들은 로그도 보고도 실행하지 않는다.** "어떤 로그·보고가 필요한가"를 값으로
/// 돌려줄 뿐이고 실행은 소비자(실행 드라이버) 몫이다 — `AXWriter`가 분류를 통로 밖으로 밀어낸
/// 이유가 그대로 여기에도 적용된다: 분류가 로깅까지 하면 아래 표를 테스트로 고정할 수 없다.
///
/// 케이스가 `AXError`보다 성긴 것이 요점이다 — 소비자가 갈라야 할 행동이 7가지이지 16가지가
/// 아니다. `KeyboardAdapter`의 스킵 분리(`unsupported`/`skipped`/`layoutBlocked`/
/// `disabledByProfile`)와 같은 규칙으로, **서로 다른 요약 버킷으로 가는 것들만** 갈라 둔다.
nonisolated enum AXWriteOutcome: Sendable, CaseIterable {
    /// 썼다.
    case success

    /// **실패 보고** — D1 구간의 유일한 보고 케이스이며 `reportExecutionFailure`의 첫 실호출자다.
    /// `.failure`는 헤더상 "시스템 오류"로 정상 사용에서 도달 불가라, 나면 우리 쪽 고장이다.
    /// `AXWriter`가 `AXValueCreate` 실패를 `.failure`로 접는 것과 정합한다("실행을 시도했는데
    /// 깨졌다"의 정직한 매핑).
    case failure

    /// **관측 전용** — 보고가 아니라 앱 번들 ID를 실은 별도 요약 로그다.
    /// 사전 경계 검증(`provenWriteRange`)을 통과했는데 앱이 거부했다는 것은 오프셋 공간 불일치
    /// 신호이므로 실질적 안전망 전부이지만, 가장 현실적인 오탐(앱이 `characterCount`를 UTF-16이
    /// 아닌 단위로 보고 → 이모지·한글 문서에서 연속 거부 → 오토리핏 자동 off)의 빈도가
    /// 미실측이고 자동 트립은 영속된다. **D1 종료 시 보고 승격 재심사** — 그 판정 데이터가
    /// 이 로그다.
    case illegalArgument

    /// **미지원 스킵** — 앱의 정적 성질이다("미지원 ≠ 실패"의 연장). 경합 스킵과 갈라 두는
    /// 것은 요약 버킷이 다르기 때문이다: 이쪽 빈도는 그 앱을 강등해야 한다는 신호(D2 입력)이고,
    /// 저쪽 빈도는 대상 앱의 뷰 수명에 비례할 뿐 우리 정확도를 가리키지 않는다.
    case unsupportedSkip

    /// **경합 스킵** — 요소가 사이에 사라졌거나(`.invalidUIElement`) 앱이 바빠 응답이 없다
    /// (`.cannotComplete`). 후자는 헤더가 "실패했다는 뜻이 아닐 수 있다"를 명시해 **성공 + 응답
    /// 유실과 구분 불가**하고, 그래서 보고도 keyboard 폴백도 아니다(재실행은 이중 삭제가 된다).
    case contentionSkip

    /// **보고 아님 — 권한 회수**. TCC가 회수됐다는 뜻이며 복구는 `AccessibilityPermissionMonitor`
    /// (1초 폴링)가 전담한다. 소비자는 error 로그만 남긴다 — 여기서 실패로 세면 권한 회수 1회가
    /// 가로채기 전체 자동 off까지 끌고 간다.
    case apiDisabled

    /// **미보고 스킵 + error 로그** — 쓰기 호출에서 도달 불가한 알려진 코드(observer·notification
    /// 계열 등)와 `@unknown default`가 함께 온다. 둘을 한 클래스로 두는 것이 default-deny의
    /// 연장이다: 어느 쪽이든 "우리 표가 예상하지 못한 응답"이고, 소비자 행동(스킵 + error 로그)이
    /// 같다. 보고로 흘려보내지 않는 것이 핵심이다.
    case unexpected

    /// `AXWriter`가 돌려준 raw `AXError`를 의미 클래스로 접는다 — **표가 곧 계약**이라
    /// `AXWriteOutcomeTests`의 16케이스 전수 스윕이 이 함수의 명세다.
    ///
    /// 도달 불가 코드 6종을 `@unknown default`에 흡수시키지 않고 명시 나열하는 것은 테스트를
    /// 위해서다 — `AXError(rawValue:)`는 미지 값에 `nil`을 돌려주므로 `@unknown default` 분기는
    /// 테스트로 도달할 수 없고, 그 안에 접어 넣은 행은 아무도 검증하지 못한다.
    static func classify(_ error: AXError) -> AXWriteOutcome {
        switch error {
        case .success:
            return .success
        case .failure:
            return .failure
        case .illegalArgument:
            return .illegalArgument
        case .attributeUnsupported, .notImplemented, .parameterizedAttributeUnsupported, .noValue:
            return .unsupportedSkip
        case .invalidUIElement, .cannotComplete:
            return .contentionSkip
        case .apiDisabled:
            return .apiDisabled
        case .actionUnsupported, .notEnoughPrecision, .invalidUIElementObserver,
            .notificationUnsupported, .notificationAlreadyRegistered, .notificationNotRegistered:
            return .unexpected
        @unknown default:
            return .unexpected
        }
    }

    /// 쓰기 전 **우리 쪽** 경계 검증 — 통과한 범위만 그대로 돌려주고 아니면 `nil`이다.
    /// `ViewportReader.provenViewport`와 같은 형태이고 같은 이유다: 실기기 AX 없이 표로 검증된다.
    ///
    /// **검증 실패는 보고가 아니라 스킵**이다. 감지 가능한 우리 버그를 AX에 보내지 않는 것이
    /// 목적이고, 보내지 않았으니 "실행을 시도했는데 깨졌다"에 해당하지 않는다. 통과한 뒤에도
    /// 앱이 거부하면 그것이 `.illegalArgument`(관측 전용)이며, 이 함수가 앞에 서 있어야 그
    /// 신호가 "우리 범위가 이상함"이 아니라 "오프셋 공간 불일치"로 읽힌다.
    ///
    /// `characterCount`는 **앱이 준 값** 기준이다(`kAXNumberOfCharactersAttribute`). 앱이 그
    /// 값을 UTF-16이 아닌 단위로 보고하면 여기를 통과하고도 거부될 수 있는데, 그 창을 닫는 것은
    /// 이 함수가 아니라 위 재심사다.
    ///
    /// `length ≥ 0`은 결정 문서 문언(`0 ≤ location && upperBound ≤ characterCount`)에 없지만
    /// 같은 default-deny의 연장이다 — 문언 그대로면 음수 length가 통과한다(5 + (−3) = 2).
    /// 가드를 뺄셈 우선으로 쓴 것은 `NSNotFound` 같은 값이 섞여 들어와도 `location + length`가
    /// 오버플로로 트랩하지 않게 하기 위해서다.
    static func provenWriteRange(_ range: NSRange, characterCount: Int) -> NSRange? {
        guard range.location >= 0, range.length >= 0,
            range.location <= characterCount,
            range.length <= characterCount - range.location
        else {
            return nil
        }
        return range
    }
}

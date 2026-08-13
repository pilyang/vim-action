//
//  DispatchContext.swift
//  VimAction
//

import Foundation
import VimActionConfig

/// 실행 sink에 실리는 **키 입력 시점의 컨텍스트 스냅샷** — 요소 계열, 대상 앱 pid,
/// 최전면 앱 프로파일, 실효 전략.
///
/// 콜백(메인)이 캐시에서 읽어 값으로 넘긴다: 게시 큐가 나중에 캐시를 읽으면 그 사이
/// 포커스·최전면 앱이 옮겨간 뒤일 수 있다 (`KeyboardAdapter.execute`의 family 계약과
/// 같은 규칙). 필드가 늘어도 sink 시그니처(2인자)가 유지되는 것도 요점이다 — 기존
/// 테스트 클로저가 깨지지 않는다.
nonisolated struct DispatchContext: Equatable, Sendable {
    var family: ElementFamily = .textArea
    /// 디스패치 경로 AX 읽기의 대상 앱. **pid만 싣는 것이 규칙이다** — 게시 큐가 이 값으로
    /// `AXUIElement`를 큐 위에서 만들므로 비-`Sendable` 값이 격리를 건너지 않는다
    /// (`20260802_dispatch-read-on-posting-queue.md` ②).
    ///
    /// 출처가 `FocusedElementResolver`인 것도 계약이다: 리더가 겨냥하는 대상(포커스 요소)의
    /// 소유자와 같아야 `family`와 pid가 서로 다른 앱을 가리키는 일이 없다.
    var processID: pid_t?
    /// AX 쓰기 관측 로그가 앱을 특정하는 수단 — `AXWriteEffects`의 요약 한 줄에 실린다.
    /// `.illegalArgument` 빈도는 D1 종료 시 보고 승격 재심사의 판정 데이터인데, 어느 앱이
    /// 거부했는지 모르면 아무 데도 쓸 수 없는 숫자가 된다
    /// (`20260808_ax-write-failure-whitelist-no-fallback.md`).
    ///
    /// 출처는 `FrontmostAppGate`이며 **프로파일 조회와 같은 값**이다 — 콜백이 한 번 읽어
    /// 둘에 함께 싣는다. `processID`(포커스 요소의 소유자)와 출처가 다른 것은 계약대로다:
    /// 이 값은 읽기·쓰기의 대상이 아니라 로그의 라벨이다.
    var bundleID: String?
    var profile: ResolvedProfile = .empty
    /// 이 실행이 **실제로** 타는 전략 — 선언된 전략(`profile.strategy`)과 프로브 판정을 콜백이
    /// 접어 둔 값이고, `.auto`는 여기 오지 않는다 (`effectiveStrategy(_:verdict:)`).
    ///
    /// 프로파일과 별개 필드인 것이 계약이다: 접힌 값을 `profile.strategy`에 덮어쓰면 그 스냅샷의
    /// 프로파일이 더 이상 사용자가 쓴 값이 아니게 되고, auto 유래 실패를 명시 `accessibility`와
    /// 구분하는 관측(전략 출처 라벨)이 재료를 잃는다.
    var effectiveStrategy: ProfileStrategy = .keyboard
}

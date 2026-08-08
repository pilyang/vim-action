//
//  ActionExecutor.swift
//  VimAction
//

import CoreGraphics

/// 합성 이벤트에 찍는 비공개 마커. 게시자(`ActionExecutor`)와 판독자(이벤트 탭)가
/// 공유하는 유일한 계약이다.
///
/// **마커를 빠뜨리면 탭이 자기 출력을 재해석해 무한 루프** — 이벤트 탭 기반 도구의
/// 병적 루프의 가장 흔한 원인이다. 그래서 게시는 전부 `ActionExecutor`를 거치고,
/// 마킹은 그 안에서만 일어난다 (우회 경로가 생기면 불변식을 감사할 수 없다).
///
/// 타입 단위 `nonisolated` — 이 파일의 기본 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)를
/// 함수뿐 아니라 `magic`까지 끊는다. 판독자인 탭 콜백이 메인 격리를 가정하지 않으므로
/// 마커는 어느 스레드에서도 찍고 읽을 수 있어야 한다.
nonisolated enum SyntheticEventMarker {
    /// `.eventSourceUserData`에 실을 매직값 — ASCII "VIMA". 하드웨어 이벤트의 기본값
    /// 0과 구분되기만 하면 되므로 의미는 가독성용이다.
    static let magic: Int64 = 0x56_49_4D_41

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: magic)
    }

    static func isMarked(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == magic
    }
}

/// 모든 합성 이벤트 게시의 단일 통로. 게시 전 마커를 찍는 유일한 지점이다.
///
/// 통로는 **프리미티브마다** 하나다 — AX 속성 쓰기는 같은 규칙으로 `AXWriter`가 소유한다
/// (그쪽엔 마커 개념이 없다: AX 쓰기는 탭으로 되돌아오지 않는다).
///
/// M1 시점엔 호출자가 없다 — `VimAction` → CGEvent 시퀀스 매핑은 Keyboard 어댑터
/// 마일스톤의 몫이고, 여기는 그 출구가 될 게시 프리미티브까지만 둔다.
///
/// 격리는 타입 단위 `nonisolated` + `Sendable`이다 — 게시는 탭 콜백 밖 직렬 큐에서
/// 일어나므로(콜백 경량 불변식) 이 값은 큐를 건너간다. `Sendable`을 명시해 두면
/// 나중에 비-`Sendable` 저장 프로퍼티가 들어오는 순간 그 자리에서 컴파일 에러가 난다.
///
/// `CGEvent`는 `Sendable`이 아니다. 그래서 계약은 **이벤트를 `post` 호출자와 같은
/// 컨텍스트(직렬 큐)에서 만든다**는 것 — 어댑터가 큐 위에서 시퀀스를 생성하면 격리를
/// 건너는 비-`Sendable` 값이 애초에 없다.
nonisolated struct ActionExecutor: Sendable {
    /// 게시 함수 주입 — 프로덕션은 `.cgSessionEventTap`(메인 탭이 붙은 곳과 같은 탭이라
    /// 합성 이벤트가 탭으로 되돌아온다 = 마커가 필요한 이유). 테스트는 실제 키 입력을
    /// 머신에 주입하지 않고 마커 불변식만 검증하려고 이 자리를 대체한다.
    private let postEvent: @Sendable (CGEvent) -> Void

    init(postEvent: @escaping @Sendable (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }) {
        self.postEvent = postEvent
    }

    /// 시퀀스를 순서대로 게시한다. 마킹은 이벤트마다 게시 직전에 — 마킹되지 않은
    /// 합성 이벤트는 존재하지 않는다.
    func post(_ events: [CGEvent]) {
        for event in events {
            SyntheticEventMarker.mark(event)
            postEvent(event)
        }
    }
}

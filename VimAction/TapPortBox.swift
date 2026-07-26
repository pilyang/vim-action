//
//  TapPortBox.swift
//  VimAction
//

import CoreGraphics
import os

/// `CFMachPort`(이벤트 탭 포트) 참조를 스레드 간에 주고받는 잠금 상자.
///
/// 잠금이 지키는 것은 **포트 참조의 원자적 교체**뿐이다 — `CGEvent.tapEnable`/`tapIsEnabled`는
/// 스레드 안전 C API이고, `CFMachPortInvalidate` 뒤의 늦은 호출도 무해한 no-op이다
/// (`EventTapController.startWatchdog`의 강캡처 근거와 같은 전제).
///
/// 쓰는 곳은 둘이다: 킬 탭 자신의 포트(메인이 설치하고 킬 스레드 콜백이 읽는다)와 메인 탭
/// 포트(메인이 설치하고 킬 스레드가 발동 시 읽어 즉시 비활성화한다). 둘 다 소유자는 메인
/// 격리인데 읽는 쪽이 전용 스레드라, 격리로는 안전하게 건넬 수 없어 잠금이 필요하다.
///
/// `CFMachPort`가 `Sendable`이 아니라 `withLock`(반환값에 `Sendable`을 요구)을 쓸 수 없어
/// `withLockUnchecked`를 쓴다 — 안전성 근거는 위의 "스레드 안전 C API" 전제다.
nonisolated final class TapPortBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var port: CFMachPort?

    func get() -> CFMachPort? {
        lock.withLockUnchecked { port }
    }

    func set(_ newPort: CFMachPort?) {
        lock.withLockUnchecked { port = newPort }
    }
}

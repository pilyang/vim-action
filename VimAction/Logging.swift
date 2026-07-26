//
//  Logging.swift
//  VimAction
//

import os

/// `nonisolated`는 필수다 — 프로젝트 기본 격리가 MainActor라 그냥 두면 이 상수들이
/// MainActor에 묶여, 탭 콜백·킬 탭 전용 스레드 같은 nonisolated 경로에서 로그를 남길 때마다
/// 격리 경고가 난다. `Logger`는 Sendable이고 어느 컨텍스트에서든 쓰라고 있는 타입이다.
nonisolated extension Logger {
    /// 모든 VimAction 로그의 서브시스템.
    /// 확인: `log stream --predicate 'subsystem == "dev.pilyang.VimAction"' --level debug`
    /// (`.debug`/`.info`는 디스크에 남지 않으므로 stream 또는 Console.app 디버그 표시로 봐야 한다.)
    private static let subsystem = "dev.pilyang.VimAction"

    /// 이벤트 탭 라이프사이클과 수신 이벤트.
    static let eventTap = Logger(subsystem: subsystem, category: "eventTap")

    /// TCC 권한 상태 전이.
    static let permission = Logger(subsystem: subsystem, category: "permission")
}

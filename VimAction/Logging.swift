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

    /// 설정 시딩·로드·리로드와 경고/에러. `VimActionConfig`는 경고·에러를 값으로만
    /// 반환하므로, 로그로 흘리는 책임은 전부 앱(`ConfigStore`)에 있다.
    static let config = Logger(subsystem: subsystem, category: "config")

    /// 로그인 시 자동 시작(`SMAppService`) 등록·해제 실패.
    static let launchAtLogin = Logger(subsystem: subsystem, category: "launchAtLogin")
}

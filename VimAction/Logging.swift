//
//  Logging.swift
//  VimAction
//

import os

extension Logger {
    /// 모든 VimAction 로그의 서브시스템.
    /// 확인: `log stream --predicate 'subsystem == "dev.pilyang.VimAction"' --level debug`
    /// (`.debug`/`.info`는 디스크에 남지 않으므로 stream 또는 Console.app 디버그 표시로 봐야 한다.)
    private static let subsystem = "dev.pilyang.VimAction"

    /// 이벤트 탭 라이프사이클과 수신 이벤트.
    static let eventTap = Logger(subsystem: subsystem, category: "eventTap")

    /// TCC 권한 상태 전이.
    static let permission = Logger(subsystem: subsystem, category: "permission")
}

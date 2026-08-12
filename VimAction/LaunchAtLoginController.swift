//
//  LaunchAtLoginController.swift
//  VimAction
//

import Foundation
import Observation
import ServiceManagement
import os

/// 로그인 시 자동 시작 — `SMAppService.mainApp` 등록의 소유자.
///
/// **상태를 저장하지 않는다.** 표시값의 SSOT는 `SMAppService.mainApp.status` 하나이고,
/// UserDefaults 미러는 두지 않는다: 사용자가 시스템 설정 > 일반 > 로그인 항목에서 아무 통지
/// 없이 끌 수 있어서, 미러를 두는 순간 "토글은 on인데 실제로는 안 뜨는" 상태가 만들어진다.
/// 그래서 매번 시스템에 다시 묻는다 (설정 창을 열 때마다 — `AppState.settingsWindowDidAppear`).
///
/// `.enabled`만 on이다 — `.requiresApproval`(사용자가 껐다)·`.notFound`는 어느 쪽이든 로그인
/// 시 실제로 뜨지 않으므로 on으로 보이면 거짓말이 된다.
@MainActor
@Observable
final class LaunchAtLoginController {
    /// 마지막으로 읽은 등록 상태의 파생값. 저장된 설정이 아니라 시스템 상태의 스냅샷이다.
    private(set) var isEnabled = false

    /// 직전 register/unregister가 실패했다면 그 사유 — 설정 창 Behavior 섹션이 인라인으로
    /// 보여준다. 클릭이 조용한 무동작이 되면 안 된다는 레포 관례(`setAppEnabled`의 NSAlert
    /// 폴백)를 따르되, 창이 이미 떠 있는 경로라 모달 대신 클릭한 자리에서 알린다.
    private(set) var failureMessage: String?

    /// 세 seam 전부 주입 지점이다 — 테스트가 개발 머신의 실제 로그인 항목을 바꾸면 안 된다.
    /// (읽기인 `currentStatus`만은 부작용이 없어 프리뷰·테스트에서 실물이 불려도 무해하다.)
    private let currentStatus: @MainActor () -> SMAppService.Status
    private let register: @MainActor () throws -> Void
    private let unregister: @MainActor () throws -> Void

    init(
        currentStatus: @escaping @MainActor () -> SMAppService.Status = {
            SMAppService.mainApp.status
        },
        register: @escaping @MainActor () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping @MainActor () throws -> Void = {
            try SMAppService.mainApp.unregister()
        }
    ) {
        self.currentStatus = currentStatus
        self.register = register
        self.unregister = unregister
    }

    /// 등록 상태를 다시 읽는다. 설정 창이 열릴 때마다 불리므로 멱등이고, 그 사이 시스템
    /// 설정에서 꺼진 변경이 여기서 따라잡힌다. 지난 실패 문구도 함께 지운다 — 창을 다시
    /// 여는 것은 새로 보는 것이다.
    func refresh() {
        isEnabled = currentStatus() == .enabled
        failureMessage = nil
    }

    /// 토글이 부른다. **요청값이 아니라 재조회한 status가 결과를 정한다** — 실패하면 토글이
    /// 그대로 원위치로 돌아간다.
    func setEnabled(_ enabled: Bool) {
        do {
            try enabled ? register() : unregister()
            refresh()
        } catch {
            let attempt: String = enabled ? "등록" : "해제"
            Logger.launchAtLogin.error(
                "로그인 항목 \(attempt, privacy: .public) 실패: \(error.localizedDescription, privacy: .public)"
            )
            refresh()
            failureMessage =
                enabled
                ? "Couldn't turn this on. Open System Settings › General › Login Items and allow VimAction there."
                : "Couldn't turn this off. Remove VimAction from System Settings › General › Login Items."
        }
    }
}

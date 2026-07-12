//
//  AccessibilityPermissionMonitor.swift
//  VimAction
//

import AppKit
import ApplicationServices
import Observation
import os

/// Accessibility(손쉬운 사용) TCC 권한 상태를 관찰한다.
///
/// TCC는 번들ID + 코드서명 identity 기준이다. Apple Development 인증서(팀 설정)면 리빌드에도
/// 권한이 유지되지만, ad-hoc 서명 빌드는 리빌드마다 "체크박스는 켜져 있는데 신뢰 안 됨" 상태가
/// 될 수 있다 — 시스템 설정에서 항목 제거 후 재추가하거나
/// `tccutil reset Accessibility dev.pilyang.VimAction`으로 복구한다.
@MainActor
@Observable
final class AccessibilityPermissionMonitor {
    private(set) var isTrusted = false

    /// 미허용→허용 전이 순간 1회 호출된다 — 이벤트 탭 설치 트리거.
    @ObservationIgnored var onGranted: (() -> Void)?

    @ObservationIgnored private var pollTimer: Timer?

    /// 프롬프트 없이 현재 상태만 갱신.
    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// 시스템 권한 프롬프트와 함께 요청. 다이얼로그는 TCC 상태당 1회만 뜨므로
    /// 재시도 경로로 `openSystemSettings()`를 함께 제공해야 한다.
    func requestWithPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        Logger.permission.info("Accessibility 권한 프롬프트 요청 (isTrusted=\(self.isTrusted))")
    }

    /// 시스템 설정의 손쉬운 사용 프라이버시 패널로 딥링크.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 1초 간격으로 부여 순간을 감지해 재시작 없이 온보딩을 이어간다. 허용되면 스스로 멈춘다.
    /// (권한 회수 감지는 다루지 않는다 — 회수 시 macOS가 탭을 무력화하므로 다음 마일스톤 몫.)
    func startPollingUntilGranted() {
        guard pollTimer == nil, !isTrusted else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // 메인 액터에서 스케줄한 Timer는 메인 런루프에서 발화한다.
            MainActor.assumeIsolated {
                self.pollOnce()
            }
        }
    }

    private func pollOnce() {
        guard AXIsProcessTrusted() else { return }
        isTrusted = true
        stopPolling()
        Logger.permission.info("Accessibility 권한 부여 감지 — 재시작 없이 계속")
        onGranted?()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

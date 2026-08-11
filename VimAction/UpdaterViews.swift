//
//  UpdaterViews.swift
//  VimAction
//

import Combine
import Sparkle
import SwiftUI

/// Sparkle 공식 SwiftUI 통합 형태 — `canCheckForUpdates`(KVO)를 구독해 확인이 진행 중일 때
/// 버튼을 비활성화한다. Sparkle은 Observation이 아니라 KVO로 상태를 내보내므로 Combine
/// 브리지가 필요하다 (앱의 @Observable 관례에서 벗어나는 유일한 이유).
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// "Check for Updates…" 버튼 — 메뉴바 메뉴와 설정 About 탭이 공유한다. 클릭 이후의 모든
/// UI(발견 다이얼로그·다운로드 진행·설치·재실행)는 Sparkle 표준 UI가 맡는다.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

/// 자동 업데이트 확인 토글 — Sparkle 공식 예제의 @State + onChange 형태. 값의 영속은
/// Sparkle이 소유하고(UserDefaults `SUEnableAutomaticChecks`), 여기는 그 값을 읽고 쓸 뿐이다.
/// 사용자가 아직 Sparkle의 최초 동의 프롬프트(두 번째 실행 시)에 답하지 않았어도, 이 토글을
/// 켜면 그 자체가 동의 기록이 되어 프롬프트는 더 뜨지 않는다.
struct UpdaterSettingsToggle: View {
    private let updater: SPUUpdater
    @State private var automaticallyChecksForUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }

    var body: some View {
        Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
            .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                updater.automaticallyChecksForUpdates = newValue
            }
    }
}

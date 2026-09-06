//
//  ModeIndicatorController.swift
//  VimAction
//

import AppKit
import Foundation
import VimEngine

/// 모드 전환 → 기하 읽기 → 오버레이 표시를 잇는 조율자.
///
/// 갱신은 **이벤트 기반만**이다 — 타이머 폴링도, 키마다 재배치도 없다. PR 1의 트리거는 모드
/// 전환 하나이고, 포커스·창 이벤트 재앵커는 PR 2의 몫이다
/// (`20260906_mode-indicator-anchor-ladder-event-driven.md` 결정 3).
@MainActor
final class ModeIndicatorController {
    /// 기하 읽기 전용 직렬 큐. **리졸버의 `readQueue`를 재사용하지 않는 것이 계약이다** —
    /// 콜드 앱에서 이 읽기는 요소·position·size·창까지 AX 호출 여섯 번(최악 50ms×6)이 될 수
    /// 있는데, 리졸버 큐는 **키 디스패치가 의존하는 포커스 계열 캐시**를 먹인다. 표시용 읽기가
    /// 그 캐시를 지연시키면 앱 전환 직후 `.unresolved` 창이 넓어져 첫 편집이 조용히 떨어진다.
    /// QoS를 `.utility`로 낮춘 것도 같은 이유다(리졸버는 `.userInitiated`). ~600ms 프로브
    /// 때문에 큐를 따로 두는 `AXTrustProber`와 같은 근거·같은 형태다.
    private nonisolated static let geometryQueue = DispatchQueue(
        label: "dev.pilyang.VimAction.mode-indicator-geometry", qos: .utility)

    /// 아직 화면에 반영되지 않은 최신 전환. 읽는 도중 새 전환이 오면 여기만 덮어써
    /// **최신 라벨 하나로 접힌다**.
    private struct Request {
        var label: String
        var processID: pid_t
    }

    /// 패널은 첫 표시에서야 만든다 — 런치 시 `NSPanel`을 만들지 않고, 표시할 일이 없는
    /// 실행(권한 미허용, 계속 Insert)에서는 끝까지 만들어지지 않는다.
    private var panel: ModeIndicatorPanel?
    private var pending: Request?
    private var isReading = false
    /// 늦게 착지한 읽기를 버리기 위한 토큰 — **모든** 전환이 올린다. 읽는 도중 사다리가
    /// `.mode`를 벗어나면(마스터 off·킬스위치·disable 앱) `pending`을 비우는 것만으로는
    /// 부족하다: 이미 떠 있는 읽기가 착지해 "가로채지 않는데 NORMAL이라고 말하는" 라벨을
    /// 띄운다 (`FocusedElementResolver.refreshToken`과 같은 장치·같은 이유).
    private var token = 0

    /// 모드가 바뀌었다. **탭 콜백의 동기 구간에서 불린다** — 여기서 하는 일은 사다리 판정
    /// (순수) + 요청 대입 + 큐 적재 1회뿐이고, AX 읽기와 `NSScreen` 조회는 전부 뒤로 밀린다
    /// (콜백 경량 불변식, `20260725_callback-light-invariant.md`).
    ///
    /// 표시 조건은 메뉴바 사다리를 그대로 재사용한다 — `.mode`가 아니면(탭 고장·마스터 off·
    /// 앱별 disabled·Secure Input) 감춘다. 가로채지 않는 상태에서 모드 라벨을 띄우면
    /// 메뉴바에서 없앤 "가로채지 않는데 Normal이라고 말하는" 거짓말을 화면 한가운데서
    /// 되풀이하게 된다 (`20260906_mode-indicator-hybrid-display-policy.md` 결정 3).
    func modeDidChange(mode: Mode, indicator: MenuBarIndicator, processID: pid_t?) {
        token &+= 1
        guard case .mode = indicator, let processID else {
            pending = nil
            panel?.hide()
            return
        }
        pending = Request(label: mode.overlayLabel, processID: processID)
        pump()
    }

    /// 읽기는 **한 번에 하나만** 띄운다. 버스트 중 요청이 쌓이면 큐가 아니라 `pending` 한 칸이
    /// 최신 것만 들고 있다가 이번 읽기가 끝난 뒤 이어 돈다.
    private func pump() {
        guard !isReading, let request = pending else { return }
        pending = nil
        isReading = true
        let token = self.token
        Self.geometryQueue.async { [weak self] in
            let anchors = ModeIndicatorGeometryReader.read(processID: request.processID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finish(request, token: token, anchors: anchors)
                }
            }
        }
    }

    private func finish(
        _ request: Request, token: Int, anchors: ModeIndicatorLayout.Anchors
    ) {
        isReading = false
        // 읽는 사이에 전환이 또 왔다 — 이 결과는 이미 낡았다. 그리지 않고 바로 다음 읽기로
        // 넘어가야 낡은 라벨이 한 프레임 스치지 않는다. 사다리를 벗어난 전환이었다면
        // `pending`이 비어 있어 `pump()`가 no-op이고, 화면은 그쪽이 이미 감췄다.
        guard token == self.token else {
            pump()
            return
        }
        let size = ModeIndicatorPanel.size(for: request.label)
        // `NSScreen`은 메인에서만 읽는다 — 순수 계층은 그 결과를 값으로 받는다.
        let screens = NSScreen.screens
        guard let primary = screens.first,
            let frame = ModeIndicatorLayout.panelFrame(
                anchors: anchors, size: size, screens: screens.map(\.frame),
                primaryScreenMaxY: primary.frame.maxY)
        else {
            // 사다리의 마지막 단 — 붙일 곳이 없으면 표시하지 않는다.
            panel?.hide()
            return
        }
        let panel = panel ?? ModeIndicatorPanel()
        self.panel = panel
        panel.flash(request.label, at: frame)
    }
}

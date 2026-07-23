//
//  AppState.swift
//  VimAction
//

import AppKit
import Foundation
import Observation
import os
import VimEngine

/// 앱 셸이 관찰하는 UI 상태와 전역 컴포넌트(권한 모니터, 이벤트 탭)의 소유자.
@Observable
final class AppState {
    let permissionMonitor = AccessibilityPermissionMonitor()
    let eventTap = EventTapController()

    /// 앱 시작 시 1회: 권한 확인 → 탭 설치 시도, 미허용이면 부여 감지 폴링 시작.
    func bootstrap() {
        // TEST_HOST로 launch된 단위 테스트 실행 중에는 시동하지 않는다 —
        // 테스트가 라이브 이벤트 탭을 설치하거나 권한 폴링을 돌리면 안 된다.
        if isRunningUnderXCTest() {
            // 이 변수가 일반 launch에 새어 들어오면 앱이 통째로 비활성이 되므로 흔적을 남긴다.
            Logger.eventTap.notice("XCTest 환경변수 감지 — bootstrap 생략 (탭 설치·권한 폴링 비활성)")
            return
        }
        permissionMonitor.onGranted = { [eventTap] in
            eventTap.startIfPermitted()
        }
        permissionMonitor.refresh()
        // 미허용이어도 항상 호출한다 — "설치 보류" 로그가 launch 시 관측 가능해야 한다.
        eventTap.startIfPermitted()
        if !permissionMonitor.isTrusted {
            permissionMonitor.startPollingUntilGranted()
        }
    }

    /// 메뉴바 글리프 — 탭이 안 돌면 비활성(square.dashed), 토글 off면 square.slash,
    /// Secure Input 억제 중이면 lock.square, 그 외 모드 글리프 (PRD §7.7 최소 구현).
    /// 우선순위: 탭 고장 > 토글 off > Secure Input — 고장이면 토글과 무관하게 가로채기
    /// 불가능하고, 사용자가 끈 상태(off)는 OS의 일시 억제 표시보다 우선한다.
    var menuBarGlyph: String {
        switch eventTap.status {
        case .running, .secureInput:
            guard eventTap.isInterceptionEnabled else { return "square.slash" }
            return eventTap.status == .secureInput ? "lock.square" : eventTap.mode.menuBarGlyph
        default:
            return "square.dashed"
        }
    }

    /// Visual-line일 때만 참 — 메뉴바 라벨이 커스텀 "VL" 글리프로 wise를
    /// 구분한다 (fill 축은 "차단 여부"라 wise에 재사용할 수 없음). 모드 글리프가
    /// 실제로 표시되는 조건에서만 참이 되도록 `menuBarGlyph`와 같은 우선순위를 따른다.
    var menuBarShowsVisualLineGlyph: Bool {
        eventTap.status == .running && eventTap.isInterceptionEnabled
            && eventTap.mode == .visualLine
    }

    /// VoiceOver 등 사람이 읽는 메뉴바 상태 문구.
    var menuBarAccessibilityLabel: String {
        switch eventTap.status {
        case .running, .secureInput:
            guard eventTap.isInterceptionEnabled else { return "VimAction — disabled" }
            return eventTap.status == .secureInput
                ? "VimAction — paused for secure input"
                : "VimAction — \(eventTap.mode.displayName) mode"
        default:
            return "VimAction — inactive"
        }
    }
}

extension Mode {
    /// 메뉴바 아이템에 표시할 SF Symbol 이름. macOS 표현은 앱 레이어에만 둔다
    /// (엔진 `Mode`는 플랫폼을 모른다). fill은 "키 차단 여부" 축이다 — 차단
    /// 모드(Normal/Visual)는 fill, 통과 모드(Insert)는 미채움. Visual-line은
    /// 커스텀 "VL" 템플릿 글리프(`NSImage.visualLineMenuBarGlyph`)가 대신 표시되며
    /// 여기 값은 폴백이다 (`AppState.menuBarShowsVisualLineGlyph`).
    var menuBarGlyph: String {
        switch self {
        case .normal: "n.square.fill"
        case .insert: "i.square"
        case .visualChar, .visualLine: "v.square.fill"
        }
    }

    /// 접근성 레이블 등 사람이 읽는 모드 이름.
    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .insert: "Insert"
        case .visualChar: "Visual"
        case .visualLine: "Visual Line"
        }
    }
}

extension NSImage {
    /// Visual-line 전용 메뉴바 글리프 — SF Symbols의 글자 사각형은 1글자뿐이라
    /// (vl.square 부재) "VL"을 채운 사각형에서 뚫어낸 커스텀 템플릿 이미지를 그린다.
    /// `v.square.fill`과 같은 시각 문법(채운 라운드 사각형 + 글자 컷아웃)을 유지하며,
    /// isTemplate이라 메뉴바 라이트/다크 외양을 시스템이 입힌다.
    static let visualLineMenuBarGlyph: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5
            ).fill()
            let text = NSAttributedString(
                string: "VL",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: NSColor.black,
                ]
            )
            let textSize = text.size()
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
            text.draw(
                at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2)
            )
            return true
        }
        image.isTemplate = true
        return image
    }()
}

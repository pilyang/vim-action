//
//  VimActionApp.swift
//  VimAction
//
//  Created by 양재필 on 7/12/26.
//

import SwiftUI
import VimEngine

@main
struct VimActionApp: App {
    // 엔진 패키지 링크 검증용 최소 사용. 실제 탭↔엔진 연결은 다음 플랜에서 대체된다.
    private let engine = VimEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

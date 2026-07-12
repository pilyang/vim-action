//
//  SettingsView.swift
//  VimAction
//

import SwiftUI

/// 설정 창 뼈대. 권한 온보딩·키맵 편집은 다음 마일스톤에서 채운다.
struct SettingsView: View {
    var body: some View {
        Form {
            Section("VimAction") {
                LabeledContent("Version", value: "1.0")
            }
            Section {
                Text("권한 온보딩과 키맵 설정은 다음 마일스톤에서 추가됩니다.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
    }
}

#Preview {
    SettingsView()
}

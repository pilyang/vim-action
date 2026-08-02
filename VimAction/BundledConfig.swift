//
//  BundledConfig.swift
//  VimAction
//

import Foundation
import os

/// 번들에 동봉된 기본 설정 파일 읽기 — `ConfigSeeder`는 `Bundle`을 모르므로 앱이
/// 문자열로 꺼내 넘긴다. 원본은 `VimAction/BundledConfig/` 하위 yaml 3개다.
///
/// 번들 기본값은 병합 계층이 아니라 **첫 실행 시딩용 초기 내용**이다
/// (`20260802_bundled-defaults-seeded-not-merged.md`) — 런타임 동작은 항상
/// `~/.config/vim-action/`의 사용자 파일만 읽는다.
nonisolated enum BundledConfig {
    /// 동봉 프로파일 대상 앱 — 설치 즉시 위험 해소(Slack의 Return=전송) + 프로파일
    /// 작성 시의 실물 예시 문서 역할 (`20260802_bundled-default-profiles-slack-notion.md`).
    static let profileBundleIDs = ["com.tinyspeck.slackmacgap", "notion.id"]

    static func config() -> String? {
        read(resource: "config")
    }

    static func profiles() -> [String: String] {
        var profiles: [String: String] = [:]
        for bundleID in profileBundleIDs {
            if let contents = read(resource: bundleID) {
                profiles[bundleID] = contents
            }
        }
        return profiles
    }

    /// 누락은 사용자 조건이 아니라 **패키징 버그**다 — 시딩이 조용히 빠지면 첫 실행
    /// 기본 동작(off 목록·Slack 보호)이 통째로 사라지므로 error로 남긴다.
    private static func read(resource name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "yaml"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            Logger.config.error("번들 기본 리소스 누락 — \(name, privacy: .public).yaml (패키징 버그)")
            return nil
        }
        return contents
    }
}

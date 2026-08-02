//
//  ConfigStoreTests.swift
//  VimActionTests
//

import Foundation
import Testing
import VimActionConfig
@testable import VimAction

/// 스토어 테스트가 주입하는 인메모리 파일시스템 — 패키지 `FixtureSupport`의 미러다
/// (테스트 타깃 간 코드 공유가 없어 복제한다). 실제 `~/.config`는 어떤 테스트도 건드리지
/// 않는다: `.live` seam은 여기서 절대 쓰지 않는다.
/// (테스트는 단일 스레드에서 돌고 seam 클로저가 `@Sendable`이라 `@unchecked`로 둔다.)
private final class InMemoryFileSystem: @unchecked Sendable {
    var files: [String: String]
    var directories: Set<String> = []
    var unwritablePaths: Set<String> = []

    init(files: [String: String] = [:]) {
        self.files = files
    }

    var loaderFileSystem: ConfigLoader.FileSystem {
        ConfigLoader.FileSystem(
            readFile: { [self] path in files[path] },
            listDirectory: { [self] directory in
                files.keys
                    .filter { $0.hasPrefix(directory + "/") }
                    .map { String($0.dropFirst(directory.count + 1)) }
                    .filter { !$0.contains("/") }
            }
        )
    }

    var seederFileSystem: ConfigSeeder.FileSystem {
        ConfigSeeder.FileSystem(
            fileExists: { [self] path in files[path] != nil },
            createDirectory: { [self] path in
                directories.insert(path)
                return true
            },
            writeFile: { [self] path, contents in
                guard !unwritablePaths.contains(path) else { return false }
                files[path] = contents
                return true
            }
        )
    }
}

private let configPath = "config/config.yaml"
private let profilesDirectory = "config/profiles"

@MainActor
private func makeStore(
    _ fileSystem: InMemoryFileSystem,
    bundledConfig: String? = nil,
    bundledProfiles: [String: String] = [:]
) -> ConfigStore {
    ConfigStore(
        configPath: configPath, profilesDirectory: profilesDirectory,
        loaderFileSystem: fileSystem.loaderFileSystem,
        seederFileSystem: fileSystem.seederFileSystem,
        bundledConfig: { bundledConfig },
        bundledProfiles: { bundledProfiles })
}

@MainActor
struct ConfigStoreTests {
    @Test("시딩은 없는 파일만 만들고, 기존 파일은 내용을 보지 않고 둔다")
    func seedingNeverTouchesExistingFiles() {
        let fileSystem = InMemoryFileSystem(files: [configPath: "apps:\n  user.app: false\n"])
        let store = makeStore(
            fileSystem,
            bundledConfig: "apps:\n  bundled.app: false\n",
            bundledProfiles: ["notion.id": "name: Notion\n"])

        store.seedAndLoad()

        #expect(fileSystem.files[configPath] == "apps:\n  user.app: false\n", "기존 config는 무수정")
        #expect(fileSystem.files["\(profilesDirectory)/notion.id.yaml"] == "name: Notion\n")
        #expect(store.disabledBundleIDs == ["user.app"], "로드는 사용자 파일 기준")
    }

    @Test("apps 맵의 false 항목만 disable 집합이 된다")
    func disabledBundleIDsDerivation() {
        let fileSystem = InMemoryFileSystem(files: [
            configPath: "apps:\n  off.app: false\n  on.app: true\n"
        ])
        let store = makeStore(fileSystem)

        store.seedAndLoad()

        #expect(store.disabledBundleIDs == ["off.app"])
    }

    @Test("프로파일이 실행용으로 변환돼 bundle id로 조회된다 — 없으면 .empty")
    func resolvedProfileLookup() {
        let fileSystem = InMemoryFileSystem(files: [
            "\(profilesDirectory)/com.tinyspeck.slackmacgap.yaml": """
            name: Slack
            actions:
              open_line: disabled
            """
        ])
        let store = makeStore(fileSystem)

        store.seedAndLoad()

        let slack = store.resolvedProfile(for: "com.tinyspeck.slackmacgap")
        #expect(slack.name == "Slack")
        #expect(slack.actionOverrides == [.openLine: .disabled])
        #expect(store.resolvedProfile(for: "com.apple.TextEdit") == .empty)
        #expect(store.resolvedProfile(for: nil) == .empty)
    }

    /// 최초 로드는 에러가 있어도 부분 스냅샷을 적용한다 — 깨진 파일은 로더가 부재 처리했고,
    /// 유지할 직전 설정이 없다. 에러는 UI가 보여줄 수 있게 남는다.
    @Test("최초 로드의 파일 통째 에러 — 부분 적용 + 에러 노출")
    func initialLoadAppliesPartialSnapshotDespiteErrors() {
        let fileSystem = InMemoryFileSystem(files: [
            configPath: "apps: [broken",
            "\(profilesDirectory)/notion.id.yaml": "name: Notion\n",
        ])
        let store = makeStore(fileSystem)

        store.seedAndLoad()

        #expect(store.errors.count == 1)
        #expect(store.errors.first?.file == configPath)
        #expect(store.disabledBundleIDs.isEmpty, "깨진 config.yaml은 부재 취급")
        #expect(store.resolvedProfile(for: "notion.id").name == "Notion", "성한 파일은 적용된다")
    }

    /// 리로드 실패의 계약 — **직전 유효 설정 유지** + 에러는 최신으로 노출.
    /// (config.yaml 키 중복 하나로 off 앱이 전부 켜지는 사고를 막는 규칙.)
    @Test("리로드 실패 시 직전 유효 스냅샷이 유지된다")
    func failedReloadKeepsLastGoodSnapshot() {
        let fileSystem = InMemoryFileSystem(files: [configPath: "apps:\n  off.app: false\n"])
        let store = makeStore(fileSystem)
        store.seedAndLoad()
        #expect(store.disabledBundleIDs == ["off.app"])

        fileSystem.files[configPath] = "apps: [broken"
        let succeeded = store.reload()

        #expect(!succeeded)
        #expect(store.errors.count == 1, "에러는 사용자에게 보여줄 수 있게 최신이다")
        #expect(store.disabledBundleIDs == ["off.app"], "직전 유효 설정 유지")

        fileSystem.files[configPath] = "apps:\n  other.app: false\n"
        #expect(store.reload())
        #expect(store.errors.isEmpty)
        #expect(store.disabledBundleIDs == ["other.app"], "복구되면 새 값이 적용된다")
    }

    @Test("리로드가 프로파일 변경도 반영한다 — 수동 리로드가 반영 단위")
    func reloadRefreshesProfiles() {
        let fileSystem = InMemoryFileSystem(files: [
            "\(profilesDirectory)/notion.id.yaml": "scroll:\n  half_page_lines: 12\n"
        ])
        let store = makeStore(fileSystem)
        store.seedAndLoad()
        #expect(store.resolvedProfile(for: "notion.id").halfPageLines == 12)

        fileSystem.files["\(profilesDirectory)/notion.id.yaml"] = "scroll:\n  half_page_lines: 20\n"
        #expect(store.reload())

        #expect(store.resolvedProfile(for: "notion.id").halfPageLines == 20)
    }

    @Test("항목 단위 경고는 값으로 노출된다 — 앱이 로그·UI로 흘릴 근거")
    func warningsAreExposed() {
        let fileSystem = InMemoryFileSystem(files: [
            configPath: "apps:\n  some.app: maybe\n"
        ])
        let store = makeStore(fileSystem)

        store.seedAndLoad()

        #expect(!store.warnings.isEmpty)
        #expect(store.errors.isEmpty, "항목 경고는 파일 통째 에러가 아니다")
    }
}

/// 메뉴바·Settings 공용 상태 문구 — 순수 함수라 전 분기를 커버한다.
struct ConfigStatusTextTests {
    @Test("에러 없음 — 프로파일 수 표시 (단수/복수)")
    func showsProfileCount() {
        #expect(configStatusText(profileCount: 0, errors: []) == "Config: 0 profiles")
        #expect(configStatusText(profileCount: 1, errors: []) == "Config: 1 profile")
        #expect(configStatusText(profileCount: 2, errors: []) == "Config: 2 profiles")
    }

    @Test("에러 1건 — 파일 이름을 그 자리에서 보여준다")
    func showsSingleErrorFile() {
        let error = ConfigError(file: "/home/user/.config/vim-action/config.yaml", message: "dup")
        #expect(configStatusText(profileCount: 3, errors: [error]) == "Config error — config.yaml")
    }

    @Test("에러 여러 건 — 파일 수로 접는다")
    func showsErrorFileCount() {
        let errors = [
            ConfigError(file: "a.yaml", message: "x"), ConfigError(file: "b.yaml", message: "y"),
        ]
        #expect(configStatusText(profileCount: 0, errors: errors) == "Config errors — 2 files")
    }
}

/// Settings "Configuration" 섹션의 파생 문구.
struct ConfigSectionTextTests {
    @Test("disable 앱 목록 — 비면 None, 있으면 정렬 목록")
    func disabledAppsListing() {
        #expect(disabledAppsText([]) == "None")
        #expect(disabledAppsText(["b.app", "a.app"]) == "a.app\nb.app")
    }

    @Test("프로파일 목록 — 이름이 있으면 병기한다")
    func profileListing() {
        #expect(profilesText([:]) == "None")
        #expect(
            profilesText([
                "notion.id": AppProfile(),
                "com.tinyspeck.slackmacgap": AppProfile(name: "Slack"),
            ]) == "com.tinyspeck.slackmacgap (Slack)\nnotion.id")
    }
}

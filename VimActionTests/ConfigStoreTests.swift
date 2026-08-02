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
    /// 쓰기 seam이 **호출됐는지** — 내용 비교만으로는 "같은 바이트로 덮어쓰기"를 못 잡는다.
    var writtenPaths: [String] = []

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
                writtenPaths.append(path)
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

/// 메뉴 'Create/Open Profile'의 scaffold 경로. 이 기능은 UI 읽기 전용 결정의 유일한
/// 예외(없는 파일 신규 생성)라, "기존 파일을 건드리지 않는다"가 계약의 전부다.
@MainActor
struct ProfileScaffoldStoreTests {
    private let slack = "com.tinyspeck.slackmacgap"

    @Test("프로파일이 없으면 scaffold를 만들고 그 경로를 준다")
    func createsScaffoldWhenMissing() {
        let fileSystem = InMemoryFileSystem()
        let store = makeStore(fileSystem)

        let path = store.prepareProfileFile(for: slack)

        // 시더가 내부에서 만드는 경로와 스토어의 경로 조합이 어긋나면 안 된다.
        #expect(path == store.profilePath(for: slack))
        #expect(path == "\(profilesDirectory)/\(slack).yaml")
        #expect(fileSystem.files[path ?? ""]?.hasPrefix("#") == true)
    }

    /// scaffold가 사용자 프로파일을 날리면 "UI는 YAML을 쓰지 않는다" 결정 자체가 무너진다.
    @Test("기존 프로파일이 있으면 writeFile이 아예 호출되지 않는다")
    func neverWritesOverExistingProfile() {
        let path = "\(profilesDirectory)/\(slack).yaml"
        let fileSystem = InMemoryFileSystem(files: [path: "name: My Slack\n"])
        let store = makeStore(fileSystem)

        #expect(store.prepareProfileFile(for: slack) == path)

        #expect(fileSystem.writtenPaths.isEmpty, "쓰기 seam을 타지 않는 것이 계약이다")
        #expect(fileSystem.files[path] == "name: My Slack\n")
    }

    @Test("쓰기 실패는 nil — 없는 파일을 열려 하지 않는다")
    func failedWriteReturnsNil() {
        let fileSystem = InMemoryFileSystem()
        fileSystem.unwritablePaths = ["\(profilesDirectory)/\(slack).yaml"]
        let store = makeStore(fileSystem)

        #expect(store.prepareProfileFile(for: slack) == nil)
    }

    /// bundle id는 다른 프로세스에서 흘러온 문자열이 파일 경로가 되는 유일한 지점이다.
    @Test("파일명으로 쓸 수 없는 bundle id는 쓰지 않고 nil")
    func rejectsUnusableBundleIDs() {
        let fileSystem = InMemoryFileSystem()
        let store = makeStore(fileSystem)

        #expect(store.prepareProfileFile(for: "../../etc/passwd") == nil)
        #expect(store.prepareProfileFile(for: ".hidden") == nil)
        #expect(store.prepareProfileFile(for: "") == nil)
        #expect(fileSystem.writtenPaths.isEmpty)
    }

    /// 템플릿이 실제 파서를 통과하는지 — 로더를 거치므로 파싱 경로가 프로덕션과 같다.
    @Test("생성한 scaffold는 리로드에서 에러 없이 빈 프로파일로 읽힌다")
    func scaffoldReloadsCleanly() {
        let fileSystem = InMemoryFileSystem()
        let store = makeStore(fileSystem)
        store.seedAndLoad()

        _ = store.prepareProfileFile(for: slack)
        #expect(store.resolvedProfile(for: slack) == .empty, "생성만으로는 적용되지 않는다")

        #expect(store.reload())
        #expect(store.errors.isEmpty)
        #expect(store.warnings.isEmpty, "전부 주석이라 무시할 항목도 없다")
        #expect(store.appliedSnapshot.profiles[slack] != nil)
        #expect(store.resolvedProfile(for: slack) == .empty, "빈 프로파일이라 동작은 그대로다")
    }

    @Test("hasProfile은 파일 유무를 그대로 돌려준다 — 메뉴 제목의 근거")
    func hasProfileReflectsDisk() {
        let fileSystem = InMemoryFileSystem()
        let store = makeStore(fileSystem)
        #expect(!store.hasProfile(for: slack))

        _ = store.prepareProfileFile(for: slack)

        #expect(store.hasProfile(for: slack))
    }
}

/// scaffold 템플릿 자체의 계약.
struct ProfileScaffoldTemplateTests {
    /// 활성 키가 하나라도 들어가면 "프로파일 열기" 클릭만으로 그 앱 동작이 바뀐다.
    @Test("비어 있지 않은 모든 줄이 주석이다 — 만들어도 동작이 바뀌지 않는다")
    func everyLineIsCommented() {
        let lines = profileScaffoldYAML(bundleID: "com.apple.TextEdit")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.hasPrefix("#") })
    }

    @Test("어느 앱의 파일인지 본문에 적힌다")
    func namesTheTargetApp() {
        #expect(profileScaffoldYAML(bundleID: "com.apple.TextEdit").contains("com.apple.TextEdit"))
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

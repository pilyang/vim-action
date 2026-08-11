# 보안 하드닝 — 릴리스 파이프라인 공급망 + 빌드 설정 고정

- **생성일**: 2026-08-12
- **갱신일**: 2026-08-12

## 목표

상위 세션 보안 점검의 4개 지적(#1 Sparkle 툴 무검증 다운로드, #2 hardened runtime 미고정, #3 create-dmg 무핀 설치, #4 actions 태그 핀)을 PR 2개로 수정한다. 코드 검증·수정안·다이제스트는 확정됨(아래 컨텍스트) — 남은 것은 구현, PR, 다음 릴리스 e2e.

## 완료된 것

- [x] 4건 전부 실코드 검증 + 사실관계 교정 (2026-08-12, security-hardening worktree) — 아래 "검증된 사실"
- [x] **단일 PR 구현 완료** (2026-08-12, `security-hardening` 브랜치에 커밋됨): release.yml(#1 `SPARKLE_SHA256` 검증, #3 create-dmg SHA 핀, 선택6 키체인 조기 삭제 — 이후 스텝의 키체인 비의존 스텝별 확인 후 포함), pbxproj `ENABLE_HARDENED_RUNTIME`(#2), checkout SHA 핀 + dependabot.yml(#4), KEYBINDINGS.md 클립보드 경고(#5)
- [x] 로컬 검증 통과: CI 동일 앱 빌드 성공(경고 추가 0), 엔진 테스트 100건 통과, `shasum -c` 네거티브 테스트(틀린 다이제스트 → exit 1), create-dmg 핀 SHA에서 `--version` 정상(1.3.0), 워크플로 YAML 파스 OK
- [x] decisions 기록: [20260812_ci-signing-job-tools-digest-pinned.md](../../decisions/references/20260812_ci-signing-job-tools-digest-pinned.md)
- [x] [PR #47](https://github.com/pilyang/vim-action/pull/47) CI 통과 → 머지 (main `1e02271`)
- [x] **v0.1.1 태그에서 e2e 확인** (2026-08-12): 하드닝된 release.yml 전 스텝 성공 — Sparkle tarball 다이제스트 검증 통과, 핀 SHA create-dmg로 DMG 생성(재시도 없이 1회), 키체인 조기 삭제 후 공증·appcast·릴리스·cask bump 전부 정상. 릴리스 DMG 실측: `codesign -dv`에서 앱·중첩 Sparkle Updater 모두 `flags=0x10000(runtime)`, 버전 0.1.1/0.1.1, Gatekeeper "Notarized Developer ID"

## 남은 것

- 없음 — 4건 전부 반영·머지되고 릴리스 e2e까지 확인됨. 이 플랜은 완료 처리(삭제) 대상.

## 진행 중 컨텍스트

**현재 상태 (2026-08-12)**: 완료. PR #47 머지(main `1e02271`) 후 v0.1.1 릴리스에서 하드닝된 파이프라인이 실제로 동작함을 확인. 아래 "검증된 사실"의 라인 번호는 구현 **전** 기준.

### 검증된 사실 (2026-08-12, 구현 전 기준 라인 번호)

- **#1 (Medium)**: `release.yml` 145–161행 Generate appcast — 149–150행 curl 무검증 다운로드, 152행 tar, 155행 `generate_appcast`에 EdDSA 개인키 전달. 키체인은 45–62행 생성 → 193–197행(`if: always()`)에서만 삭제라 이 시점에 생존. **교정 1건**: 대조 근거의 checksum `34b9b20…`은 이 레포 Package.swift가 아니라 **Package.resolved가 핀한 Sparkle 커밋(`79bc9e87…`) 안의 Package.swift**에 있음 — SPM 경로가 다이제스트로 끝까지 고정된다는 주장 자체는 성립.
- **#2 (Low)**: pbxproj에 `ENABLE_HARDENED_RUNTIME` 전무. 앱 타깃 config 두 블록: Debug `B52D10C2`(433행 `ENABLE_APP_SANDBOX = NO`), Release `B52D10C3`(465행 동일). 다른 `CODE_SIGN_STYLE` 4곳(493·513·532·550행)은 테스트 타깃 — 건드리지 않음.
- **#3 (Low)**: `release.yml:103` `brew install create-dmg` — 서술대로 확인.
- **#4 (Low)**: 워크플로우 전체에서 서드파티 액션은 `actions/checkout@v4` 3곳뿐(release.yml:39, ci.yml:21·29). **교정**: 릴리스 잡 시크릿은 4개가 아니라 **5개**(TAP_PUSH_TOKEN 포함) — 논지는 오히려 강화.
- **#5 (정보성)**: `EditKeyMapper.swift:416–429` `operatorStrokes` — `.delete`/`.change` → `[cut]`, `cut = Cmd-X`(448행). 406–408행 주석이 "시스템 클립보드 = 무명 레지스터" 의도 설계임을 명시. **코드 수정 없음** — 문서 경고 한 줄만 선택 항목.

### 확정 상수 (태그성 SHA는 구현 시점에 `gh api`로 재확인)

- `SPARKLE_SHA256 = 015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc` — 실측 다운로드 + **Homebrew cask `sparkle.rb`와 교차 일치** (독립 2원 확인 완료).
- `actions/checkout` v4 태그 → `11d5960a326750d5838078e36cf38b85af677262` (= v4.4.0). 주석으로 `# v4.4.0` 병기.
- `create-dmg` v1.3.0 태그 → `a2b71d0fda6d0df2a86dc7f67082d4d73e84c59f`.

### 수정안 세부

**release.yml 공급망 (#1+#3+선택6):**

1. env에 `SPARKLE_SHA256` 추가(31행 `SPARKLE_VERSION` 옆, "버전 bump 시 함께 갱신" 주석). Generate appcast 스텝에서 tar 전에
   `echo "$SPARKLE_SHA256  $RUNNER_TEMP/sparkle.tar.xz" | shasum -a 256 -c -`
   (해시-파일명 사이 공백 2칸; 불일치 시 비0 종료로 잡 중단).
2. Package DMG 스텝의 `brew install create-dmg` 제거 →
   `git clone https://github.com/create-dmg/create-dmg "$RUNNER_TEMP/create-dmg"` + `git -C ... checkout <핀 SHA>` 후 `"$RUNNER_TEMP/create-dmg/create-dmg"`로 호출 (create-dmg는 셸 스크립트라 설치 불필요, git 체크아웃이 내용을 SHA로 고정). 대안 `hdiutil create`는 DMG 레이아웃(아이콘 배치·drop-link)을 잃어 기각.
3. (선택, 소폭 개선) Package DMG 직후 키체인 조기 삭제 스텝 — 이후 스텝은 키체인 불필요(notarize=ASC API 키, appcast=EdDSA 시크릿, release/tap=토큰). 마지막 `if: always()` 백스톱은 유지(`|| true`라 중복 무해).

**설정 고정 (#2+#4+#5):**

1. pbxproj `B52D10C2`·`B52D10C3` 두 블록에 `ENABLE_HARDENED_RUNTIME = YES;` 추가 (433·465행 `ENABLE_APP_SANDBOX` 다음 줄, 알파벳 순 유지). Debug 디버깅은 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` 기본값이 get-task-allow를 주입해 lldb 계속 동작. CLAUDE.md 도그푸딩 명령의 `ENABLE_HARDENED_RUNTIME=YES` 오버라이드는 중복이 되지만 무해 — 문서 수정 안 함.
2. `actions/checkout@v4` 3곳을 `actions/checkout@<SHA> # v4.4.0` 형태로. `.github/dependabot.yml` 신규(`package-ecosystem: github-actions`, weekly) — Dependabot이 SHA 핀을 버전 주석과 함께 갱신.
3. (선택 #5) `docs/KEYBINDINGS.md` 오퍼레이터 표 근처에 "delete/change는 시스템 클립보드(무명 레지스터)를 덮어쓴다" 한 줄.

### 검증 방법

- **PR A**: 수정 스니펫 로컬 재현(정상 다이제스트 통과는 이미 실측), 오염 다이제스트 네거티브 테스트(`shasum -c` 실패로 비0 종료 확인), create-dmg SHA 체크아웃 후 `--version` 실행 확인. 완전 e2e는 다음 태그 push에서만 가능 — 아티팩트 산출 로직은 무변경이라 다이제스트만 맞으면 동작 동일.
- **PR B**: CI 앱 빌드(`CODE_SIGNING_ALLOWED=NO`)는 서명 플래그를 무시하므로 통과 필수. 추가로 로컬 Release 빌드를 **CLI 오버라이드 없이** 돌려 `codesign -dv`에서 `flags=0x10000(runtime)` 확인(pbxproj가 이제 속성을 보유한다는 증명). #4는 PR 자체의 CI 통과(핀 SHA로 checkout 동작)가 검증.

## 관련 링크

- 배포 준비 플랜(release.yml의 유래): [20260810_release-prep.md](20260810_release-prep.md)
- decisions: 구현 시 공급망 핀 정책 기록 예정

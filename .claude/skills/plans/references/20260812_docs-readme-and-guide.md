# 문서 정비 — README 재작성 + 데모 GIF (docs/readme-and-guide 브랜치)

- **생성일**: 2026-08-12
- **갱신일**: 2026-08-12

## 목표

사용자 유입을 받을 수 있는 repo 첫인상 완성: 실제 릴리스 상태(v0.1.x, Homebrew, Sparkle)를 반영한 영어 README + 한국어 병행본, 데모 GIF까지 포함해 PR 하나로 머지.

## 완료된 것

- [x] 방향 확정 (사용자와 합의): **영어 단일** README(한국어 병행본은 만들었다가 제거 — Vim 쓰는 한국 개발자에게 영어 README는 부담 아님, docs도 전부 영어), 짧은 가이드(온보딩·설정)는 README 안에 포함(길어지면 그때 docs/로 분리), GIF는 이 브랜치에서 PR 전에 처리.
- [x] `README.md` 영어 재작성 — Install(brew cask `pilyang/tap/vimaction`, DMG)·Getting started(권한 온보딩, 메뉴바 글리프 표)·Keybindings 미리보기·Per-app configuration·Privacy & safety·How it works·Development·Related projects(kindaVim·SketchyVim, 중립 서술)·Acknowledgements(Vim/Neovim·Sparkle·Yams)·MIT. 낡은 "실행 계층 미구현" 경고·Stage 로드맵·"라이선스 미정" 제거.
- [x] config 문서 — 신규 `docs/CONFIGURATION.md`(전체 레퍼런스: config.yaml `apps:` 맵, 프로파일 필드 4종, 키 토큰 표기, 모션 12종·액션 5종 표, 에러 처리, 시딩/소유권) + README Per-app configuration 섹션에 Slack `open_line: [shift-return]` 대표 예시와 CONFIGURATION.md 링크 추가. 분리 근거: KEYBINDINGS.md와 같은 "README 미리보기 + docs/ 전체 레퍼런스" 패턴. `strategy:`는 계획대로 미문서.

## 남은 것

- [ ] GitHub 렌더링 최종 확인 (GIF·글리프 표 인라인 이미지·스크린샷 2장).
- [ ] 최종 검토 후 PR 생성 (base: main).
- [ ] (별도) repo Settings → Social preview에 `assets/social-preview/github-social-preview.png` 업로드 여부 확인.

## 진행 중 컨텍스트

- `docs/assets/demo.gif`(960×336, 355KB, 193프레임)는 `assets/readme/video-without-keycast.mov`(메인 체크아웃)에서 **AVFoundation+ImageIO Swift 스크립트로 생성** — 렌더 스크립트는 `assets/readme/render-demo-gif.swift`에 보관(세그먼트 컷 8.8–22.45s + 26.2–32.5s로 중복 삭제·붙여넣기 사이클 제거, 1.25배속 12fps, 크롭 y72–520, **메뉴바 글리프 확대 칩 합성**(우상단 "menu bar" — 모드 전환 i/N/Vl 표시), 원본의 스트레이 오타 "back.b"의 b를 줄 수 자동 감지로 픽셀 패치, 하단 키캡 캡션 6구간 — 복원 캡션은 `P`). ffmpeg/gifski 불필요.
- `docs/assets/how-it-works.gif`(960×422, 174KB, 6초 실시간)는 `video-with-keycast.mov`의 11.3–17.3s에서 생성 — 텍스트 밴드(y188–428)와 KeyCastr 오버레이 밴드(y600–920)를 상하로 붙인 구성(중간 빈 공간 제거), 스크립트는 `assets/readme/render-howitworks-gif.swift`. `^[`·`b→⌥←`·`$→⌘→`·`0→⌘←` 번역 짝이 보이는 구간.
- **글리프 표 인라인 아이콘 7종**(`docs/assets/menubar-*.png`, 56×56)은 사용자가 찍은 메뉴바 캡처(`assets/readme/menu-icon-*.png`)에서 크롭 — 단 **`menubar-secure-input.png`(lock)만은 캡처가 아니라 앱이 쓰는 `lock.square` SF Symbol을 캡처 배경 위에 렌더**한 것(Secure Input 상태 연출이 번거로워서). 재생성 좌표·코드는 세션 스크래치라 필요 시 캡처에서 다시 크롭하면 됨.
- `docs/assets/settings-permission.png` = `assets/readme/setting-perm-required.png`, `docs/assets/menubar-menu.png` = `assets/readme/menubar-perm-granted.png`(Ghostty 최전면 + Disable 체크 상태) 이름만 바꿔 복사.
- `docs/assets/icon.png`(README 헤더용, 1024px)는 설치된 `/Applications/VimAction.app`의 **시스템 렌더링 아이콘을 NSWorkspace로 추출**한 것 — 아이콘이 바뀌면 같은 방법으로 재추출 (`NSWorkspace.shared.icon(forFile:)` → PNG 덤프).
- `strategy:` 프로파일 필드는 **의도적으로 미문서** — PR-E 스키마 확정 전까지 사용자 문서화 금지 (architecture profiles-and-config의 미결 질문 참조). "How it works"는 KEYBINDINGS.md와 같은 수위("native editing commands, AX where enabled")로만 서술해 둠.
- 최소 macOS 버전은 pbxproj `MACOSX_DEPLOYMENT_TARGET = 26.5` 기준으로 26.5+로 표기함 — 의도한 최소 버전이 더 낮으면 pbxproj부터 조정 필요.

## 관련 링크

- architecture: [profiles-and-config.md](../../architecture/references/profiles-and-config.md) (strategy 미문서 근거), [system-overview.md](../../architecture/references/system-overview.md)

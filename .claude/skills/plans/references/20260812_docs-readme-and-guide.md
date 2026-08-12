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

- [ ] 데모 GIF 녹화·삽입 — README 상단의 주석 처리된 `docs/assets/demo.gif` 블록을 살리면 됨 (Notes/Notion에서 Normal 모션 + `ciw` 류 오퍼레이터 시연 권장).
- [ ] 최종 검토 후 PR 생성 (base: main).

## 진행 중 컨텍스트

- `docs/assets/icon.png`(README 헤더용, 1024px)는 설치된 `/Applications/VimAction.app`의 **시스템 렌더링 아이콘을 NSWorkspace로 추출**한 것 — 아이콘이 바뀌면 같은 방법으로 재추출 (`NSWorkspace.shared.icon(forFile:)` → PNG 덤프).
- `strategy:` 프로파일 필드는 **의도적으로 미문서** — PR-E 스키마 확정 전까지 사용자 문서화 금지 (architecture profiles-and-config의 미결 질문 참조). "How it works"는 KEYBINDINGS.md와 같은 수위("native editing commands, AX where enabled")로만 서술해 둠.
- 최소 macOS 버전은 pbxproj `MACOSX_DEPLOYMENT_TARGET = 26.5` 기준으로 26.5+로 표기함 — 의도한 최소 버전이 더 낮으면 pbxproj부터 조정 필요.

## 관련 링크

- architecture: [profiles-and-config.md](../../architecture/references/profiles-and-config.md) (strategy 미문서 근거), [system-overview.md](../../architecture/references/system-overview.md)

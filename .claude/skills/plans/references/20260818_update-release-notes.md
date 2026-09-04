# 업데이트에 릴리스 노트(변경사항) 노출

- **생성일**: 2026-08-18
- **갱신일**: 2026-09-04

## 목표

업데이트할 때 "새 버전이 있다"만 알려주는 지금 상태에서 나아가, **그 버전에서 무엇이 추가·변경됐는지(릴리스 노트/변경사항 목록)를 사용자가 업데이트 전에 볼 수 있게** 한다.

## 완료된 것

- [x] 릴리스 노트의 원천 결정 — **annotated tag 본문**(제목 줄 제외)이 원본이고, appcast `<description>`과 GitHub Release 본문이 모두 여기서 파생된다. `CHANGELOG.md`(이중 관리)·GitHub 자동 생성 노트 단독(PR 제목 덤프) 기각
- [x] 릴리스 파이프라인 배선 — `release.yml`에 `Extract release notes from tag` 게이트 추가(annotated 여부 + 빈 본문 검사, 빌드 전), `generate_appcast`에 `--embed-release-notes`·`--full-release-notes-url`, `gh release create`에 `--notes-file`
- [x] 작성 규칙 정리 — `CLAUDE.md` 커밋·릴리스 태그 컨벤션 섹션에 원본·형식·분량(문단 1~2개) 규칙 추가. 분량은 문서 가이드로만 두고 CI는 강제하지 않는다
- [x] architecture 최종 상태 갱신 — [app-shell.md](../../architecture/references/app-shell.md) Sparkle 문단

## 남은 것

- [ ] **첫 실제 릴리스에서 노출 확인** — ① 게이트 로그의 `tag object type`이 `tag`인지(= `actions/checkout`이 annotated tag 객체를 가져온다는 가정의 유일한 실증 지점, 아니면 `gh api .../git/tags/{sha}` 폴백으로 전환) ② `cat dist/appcast.xml`에 `<description sparkle:format="markdown">`·`<sparkle:fullReleaseNotesLink>`가 있고 `sparkle:releaseNotesLink`는 없는지 ③ Release 본문에서 산문이 "What's Changed" 위에 붙었는지 ④ 구버전 앱으로 업데이트 다이얼로그·Version History 버튼 실물 확인

## 진행 중 컨텍스트

파이프라인·문서 변경은 끝났고 남은 것은 실물 검증뿐이다. 검증이 끝나면 이 플랜은 완료 처리(문서 삭제 + 인덱스 제거) 대상이다.

이번 범위에서 **의도적으로 뺀 것**: About 탭 "Release Notes" 링크(`AboutLinks`에 URL 한 줄 + `Link` 한 줄이면 되지만 앱 코드를 건드리지 않기로 함), 인앱 "What's New" 창(노트를 번들하거나 네트워크로 받아야 해서 README의 "네트워크 트래픽은 Sparkle뿐" 주장과 충돌).

decisions 문서는 만들지 않았다 — 배선이 `release.yml`에 주석과 함께 드러나 있어 코드에서 역추적 가능하다는 판단. 파이프라인만 봐서는 안 보이는 두 가지(아이템 1개 제약, `--clobber` 정정 예외 경로)는 그 워크플로 주석에 남겼다.

## 관련 링크

- architecture: [app-shell.md](../../architecture/references/app-shell.md)
- decisions: [20260810_sparkle-auto-update.md](../../decisions/references/20260810_sparkle-auto-update.md)
- decisions: [20260810_appcast-hosting-github-releases.md](../../decisions/references/20260810_appcast-hosting-github-releases.md)
- decisions: [20260811_sparkle-updater-ui-and-consent.md](../../decisions/references/20260811_sparkle-updater-ui-and-consent.md)

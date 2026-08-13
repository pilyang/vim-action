# main 브랜치 보호 — CI 3잡 required status checks

- **결정일**: 2026-08-13

## 결정

`main`에 branch protection을 걸고 CI 워크플로의 세 잡 — `Engine tests (VimActionCore)`, `App build (xcodebuild)`, `App build (macOS 14.0 deployment floor)` — 을 required status checks로 지정한다. `strict=false`(브랜치 up-to-date 강제 없음), `enforce_admins=false`(관리자 직접 push 허용), 리뷰 요구·restrictions 없음.

## 배경·근거 (왜)

PR #54에서 `gh pr merge --squash --auto`가 CI 완료를 기다리지 않고 **즉시 merge**됐다 — auto-merge는 "merge 요건이 채워질 때까지 대기"인데, required checks가 하나도 없어 대기할 요건 자체가 없었기 때문이다. CI는 사후에 green이었지만 merge가 CI에 gate되지 않았다는 사실이 드러났고, 향후 `--auto`가 실제 gate로 동작하려면 required checks 지정이 필요하다.

- **세 잡 전부인 이유**: 요청 문언은 "두 체크"였지만 이는 에이전트 보고 요약(엔진 테스트 + 앱 빌드)에서 온 표현이고, 실제 `ci.yml`은 3잡이다. 하나라도 빠지면 그 잡은 빨간불이어도 merge가 통과하므로 "CI green이 gate"라는 의도에 맞게 전부 지정했다.
- **`strict=false`**: up-to-date 강제는 솔로 플로우에서 매 PR마다 branch update 클릭을 요구하는 마찰이고, 순차 merge 위주라 stale-branch 시맨틱 충돌 위험이 낮다.
- **`enforce_admins=false`**: `docs(decisions)`·`docs(plans)` 커밋을 main에 직접 push하는 기존 워크플로우(git 히스토리에 선례 다수)가 있다. `enforce_admins=true`면 이 경로가 막힌다. 대가로 관리자는 보호를 우회할 수 있지만, gate의 목적이 자기 강제가 아니라 auto-merge의 대기 요건 확보이므로 수용한다.

## 검토한 대안

- **두 체크만 required (요청 문언 그대로)**: 셋째 잡(`App build (macOS 14.0 deployment floor)` — 배포 타깃 하한 게이트, [20260812_deployment-target-macos-14.md](20260812_deployment-target-macos-14.md))이 gate 밖에 남아 빨간불 merge가 가능해진다. 문언이 아니라 의도(CI green gate)를 따랐다.
- **`enforce_admins=true`**: main 직접 docs 커밋 워크플로우가 막혀 기각.

## 영향 범위

- 갱신한 architecture reference: 없음 — 저장소 설정(GitHub) 변경이며 코드·구조 변경이 없다.
- GitHub 저장소 설정: `pilyang/vim-action` main branch protection. `ci.yml` 잡 이름을 바꾸면 required check 이름도 함께 갱신해야 한다 (이름 불일치 시 해당 체크가 영원히 pending으로 남아 merge가 막힌다).
- 관련 결정: [20260712_github-actions-ci.md](20260712_github-actions-ci.md) (CI 잡 구성), [20260812_deployment-target-macos-14.md](20260812_deployment-target-macos-14.md) (셋째 잡의 출처).

# Hardened Runtime은 pbxproj에 고정 (CLI 오버라이드 비의존)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-12

## 결정

앱 타깃의 Debug·Release 두 build config(`B52D10C2`·`B52D10C3`)에 `ENABLE_HARDENED_RUNTIME = YES`를 넣어 hardened runtime을 프로젝트 설정으로 고정한다. `release.yml`의 동명 CLI 오버라이드는 중복이 되지만 **그대로 둔다**(서명 오버라이드 묶음의 가독성 — 파이프라인만 봐도 산출물 속성이 읽힌다).

## 배경·근거 (왜)

- 릴리스 산출물은 이미 하드닝돼 있었지만 그 근거가 **파이프라인의 한 줄뿐**이었다. 워크플로 리팩터로 그 줄이 빠지면 빌드는 조용히 성공하고 공증 단계에서야 깨진다 — 속성의 진실이 빌드 설정에 없다는 것이 문제였다.
- 프로젝트에 고정하면 로컬 도그푸딩 빌드(CLAUDE.md의 Developer ID 서명 명령)도 릴리스와 같은 런타임 제약 아래에서 돌아, 하드닝 때문에 깨지는 동작을 릴리스 전에 만난다.
- **Debug도 YES인데 디버깅이 되는 이유**: `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`가 기본값(YES)이라 `get-task-allow`가 주입돼 lldb가 계속 붙는다. 릴리스 경로에서만 이 값을 `NO`로 꺼서 공증 거부를 피한다(20260810_tag-push-release-pipeline 참고) — 두 설정이 짝으로 움직인다는 것이 이 배치의 핵심이다.
- 실측 검증: v0.1.1 릴리스 DMG에서 `codesign -dv` 결과 앱과 중첩 Sparkle `Updater.app` 모두 `flags=0x10000(runtime)`.

## 검토한 대안

- **CLI 오버라이드만 유지(현행 유지)**: 산출물은 같지만 속성이 워크플로 편집 한 번에 사라진다 — 기각.
- **Release config에만 추가**: 로컬 도그푸딩(Release 구성으로 빌드)은 커버되지만 Debug 빌드와의 런타임 차이가 남는다. 두 config 모두 넣어도 디버깅이 깨지지 않음이 확인돼(위 엔타이틀먼트 이유) 굳이 가르지 않았다.

## 영향 범위

- `VimAction.xcodeproj/project.pbxproj` 앱 타깃 두 config. 테스트 타깃 config 4곳은 무수정.
- `.github/workflows/release.yml`의 `ENABLE_HARDENED_RUNTIME=YES`, CLAUDE.md 도그푸딩 명령의 같은 오버라이드는 중복이지만 유지 — 문서 수정 없음.
- architecture reference 갱신 없음 — 앱 구조 무관, 빌드 설정 한정.

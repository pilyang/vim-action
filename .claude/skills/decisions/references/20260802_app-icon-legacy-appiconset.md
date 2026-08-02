> Superseded by [20260802_app-icon-icon-composer.md](20260802_app-icon-icon-composer.md)

# App Icon은 legacy AppIcon.appiconset(PNG 10슬롯)

- **결정일**: 2026-08-02

## 결정

App Icon은 에셋 카탈로그의 legacy `AppIcon.appiconset`에 PNG 10장(16/32/128/256/512 × @1x/@2x)을 채워 배선한다. macOS 26의 Icon Composer(`.icon`, 레이어드 Liquid Glass) 전환은 하지 않고 보류한다.

## 배경·근거 (왜)

디자인 저장소(`~/Projects/vim-action/assets/icon/macos/AppIcon.iconset/`)에 macOS 규격을 이미 만족하는 PNG 세트가 있었다 — 1024 캔버스에 824px 스퀘어클(80.5%), Deep Navy `#070B16` 배경에 V + Λ 마크. 이 10장의 크기·스케일이 Xcode 기본 템플릿의 빈 10슬롯과 1:1로 정확히 대응해서, 파일 복사 + `Contents.json`의 `filename` 채우기만으로 끝났다.

Icon Composer를 택하지 않은 이유는 자동화 불가다. Icon Composer는 GUI 전용 앱이고 레이어 분리·내보내기를 사람이 직접 해야 한다 — 에이전트가 헤드리스로 만들 수 없고, 현재 있는 것은 단일 플랫 벡터라 레이어 소스도 없다. legacy 경로도 macOS 26에서 정상 표시되므로 지금 얻는 게 없다.

트레이드오프로 **다크/틴트/클리어 등 macOS 26의 동적 아이콘 외형 변형은 지원하지 않는다.** 도형이 이미 시스템 스퀘어클과 같은 계열이라 마스킹 차이는 육안으로 드러나지 않는다.

빌드 설정 변경이 전혀 필요 없었던 점도 이 선택을 싸게 만들었다: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`이 이미 걸려 있었고, 프로젝트가 `PBXFileSystemSynchronizedRootGroup`(objectVersion 77)이라 `project.pbxproj` 수정 없이 파일만 놓으면 타깃에 포함된다. `GENERATE_INFOPLIST_FILE = YES`라 `CFBundleIconName`은 actool이 자동 주입한다.

## 검토한 대안

- **Icon Composer `.icon`**: macOS 26 네이티브·동적 외형까지 지원하지만 GUI 수작업 필수라 자동화 불가, 레이어 소스도 없음. 별도 건으로 보류.
- **`.icns`를 `CFBundleIconFile`로 직접 지정**: 에셋 카탈로그를 우회하는 구식 경로. `vimaction.icns`가 이미 있어 가능하지만, Xcode 표준 파이프라인을 벗어나고 Info.plist 수작업이 생긴다.
- **에셋 저장소 파일을 심볼릭 링크·상대 경로로 참조**: 불가. 에셋은 리모트 없는 바깥 저장소 `~/Projects/vim-action`에 있고 앱은 중첩된 별개 저장소(`app/VimAction`, remote `pilyang/vim-action`)라 CI에서 해석되지 않는다. 내보낸 PNG를 앱 저장소로 복사해 커밋하는 것이 `assets/README.md`의 원칙("소스는 assets/에, 내보낸 프로덕션 파일만 앱으로")과도 맞는다.

## 영향 범위

- `VimAction/Assets.xcassets/AppIcon.appiconset/` — PNG 10장 + `Contents.json`의 `filename` 키. 파일명은 iconset 원본 그대로(`icon_16x16.png` … `icon_512x512@2x.png`) 유지해 원본 대조가 가능하게 했다.
- 아키텍처 구조 변경 없음 — architecture reference 갱신 대상 없음.
- **메뉴바 글리프와 무관하다.** `AppState.swift`의 `menuBarGlyph`/`menuBarImage`는 SF Symbols + 프로그램 생성 template 이미지이며 App Icon과 독립적이다.
- 앱이 `INFOPLIST_KEY_LSUIElement = YES`인 메뉴바 백그라운드 앱이라 **Dock에는 아이콘이 뜨지 않는다.** 실제로 보이는 곳은 Finder, 로그인 항목, 알림 배너, 강제 종료 창, 향후 배포 DMG.

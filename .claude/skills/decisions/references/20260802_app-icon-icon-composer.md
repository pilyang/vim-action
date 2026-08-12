# App Icon은 Icon Composer `.icon`

> Superseded (부분) by [20260812_deployment-target-macos-14.md](20260812_deployment-target-macos-14.md) — "배포 타깃 26.5라 구버전 폴백 불필요" 전제만 무효(하한이 14.0으로 내려가 14~15에서는 Xcode가 `.icon`에서 자동 생성하는 평면화 폴백에 의존) / `.icon` 단독 채택·appiconset 제거 결정은 유효.

- **결정일**: 2026-08-02

## 결정

App Icon은 Icon Composer가 만든 `VimAction/AppIcon.icon` 패키지로 배선한다. 같은 날 먼저 채택했던 legacy `AppIcon.appiconset`(PNG 10슬롯)은 제거한다.

## 배경·근거 (왜)

legacy appiconset을 붙인 뒤 실물을 확인하니 **macOS 26이 legacy 아이콘을 자체 컨테이너에 강제 합성**했다. `NSWorkspace.icon(forFile:)`으로 시스템이 실제 반환하는 이미지를 뽑아 보니, 밝은 회색 플레이트 안에 우리 아이콘이 약 62% 크기로 축소돼 들어가 있었다. 시스템 설정·손쉬운 사용 목록에 뜨는 것이 이 형태다.

소스 PNG를 바꿔 회피할 수 있는지 대조 실험했다. `assets/icon/web/png`의 full-bleed 이미지로 별도 프로브 번들을 만들어 같은 방식으로 렌더한 결과, **아이콘이 차지하는 면적만 커질 뿐 회색 플레이트는 그대로**였다. 즉 legacy 경로(icns·appiconset)인 이상 컨테이너는 벗어날 수 없고, `.icon`이 유일한 해법이다.

`.icon` 배선 후 같은 프로브로 재측정해 회색 플레이트가 사라지고 딥네이비 스퀘어클이 프레임을 꽉 채우는 것을 확인했다. 16·24·32·48·64·128px 전 크기에서 정상 렌더도 확인했다.

배포 타깃이 macOS 26.5라 구버전 폴백용으로 appiconset을 병존시킬 이유가 없다. 이름이 둘 다 `AppIcon`이라 병존 시 충돌하기도 한다.

## Icon Composer 소스의 필수 조건 — stroke는 외곽선으로 변환

브랜드 마크는 원래 `fill="none"` + `stroke-width` 로 그린 열린 path였다(`M220,352 L360,680 L500,352`). 이 SVG를 그대로 Icon Composer에 넣으면 **Liquid Glass가 글자 획이 아니라 삼각형에 적용된다** — 열린 path가 암묵적으로 닫히면서 fill 영역이 삼각형이 되기 때문이다. V·Λ 각각 삼각형 하나씩.

그래서 `CGPath.copy(strokingWithWidth:lineCap:lineJoin:miterLimit:)`로 stroke를 채워진 외곽선 path로 변환한 SVG를 소스로 쓴다. 변환본은 원본과 시각적으로 동일하게 렌더된다(round cap·join, 획 두께, 위치 보존). 이 파일은 `AppIcon.icon/Assets/vimaction-glyph-outlined-1024.svg`로 패키지 안에 들어 있다.

**향후 마크를 수정할 때도 같은 제약이 적용된다** — Icon Composer에 넣는 벡터는 stroke가 아니라 fill geometry여야 한다.

`icon.json` 구성: 배경 `automatic-gradient` `srgb:0.02745,0.04314,0.08627`(= `#070B16`), 전경 레이어 1개에 `glass: true`, shadow neutral 0.5, translucency 0.5, `supported-platforms.squares: shared`.

## 검토한 대안

- **legacy appiconset 유지**: 회색 컨테이너를 피할 수 없음 (위 실측). 폐기.
- **full-bleed PNG로 appiconset 교체**: 대조 실험 결과 플레이트가 남아 부분 개선에 그침. 게다가 macOS 권장 여백 규격을 버리는 선택이라 이득 대비 손해.
- **`.icon`과 appiconset 병존**: 배포 타깃이 26.5라 폴백 불필요하고, `AppIcon` 이름이 충돌한다.

## 영향 범위

- 신규: `VimAction/AppIcon.icon/` (`icon.json` + `Assets/vimaction-glyph-outlined-1024.svg`). **`Assets.xcassets` 안이 아니라 옆**에 둔다 — Xcode가 `.icon`을 `folder.iconcomposer.icon`(`BasedOn = folder.abstractassetcatalog`)으로 정의해, `.xcassets`와 같은 급의 독립 입력이기 때문이다.
- 제거: `VimAction/Assets.xcassets/AppIcon.appiconset/` (PNG 10장 + Contents.json).
- **빌드 설정·pbxproj 수정 없음.** actool이 `AppIcon.icon`과 `Assets.xcassets`를 둘 다 입력으로 받아 `--app-icon AppIcon`으로 컴파일한다. FS-synchronized 그룹이라 파일을 두기만 하면 타깃에 포함된다.
- `Assets.car` 91KB → 1.8MB (벡터 레이어와 외형 변형이 들어감).
- 메뉴바 글리프와는 여전히 무관하다 (SF Symbols + 프로그램 생성 template 이미지).

## 도그푸딩·검증 시 주의 — 아이콘 캐시와 앱 위치

두 가지가 검증을 방해했다. 아이콘이 안 바뀐 것처럼 보일 때 배선을 의심하기 전에 이것부터 확인한다.

1. **경로별 아이콘 캐시**: 증분 빌드 후에도 시스템은 그 번들 경로에 대해 옛 아이콘을 계속 반환했다. 디스크의 번들은 이미 새 아이콘인데도 그랬다. `xcodebuild clean build`로 `.app`을 삭제·재생성하면 해소된다.
2. **DerivedData의 개발 빌드는 시스템 설정 목록에서 빈 아이콘으로 뜬다**: 번들이 전 크기에서 정상 렌더되는데도 손쉬운 사용 목록만 비어 있었다. `/Applications`로 복사해 `lsregister` 재등록 후 실행하니 정상 표시됐다. 배선 문제가 아니라 개발 빌드 환경의 문제다.

## Supersedes

- [20260802_app-icon-legacy-appiconset.md](20260802_app-icon-legacy-appiconset.md) — legacy appiconset 채택 결정. 그 문서의 "마스킹 차이는 육안으로 드러나지 않는다"는 측정 없이 쓴 서술이며, 위 실측으로 반증됐다.

# README 데모 미디어는 소스 녹화 + 네이티브 렌더 스크립트로 재생성

- **결정일**: 2026-08-12

## 결정

README의 데모 미디어(`docs/assets/`의 demo.gif · how-it-works.gif · menubar-*.png · icon.png)는 손으로 다시 만드는 산출물이 아니라, 메인 체크아웃 `assets/readme/`(git 비추적 스튜디오 폴더)의 소스 녹화·스크린샷에서 **Swift 스크립트로 재생성**한다. 렌더는 macOS 네이티브 API만 쓴다 — AVFoundation(프레임 추출) + CoreGraphics(크롭·합성·캡션) + ImageIO(GIF 인코딩), ffmpeg/gifski 등 외부 도구 무의존.

## 배경·근거 (왜)

- repo에는 `docs/assets/` 산출물만 커밋되고 재생성 방법이 코드 어디에도 남지 않아, 미디어를 갱신할 다음 세션이 처음부터 다시 발명하게 된다 — 그 맥락을 여기 고정한다.
- 소스·스크립트 위치(전부 `assets/readme/`): `video-without-keycast.mov`(히어로 GIF 원본), `video-with-keycast.mov`(How-it-works 번역 GIF 원본), `menu-icon-*.png`·`menubar-perm-*.png`·`setting-perm-*.png`(글리프·스크린샷 원본), `render-demo-gif.swift`·`render-howitworks-gif.swift`(렌더 스크립트). **이 폴더는 git 비추적이라 백업이 사용자 몫이다.**
- 네이티브 렌더를 택한 이유: 작업 머신에 ffmpeg가 없었고, 세그먼트 컷·키캡 캡션·메뉴바 모드 칩 합성·오타 픽셀 패치 같은 커스텀 합성은 어차피 CGContext 직접 그리기가 필요했다. 결과물 품질(다크 UI GIF, 수백 KB)도 충분했다.
- 캡처가 아닌 연출 2건은 알고 있어야 한다:
  - `menubar-secure-input.png`(lock)은 실제 캡처가 아니라 **앱이 쓰는 `lock.square` SF Symbol을 캡처 배경 위에 렌더**한 것 — Secure Input 상태를 실기기에서 연출하는 수고를 회피했다.
  - `icon.png`는 설치된 `/Applications/VimAction.app`의 **시스템 렌더링 아이콘을 `NSWorkspace.shared.icon(forFile:)`로 추출** — Liquid Glass 처리까지 Dock에 보이는 그대로다. 앱 아이콘이 바뀌면 같은 방법으로 재추출한다.

## 검토한 대안

- **ffmpeg/gifski 설치 후 표준 파이프라인**: 미설치 환경에 외부 의존만 추가하고, 커스텀 합성은 결국 별도 단계가 필요 — 기각.
- **KeyCastr에 합성 이벤트 마커(`eventSourceUserData == "VIMA"`) 필터 패치**를 만들어 라이브 오버레이로 녹화: 히어로 GIF 1회 목적에 과잉 — 기각. 합성 이벤트가 키 시각화 도구에 그대로 보이는 현상 자체는 README Known limitations에 명시했고, How-it-works GIF는 오히려 그 현상을 소재로 쓴다.

## 영향 범위

- `docs/assets/*` (README가 참조하는 미디어), `assets/readme/*` (소스·스크립트, git 비추적)
- architecture reference 갱신: 없음 — 앱 구조와 무관한 문서 미디어 파이프라인.

# App Sandbox 해제 + Developer ID 직접 배포

- **결정일**: 2026-07-12

## 결정

앱 타깃의 App Sandbox를 해제한다(`ENABLE_APP_SANDBOX = NO`). 이에 따라 Mac App Store 배포를 포기하고 **Developer ID 서명 기반 직접 배포** 노선을 택한다.

## 배경·근거 (왜)

VimAction의 핵심 메커니즘인 시스템 전역 `CGEventTap`(kCGSessionEventTap)과 접근성(AXUIElement) API는 App Sandbox 안에서 동작하지 않는다 — 샌드박스는 다른 프로세스의 이벤트 스트림 가로채기와 임의 앱의 AX 조작을 근본적으로 금지한다. 따라서 샌드박스 유지와 제품 기능은 양립 불가하며, MAS는 샌드박스를 강제하므로 MAS 배포 경로 자체가 닫힌다. 메뉴바 셸 전환 시점에 함께 해제해 다음 작업(CGEventTap 스파이크)의 실기기 검증 경로를 연다.

## 검토한 대안

- **샌드박스 유지 + 예외 엔타이틀먼트**: 이벤트 탭/전역 AX를 허용하는 샌드박스 엔타이틀먼트는 존재하지 않는다. temporary-exception 류로도 MAS 심사를 통과할 수 없어 기각.

## 영향 범위

- `VimAction.xcodeproj/project.pbxproj` 앱 타깃 Debug/Release: `ENABLE_APP_SANDBOX = NO`. 별도 `.entitlements` 파일은 만들지 않음 — 접근성/입력 모니터링은 빌드 엔타이틀먼트가 아니라 런타임 TCC 권한이라 온보딩(다음 플랜)에서 처리.
- 배포: 향후 Developer ID 서명 + notarization + Hardened Runtime 구성이 필요(다음 배포 작업 범위). CI 사이닝은 현재 off 유지([20260712_github-actions-ci.md](20260712_github-actions-ci.md)).
- 갱신한 architecture reference: [system-overview.md](../../architecture/references/system-overview.md) (앱 셸 엔타이틀먼트/배포 주석).

# 킬스위치 탭 위치 — HID 우선 + 세션 head-insert 2단 폴백 (HID 비루트 생성 성공 실측)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

킬스위치 탭은 `kCGHIDEventTap`에 `.headInsertEventTap` + `.defaultTap`(능동)으로 설치하고, 생성 실패 시 `.cgSessionEventTap`에 같은 조건으로 **한 번만** 폴백한다. 어느 지점에 설치됐는지는 로그와 Settings의 읽기 전용 "Kill Switch" 행으로 노출한다.

## 배경·근거 (왜)

Apple 문서에는 "HID 위치에 탭을 두려면 root여야 한다"는 취지의 오래된 서술이 있어, 비루트 프로세스에서 능동 HID 탭 생성이 거부될 가능성이 설계 시점의 최대 미지수였다. 폴백 없이 실패하면 안전장치가 **조용히 통째로 사라진다** — 사용자가 알 방법도 없다.

**실기기 확인 결과(2026-07-26, macOS 26 / ad-hoc 서명 로컬 빌드): Accessibility 권한만으로 능동 HID 탭 생성이 성공했다** (`킬스위치 탭 설치 완료 (hid)`). 문서 서술은 현재 macOS 동작과 다르며, 폴백 경로는 이번 검증에서 한 번도 타지 않았다. 그래도 폴백은 유지한다 — 근거가 "관측된 성공"뿐이라 다른 서명·OS 조합에서 거부될 여지를 배제할 수 없고, 폴백 비용이 분기 하나이기 때문이다.

세션 폴백에는 알려진 약점이 있다: 메인 탭과 **같은 위치에 둘 다 head-insert**되므로 우선순위가 설치 순서에 의존한다. 그래서 **설치 순서를 계약으로 고정**한다 — 메인 탭 설치 다음에 킬 탭을 설치해야 킬 탭이 앞선다(`AppState.bootstrap`과 `permissionMonitor.onGranted` 두 지점 모두). 메인 탭이 off→on으로 재설치되면 킬 탭이 다시 뒤로 밀리는 잔여 약점은 **수용하고 문서화만 한다**: 이를 닫으려면 `EventTapController`와 킬 탭을 재설치 경로로 묶어야 하는데, 이는 "안전장치 탭은 메인 탭과 생명주기를 공유하지 않는다"는 불변식을 정면으로 흔든다. HID가 실제로 성공하는 지금은 도달 불가한 경로이기도 하다.

Settings 노출은 단축키 커스터마이즈 UI가 아니라 **상태 표시**다 — 안전장치가 부재한 채로 돌아가는 것이 이 기능의 가장 위험한 실패 모드이므로, `log stream` 없이도 알 수 있어야 한다.

## 검토한 대안

- **3단 사다리 (HID 능동 → HID listenOnly → 세션 능동)**: root 제약이 능동 탭에만 걸린다면 listenOnly가 통과해 세션 폴백보다 나은 격리를 줄 수 있다. 그러나 listenOnly는 이벤트를 삼킬 수 없어 콤보가 포커스 앱으로 새고, 상태가 하나 늘어난다. HID 능동이 실제로 거부되는지 확인되기 전의 선제 복잡도라 기각 — 실제로 성공했으므로 결과적으로도 불필요했다.
- **폴백 없음**: 코드는 가장 단순하지만 HID 실패 시 안전장치가 통째로 사라진다. 안전장치는 타협 불가라는 기존 전제와 충돌해 기각.
- **폴백 시 메인 탭 재설치와 킬 탭 재설치를 연동**: 위의 잔여 약점을 닫지만 생명주기 비공유 불변식을 깬다. 도달 불가 경로를 위해 핵심 불변식을 흔드는 거래라 기각.

## 영향 범위

- 코드: `VimAction/KillSwitchTap.swift`(`Installation` 상태와 2단 생성), `VimAction/AppState.swift`(설치 순서 계약 주석 2곳), `VimAction/SettingsView.swift`(`killSwitchStatusText` 순수 함수 + Permissions 행·안내 각주)
- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)

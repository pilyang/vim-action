# 미지원 액션은 실행 실패가 아니다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

어댑터가 **아직 구현하지 않은** `VimAction`(M2 시점의 `edit`/`paste`/`beginSelection` 등)은 `reportExecutionFailure`로 보고하지 않는다 — 조용히 스킵하고 DEBUG 로그만 남긴다. `reportExecutionFailure`의 의미론은 "**실행을 시도했는데 깨졌다**"로 한정한다. "구현이 없어서 실행하지 못했다"는 실패가 아니다.

## 배경·근거 (왜)

M2는 모션만 실행하는데 엔진은 v1 어휘 전체를 `.replace`로 내보낸다. 미지원 액션을 실패로 보고하면 사용자가 `dd`를 1초에 5번 누르는 정상 사용만으로 폭주 카운터(1초/5회)가 트립해 가로채기 전체가 꺼진다 — 폭주 감지의 목적(버그 있는 실행 코드로부터의 보호)과 정반대의 오탐이다. 폭주 카운터가 지키려는 것은 "실행 코드가 오동작 중"이라는 신호이지 "기능이 아직 없음"이 아니다.

M2~M3 구간은 배포 전 개발 단계라 미지원 액션의 사용자 피드백 부재(죽은 키)는 수용한다 — 어차피 릴리스 배포 금지 규칙([20260717_replace-swallow-transitional-rule.md](20260717_replace-swallow-transitional-rule.md))이 이 구간을 덮고 있고, M3에서 편집 계열이 구현되면 미지원 집합 자체가 사라져 간다.

## 검토한 대안

- **미지원도 실패로 보고**: 위의 오탐 — 정상 사용이 자동 off를 트립한다. 기각.
- **미지원 전용 보고 채널 신설**: M2~M3 과도기만을 위한 인프라라 범위 과잉. 기각 — DEBUG 로그로 충분.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (폭주 자동 비활성화 항목의 보고 의미론)
- Keyboard 어댑터의 액션 루프 (M2 구현 예정), `EventTapController.reportExecutionFailure` 호출 규약
- M3에서 편집 계열을 구현할 때 같은 규칙 적용 — 그때의 미지원 잔여(예: 텍스트 오브젝트 일부)도 실패가 아니다

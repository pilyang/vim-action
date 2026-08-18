# 숨은 입력 요소는 기하로 걸러낸다 — 프로브 신호 `AXSize` 짧은 변 임계

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-18

## 결정

auto 프로브 신호에 **요소 기하** 축을 더한다: 포커스 요소의 `AXSize`를 1회 읽어 **짧은 변이 4pt 미만**(또는 크기를 못 읽음)이면 untrusted, 탈락 계층은 새 케이스 `.geometry`(요소 실증 뒤·읽기·쓰기 실증 앞). 이 실패는 **확정 답변**이라 콜드 형태 실패가 아니다 — 재시도도 Electron 기상도 걸리지 않는다(settable=false 단독과 같은 편). 판정 함수는 신호 5비트 전수 32행으로 유지한다.

## 배경·근거 (왜)

- **조용한 거짓말의 첫 실측** (2026-08-18, Arc의 Google Docs): 포커스 요소는 `AXTextArea "문서 내용"`, **frame 625×1pt**, 값은 제로폭 공백 2개, `AXSelectedTextRange` settable, `AXStringForRange` 전부 성공. 즉 신호 3종(요소·읽기·settable) **전부 통과**하고 AX 범위 쓰기도 수락·되읽기 일치하는데 화면 캐럿은 안 움직인다 — 캔버스 렌더 + 숨은 contenteditable(iframe `about:blank`)이 입력만 받는 구조. 프로브·런타임 강등(`.axUnavailable` 없음)·되읽어 검증(일치) 세 겹이 전부 사각이다.
- **기하는 명백히 갈린다**: 정상 텍스트 요소는 한 줄짜리도 16pt 이상이다(VS Code Monaco 편집기 800×23pt 실측 — AX 캐럿 쓰기가 화면에 반영되는 정직한 요소). 임계 4pt는 "1~2pt 미끼"와 "실제 입력 UI" 사이 여백이 넓은 자리이고, 크기 미노출은 default-deny 방향(모름 = 불가)으로 접는다.
- **목록이 아니라 감지인 이유**: 숨은 입력 편집기는 클래스다(Docs·Sheets·캔버스 편집기류) — 브라우저 밖 Electron 앱에서도 같은 형태가 가능하고, 그때는 브라우저 클래스 규칙([20260818_browser-class-auto-untrusted.md](20260818_browser-class-auto-untrusted.md))이 못 잡는다. 기하 신호는 앱 무관 1회 읽기(웜 <1ms)로 그 클래스를 덮는다.
- **콜드 형태가 아닌 이유**: 잠든 트리·콜드 웜업은 요소 부재·미노출·읽기 실패로 나타나지 요소 크기가 1pt로 나타나지 않는다. 재시도·기상을 걸면 프로브가 최대 ~3s를 헛되이 쓴다.

## 검토한 대안

- **`AXValue` 내용 휴리스틱(제로폭 공백만·글자 수 극소)**: Docs 한 사례의 우연한 특징이라 클래스를 못 덮는다. 기각.
- **`about:blank` iframe 등 트리 형태 휴리스틱**: 브라우저·Docs 종속. 기각.
- **VS Code·Cursor 정적 등재**: 실측 결과 정직(AX 캐럿 쓰기가 화면에 반영, 문서 전체·실제 오프셋 노출)이라 등재할 이유가 없다. 기각.
- **값 변경 쓰기 왕복으로 적용 검증**: [20260813 결정](20260813_ax-lie-detection-read-attestation-settable.md)이 기각한 그대로 — Docs는 되읽기도 통과하므로 어차피 못 잡는다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) — auto 프로브 판정 계층 문단.
- `AXTrustProbeSignals.hasVisibleExtent`(+순수 판별 함수·임계 상수), `AXTrustProbeLayer.geometry`, `classifyAXTrustProbe` 순서(요소 → 기하 → 읽기·쓰기), `collectViaAccessibility`의 `AXSize` 1회 읽기, 프로브 완료 로그에 `기하` 비트, 판정 표 테스트 32행.

## Supersedes

- [20260813_ax-lie-detection-read-attestation-settable.md](20260813_ax-lie-detection-read-attestation-settable.md) — **부분**: "프로브 신호는 요소·읽기·settable 3종"이라는 전제만. 값 변경 왕복 제외·visible 정합 제외·선택 진실성 축의 런타임 검출은 유효.

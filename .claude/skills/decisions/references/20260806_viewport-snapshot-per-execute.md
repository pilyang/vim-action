# 뷰포트 스냅샷은 execute당 1회 — "액션마다 새로" 계약의 명시적 이탈

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

`ViewportSnapshot`은 `KeyboardAdapter.execute` **1회당 1개**다(액션 루프 밖 생성).
`FocusedTextSnapshot`의 "액션마다 새로 만드는 것이 계약"
([20260802_focused-text-read-api-shape.md](20260802_focused-text-read-api-shape.md))에서
**의도적으로 이탈**한다. lazy·1회 memo·실패도 memo는 그대로다.

## 배경·근거 (왜)

액션별 재생성 계약의 사유는 "같은 버스트의 앞 액션이 캐럿을 옮기므로 실행 직전 값만
정확하다"는 것이다. **뷰포트 높이에는 이 사유가 성립하지 않는다** — 스크롤이 뷰를 옮겨도
창 크기(표시 줄 수)는 버스트 중 불변이다.

반면 비용 축은 실재한다: 엔진은 `3Ctrl-f`를 액션 3건으로 복제하고
([20260801_scroll-count-clamp-33.md](20260801_scroll-count-clamp-33.md) — 최대 33건),
액션별로 읽으면 타임아웃 앱에서 최악 33 × 50ms를 정확도 이득 0에 문다.
실패 memo와 합쳐 execute당 AX 왕복이 최대 1회로 바운드된다.

## 검토한 대안

- **액션마다 새로 (계약 형태 일치)**: 이탈이 없다는 것 외의 이득이 없고, 카운트 스크롤에서
  비용이 액션 수만큼 곱해진다. 기각 (사용자 확인).

## 영향 범위

- `KeyboardAdapter.execute`의 액션 루프 밖에서 `ViewportSnapshot` 생성 —
  `KeyboardAdapterViewportTests`의 "execute당 1회" 테스트가 계약으로 고정.
- 캐럿 주변 스냅샷(`FocusedTextSnapshot`)의 액션별 계약은 **불변**이다 — 이 이탈은
  뷰포트 프리미티브에 한정된다.
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

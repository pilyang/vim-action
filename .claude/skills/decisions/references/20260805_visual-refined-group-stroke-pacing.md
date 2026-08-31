> Superseded (부분) by [20260806_paste-groups-stroke-pacing.md](20260806_paste-groups-stroke-pacing.md) — 페이싱 범위에 `.paste` 그룹 추가 / 5ms 상수·정확화 그룹 페이싱·스크롤 등 타이밍 현행 유지 원칙은 유효
> Superseded (부분) by [20260831_edit-group-stroke-pacing.md](20260831_edit-group-stroke-pacing.md) — "무상태 다타는 드롭 미관측이라 페이싱 안 함" 문언에 편집 그룹(단일 청크 한정)이 반례로 추가 / 스크롤·카운트 버스트 현행 유지 원칙은 유효

# Visual 정확화 그룹 한정 스트로크 페이싱 (5ms)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-05

## 결정

**Visual 정확화(refined) 시퀀스의 다타 그룹**에 한해, 그룹 안 스트로크(다운·업 쌍) 사이에 **5ms 고정 간격**을 두고 게시한다. 배선은 `VisualStrokes.paced`(매퍼가 정확화 다타에만 참) → `Mapping.groups(paced:)` → 어댑터의 전용 게시 경로(`postPaced` — pending을 먼저 비우고 단독 게시, 최신 확인·중단 시 상태 폐기는 `flush`와 같은 계약)다. 그 밖의 모든 경로 — 스크롤, 카운트 버스트, 폴백 시퀀스, 편집·모션·paste — 는 **타이밍까지 현행 그대로**다.

5ms는 실측으로 충분이 확인된 값이며 최솟값은 탐색하지 않았다. `pacedStrokeInterval`은 `chunkInterval`과 같은 도그푸딩 조절값이다.

## 배경·근거 (왜)

세션 1 도그푸딩에서 Notion(웹 에디터)이 재앵커 4타(`←,→,Shift-←×2`)를 0간격 버스트로 받으면 뒤의 Shift 확장을 소화하지 못해 접두만 반영됐다. 손 입력·이벤트당 5ms 프로브에서는 완전 정상이라 **시맨틱 문제가 아니라 간격 문제로 확정**됐다 — 재앵커류 시퀀스는 각 스트로크의 의미(collapse → 이동 → Shift 확장)가 앞 스트로크의 착지에 의존하므로, 앱이 소화할 시간이 필요하다.

범위를 "정확화 그룹만"으로 한정한 것은 설계 시점 문언("다타 그룹 한정")을 코드에 그대로 대면 모순이 생기기 때문이다: **스크롤은 15~30타 단일 다타 그룹**이고 폴백 경로의 `500x`는 501타 단일 그룹이라, 다타 그룹 전부를 페이싱하면 "카운트 버스트·스크롤 무영향" 제약과 충돌한다(+75ms~2.5s). 실측된 실패 지점(재앵커)과 정확히 일치하는 최소 범위로 좁히면 — 정확화 시퀀스는 재조립 불변식이 길이를 바운드하므로 수 타 × 5ms로 무해하고 — 나머지 경로는 폴백 바이트 동일 계약을 타이밍까지 지킨다. 무상태 다타(`dd` 3타, `w` 3타 등)는 Notion 포함 실사용에서 드롭이 관측된 적이 없어 페이싱하지 않는다.

## 검토한 대안

- **전역 이벤트당 지연**: 스크롤·버스트 총 소요가 그대로 늘어난다. 설계 시점에 이미 기각.
- **모든 다타 그룹 페이싱**: 위 모순 — 스크롤 +75~150ms, 폴백 `500x` +2.5s(원자 그룹이라 중단도 불가). 기각.
- **전이 간격만(직전 타와 다른 스트로크 앞만 5ms)**: 스크롤·반복이 자연 제외되지만, 재앵커 꼬리 `Shift-←×2` 같은 동일타 연속 구간이 무간격이 되어 실측된 프로브(이벤트당 5ms)와 패턴이 달라진다 — 재실패 위험. 기각.
- **길이 상한(≤8타 그룹 전부)**: 스크롤·대카운트는 자연 제외되나 `V`→`v` 재선택(열 거리 비례 — 페이싱이 가장 필요한 긴 정확화 시퀀스)이 상한을 넘으면 빠지는 구멍. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/VisualKeyMapper.swift`(`VisualStrokes.paced`), `VimAction/KeyboardAdapter.swift`(`Mapping.groups(paced:)`·`postPaced`·`pacedStrokeInterval`)
- 관련: [청크 게시 + 페이싱](20260730_chunked-posting-with-pacing.md)(중단 장치로서의 청크 간격 — 목적이 다르다), [재앵커](20260804_visual-backward-keyboard-reanchor.md)

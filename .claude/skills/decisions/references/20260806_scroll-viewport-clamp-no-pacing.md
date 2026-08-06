# AX 뷰포트 줄 수는 클램프만 — 산식은 Vim(half n/2·full n−2), 페이싱 없음

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

AX 뷰포트에서 파생한 줄 수는 `min(max(1, n), 200)`으로 클램프한다 (`viewportLineClamp = 200`).
산식은 Vim 그대로다: **half = 뷰포트/2(내림), full = 뷰포트 − 2**(문맥 2줄 겹침).
`.scroll` 그룹은 계속 **`paced: false`**다 — 뷰포트 유래로 그룹이 최대 200타가 되어도
페이싱을 걸지 않는다.

## 배경·근거 (왜)

- **상한 200은 파서 정렬이다.** 프로파일 scroll 값의 유효 범위가 1...200
  ([20260802_scroll-override-bounds.md](20260802_scroll-override-bounds.md))이므로, AX 유래
  값도 같은 상한이면 "어느 출처든 스크롤 줄 수는 1...200"으로 이야기가 하나가 된다.
  최악 밴드(엔진 카운트 33 × 200)는 프로파일 명시로도 오늘 도달 가능해 새 위험이 아니다 —
  폭주는 청크 중단 래치 몫이다. 실측 최대 뷰포트(TextEdit 세로 풀스크린 118~120 표시 줄)를
  여유 있게 덮는다.
- **하한 `max(1, …)`은 안전 필수다.** 뷰포트 1~2줄(좁은 창·단일행 필드)에서 `full = n − 2`는
  0·음수가 되는데, `Array(repeating:count:)`는 음수에서 **트랩**하고 0은 "지원 ⟹ 빈 시퀀스
  아님" 매퍼 불변식을 깬다.
- **full − 2는 Vim의 `Ctrl-f` 시맨틱**이다(문맥 2줄 겹침) — 연속 `Ctrl-f`로 읽어 내려갈 때
  이어짐이 보인다. 그래서 "full == half × 2" 불변식은 **상수(폴백) 경로 한정**으로 좁혀졌다.
- **페이싱 없음**은 C1의 "페이싱은 refined 그룹 한정, 스크롤 제외" 결정
  ([20260805_visual-refined-group-stroke-pacing.md](20260805_visual-refined-group-stroke-pacing.md))
  유지다. 스크롤 화살표가 0간격 버스트에서 드롭돼도 실패 방향이 "덜 스크롤"이라 무해하다 —
  Visual 재앵커·paste 접두처럼 뒤 스트로크의 전제가 되는 화살표가 아니다.

## 검토한 대안

- **상한 120 (실측 최대 뷰포트 기준)**: 더 큰 실제 창(4K 세로 ~150줄)에서 덜 스크롤된다.
  가드의 목적은 오보·폭주 차단이지 실뷰포트 제한이 아니므로 실뷰포트보다 큰 값이 맞다. 기각.
- **full = 뷰포트 그대로**: 산식은 단순하지만 겹침이 없어 연속 스크롤에서 문맥이 끊긴다.
  Vim 시맨틱 우선. 기각 (사용자 확인).

## 영향 범위

- `CommandKeyMapper.viewportLineClamp`·`clamped(_:)`·`lineCount` 산식. 골든
  `refinedScrollFixtures`(경계: 뷰포트 1 → 1타, 뷰포트 500 → 200타)와
  `viewportFormulae`가 고정.
- `Mapping.groups(paced:)` 주석의 "스크롤 15~30타" 문구가 "뷰포트 유래 최대 200타,
  무페이싱 유지"로 갱신됨.
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

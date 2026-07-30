# 스크롤은 half/full 모두 페이지 키로 수렴

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-30

## 결정

`Ctrl-d`/`Ctrl-u`(half)와 `Ctrl-f`/`Ctrl-b`(full) **네 조합이 두 시퀀스로 수렴**한다: 전진 = `PageDown` 1타, 후진 = `PageUp` 1타. `ScrollExtent`는 매퍼가 **의도적으로 무시**한다.

**캐럿이 스크롤을 따라가지 않는 것**(그리고 그 동작이 앱마다 다른 것)은 수용한다.

## 배경·근거 (왜)

macOS에는 half-page 프리미티브가 없다. 화면 높이를 알아야 절반을 계산할 수 있고, 그건 Keyboard 전략이 갖지 못한 정보다(뷰포트 측정은 AX 영역). 남은 선택은 "half를 뭔가로 근사한다"와 "full과 같게 둔다"뿐이었다.

근사 후보는 `↓`·`↑` N타였는데 두 가지 이유로 기각했다: **캐럿을 끌고 다닌다**(스크롤은 뷰 이동인데 문서를 편집 위치까지 바꿔 버린다), 그리고 **버스트를 곱한다**(`3 Ctrl-d`가 이미 반복 액션 3개인데 각각이 N타면 곱이 된다 — 카운트 폭탄 실측이 경고한 바로 그 형태, [래치 승격 결정](20260726_count-burst-abort-latch-promotion.md)). 수렴은 "half가 full만큼 움직인다"는 양적 편차만 남기고, 이건 사용자가 즉시 보고 적응할 수 있는 종류다.

`ScrollExtent` 케이스를 엔진에 유지하는 이유는 [스크롤·redo 출력 계약](20260724_scroll-redo-output-contract.md)이 정한 대로 **실행 수단이 어댑터 몫**이기 때문이다 — M5 AX가 뷰포트를 읽으면 half가 진짜 half가 되고, 그때 엔진은 손대지 않는다.

**수용 편차 — 캐럿이 따라오지 않는다.** Cocoa 텍스트 시스템에서 Page Down 키는 `scrollPageDown:`(뷰포트만)에 묶여 있고 `pageDown:`(삽입점까지 이동)이 아니다. 그래서 네이티브 앱에서는 `Ctrl-d`가 뷰만 굴리고 캐럿은 남으며, **다음 모션 키 한 번에 뷰가 원래 자리로 되돌아온다** — 사용자에게는 "`Ctrl-d`가 아무 일도 안 했다"로 보인다. 반면 Chromium/Electron의 텍스트 영역은 PageDown에 캐럿도 옮긴다. 즉 **세 기준 앱(네이티브·Notion·Chrome) 사이에서 동작이 갈린다.** Vim과의 의미 이탈이라 각주가 아니라 이 결정의 일부로 기록한다.

## 검토한 대안

- **`↓`/`↑` N타로 half 근사**: 캐럿 동반 + 버스트 곱 — 기각(위).
- **`Opt-PageDown`/`Opt-PageUp`**: 표준 키바인딩에서 `pageDown:`/`pageUp:`에 묶여 뷰와 캐럿이 함께 움직인다(= `Ctrl-d`에 더 가깝다). 다만 웹/Electron에서 미바인딩이면 **스크롤 자체가 사라져** 지금보다 후퇴한다. 평범한 페이지 키로 출하하고 A/B는 **도그푸딩 측정 항목으로 이연**.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/CommandKeyMapper.swift`의 `.scroll` 케이스, 골든 4행 + 수렴 불변식 테스트
- **단계 2.5 입력**: 스크롤은 비파괴적이면서 가장 값싼 버스트(`9999 Ctrl-f` = 액션 9,999개)라 실행 중단 래치 검증의 안전한 카나리아다
- 관련: [스크롤·redo 출력 계약](20260724_scroll-redo-output-contract.md), [매퍼 신설](20260730_command-key-mapper-scope.md)

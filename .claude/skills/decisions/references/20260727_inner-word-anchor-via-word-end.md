# `iw` 앵커는 단어 끝 경유 3타

- **결정일**: 2026-07-27

## 결정

`diw`/`ciw`/`yiw`의 선택 앵커를 `Opt-←` 1타에서 **`Opt-→, Opt-←` 2타 경유**로 바꾼다 — 단어 끝을 지나친 뒤 시작으로 복귀해 앵커를 잡고, 이어서 `Shift-Opt-→`로 단어 끝까지 선택한다(총 3타 + 오퍼레이터).

## 배경·근거 (왜)

단계 1 도그푸딩에서 나온 실측 결함이다: 캐럿이 **단어 시작**에 있을 때 `Opt-←`가 앞 단어의 시작으로 넘어가, `diw`가 커서가 놓인 단어가 아니라 **앞 단어를 지웠다**. 단순 부정확이 아니라 "엉뚱한 단어를 파괴"라 수용할 수 없다.

macOS에는 "현재 단어의 시작"이라는 프리미티브가 없다. 단어 끝으로 간 뒤 되돌아오면 캐럿이 단어 시작이든 중간이든 같은 지점(그 단어의 시작)으로 수렴한다 — `lineFirstNonBlank`(`^`·`I`)에서 이미 채택한 것과 **같은 패턴**이라 매퍼에 새 개념이 늘지 않는다 ([20260726_word-forward-first-nonblank-multi-stroke.md](20260726_word-forward-first-nonblank-multi-stroke.md)).

**수용 엣지**: 캐럿이 단어 바로 뒤 공백 위면 다음 단어를 잡는다(Vim은 공백 런을 지운다). 변경 전에는 앞 단어를 잡았으므로 어느 쪽이든 틀리며, 훨씬 흔한 단어 시작 케이스가 정확해지는 쪽을 택했다. 정확한 오브젝트 경계는 M5 AX의 몫이다.

## 검토한 대안

- **`iw`를 미지원으로 강등**(스킵+로그, M5 AX까지 대기): 캐럿 위치를 읽을 수 없어 어떤 시퀀스에도 엣지가 남는다는 판단. 그러나 단어 시작·중간이라는 지배적 케이스가 정확해지는 이상, 흔한 동작을 통째로 죽이는 비용이 더 크다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/EditKeyMapper.swift`의 `.textObject(.word(.inner))` 분기, 골든 픽스처 3행.
- 편집 매핑 계약([20260727_edit-keystroke-mapping-contract.md](20260727_edit-keystroke-mapping-contract.md))은 불변 — 표의 한 행만 바뀐 것이라 supersede가 아니다.

# 프로파일 재정의·disable은 모션 조회 전면에 전파

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

프로파일 모션 재정의·disable의 실행 배선(M4 세션 B):

1. **단일 조회 지점은 `MotionKeyMapper.keyStrokes(for:profile:)` 자체다** — 옵셔널 반환으로 바뀌고(재정의 시퀀스 / disabled면 `nil` / 없으면 내장 테이블), `selectionStrokes`는 여기서 파생된다. 앱은 로드 시 `AppProfile`을 `ResolvedProfile`(ConfigKeyStroke→KeyStroke 1회 변환, append 상속 베이킹)로 바꿔 디스패치마다 값 스냅샷으로 넘긴다.
2. **전파는 이 조회를 거치는 모든 소비처다** — 편집의 선택(d+모션)·Visual 확장(v+모션)만이 아니라 **명령 계열의 내부 접두**(paste 위치 잡기, o/O의 lineEnd/lineStart/lineUp, scroll의 반복 모션)와 **yank collapse(`←`)까지** 포함한다.
3. **disabled는 `nil`을 위로 전파해 복합 액션을 통째로 접는다** — 시퀀스의 어느 조각이든 disabled 모션이 나타나면 `guard let`이 nil을 올려 편집·paste·openLine 전체가 정직한 스킵이 된다. 부분 시퀀스는 만들지 않는다.
4. **어댑터는 매퍼 `nil`을 `.empty` 프로파일 재조회로 분류한다** — 프로파일 없이 값이 나오면 `.disabledByProfile`(신설 Mapping 케이스, 별도 DEBUG 요약 집계), 그래도 nil이면 `.unsupported`. `actions:` disable 판정은 모든 게이트·부수효과보다 앞이고, `.edit`의 `recordLinewiseEdit()`는 **게시가 확정된 뒤에만** 남긴다(스킵된 편집이 paste wise 기억을 오염시키지 않게).
5. **Visual 세션 메커니즘(진입·wise 전환·collapse)은 전파 대상이 아니다** — 모션 어휘가 아니라 리터럴 시퀀스를 유지한다 (도그푸딩에서 어긋나면 재검토).

## 배경·근거 (왜)

- 재정의의 의미는 "이 앱에서 이 모션을 **달성하는 방법**"이다 — `line_end`가 기본 매핑으로 동작하지 않아 재정의한 앱에서, `o`(lineEnd+Return)와 linewise `p`의 접두가 여전히 기본 매핑을 쓰면 그 앱에서 계속 깨진다. 복합 시퀀스도 재정의를 써야 재정의가 목적을 이룬다.
- disabled의 의미는 "이 앱에서 실행 불가"다 — 그 모션을 조각으로 쓰는 복합 액션은 위치가 틀린 채 절반만 실행되는 것(파괴적)보다 통째 스킵이 정직하다. "지원 ⟹ 빈 시퀀스 아님" 불변식과 부분 게시 금지 계약이 그대로 유지된다.
- 분류를 `.unsupported`와 가르는 이유: 무로그 삼킴 금지 계약의 로그 집계는 릴리스 게이트 심사·사용자 오타 진단의 근거다 — 사용자 설정이 만든 스킵이 미구현으로 집계되면 양쪽 다 틀린다. 재조회는 nil 경로(드묾)에서만 1회라 비용이 무시된다.

## 검토한 대안

- **모션-어휘 사용처만 전파 (명령 접두 제외)**: 기각 — 재정의가 필요한 바로 그 앱에서 o/O·paste가 깨진 채 남고, "어디까지 전파되는가"라는 자의적 경계가 생긴다.
- **매퍼 반환을 enum(정상/disabled/미지원)으로 교체**: 기각 — 네 매퍼와 모든 조합 지점의 시그니처 전면 교체 대비, 어댑터의 nil 경로 한정 재조회가 훨씬 저렴하고 분류 규칙이 한 곳(`classify`)에 모인다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- [20260801_profile-motion-override-unit.md](20260801_profile-motion-override-unit.md)의 "편집·Visual 자동 전파"를 명령 접두·collapse까지 **확장**한다 (supersede 아님 — 그 결정의 전파 범위 기술이 부분집합이었을 뿐 방향이 같다).
- 수용한 대가: 모션 하나의 재정의·disable이 그 모션을 조각으로 쓰는 어휘 전체에 미친다 — `char_left` disable이 yank를, `line_down` disable이 scroll을 함께 접는다. 사용자 문서화 대상.

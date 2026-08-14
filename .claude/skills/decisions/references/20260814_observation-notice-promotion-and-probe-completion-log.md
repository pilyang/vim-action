# 사후 판독 관측 로그는 `.notice` + 프로브 완료(untrusted) 신호 로그

- **결정일**: 2026-08-14

## 결정

**사후 판독이 목적인 관측 로그 전부를 `.info`에서 `.notice`(default 레벨)로 승격**한다: 판정 전이(trusted/untrusted + 탈락 계층)·런타임 강등·거부 목록 override·auto발 `.axUnavailable` 요약·Visual 가드 불일치·되읽어 검증 불일치 버킷·`.illegalArgument` 관측 버킷. 추가로 **프로브 완료가 untrusted면 신호 Bool 4종(요소·노출·읽기·settable) + 기상 여부 + 재프로브 횟수를 `.notice` 1줄로** 남긴다 — untrusted → untrusted 재프로브는 전이가 아니라 기존 전이 로그에 안 잡히는 사각이었다. 일반 운영 로그(탭 설치·가로채기 토글·워치독 등)는 `.info` 유지 — 사후 판독 목적이 아니다.

## 배경·근거 (왜)

- **도그푸딩 실측 (2026-08-14)**: 하루 실사용 뒤 `log show --info`에 D2 관측 로그가 0건이었다. macOS는 `.info`를 **디스크에 영속하지 않는다** — 메모리 버퍼에만 두다 버리고, 같은 시점에 error/fault가 나야 함께 저장된다(무사고 하루 = 전부 증발). "릴리스에서 생존하는 `.info`"라는 기존 문언은 stream 관측에는 참이지만 **사후 회수에는 거짓**이었고, `.illegalArgument` 결정(20260808)의 "log show --info로 사후 회수" 전제도 같은 결함이다. `.notice`는 default 레벨이라 시스템 로그 저장소에 영속된다(로테이션 며칠).
- **일반 사용자 머신에도 남는 것이 의도다** (사용자 확정 — A안): 지원 흐름에서 "`log show` 한 줄 돌려 결과 주세요"가 가능해진다. 남는 내용은 로컬 전용·희귀 이벤트·Bool + 번들 ID뿐 — 프로브 신호를 Bool로만 싣는 타입 계약이 본문 유출을 원천 차단하므로 영속해도 무해하다.
- **프로브 완료 로그**: 이번 진단에서 재프로브가 돌았는지·왜 떨어졌는지(읽기 콜드 vs settable 거짓)를 릴리스 로그로 구분할 수 없어 CLI 실측으로 우회했다. 신호 Bool이 있으면 "요소 true·읽기 false = 반콜드"를 로그 한 줄로 판독한다 — 거부 목록 성장·기본값 전환 게이트의 판정 데이터다.

## 검토한 대안

- **`log config` 영속 설정 (코드 무변경, 도그푸딩 머신 한정)**: 일반 사용자 머신에 안 남아 지원 흐름이 "재현해 주세요"로 퇴행. 도그푸딩 임시책으로는 유효하나 본책으로 기각.
- **`.error` 승격**: 관측은 오류가 아니다 — 오류 채널의 신호 대 잡음을 해친다. 기각.
- **전 `.info` 일괄 승격**: 운영 로그(탭 설치 등)까지 영속할 이유가 없다 — 사후 판독 목적인 관측만. 기각.

## Supersedes

- [20260813_auto-trusted-runtime-demotion-and-observability.md](20260813_auto-trusted-runtime-demotion-and-observability.md) **부분** — 관측 포인트의 로그 레벨(`.info`)과 "릴리스 생존 = 사후 회수 가능" 전제를 대체. 강등 규칙·관측 포인트 구성·메뉴바 표시는 유효.
- [20260808_ax-illegal-argument-observation-log-level.md](20260808_ax-illegal-argument-observation-log-level.md) **부분** — 레벨(`.info`)과 `log show --info` 회수 전제를 대체. "관측 전용 버킷, `.debug` 불가, 강등 없음" 결정은 유효.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md), [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `AXTrustProber`(전이·강등·override + 신규 완료 로그), `KeyboardAdapter`(auto 스킵 요약·가드 불일치), `AXWriteEffects`(되읽어 검증·`.illegalArgument` 행). `completeProbe`가 `signals`를 받는다(기본 nil — 테스트 호환).
- 사후 판독 명령이 `log show --info`에서 `log show`(기본)로 단순해진다.

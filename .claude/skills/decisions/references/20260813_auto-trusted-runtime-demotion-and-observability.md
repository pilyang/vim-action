# auto trusted의 런타임 강등 + 관측 포인트·메뉴바 표시

- **결정일**: 2026-08-13

## 결정

auto가 trusted로 라우팅한 앱에서 **`.axUnavailable`(요소·읽기 실패 스킵)이 연속 N회(잠정 3 — 도그푸딩 조절값)면 그 앱(pid) 판정을 untrusted로 강등**한다. 실패한 그 액션은 현행대로 접고(재실행 없음) **다음 액션부터** keyboard다. 강등은 pid 수명 sticky다(재승격은 앱 재실행 = 재프로브뿐 — 왕복 없음). **되읽어 검증 불일치는 강등 신호에서 제외**하고 관측 버킷으로만 남긴다. 관측 포인트 3종을 릴리스에서 생존하는 `.info`로 둔다: ① 판정 전이(번들 ID + 판정 + 탈락 계층) ② auto가 보낸 AX 실행의 `.axUnavailable` 요약(전략 출처 라벨 포함 — 명시 accessibility와 구분) ③ 강등 이벤트. **메뉴바에 최전면 앱의 현재 판정을 표시**한다("현재 앱: AX / 키보드 / 판정 중"). 사용자 안내: 강등이 반복되는 앱은 프로파일에 `strategy: keyboard` 명시를 권고한다 — 문서화는 PR-E 사용자 문서에 예약.

## 배경·근거 (왜)

- **독립 검토 3건이 같은 자리를 최대 실이슈로 수렴**: trusted를 고정하면 앱이 AX를 닫았을 때(Electron 트리 수면·요소 핸들 무효화) 회복 경로가 없다 — 리졸버 family 폴백은 `.textArea`(허용 방향)라 계열 강등이 안 일어나고, `.axUnavailable`의 로그는 DEBUG 전용이라 **릴리스에서 무로그 죽은 키**가 된다. `FailureBurstCounter`(실행 실패 폭주 방어)는 검증 실패·스킵이 `reportExecutionFailure` 대상이 아니라 이 축에 원리적으로 안 걸린다. auto가 기본값이 되면([20260813_bundled-default-strategy-auto-flip-gated.md](20260813_bundled-default-strategy-auto-flip-gated.md)) 이것이 전 앱의 기본 실패 모드다.
- **금지된 "쓰기 후 폴백"과 다르다**: D1 결정(폴백 없음)의 근거는 같은 액션 안의 재실행이 어긋난 상태 위 상대 시퀀스가 되는 위험이다. 강등은 실패 액션을 무동작으로 끝내고 다음 액션의 경로만 바꾸므로 이중 실행이 없다.
- **강등 신호에서 되읽어 검증을 뺀 이유**: 멀쩡한 앱에서도 검증 불일치는 난다 — TextEdit 도그푸딩 49건 전부 사용자 마우스 개입 뒤였고 정상 방어 동작이었다(D1b 세션 4 실측). 포함하면 오강등한다. `.axUnavailable` 연속은 "물어볼 요소 자체가 없다"라 신호가 강하고, 다중 표면 앱(브라우저)의 오판·트리 수면·핸들 무효화를 모두 같은 자리에서 흡수한다.
- 형태는 `FailureBurstCounter`의 슬라이딩 창(시간 주입 순수 카운터)을 재사용할 수 있는 모양이다.
- 관측 `.info` 승격은 [`.illegalArgument` 관측 로그 결정](20260808_ax-illegal-argument-observation-log-level.md)과 같은 근거다 — `.debug`는 저장소에 안 남아 `log show`로 사후 회수가 불가하고, 기본값 전환 게이트·거부 목록 성장의 판정 데이터가 정확히 이 로그들이다. 전략 출처 라벨이 없으면 "auto가 보낸 실패"와 "사용자가 지시한 실패"를 사후에 못 가른다.
- 메뉴바 표시는 auto 기본화 이후 사용자의 첫 질문("이 앱 지금 뭘로 돌아?")에 대한 최소 진단 수단이고, 판정 캐시가 `@MainActor`라 배선 비용이 낮다 (사용자 확인으로 D2 포함).

## 검토한 대안

- **trusted 영구 sticky (강등 없음, 초안)**: 무로그 죽은 키가 영구화. 독립 검토가 "이 상태로 기본값 전환 반대"를 명시. 기각.
- **되읽어 검증 불일치 포함 강등**: 정상 앱 오강등 (TextEdit 49건 실측). 기각 — 관측만.
- **실패 액션 내 keyboard 폴백**: D1 금지 유지 (이중 실행·어긋난 상태 위 상대 시퀀스). 기각.
- **trusted의 포커스 변경마다 재프로브**: 오판 표면도 읽기 실증은 통과해 판별력이 낮고 상시 왕복만 는다. 강등이 실측 기반이라 우세.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 판정 캐시(강등 간선), AX 스킵 요약 로그 레벨, 메뉴바 메뉴, PR-E 사용자 문서 항목 1건 예약.

# 이벤트 탭 자동복구 워치독

- **생성일**: 2026-07-13
- **갱신일**: 2026-07-13

## 목표

메인 이벤트 탭이 콜백 재활성화만으로 못 잡는 실패 모드(완전 정지·장기 스톨로 탭이 죽은 채 방치)에서 자동 복구되도록, `CGEventTapIsEnabled()` 주기 폴링 워치독을 `EventTapController`에 추가한다.

## 완료된 것

- (없음 — 착수 전)

## 남은 것

- [ ] `EventTapController`에 워치독 폴링 구현 (콜백 재활성화는 유지, 별도 타이머/스레드에서 `CGEventTapIsEnabled()` 감시 → 꺼져 있으면 재활성화). 상세 설계는 착수 시 결정.

## 진행 중 컨텍스트

- **발견 경위**: MVP 1차 스파이크 실기기 검증(2026-07-13) 중 `SIGSTOP`으로 앱을 완전 정지시켰을 때, OS의 `tapDisabledByTimeout` 콜백이 유실되어 재활성화 코드가 실행되지 못하고 탭이 죽은 채 방치됨을 관찰. 콜백 의존 재활성화만으로는 불충분하다는 것이 근거.
- 결정 문서에 "엔진 연결 마일스톤에서 구현"으로 적혀 있어 스파이크 스코프에서는 미착수. 이 플랜은 그 후속을 잊지 않기 위한 자리표시 — 착수 시 결정 문서부터 다시 읽을 것.

## 관련 링크

- decisions: [20260713_tap-reenable-watchdog-polling.md](../../decisions/references/20260713_tap-reenable-watchdog-polling.md)
- architecture: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 #6)

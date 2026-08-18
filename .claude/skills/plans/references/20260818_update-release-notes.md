# 업데이트에 릴리스 노트(변경사항) 노출

- **생성일**: 2026-08-18
- **갱신일**: 2026-08-18

## 목표

업데이트할 때 "새 버전이 있다"만 알려주는 지금 상태에서 나아가, **그 버전에서 무엇이 추가·변경됐는지(릴리스 노트/변경사항 목록)를 사용자가 업데이트 전에 볼 수 있게** 한다.

## 완료된 것

- 없음 (미착수 — 예정 기록용 플랜)

## 남은 것

- [ ] 릴리스 노트의 원천(source) 결정 — GitHub Release 본문, 별도 문서, 태그 메시지 등 중 무엇을 SSOT로 쓸지
- [ ] 릴리스 파이프라인에서 그 내용이 appcast에 실리도록 연결
- [ ] 업데이트 UI에서 실제로 노출되는지 확인 + 릴리스 노트 작성 규칙(영어, 커밋·태그 컨벤션과 동일선상) 정리

## 진행 중 컨텍스트

미착수. 구현 방식은 착수 시점에 정한다.

기록 시점 사실관계만: 업데이터는 Sparkle이고(`UpdaterViews.swift`, 발견·다운로드·설치 UI는 Sparkle 표준 UI), appcast는 릴리스 워크플로(`.github/workflows/release.yml`)의 `generate_appcast` 단계에서 생성돼 GitHub Release로 배포된다. 현재 이 단계에는 릴리스 노트를 실어 보내는 배선이 없다.

## 관련 링크

- decisions: [20260810_sparkle-auto-update.md](../../decisions/references/20260810_sparkle-auto-update.md)
- decisions: [20260810_appcast-hosting-github-releases.md](../../decisions/references/20260810_appcast-hosting-github-releases.md)
- decisions: [20260811_sparkle-updater-ui-and-consent.md](../../decisions/references/20260811_sparkle-updater-ui-and-consent.md)

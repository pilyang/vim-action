---
name: architecture
description: VimAction 프로젝트의 현재 아키텍처·구조(최종 상태) 컨텍스트 로드 및 유지용 스킬. Use this skill BEFORE any VimAction code work — like implementing or modifying the event tap, mode engine, strategy dispatcher, AX/keyboard adapters, action executor, profile loader, settings UI, or tests — and whenever the current structure is questioned ("구조가 어떻게 되지?", "이 컴포넌트 책임이 뭐지?", "왜 이렇게 되어있지?"). Also use when creating new SPM targets, adding dependencies, or choosing between implementation approaches, even if the user doesn't mention "architecture" explicitly. (결정의 기록·변경·번복은 decisions 스킬이 진입점 — 거기서 이 스킬의 최종 상태 갱신까지 이어집니다.)
---

# VimAction 아키텍처 (현재 구조)

이 스킬은 VimAction 구조의 **현재 최종 상태**의 단일 소스(SSOT)입니다. 상세 내용은 전부 `references/` 파일에 있고, 이 파일은 규칙과 인덱스만 관리합니다.

역할 분담: 이 스킬은 "**지금** 구조가 어떤가"를 담당합니다. "언제, 왜 그렇게 결정했는가"(히스토리)는 `decisions` 스킬이 담당하며, **결정의 기록·변경은 `decisions` 스킬이 진입점**입니다.

## 워크플로우 1 — 컨텍스트 로드 (코드 작업 전)

작업 대상과 관련된 항목을 아래 인덱스에서 찾아 **해당 reference 파일만** 읽습니다. 전부 읽지 마세요 — 인덱스의 short-description으로 관련 여부를 판단합니다. 읽은 구조(불변식, 계약)를 따르고, 따를 수 없다면 그것은 곧 구조 변경 결정이므로 `decisions` 스킬로 결정을 기록한 뒤 여기 최종 상태를 갱신합니다.

## 워크플로우 2 — 최종 상태 갱신 (결정 반영 시)

구조에 영향을 주는 결정이 내려지면 (먼저 `decisions` 스킬에 결정 문서가 기록된 뒤):

1. 해당 주제의 reference 파일을 **결정이 반영된 최종 상태로** 갱신합니다. 이 파일들은 살아있는 문서입니다 — 변경 이력이나 이전 값을 파일 안에 남기지 않습니다 (히스토리는 decisions의 결정 문서가 담당). 낡은 값이 남으면 다음 작업자가 어느 쪽이 현재인지 알 수 없습니다.
2. 새 주제면 `references/_template.md`를 복사해 `references/<kebab-case-slug>.md` 생성.
3. `근거 요약` 섹션의 관련 결정 링크에 해당 decisions 문서를 연결합니다.
4. **인덱스 테이블에 반드시 반영** — reference 파일만 만들고 인덱스를 빼먹으면 다음 작업자가 찾지 못합니다.

## 기록 규칙

- 디테일은 references/에, 이 파일에는 인덱스만. SKILL.md는 가볍게 유지합니다.
- reference는 항상 **현재 상태만** 기술합니다. "예전에는 ~였다", Status 필드, 파일 내 변경 이력, "과도기"·마일스톤 경위 같은 히스토리 프레이밍을 두지 않습니다.
- 근거는 **요약 + decisions 결정 문서 링크**로 남깁니다. 상세한 배경·대안·실측 서사는 결정 문서에 있습니다 — reference 본문은 "현재 계약(불변식·표·현재 조절값) + 근거 1줄 + 링크"까지만 담고, 결정 문서 내용을 본문에 반복하지 않습니다. 단 결정 문서에 없는 내용(결정 문언 밖 확정, 교차 서술)은 남깁니다 — 압축·삭제 전 링크된 결정 문서와 대조가 필수입니다.
- **reference 하나는 "작업 하나가 통째로 읽는 단위"입니다.** 한 파일이 독립적으로 소비되는 주제 여럿을 담게 되면 인덱스 단위로 분할합니다.
- 구조·플로우가 다이어그램으로 표현되기 좋다면 **mermaid**로 기록합니다.
- 사소하거나 코드만 봐도 자명한 것은 기록하지 않습니다.

## Reference Index

| Title | Short Description | Reference |
|---|---|---|
| 시스템 개요 | 전체 파이프라인(CGEventTap→모드 엔진→디스패처→어댑터)과 컴포넌트별 책임, 탭 배선·키 번역 | [system-overview.md](references/system-overview.md) |
| 모드 엔진 | macOS 의존성 없는 순수 Swift SPM 타깃, `Key`→`VimAction` 계약과 불변식 | [mode-engine.md](references/mode-engine.md) |
| 전략 디스패치 | 앱 수준 게이트, AX vs Keyboard 선택 플로우, `usesAXWrite` 단일 판정 지점 | [strategy-dispatch.md](references/strategy-dispatch.md) |
| auto 전략 프로브 | auto 판정 계층(default-deny)·pid 수명 캐시·런타임 강등·관측, 번들 기본 전략 | [auto-strategy-probe.md](references/auto-strategy-probe.md) |
| Accessibility 어댑터 | AX 쓰기 통로·위임 표·하이브리드·되읽어 검증·오프셋 산출·Visual 세션 경로 고정 | [ax-adapter.md](references/ax-adapter.md) |
| Keyboard 어댑터 | 요소 계열 걸러내기, force-text 치환, 네 순수 매퍼, 정확화 표, 비-QWERTY 처리 | [keyboard-adapter.md](references/keyboard-adapter.md) |
| 포커스 리졸버·디스패치 읽기 | 계열 캐시·갱신 트리거, 게시 큐 위 창 읽기(`FocusedText`)와 파생 질의·소비 지점 | [focus-and-dispatch-reads.md](references/focus-and-dispatch-reads.md) |
| 재진입과 안전장치 | 합성 이벤트 마커 불변식(무한 루프 방지), 단일 ActionExecutor, 킬스위치·중단 래치·원자 그룹 | [reentrancy-and-safety.md](references/reentrancy-and-safety.md) |
| 프로파일과 설정 | YAML(Yams) 설정 시딩·스키마, 앱별 프로파일, 수동 리로드, UserDefaults 경계 | [profiles-and-config.md](references/profiles-and-config.md) |
| 앱 셸 | 메뉴바·설정 창 3탭·Dock 아이콘 수명·로그인 자동 시작·Sparkle·온보딩 push | [app-shell.md](references/app-shell.md) |
| 온스크린 모드 인디케이터 | 모드 전환 시 오버레이 라벨 — 콜백 훅·전용 읽기 큐·앵커 사다리(요소→창)·순수 레이아웃·비활성화 패널·메뉴바 표시 사다리 재사용 | [mode-indicator-overlay.md](references/mode-indicator-overlay.md) |

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
- reference는 항상 **현재 상태만** 기술합니다. "예전에는 ~였다", Status 필드, 파일 내 변경 이력을 두지 않습니다.
- 근거는 **요약 + decisions 결정 문서 링크**로 남깁니다. 상세한 배경·대안은 결정 문서에 있습니다.
- 구조·플로우가 다이어그램으로 표현되기 좋다면 **mermaid**로 기록합니다.
- 사소하거나 코드만 봐도 자명한 것은 기록하지 않습니다.

## Reference Index

| Title | Short Description | Reference |
|---|---|---|
| 시스템 개요 | 전체 파이프라인(CGEventTap→모드 엔진→디스패처→어댑터)과 컴포넌트별 책임 | [system-overview.md](references/system-overview.md) |
| 모드 엔진 | macOS 의존성 없는 순수 Swift SPM 타깃, `Key`→`VimAction` 계약과 불변식 | [mode-engine.md](references/mode-engine.md) |
| 전략 디스패치 | 앱/요소별 Accessibility vs Keyboard 전략 선택 로직, key-mapping/force-text 계열 | [strategy-dispatch.md](references/strategy-dispatch.md) |
| 재진입과 안전장치 | 합성 이벤트 마커 불변식(무한 루프 방지), 단일 ActionExecutor, 안전장치 단축키·실패 모드 | [reentrancy-and-safety.md](references/reentrancy-and-safety.md) |
| 프로파일과 설정 | YAML(Yams) 3계층 설정, 앱별 프로파일 스키마, 파일 감시 리로드 | [profiles-and-config.md](references/profiles-and-config.md) |

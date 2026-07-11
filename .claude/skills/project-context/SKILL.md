---
name: project-context
description: VimACtion 프로젝트의 아키텍처·구조 결정사항 기록 및 컨텍스트 로드용 스킬. Use this skill BEFORE any VimACtion code work — like implementing or modifying the event tap, mode engine, strategy dispatcher, AX/keyboard adapters, action executor, profile loader, settings UI, or tests — and whenever an architecture/structure decision is made, changed, or questioned ("왜 이렇게 되어있지?", "이 결정 기록해줘", "구조가 어떻게 되지?"). Also use when creating new SPM targets, adding dependencies, or choosing between implementation approaches, even if the user doesn't mention "architecture" explicitly.
---

# VimACtion 프로젝트 컨텍스트

이 스킬은 VimACtion의 코드 레벨 아키텍처·구조 결정의 **단일 소스(SSOT)** 입니다. 상세 내용은 전부 `references/` 파일에 있고, 이 파일은 규칙과 인덱스만 관리합니다.

## 워크플로우

### 1. 컨텍스트 로드 (코드 작업 전)

작업 대상과 관련된 항목을 아래 인덱스에서 찾아 **해당 reference 파일만** 읽습니다. 전부 읽지 마세요 — 인덱스의 short-description으로 관련 여부를 판단합니다. 읽은 결정(불변식, 계약, 구조)을 따르고, 따를 수 없다면 그것은 곧 결정 변경이므로 아래 2번 워크플로우로 기록합니다.

### 2. 결정 기록 (새 결정 / 결정 변경 시)

구조·플로우·계약에 대한 결정이 생기거나 바뀌면:

1. 기존 reference가 다루는 주제면 해당 파일을 갱신 (변경 이력은 파일 내 Status/Date로 관리, 이전 결정을 뒤집으면 근거에 왜 바뀌었는지 남김).
2. 새 주제면 `references/_template.md`를 복사해 `references/<kebab-case-slug>.md` 생성.
3. **인덱스 테이블에 반드시 반영** — reference 파일만 만들고 인덱스를 빼먹으면 다음 작업자가 찾지 못합니다.

## 기록 규칙

- 디테일은 references/에, 이 파일에는 인덱스만. SKILL.md는 가볍게 유지합니다.
- 결정에는 **근거(왜)** 를 반드시 포함 — 코드에서 역추적할 수 없는 것이 근거입니다.
- 구조·플로우 결정이 다이어그램으로 표현되기 좋다면 **mermaid**로 기록합니다.
- 사소하거나 코드만 봐도 자명한 것은 기록하지 않습니다.

## Reference Index

| Title | Short Description | Reference |
|---|---|---|
| 시스템 개요 | 전체 파이프라인(CGEventTap→모드 엔진→디스패처→어댑터)과 컴포넌트별 책임 | [system-overview.md](references/system-overview.md) |
| 모드 엔진 | macOS 의존성 없는 순수 Swift SPM 타깃, `Key`→`VimAction` 계약과 불변식 | [mode-engine.md](references/mode-engine.md) |
| 전략 디스패치 | 앱/요소별 Accessibility vs Keyboard 전략 선택 로직, key-mapping/force-text 계열 | [strategy-dispatch.md](references/strategy-dispatch.md) |
| 재진입과 안전장치 | 합성 이벤트 마커 불변식(무한 루프 방지), 단일 ActionExecutor, 안전장치 단축키·실패 모드 | [reentrancy-and-safety.md](references/reentrancy-and-safety.md) |
| 프로파일과 설정 | YAML(Yams) 3계층 설정, 앱별 프로파일 스키마, 파일 감시 리로드 | [profiles-and-config.md](references/profiles-and-config.md) |

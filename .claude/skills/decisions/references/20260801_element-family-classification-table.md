# 요소 계열 판별자는 role이 아니라 `AXSelectedTextRange` 노출

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

포커스 요소가 텍스트인지 아닌지는 **role 화이트리스트가 아니라 `AXSelectedTextRange` 속성의 노출 여부**로 판정한다. role은 텍스트로 판정된 뒤 TextArea/TextField를 가르는 데만 쓴다.

```
포커스 요소 없음 / 속성 목록 조회 실패  → .textArea (폴백)
AXSelectedTextRange 미노출              → .nonText
노출 + role == AXTextField              → .textField
노출 + subrole ∈ {AXSearchField, AXSecureTextField} → .textField
노출 + 그 외                            → .textArea
```

노출 여부는 **`AXUIElementCopyAttributeNames`의 목록 포함 여부**로 본다 — 값 조회(`CopyAttributeValue`)는 판별자가 되지 못한다.

## 배경·근거 (왜)

원래 설계는 "명시적으로 아는 비텍스트 role만 `.nonText`, 나머지는 폴백"이라는 role 화이트리스트였다. **실측이 그 전제를 무너뜨렸다.**

2026-08-01 실기기 서베이 (읽기 전용 AX, 앱 활성화 자동화):

| 앱 / 포커스 | role | subrole | `AXSelectedTextRange` 노출 | 계열 |
|---|---|---|---|---|
| TextEdit 문서 본문 | `AXTextArea` | (미지원) | ✅ (속성 24개) | `.textArea` |
| Notion 블록 본문 | `AXTextArea` | `AXApplicationGroup` | ✅ (47개) | `.textArea` |
| Slack 컴포저 | `AXTextArea` | (없음) | ✅ (50개) | `.textArea` |
| Chrome 주소창 | `AXTextField` | (없음) | ✅ (45개) | `.textField` |
| **Finder 리스트** | **`AXGroup`** | (없음) | **❌ (13개)** | `.nonText` |
| VS Code 에디터 본문 | — 포커스 요소 자체를 보고하지 않음 (`AXError=-25212`) | | | 폴백 `.textArea` |

**Finder가 `AXGroup`을 보고하는 것이 핵심**이다. Finder는 리졸버가 겨냥한 1순위 위험인데(`p`=파일 붙여넣기, `u`=파일 조작 취소), 그 role은 Chromium·Electron이 **편집 가능한 영역에도** 붙이는 대표적인 애매한 role이다. role 화이트리스트로는 양자택일이 전부 나쁘다:

- `AXGroup`을 텍스트로 두면 → **Finder를 못 걸러낸다**(단계 3의 존재 이유가 사라진다).
- `AXGroup`을 비텍스트로 두면 → 웹 앱·Electron에서 Vim 레이어가 통째로 죽는다(주력 앱이 Electron이다).

속성 노출은 그 딜레마가 없다. 같은 `AXGroup`이라도 텍스트를 편집할 수 있는 요소는 `AXSelectedTextRange`를 내놓고, Finder의 리스트 그룹은 내놓지 않는다. **판별자가 "무엇이라고 자칭하는가"가 아니라 "텍스트 편집 인터페이스를 실제로 제공하는가"** 로 바뀐 것이며, 이는 우리가 실제로 필요로 하는 것과 정확히 일치한다 — 우리 시퀀스는 전부 캐럿·선택 조작이다.

**값 조회를 쓰면 안 되는 이유**도 실측이다: Finder의 `AXGroup`에 `AXSelectedTextRange` **값**을 물으면 `.success`가 돌아온다(속성 목록에는 없는데도). 목록 포함 여부만이 갈린다.

폴백은 그대로다 — 어느 단계에서 실패하든 `.textArea`이며, 걸러내기는 확실한 보고에만 발동한다([폴백 결정](20260801_resolver-fallback-defaults-to-text-area.md)). VS Code가 그 경로의 실증이다: Electron이 접근성 트리를 열지 않아 포커스 요소 자체가 없고, 폴백 덕에 텍스트 에디터에서 Vim 레이어가 정상 동작한다.

**Slack이 보여주는 한계**: 컴포저의 role은 `AXTextArea`이고 속성도 텍스트 요소 그대로다 — `Return`이 전송이라는 사실은 AX 어디에도 없다. 예정대로 M4 프로파일의 몫이다([o/O 시퀀스](20260730_openline-return-sequence.md)).

## 검토한 대안

- **role 화이트리스트**: Finder의 `AXGroup` 때문에 위 양자택일에 걸려 기각.
- **`AXSelectedTextRange` 값 조회**: Finder에서도 `.success`라 판별력이 없다 — 기각.
- **`AXValue`가 문자열인지**: 실측에서는 속성 노출과 같은 결과였지만 신호가 더 약하다(읽기 전용 라벨도 문자열 값을 갖는다) — 기각.
- **`AXRole`+속성 둘 다 요구(AND)**: Finder는 걸러지지만 Chromium의 `AXGroup` 편집 영역도 함께 걸러져 폴백 원칙에 어긋난다 — 기각.

## 미측정으로 남은 것 (세션 2)

- **Chrome 페이지 본문** — 자동화로는 포커스가 옴니박스를 벗어나지 않아(⌘L·Esc·Tab 전부 옴니박스에 머무름) 측정하지 못했다. 클릭이 필요하다.
- **Finder 데스크탑**, **Mail 메시지 리스트** — Mail은 미실행이라 실행 자체가 침습적이어서 보류.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) — 포커스/컨텍스트 리졸버 절
- `FocusedElementResolver.family(role:subrole:exposesSelectedTextRange:)` — 순수 함수라 위 표가 그대로 골든 픽스처다(`FocusedElementResolverTests`)
- 관련: [폴백 기본값](20260801_resolver-fallback-defaults-to-text-area.md), [캐시 형태](20260801_focused-role-cache-shape.md), [비텍스트 UI 위험](20260730_native-command-non-text-ui-hazard.md)

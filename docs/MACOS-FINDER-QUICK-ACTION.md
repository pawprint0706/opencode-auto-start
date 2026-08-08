# macOS Finder 빠른 동작(Quick Actions) 등록 가이드

Finder 폴더 우클릭 메뉴에서 **빠른 동작**과 **서비스** 양쪽에 "OpenCode에서 열기"를 노출하기 위해
조사·실험한 결과를 정리한 문서입니다. macOS 26.6(빌드 25G72) 기준으로 검증했습니다.

## 1. Finder 우클릭 메뉴 구조 (macOS 26)

폴더를 우클릭했을 때 메뉴는 대략 다음과 같은 섹션으로 나뉩니다.

```
...
빠른 동작 ▶            ← 섹션 라벨 + 서브메뉴
  <Quick Action 항목들>   ← Automator 퀵 액션 (등록·활성화된 것만)
  사용자화…               ← 항상 표시
opencode-auto-start.zip으로 압축하기   ← Finder 내장(압축) 인라인 항목
반디집으로 압축하기                     ← 최근 사용 기반 인라인 항목(추정)
서비스 ▶                 ← 서비스 서브메뉴
  (이름).zip으로 압축하기 …             ← 번들 ID가 있는 서비스만 표시
  OpenCode에서 열기
```

- **빠른 동작 서브메뉴**에는 Automator 퀵 액션 형식의 워크플로가 들어갑니다.
- **서비스 서브메뉴**에는 기존 "서비스" 형식(번들 ID 있는 것)이 들어갑니다.
- **한 워크플로가 양쪽 메뉴에 모두 나오지는 않습니다.** (아래 2장)

## 2. "반디집 방식(파일 제공자)"은 참고할 수 없음

반디집이 시스템 설정에서 "파일 제공자"로 보이는 것은 **FinderSync 확장**
(`BandizipFinderSyncExtension.appex`, `com.apple.FinderSync` 익스텐션 포인트)입니다.
이것은 Finder 툴바 버튼/배지/사이드바 통합용이며 **우클릭 메뉴와는 무관**합니다.

- 우클릭 메뉴의 "반디집으로 압축하기/압축 풀기/(이름).zip·7z으로 압축하기" 항목은
  `Bandizip.app`의 `Info.plist` **`NSServices`**(표준 서비스 메커니즘)로 등록된 것입니다.
- FinderSync 확장 방식은 **코드 서명된 앱 번들 + 임베디드 .appex**가 필요하고,
  확장 자체는 우클릭 메뉴 항목을 제공하지 않으므로, 이 프로젝트(스크립트 기반 설치)에 부적합합니다.
- "반디집으로 압축하기"가 빠른 동작 영역에 인라인으로 보이는 것은 최근 사용 기반 표시로 보이며
  (반디집 서비스 등록에는 퀵 액션 전용 플래그가 없음), 우리가 제어할 수 있는 메커니즘이 아닙니다.

## 3. 두 등록 방식의 차이

### 3-1. 서비스(서비스 메뉴) 방식 — 기존 구현

`~/Library/Services/OpenCode에서 열기.workflow` (기존 설치 스크립트가 생성)

- `Contents/Info.plist`에 **`CFBundleIdentifier` 포함** (`com.anomalyco.opencode-attach.quickaction`)
- `NSMessage = runWorkflowAsService`, `NSRequiredContext = com.apple.finder`,
  `NSSendFileTypes = public.folder`
- 결과: **서비스 서브메뉴에만** 표시. 빠른 동작에는 표시되지 않음.

### 3-2. 빠른 동작(Quick Actions) 방식 — 실험으로 검증

Automator에서 "빠른 동작" 템플릿으로 저장하면 생성되는 구조입니다.

- `Contents/Info.plist`에 **`CFBundleIdentifier` 없음**
- 추가 키: `NSBackgroundColorName = background`, `NSIconName = NSActionTemplate`
- 그 외 서비스와 동일: `NSMessage = runWorkflowAsService`,
  `NSRequiredContext = com.apple.finder`, `NSSendFileTypes = public.folder`
- `document.wflow`의 `workflowMetaData`에 다음 값 포함:
  - `inputTypeIdentifier = com.apple.Automator.fileSystemObject.folder`
  - `serviceInputTypeIdentifier = com.apple.Automator.fileSystemObject.folder`
  - `applicationBundleID = com.apple.finder`, `applicationPaths = [Finder.app]`
  - `presentationMode = 15`
  - `systemImageName = NSActionTemplate`
  - `processesInput = false`, `serviceProcessesInput = false`
  - `useAutomaticInputType = false`
  - `workflowTypeIdentifier = com.apple.Automator.servicesMenu` (서비스와 동일)
- 결과: **빠른 동작 서브메뉴에만** 표시. 서비스 메뉴에는 표시되지 않음.

> 참고: `workflowTypeIdentifier`는 두 방식 모두 `com.apple.Automator.servicesMenu`로 동일합니다.
> "빠른 동작" 여부는 wflow 타입이 아니라 Info.plist의 구조와 아래 4장의 활성화 등록으로 결정됩니다.

## 4. 빠른 동작 활성화 메커니즘

### 4-1. 활성화 상태 저장 위치: `~/Library/Preferences/pbs.plist`

```
NSServicesStatus = {
  "(null) - <메뉴 이름> - runWorkflowAsService" = {
    presentation_modes = {
      ContextMenu    = true;   ← Finder 우클릭 빠른 동작에 표시
      FinderPreview  = true;
      ServicesMenu   = true;
      TouchBar       = true;
    };
  };
};
```

- 키 형식: `<번들ID 또는 (null)> - <메뉴 이름> - <NSMessage>`
  - `CFBundleIdentifier`가 없으면 `(null)`, 있으면 그 번들 ID가 들어감
- `ContextMenu = true`가 빠른 동작 표시의 핵심 플래그

### 4-2. 활성화 방법(신뢰도 순)

| 방법 | 신뢰도 | 비고 |
|------|--------|------|
| Automator에서 퀵 액션 저장 | ✅ 확실 | 저장 시 즉시 ON 등록 (XPC) |
| 시스템 설정 > 로그인 항목 및 확장 프로그램 > Finder > 토글 ON | ✅ 확실 | 즉시 반영 (XPC), pbs.plist도 갱신 |
| pbs.plist 직접 작성 + `pbs -flush` + `killall Finder` | ⚠️ 불안정 | 번들/캐시 상태에 따라 반영되기도, 안 되기도 함 |

- `pbs -flush` + Finder 재시작만으로는 신규 번들의 활성화가 반영되지 않는 경우가 많았습니다.
- 시스템 설정 토글은 런타임에 pbs/Finder로 즉시 통보하므로 가장 확실합니다.

## 5. 실험으로 검증한 규칙

| 실험 | 번들 ID | 아이콘 키 | wflow | NSServicesStatus | 빠른 동작 표시 |
|------|---------|-----------|-------|------------------|----------------|
| 기존 서비스 | 있음 | 없음 | 구형 | 없음 | ❌ (서비스에만 표시) |
| TestQA (Automator 저장) | 없음 | 있음 | 신형 | 있음 | ✅ |
| TestQA 파일 구조를 직접 생성 + 항목 작성 | 없음 | 있음 | 신형 | 있음 | ⚠️ 일부만 ✅ |
| 위 상태에서 시스템 설정 토글 ON | 없음 | 있음 | 신형 | 있음(갱신) | ✅ 확실 |

정리하면:
- **빠른 동작 표시 조건**: (1) `CFBundleIdentifier` 없음, (2) 아이콘/색상 키 포함,
  (3) 신형 wflow 메타데이터, (4) `pbs.plist`의 `NSServicesStatus`에 항목 + ContextMenu=true.
- **서비스 표시 조건**: `CFBundleIdentifier` 있음 (기존 방식 그대로).
- **이름 제약**: 기존 서비스와 같은 메뉴 이름("OpenCode에서 열기")은 빠른 동작에 표시되지 않았음.
  다른 이름(예: "OpenCode에서 열기 QA")은 표시됨. (이름 충돌/중복 방지 추정)

## 6. 주의 사항 (함정)

1. **손상된 워크플로 번들이 전체 등록을 깨뜨림**
   - `~/Library/Services`에 잘못된 `Info.plist`를 가진 번들이 하나라도 있으면
     pbs가 모든 서비스/퀵 액션 등록을 실패하고, 빠른 동작·서비스·시스템 설정 목록이 모두 사라집니다.
   - 실험 중 `plutil -insert NSServices:0:...`로 **잘못된 배열 경로 키**를 생성한 번들이
     원인이었고, 삭제 후 정상 복구됨.
2. **`plutil`은 배열 인덱스를 지원하지 않음**
   - `plutil -insert NSServices:0:NSIconName ...`처럼 쓰면 루트에 `NSServices:0:NSIconName`이라는
     잘못된 키가 만들어집니다. 배열 내부 수정은 Python `plistlib`나 PlistBuddy를 써야 합니다.
3. **wflow UUID 중복 시 무시됨**
   - 다른 번들의 wflow UUID를 그대로 복사하면 같은 워크플로로 인식되어 메뉴에 표시되지 않음.
     번들 생성 시 wflow 내부 UUID를 새로 생성해야 합니다.
4. **이름 충돌**
   - 기존 서비스와 같은 메뉴 이름을 빠른 동작에 사용하면 표시되지 않습니다.
     빠른 동작용 번들은 다른 이름을 써야 합니다.
5. **번들 파일 권한**
   - `cp -R`로 복사한 번들은 디렉터리 권한이 `700`이 되는 경우가 있습니다.
     `755/644`로 맞춰야 안전합니다.

## 7. 설치 스크립트 반영 방향 (제안)

기존 서비스(서비스 메뉴용)를 유지한 채, **별도의 빠른 동작용 번들**을 추가로 생성합니다.

1. `~/Library/Services/OpenCode에서 열기 QA.workflow` 생성
   - Info.plist: `CFBundleIdentifier` 없음 + `NSBackgroundColorName`/`NSIconName` + Finder 폴더 서비스
   - document.wflow: 신형 메타데이터(presentationMode 15, fileSystemObject.folder 등) + **UUID 신규 생성**
   - `chmod 755/644`
2. `pbs.plist`의 `NSServicesStatus`에 `"(null) - <메뉴 이름> - runWorkflowAsService"` 추가
   (presentation_modes: ContextMenu/FinderPreview/ServicesMenu/TouchBar = true)
3. `/System/Library/CoreServices/pbs -flush` + `killall Finder`
4. 반영이 안 되는 경우(불안정), 설치 완료 후 사용자에게
   **시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램 > Finder**에서
   빠른 동작을 켜도록 안내 문구 출력
5. 삭제 시에는 생성한 번들과 `NSServicesStatus` 항목을 함께 제거
6. `~/Library/Services`에 손상된 번들이 없는지 유지 (설치 시 정리 포함)

## 8. 관련 파일 경로

- 워크플로(서비스): `~/Library/Services/OpenCode에서 열기.workflow`
- 워크플로(빠른 동작): `~/Library/Services/OpenCode에서 열기 QA.workflow` (제안)
- 활성화 상태: `~/Library/Preferences/pbs.plist` (`NSServicesStatus`)
- 서비스 캐시: `~/Library/Preferences/com.apple.ServicesMenu.Services.plist`
- 서비스 캐시: `~/Library/Caches/com.apple.nsservicescache.plist`
- 등록 확인: `/System/Library/CoreServices/pbs -dump`

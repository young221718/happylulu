# HappyLulu 기능 명세

## 2026-10-23 main 반영 기능 · 현재 기준

현재 기준은 `app/happylulu/develop`, branch `main`, HEAD `58fe8df4b32eac479f6ff6f3fc9e71c0751fb632`다. 이 절은 현재 소스의 기능·진입점·기본값을 정의한다. 아래 2026-10-21/34.x 절과 그 안의 기능 표·PR 상태·적용 대기 문구는 **당시 조사·설치 이력**으로 보존한다. 충돌할 때는 이 절을 우선하며 기존 `HL-*` ID는 계속 사용한다. 표시 이름은 **happylulu**, 내부 `AfterSix` 저장 경로와 기존 bundle ID는 유지한다.

- **있는 기능:** 출근·5개 근무 유형·퇴근 계산·전체 출근 기록·플러그인 출처·캘린더·선택적 동기화·다우오피스·외관·업데이트를 유지한다. 아래 새 기능은 Mac 범위이며 Windows 기능 동등성을 의미하지 않는다.
- **뺀 기능/이동:** 이번 기능 묶음에서 출근·연결·기록 기능을 제거하지 않았다. 패널의 설정 아이콘은 `…` 메뉴로 바뀌어 설정/종료를 제공한다. 설정 사이드바 하단의 종료 대신 사용 안내 링크를 제공한다. 종료는 패널 메뉴와 앱 메뉴/Cmd+Q에 남아 있다. 기존 `HL-REM-*`와 `HL-MOVE-*` 제거·이동 이력은 보존한다.
- **추가/변경:** 부엉이 눈 테두리 회전·색상, 선택 동물 러너, 시스템 지표, Codex 사용량 표시/연결, 야근 경과 갱신, 내일 연차/공가 눈빛, 3열 설정, macOS 26 이상 유리 재질과 패널을 아래 계약으로 반영한다.
- **반영 단계:** 이 기준은 main에 합쳐진 소스다. 소스 [Info.plist](../Resources/Info.plist)는 `1.5.19`/build `35`이며 작업 설치본의 로컬 build 접미사나 공개 릴리즈 번호와 같은 개념이 아니다. 이 문서 갱신은 새 앱 릴리즈·설치·사이트 배포를 수행하거나 공개 최신판을 확인한 증거가 아니다.

### 기존 기능 ID의 현재 동작

| 기존 ID | 현재 진입 UI·동작 | 수용 기준·소스 |
| --- | --- | --- |
| HL-BASE-001 | 기본 패널 폭 364 pt·높이 350 pt. 활성 사용량 항목당 40 pt, 시스템 러너 활성 시 184 pt를 더한다. macOS 26+ 지원 빌드는 화살표 없는 패널, 이전 환경은 팝오버 | 한 메뉴바 항목 안에 부엉이·동물·시간·사용량을 함께 표시. 모듈을 끄면 추가 높이/내용 제거. [main.swift](../Sources/AfterSix/main.swift), [PanelView.swift](../Sources/AfterSix/PanelView.swift), [MenuBarPanel.swift](../Sources/AfterSix/MenuBarPanel.swift) |
| HL-GEN-001/002, HL-TIME-001/002 | 일반 설정은 **왼쪽 항목·가운데 예시/설명·오른쪽 선택/토글** 3열. 언어 선택도 오른쪽. 시스템/한/영·5개 시간단위·퇴근예정 기본 켜짐·로그인 자동실행 상태 유지 | 예시와 실제 표시 분리, 선택 즉시 반영·재시작 유지. [SettingsView.swift](../Sources/AfterSix/SettingsView.swift) |
| HL-GEN-003 | 패널 우상단 `…` → 설정 또는 종료. 설정 사이드바 하단 → 사용 안내(선택 언어의 `/guide/` 또는 `/en/guide/`). 앱 메뉴 종료/Cmd+Q 유지 | 창 닫기는 상주 유지. 커스텀 테마의 메뉴 버튼은 기본 강조 배경 대신 투명 버튼 스타일·키보드 포커스 표현 사용. [PanelView.swift](../Sources/AfterSix/PanelView.swift), [SettingsView.swift](../Sources/AfterSix/SettingsView.swift), [ApplicationMenu.swift](../Sources/AfterSix/ApplicationMenu.swift) |
| HL-WORK-003, HL-TIME-001/002 | 예정 퇴근 **30분 후부터** 메뉴바와 패널 상태 설명에 `추가 … 중`. 선택한 5개 단위로 실제 경과 시각을 계속 갱신. 경과는 단위별 내림, 시간은 0.1시간 단위. 예정표시 켜짐이면 예정 시각도 유지 | 30분 전에는 기존 퇴근 가능/예정시각. 밀리초 0.1초·다른 단위 1초 갱신, 시각/단위 변경 즉시 반영. +120분 식대 기준은 참고이며 실제 근무·지급 승인 아님. [AppModel.swift](../Sources/AfterSix/AppModel.swift), [CountdownDisplay.swift](../Sources/AfterSixCore/CountdownDisplay.swift), [Attendance.swift](../Sources/AfterSixCore/Attendance.swift) |
| HL-APPEAR-001/002 | 6개 색상 테마(기존5+오프화이트 라일락). 신규 기본은 오프화이트 라일락, 저장된 선택 보존. 지원 환경에는 순정 리퀴드 글래스 선택 추가 | 순정은 시스템 동적 색상·밝기 사용, 세부 색상 편집 숨김. 다른 테마는 개인 색상과 아이콘 설정 유지. 유리 재질은 아래 HL-APPEAR-004. [AppearancePreferences.swift](../Sources/AfterSixCore/AppearancePreferences.swift), [AppearanceSettingsView.swift](../Sources/AfterSix/AppearanceSettingsView.swift) |
| HL-APPEAR-003 | 기존 개인 아이콘 선택·가져오기 유지. 기본/색상 아이콘과 상태별 헤더 이미지를 캐시하고 공통 이미지 처리 문맥을 재사용해 외관 진입·첫 클릭의 중복 이미지 준비를 줄임 | 잘못된 이미지·선택 취소·저장 실패 보존. 개선 소스 포함과 사용자 Mac에서의 클릭 지연 수락은 별도. [AppearanceModel.swift](../Sources/AfterSix/AppearanceModel.swift), [LuluBrand.swift](../Sources/AfterSix/LuluBrand.swift) |
| HL-PLUGIN-001/002/003 | 캘린더·다우·반차 인식 외에 시스템 러너와 선택 빌드의 AI 사용량 제공. **설치와 사용은 별개**이며 설치 직후 사용 끔. 설정의 설치된 플러그인 목록/플러그인 관리의 설정 버튼으로 상세 진입 | 기존 경로·비밀번호·일정/휴가/반차 연결 보존. 러너/AI는 일정·휴가 기능 출처를 차지하지 않음. [PluginManagerModel.swift](../Sources/AfterSix/PluginManagerModel.swift), [BundledPlugins.swift](../Sources/AfterSix/BundledPlugins.swift) |
| HL-DAOU-001 | 기존 연결·Keychain 비밀번호를 재사용. 초기 저장 비밀번호 확인은 비동기 작업으로 수행하며 조회/저장 상태에 따라 입력 활성화 | Keychain 승인·로딩·실패와 연결 성공을 구분. 초기 UI 응답성 개선이 모든 환경의 클릭 지연 제거를 증명하지 않음. [DaouOfficePluginModel.swift](../Sources/DaouOfficeIntegration/DaouOfficePluginModel.swift) |
| HL-ADD-001 | 표준 편집 메뉴 Undo/Redo/Cut/Copy/Paste/Select All이 현재 소스에 포함. 언어 전환 시 메뉴 갱신 | 과거 #54 OPEN DRAFT 문구는 이력이며 현재 구현 대기 아님. 표준 responder chain·붙여넣기 자동 검사를 유지하되 실제 key-window Cmd+V/보안 입력의 사용자 수락은 별도. [ApplicationMenu.swift](../Sources/AfterSix/ApplicationMenu.swift), [QA.md](QA.md) |
| HL-ADD-002/003 | 8상태 메뉴바 눈·부리와 패널 컬러 얼굴을 같은 상태로 연결. 상태 우선순위·기록 보호 유지, 내일 연차/공가는 별도 HL-DAY-005 | 눈빛 회전은 상태 눈의 형태/판정을 바꾸지 않음. [LuluBrand.swift](../Sources/AfterSix/LuluBrand.swift), [AppModel.swift](../Sources/AfterSix/AppModel.swift) |

### 새 기능 ID와 설정 계약

| 기능 ID | 설정 경로·현재 동작·기본값 | 지원 경계·수용 기준 |
| --- | --- | --- |
| HL-RUNNER-001 | 설정 → 플러그인 관리 → 시스템 러너 설치/사용 → 설정(또는 설치된 플러그인 → 시스템 러너). 표시 방식 기본 **부엉이 눈빛**. 눈·동공·부리 모양은 고정하고 테두리의 색 띠가 회전. 시작색 `#14C9FF`, 끝색 `#AD58FF`, 각각 선택·기본색 복원·재실행 저장 | Mac 전용·선택 활성화. CPU가 높을수록 회전이 빠름. 색 변경은 회전 방식·상태·출근 계산을 바꾸지 않음. 동작 줄이기는 정지, 저전력은 프레임 제한. [RunnerSettings.swift](../Sources/CPURunnerIntegration/RunnerSettings.swift), [CPURunnerSettingsView.swift](../Sources/CPURunnerIntegration/CPURunnerSettingsView.swift), [CPURunnerController.swift](../Sources/CPURunnerIntegration/CPURunnerController.swift) |
| HL-RUNNER-002 | 같은 상세 → 표시 방식 `동물` → 햄스터/토끼/고양이. 저장값이 없을 때 동물 선택은 햄스터. 기존 부엉이는 유지하고 동물을 같은 메뉴바 항목에 함께 표시 | CPU가 높을수록 달리기 빠름. 동물 모드가 기본 선택은 아님. 고양이는 Kyome22/menubar_runcat의 고정 commit에서 가져온 5프레임·Apache-2.0 자산이며 원본/해시/라이선스를 동봉. 전체 RunCat 제품과 기능 동등성을 주장하지 않음. [RunnerAnimal.swift](../Sources/CPURunnerIntegration/RunnerAnimal.swift), [출처](../Sources/CPURunnerIntegration/Resources/RunCat/provenance.json), [라이선스](../Sources/CPURunnerIntegration/Resources/RunCat/LICENSE.txt) |
| HL-RUNNER-003 | 러너 사용 시 패널 요약과 상세 설정에 CPU·메모리 사용/전체/압력·시동 디스크 여유/전체·네트워크 송수신 속도·배터리/전원 표시. CPU·메모리·네트워크 약 1초, 디스크·배터리 5초 갱신 | 시동 디스크는 정리 가능 공간 포함. 네트워크는 물리 Wi-Fi/유선이며 VPN·가상 인터페이스/인터넷 접속 확인 제외. 배터리 없음/미측정/첫 속도 표본은 `—` 등 별도 상태. **회전/달리기 속도는 CPU만 기준**. 잠자기 때 중지·깨면 새 표본. [SystemMetrics.swift](../Sources/CPURunnerIntegration/SystemMetrics.swift), [RunnerMetricsView.swift](../Sources/CPURunnerIntegration/RunnerMetricsView.swift) |
| HL-AI-001 | 설정 → 플러그인 관리 → AI 사용량 → 설정, 또는 설치된 플러그인 → AI 사용량. 일반 → 사용량 보기/사용량 설정, 패널 사용량 행도 상세로 연결. Codex 주간 잔여량·초기화 시각·관측 기반 시간당 소모율·마지막 조회·수동 새로고침 | AI 모듈 포함 Mac 빌드에서 제공. 기존 Codex CLI ChatGPT 로그인을 재사용, 실행 파일 선택/자동찾기·로그인/취소 제공. 다른 계정 로그인은 CLI 계정도 바꿈. API 키 계정에는 주간 한도 미지원. 오래된 값·오류·미측정을 0%로 오인하지 않음. [AIUsageSettingsView.swift](../Sources/AIUsageIntegration/AIUsageSettingsView.swift), [Usage.swift](../Sources/AIUsagePlugin/Usage.swift) |
| HL-AI-002 | 같은 상세 → 표시 및 갱신. `Codex + %`(기본), `Codex 아이콘 + %`, `%만`. 갱신 1/5/10/15/30분(기본5분). 잔여량 부족 알림 기본 끔, 기준10/20/30%(기본20%) | 일반의 사용량 보기 켜기는 필요 시 AI 모듈 설치·활성화, 끄기는 설정 보존. 심볼은 16 pt template·실패 시 Codex 텍스트 fallback. 주간 잔여량은 내림, 알림은 허용된 경우만. 일정/휴가 출처와 독립. [CodexMenuBarIcon.swift](../Sources/AIUsageIntegration/CodexMenuBarIcon.swift), [AIUsageModel.swift](../Sources/AIUsageIntegration/AIUsageModel.swift) |
| HL-DAY-005 | 휴가 현황 출처가 내일의 **승인된 하루 전체 연차/공가**를 제공하면, 오늘 예정 퇴근 10분 전부터 메뉴바·패널에 모자·선글라스 장식과 내일 휴가 상태 설명 | 오늘 출근/퇴근이 휴가 출처 시간대의 같은 오늘이어야 함. 15분 이내의 유효 조회, 엄격한 날짜·승인 상태·일수 필요. 반차·미승인·모호한 다일 범위·오래된 조회는 제외. 수동 근무유형·회사 휴가 신청을 변경하지 않음. [VacationPreview.swift](../Sources/AppPluginCore/VacationPreview.swift), [AppModel.swift](../Sources/AfterSix/AppModel.swift) |
| HL-APPEAR-004 | 지원 빌드의 **macOS 26 이상**에서는 사용자 승인에 따라 기존 색상 테마에도 유리 재질·화살표 없는 패널·통합 제목줄 적용. 순정 리퀴드 글래스 선택은 별도 테마 옵션 | Swift 6.2+ compiler 조건도 충족해야 함. 투명도 줄이기/대비 증가면 불투명 재질로 대체. 패널/제목줄 선택은 OS지원 기준이므로 접근성 재질 fallback과 구분. 이전 macOS는 기존 재질/팝오버. 기존 테마/개인색 저장값 자동 교체 없음. [LuluMaterials.swift](../Sources/AfterSix/LuluMaterials.swift), [SettingsWindowChrome.swift](../Sources/AfterSix/SettingsWindowChrome.swift), [MenuBarPanel.swift](../Sources/AfterSix/MenuBarPanel.swift) |

### 개발 QA와 사용자 기능의 구분

`HL-DEV-002`는 개발용 QA 실행·보고서·격리 화면 검사다. [QA 절차](QA.md)와 [실행기](../scripts/run-qa.py)는 smoke/full, 검사별 passed/partial/failed/blocked/not-applicable/invalidated, 소스 지문과 로그·합성 화면을 기록한다. CI에서 실패해도 결과를 업로드한다. 이는 앱 설정의 사용자 플러그인이나 새 상품 기능이 아니다.

QA PR #67이 포함된 현재 main 기준으로, 자동 검사와 합성 fixture는 실제 key window·VoiceOver·개인 캘린더 전체 접근·다우오피스 Keychain 승인 후 조회·실제 잠금해제/로그인·Windows 실기기·공개 업데이트의 수락 증거를 대신하지 않는다. 대화형 QA는 개인 기록과 외부 권한을 건드리지 않는 일회용 fixture이며, 잠긴 Mac에서 실제 클릭·붙여넣기는 미검증으로 남긴다. 이 문서 작업에서는 기존 QA를 다시 실행한 것으로 표기하지 않는다.

### 사이트 기능 문서 반영 규칙

사용자 설명은 기존 `/features/`·`/guide/`의 한영 문서 흐름에 연결한다. 시간 표시/퇴근 이후에는 HL-TIME·HL-WORK, 외관에는 HL-APPEAR, 플러그인에는 HL-PLUGIN·HL-RUN·HL-AI, 근무 유형에는 HL-DAY-005를 연결한다. 러너/AI 상세를 추가하면 기능 목록·공통 내비·관련 기능·한영 전환도 함께 갱신한다. 설정 경로·기본값·선택 활성화·Mac/OS/빌드 제한을 함께 적고 QA 실행기는 개발 문서에 둔다. 공개 다운로드 버전과 main 소스 기능을 같은 상태로 단정하지 않으며 기존 URL·릴리즈 이력은 유지한다.

## 보존된 2026-10-21 조사·로컬 설치 이력

다음 내용은 원본과 기존 ID를 보존한 역사 기록이다. 해당 날짜의 `현재`·`최신`·`대기` 표현은 그 당시 범위이며 2026-10-23 main 상태는 위 절을 따른다.

## 2026-10-21 상태별 부엉이 로컬 적용 결과 · 34.5

최신 승인 범위는 첨부한 8상태 부엉이 표를 현재 상황에 맞춰 **메뉴바와 패널 좌상단에 함께 표시**하는 것이다. 아래 34.2·34.1 절은 당시 적용 이력이다. 현재 로컬 구현·검증 결과는 이 절을 우선한다. 작업 checkout은 `app/happylulu/design-refresh-local`, branch `cy-agent/design-refresh-local`, 기준 HEAD `8a4a5380f4fd8b55848cd2e5357296dbdcc35a5c`이며 변경은 해당 checkout의 로컬 미커밋 상태로 유지한다.

- **있는 기능:** 출근 입력·5개 근무유형·계산·기록·설정·6개 테마·개인 아이콘 설정을 유지한다. 상태 우선순위는 연차/공가 → 오늘 쉬는 날 → 출근 기록 없음 → 예정 퇴근 시각 경과 → 근무유형이다. 이 디자인 변경은 계산·상태 판정·사용자 데이터 저장 계약을 바꾸지 않는다.
- **뺀 기능/요소:** 기능 제거 없음. 근무유형 옆 부엉이 장식 제거를 유지하고, 일반근무·룰루데이·오전반차·오후반차·연차/공가의 캡슐 아래 중복 설명줄을 제거한다. 출근 대기·예정 퇴근 시각 경과·오늘 쉬는 날은 추가 상태 설명을 유지한다.
- **추가/변경:** 메뉴바는 26×18 pt 단색 template 눈·부리 8종, 패널의 `HappyLulu` 왼쪽은 같은 상태의 28×28 pt 컬러 얼굴 PNG 8종을 사용한다. 오전 반차는 보는 사람 기준 왼쪽 눈, 오후 반차는 오른쪽 눈을 감는다. 룰루데이는 양쪽 눈웃음과 열린 부리, 예정 시각 경과는 눈웃음과 닫힌 부리로 구분한다. 문자와 접근성 이름도 상태에 연결한다.
- **Dock·설정:** 선택한 전체 올루루+시계 PNG를 기본 앱/Dock 아이콘으로 적용한 로컬 build 34.3 설치 이력을 반영한다. `Resources/HappyLuluIcon.png`와 `Resources/HappyLuluBrand.png`는 선택 원본과 동일한 SHA256 `82a8ba2d30478b3a68a25a9b74071c4d01706263734494e2e8a40a26a55fa084`다. 설정 사이드바는 24×24 pt 정적 브랜드 그림이며 상태별 얼굴과 구분한다. 기존 사용자 아이콘 선택·개인화 경로를 유지한다. 사이트 자산 교체는 별도 대기다.
- **원본·제작:** [첨부 원본과 8종 자산·제작 기록](../../../../디자인/happylulu/2026-10-21-design-update/state-assets/README.md)을 보존한다. 컬러 얼굴은 첨부 표를 참조해 built-in imagegen으로 재구성한 투명 PNG이며 원본 픽셀을 그대로 잘라낸 결과가 아니다. 메뉴바는 코드 벡터로 재구성한다. 런타임 PNG는 `Resources/OwlStates/`에 포함한다.
- **로컬 검증:** 8종 26×18 pt 메뉴바·28 pt 컬러 헤더의 1×/2× 외관 검사, 3시간대 패널 입력, 설정 28/28 클릭을 통과했다. 기본/근무유형 펼침 각각 한영 8상태 패널 16장·설정 4장·밝고 어두운 1×/2× 보드 4장의 렌더를 통과하고 화면을 검토했다. 보드가 처음 비어 보인 원인은 검사 도구의 `calibratedWhite` tint 변환이었다. 제품 심볼은 정상이었으며 도구를 `deviceRGB`로 수정하고 64개 영역의 명암·빈 알파·경계를 검사했다. 이전 tint는 명암 0으로 실패(exit 133), 수정 후 통과를 확인했다.
- **설치·보존:** arm64 release 빌드와 기존 고정 인증서 서명을 확인한 1.5.18 / 로컬 build 34.5 / `2026-10-21-state-icons`를 `~/Applications/HappyLulu.app`에 설치·재실행했다. 후보/설치 번들 일치·엄격한 서명·단일 프로세스 PID 26953을 확인했다. 재실행 후 출근/플러그인·외관 전체·일반 설정·캘린더 DB/WAL 보존 대조는 모두 참이다. 복구본 `~/Applications/.HappyLulu-backups/20261021-173213`을 보존했고 로컬 번들의 자동 업데이트 서비스는 비활성이다.
- **미검증·범위:** CUA 연결 timeout으로 실제 데스크톱 메뉴 조작·VoiceOver는 미검증이다. fixture 렌더를 실제 데스크톱 사용 증거로 대신하지 않는다. Windows·원격 CI·로그인/재부팅 검증은 실행하지 않았다. 기준 HEAD와 기존 로컬 미커밋 변경을 유지하며 commit/push/PR/릴리즈/사이트 배포는 하지 않았다.

## 2026-10-21 헤더 후속 로컬 적용 이력 · 34.2

사용자의 후속 승인에 따라 패널·설정의 좌상단에 선택 HappyLulu 캐릭터 PNG를 적용하고 근무유형 옆 40 pt 부엉이 장식을 제거했다. 이 절은 34.2 당시 결과이며 최신 추가 변경은 상단 34.5 결과 절을 따른다.

- **있는 기능:** 출근 입력·5개 근무유형·계산·기록·설정·6개 테마·개인 아이콘 설정과 8상태 메뉴바 눈을 유지한다.
- **뺀 기능/요소:** 기능 제거 없음. 근무유형 옆 부엉이 장식만 제거하고 상태 문구는 유지한다.
- **추가/변경:** `Resources/HappyLuluBrand.png`를 패널 28×28 pt·설정 사이드바 24×24 pt에 적용했다. 선택 원본과 SHA256 `82a8ba2d30478b3a68a25a9b74071c4d01706263734494e2e8a40a26a55fa084`가 같다. Dock/번들 아이콘과 개인 아이콘 미리보기는 기존 설정을 따른다. HL-DEC-003의 헤더 적용 범위는 승인·로컬 구현 완료이며 사이트·기본 앱 아이콘 교체는 별도다.
- **검증/설치:** 3시간대 패널 입력, 설정 28/28 클릭, 한영 8상태 기본/펼침 및 설정 최소 크기 렌더, arm64 빌드와 독립 검토를 통과했다. 설정 검사에 새 소스 의존성이 빠진 오류를 재현한 뒤 목록을 고쳐 통과를 확인했다. 1.5.18 / 로컬 build 34.2 / `2026-10-21-header`를 `~/Applications/HappyLulu.app`에 설치·재실행했다. 설치본 일치·기존 인증서 서명·단일 실행 프로세스 확인.
- **보존/범위:** 기존 앱을 복구 보관했다. 재실행 후 출근/플러그인·외관 전체·일반 설정·캘린더 DB/WAL 보존을 대조했다. 자동 업데이트 서비스는 로컬 번들에서 비활성이다. commit/push/PR/릴리즈/사이트 배포 없음. 실제 데스크톱 메뉴 조작·VoiceOver는 미검증이다.

[후속 적용 화면과 검증](../../../../디자인/happylulu/2026-10-21-design-update/local-app-header-update/README.md)

## 2026-10-21 최초 승인 로컬 적용 이력 · 34.1

사용자가 2차 A안을 승인하고 **로컬 구현·설치만** 요청했다. `app/happylulu/design-refresh-local` / `cy-agent/design-refresh-local`에서 로컬 보관 PR #53 merge `8a4a5380f4fd8b55848cd2e5357296dbdcc35a5c`를 기준으로 작업했다. 원격 fetch·commit·push·PR 발행·릴리즈·사이트 배포는 하지 않았다. `develop`의 기존 변경도 유지했다.

- **있는 기능 보존:** 기존 계산/출근 저장·근무 유형·입력·설정·5개 기존 테마·5개 아이콘·개인화 경로를 유지한다. 원본 앱 PNG도 같다.
- **뺀 기능:** 이번 로컬 디자인 작업에서 제거한 기능은 없다. 이전 제거/이동 이력과 결정 대기 항목은 아래 표에 계속 보존한다.
- **추가 기능 적용:** HL-APPEAR-001에 `offwhiteLilac` 여섯 번째 테마, HL-ADD-002/003에 8개 상태별 메뉴바/패널 눈과 한영 상태 설명을 로컬 구현했다. 저장된 테마를 자동 마이그레이션하지 않는다. 새 기본값만 A이며 이번 사용자 설치에서는 원본 외관 백업 후 A를 명시적으로 선택했다.
- **설치:** `~/Applications/HappyLulu.app`, 1.5.18 / 로컬 build 34.1 / localDesignRevision 2026-10-21. 기존 bundle ID·인증서 유지, 로컬 번들의 자동 업데이트 서비스 비활성. 기존 앱과 외관/기록/설정 복구본 보존.
- **검증:** Core, 공통 계산20건, 외관/1×·2× 경계 회귀, 3시간대 패널 입력, 붙여넣기, 프로필 격리, 설정28/28클릭, 한영 8상태 364×350 및 설정920×720/820×620 렌더, arm64 빌드와 독립 검토 통과. 설치 번들 일치·엄격한 서명·새 프로세스 실행 확인. 출근/플러그인·일반 설정·캘린더 DB/WAL·사용자 이미지 보존을 재실행 후 대조했다. SQLite 임시 공유 메모리만 달라졌다.
- **남은 검증:** 실제 데스크톱 메뉴 조작·VoiceOver·잠금해제/재부팅·Windows·원격 CI 미검증. CUA 연결 실패로 테스트 렌더와 실제 실행 증거를 구분한다. #54, 사이트 구현, 원본 픽셀 추출·정확한 트레이싱은 이번 완료 범위가 아니다.

[로컬 적용 화면과 검증 범위](../../../../디자인/happylulu/2026-10-21-design-update/local-app/README.md). 아래 기준 버전 표는 최초 조사 이력을 보존하며, 위 로컬 적용 상태가 승인 후 변경분이다.

작성 기준: 2026-10-21 (Asia/Seoul). 대상은 Mac 앱, Windows 앱, 소개 사이트다. 디자인 변경 시 현재 기능을 빠뜨리지 않도록 **있는 기능 / 뺀 기능 / 추가할 기능**을 구분한다. 시각 규격은 [디자인 명세](DESIGN-SPEC.md)를 따른다. 각 `HL-*` ID는 이 문서부터 영구 식별자로 사용하며 코드 심볼이 아니다.

기준 checkout은 `app/happylulu/develop`, 실제 branch `main`, HEAD `c44cdb8c2c6e9cd43a2ffa18d74ea2371b375008`이다. 이 checkout의 Mac 메타데이터와 사이트 표기는 **1.5.17 build 33**, Windows 표기는 **1.5.13**이다. 아래 표는 소스와 기존 명세를 조사한 결과이며 실행·설치·배포 증거가 아니다. 원격 병합과 로컬 소스 사이 차이는 다음 표로 보완한다.

| 근거 | 2026-10-21에 확인된 상태 | 명세에서의 처리 |
| --- | --- | --- |
| [PR #42](https://github.com/young221718/happylulu/pull/42) | MERGED, merge `ddedf83b` | 병합된 기존 변경 |
| [PR #44](https://github.com/young221718/happylulu/pull/44) | MERGED, merge `f3ec4109` | 병합된 기존 변경 |
| [PR #48](https://github.com/young221718/happylulu/pull/48) | MERGED, merge `d7da7c0b` | 병합된 기존 변경 |
| [PR #51](https://github.com/young221718/happylulu/pull/51) | MERGED, merge `c44cdb8c` | 로컬 기준에 포함 |
| [PR #53](https://github.com/young221718/happylulu/pull/53) | MERGED 2026-10-19 08:59 UTC; head `511c9f61d63601e2a5485f0892ffc4129bdd2f4d`, merge `8a4a5380f4fd8b55848cd2e5357296dbdcc35a5c` | 기존 외관·설정 기능 보완. `AppearanceModel` 아이콘 캐시·공유 `CIContext`, `SettingsView.contentShape(Rectangle())`, Mac 1.5.18 build 34 및 사이트 메타데이터. 로컬 기준 이후이며 신규 대기 기능으로 분류하지 않는다. |
| [PR #54](https://github.com/young221718/happylulu/pull/54) | OPEN DRAFT, head `b4c4cb3310efba405fb728602b7e5d1f4437c1fc` | 표준 편집 메뉴의 검증 대기. `HL-ADD-001` |
| [이슈 #52](https://github.com/young221718/happylulu/issues/52) | OPEN. 2026-10-19 v3 선택 이력은 보존하되 2026-10-21 2차 피드백으로 원형·색감 재검토 | `HL-ADD-002`. 원본 PNG 기준으로 눈을 다시 정교화하며 v3 그대로 적용을 확정하지 않는다. 앱 런타임 아이콘 교체 승인은 아니다. |

원격 상태는 2026-10-21 최초 조사에서 PR 상태와 diff를 확인한 기록이다. 34.5 문서 갱신에서 원격 상태를 다시 조회한 결과로 해석하지 않는다. #53의 병합은 공개 릴리즈, 사용자 설치, 라이브 사이트 반영을 증명하지 않는다. [PLATFORM-STATUS](PLATFORM-STATUS.md)와 [PLATFORM-VALIDATION](PLATFORM-VALIDATION.md)는 과거 기준일의 기록이므로 최신 버전·플러그인·외관 현황을 단독 판정하지 않는다.

## 1. 있는 기능

### 1.1 Mac 기능·UI·회귀 기준

아래 각 행은 **기능 → 현재 진입 UI → 기존 동작 → 소스 → 업데이트 후 확인할 수용 기준**의 대응이다. 디자인 작업에서 행을 삭제하거나 여러 상태를 같은 상태로 합치지 않는다. 별도 표시가 없는 행은 Mac 범위다.

| 기능 ID | 기능·진입점 | 기존 동작 | 근거 | 회귀 수용 기준(아직 실행하지 않음) |
| --- | --- | --- | --- | --- |
| HL-BASE-001 | 메뉴바·오늘 패널 | Mac 메뉴바 하나, 클릭으로 364×350 팝오버 열기/닫기. 설정 창은 별도 열리고 앱 재열기도 설정으로 연결 | [Sources/AfterSix/main.swift:50](../Sources/AfterSix/main.swift), `:123`, `:132`, `:163`; [PanelView.swift:34](../Sources/AfterSix/PanelView.swift) | 중복 메뉴바/앱 인스턴스를 만들지 않고 열기·닫기·설정 이동 가능 |
| HL-BASE-002 | 오늘 상태 표시 | 출근/퇴근 시각, 출근 대기·오늘 쉬는 날·연차/공가·퇴근 가능 상태 구분 | [Sources/AfterSix/AppModel.swift:101](../Sources/AfterSix/AppModel.swift); [PanelView.swift:53](../Sources/AfterSix/PanelView.swift) | 기록 없음은 `—`; 연차와 기록 삭제 휴무를 혼동하지 않음 |
| HL-TIME-001 | 일반→시간 표시 | 밀리초·초·분·시·시/분 5개 단위, 기본 시/분. 양수 올림, 시간은 0.1시간, 음수는 0. 밀리초는 0.1초, 나머지 1초 갱신 | [Sources/AfterSix/SettingsView.swift:236](../Sources/AfterSix/SettingsView.swift); [Sources/AfterSixCore/CountdownDisplay.swift:3](../Sources/AfterSixCore/CountdownDisplay.swift) | 90분=1.5시간, 30분=0.5시간; 메뉴바·근무 화면 일치; 재실행 유지 |
| HL-TIME-002 | 일반→퇴근 예정 표시 | 기본 켜짐. 켜면 예정 시각+카운트다운, 예정 이후 시각만. 끄면 카운트다운, 예정 이후 퇴근 가능 | [Sources/AfterSix/AppModel.swift:16](../Sources/AfterSix/AppModel.swift), `:59`, `:101`; [SettingsView.swift:245](../Sources/AfterSix/SettingsView.swift) | 기본값 없는 기존 설치 포함; 즉시 반영·재실행 유지·5개 단위 보존 |
| HL-ATT-001 | 자동 출근 | 실행 중 첫 유효 화면 잠금 해제 및 로그인 항목 실행을 관측해 기록. 수동 앱 실행·wake·session-active는 기록하지 않음. 기존 첫 기록/수동 기록/휴무 보존 | [Sources/AfterSix/AppModel.swift:226](../Sources/AfterSix/AppModel.swift), `:266`, `:278`; [Sources/AfterSixCore/Attendance.swift:191](../Sources/AfterSixCore/Attendance.swift) | 첫 이벤트 우선; 후속 이벤트 덮어쓰기 금지; 앱 미실행 과거 출근 추정 금지 |
| HL-ATT-002 | 조기 감지·허용 구간 | 일반/오후 반차 06:00~07:59:59 자동 감지는 08:00 기록. 수동 일반/오후 반차 08:00~10:00 마지막 분 포함, 오전 반차 13:00~15:00 | [Sources/AfterSixCore/Attendance.swift:172](../Sources/AfterSixCore/Attendance.swift), `:206` | 06시 전 거부; 08시 보정은 자동에만; 오전 반차 규칙 보존 |
| HL-ATT-003 | 패널 출근 숫자 편집 | HH:mm 네 자리별 직접 입력·붙여넣기·+/−. 자리올림/순환 없음. Enter/외부 클릭/패널 닫기에 저장, Escape 취소. 기록 없으면 현재 시각 초안 | [Sources/AfterSix/PanelView.swift:111](../Sources/AfterSix/PanelView.swift), `:121`, `:134`; [ArrivalClockDigitField.swift](../Sources/AfterSix/ArrivalClockDigitField.swift); [Sources/AfterSixCore/ArrivalClockEdit.swift](../Sources/AfterSixCore/ArrivalClockEdit.swift) | 미래/다른 날짜/잘못된 형식·유형 불일치는 원본 보존+오류; 자정·시간대·포커스·붙여넣기 보존 |
| HL-ATT-004 | 근무→출근 시각 수정 | 별도 sheet의 시간 필드와 유형(오늘 선택 또는 자동/일반/오전·오후 반차), 저장·취소 | [Sources/AfterSix/AttendanceControlsView.swift:36](../Sources/AfterSix/AttendanceControlsView.swift) | 시간만 수정하면 자동 판단/수동 선택 우선권 유지; 실패 시 닫히지 않음 |
| HL-DAY-001 | 오늘 근무 유형 | 일반·오전반차·오후반차·룰루데이·연차/공가 다섯 캡슐. 선택한 유형 맨 앞, 확장/접기. 오늘만 적용; 선택만으로 출근 생성하지 않음 | [Sources/AfterSix/TodayDayTypeView.swift:16](../Sources/AfterSix/TodayDayTypeView.swift); [Sources/AfterSixCore/Attendance.swift:29](../Sources/AfterSixCore/Attendance.swift), `:264` | 현재 시각과 유형 불일치 시 전체 저장 거부; 다음날 독립; 선택·시각·출처·시간대 보존 |
| HL-DAY-002 | 룰루데이·명시 일반 | 룰루데이 정상 근무에서 120분 단축; 명시 일반은 마지막 금요일에도 0분 단축 override. 반차와 중복하지 않음 | [Sources/AfterSixCore/Attendance.swift:34](../Sources/AfterSixCore/Attendance.swift), `:264`, `:298` | 평일 09시 기본=18시, 룰루=16시; 마지막 금요일 자동=16시/명시 일반=18시 |
| HL-DAY-003 | 연차/공가 | 자동 출근·예정 퇴근·카운트다운 중단, 기존 출근 보존; 날짜 상세에서 보존 기록 확인 | [Sources/AfterSixCore/Attendance.swift:167](../Sources/AfterSixCore/Attendance.swift), `:264`; [AttendanceCalendarView.swift:94](../Sources/AfterSix/AttendanceCalendarView.swift), `:119` | 유형 복귀/직접 입력으로 재개; 회사 휴가 신청·연차 잔여 계산과 구분 |
| HL-DAY-004 | 근무→오늘 쉬는 날 | 확인 후 오늘 출근·수동 유형 삭제, 자동 출근 억제. 직접 출근 저장으로 재개 | [Sources/AfterSix/AttendanceControlsView.swift:112](../Sources/AfterSix/AttendanceControlsView.swift); [Sources/AfterSixCore/Attendance.swift:282](../Sources/AfterSixCore/Attendance.swift) | 확인 취소 시 불변; 재잠금 해제에도 재기록 금지; 연차 보존 동작과 명확히 다름 |
| HL-WORK-001 | 근무→근무/휴게 | 기본 480+60분; 근무 60~960분/30분 스텝, 휴게 0~240분/15분 스텝. 오늘 계산 즉시 반영 | [Sources/AfterSix/SettingsView.swift:270](../Sources/AfterSix/SettingsView.swift); [Sources/AfterSixCore/Attendance.swift:3](../Sources/AfterSixCore/Attendance.swift) | 저장 실패 원본 유지; 현재 예정 퇴근 재계산; 잠금·절전에도 실제 경과시간 사용 |
| HL-WORK-002 | 일반/반차/마지막 금요일 계산 | 일반 출근+근무+휴게−단축, 최소 출근 시각. 반차는 휴게 없이 4시간. 매월 마지막 금요일 일반 120분 단축, 공휴일 이월 없음 | [Sources/AfterSixCore/Attendance.swift:289](../Sources/AfterSixCore/Attendance.swift), `:302` | 월말·연말·기록 당시 시간대·짧은 근무·DST·다음날 퇴근 보존 |
| HL-WORK-003 | 근무→추가 시간·식대 참고 | 퇴근부터 +120분 기준 카운트다운; +30분부터 경과 분 표시. 추가 분 내림/기준 남은 분 올림. 미기록/휴무는 숨김 | [Sources/AfterSix/AttendanceControlsView.swift:97](../Sources/AfterSix/AttendanceControlsView.swift); [Sources/AfterSixCore/Attendance.swift:318](../Sources/AfterSixCore/Attendance.swift); [SPEC.md](../SPEC.md) | 18:29/18:30/20:00 경계, 반차/룰루 계산 기준; 실제 근무·식대 승인으로 표현 금지 |
| HL-ATT-005 | 근무→최근 잠금 해제 | 최근 감지 시각 또는 이력 없음 표시 | [Sources/AfterSix/AttendanceControlsView.swift:107](../Sources/AfterSix/AttendanceControlsView.swift) | 잠금 해제 감지와 출근 채택 여부 구분; 로그인/절전과 혼동하지 않음 |
| HL-HIST-001 | 출근 기록→월 달력 | 모든 저장 월 탐색, 이전/다음·오늘, 날짜 선택. 출근·유형·기록 출처(잠금해제/로그인/수동), 기록 당시 시간대·원래 날짜·여러 기록·연차/휴무/없음 구분 | [Sources/AfterSix/AttendanceCalendarView.swift:14](../Sources/AfterSix/AttendanceCalendarView.swift), `:76`; [Sources/AfterSixCore/AttendanceHistory.swift](../Sources/AfterSixCore/AttendanceHistory.swift) | 최근 N 건으로 축소하지 않음; 저장 당시 시간대·양력 날짜 보존; 과거 편집 기능으로 오해하지 않음 |
| HL-HIST-002 | 출근 기록→기록 폴더 열기 | Finder에서 로컬 state.json 위치 표시 | [Sources/AfterSix/SettingsView.swift:263](../Sources/AfterSix/SettingsView.swift); [AppModel.swift:472](../Sources/AfterSix/AppModel.swift) | 탐색만 수행; 자동 삭제/초기화/업로드 없음 |
| HL-DATA-001 | 로컬 저장·오류 보호 | AfterSix/state.json·기존 bundle ID 유지, 원자 저장·파일 600/폴더 700. 깨진 파일/미지원 스키마/설정/시간대 값은 거부, 앱 새 저장 중단 | [Sources/AfterSixCore/Attendance.swift:332](../Sources/AfterSixCore/Attendance.swift); [AppModel.swift:143](../Sources/AfterSix/AppModel.swift), `:314` | 업데이트/실패/다운그레이드에서 원본 바이트 보존; 원격 수집·Mac/Windows 동기화 없음 |
| HL-GEN-001 | 일반→언어 | 시스템·한국어·영어, 저장 후 화면/메뉴바/설정·오류 표시 변경 | [Sources/AfterSix/AppLanguage.swift:5](../Sources/AfterSix/AppLanguage.swift), `:29`, `:47`; [main.swift:72](../Sources/AfterSix/main.swift) | 기존 오류도 언어 변경 반영; 24시간 시각과 선택 언어 보존 |
| HL-GEN-002 | 일반→로그인 자동 실행 | 최초 등록 시도, 사용자 끔 보존. enabled/requiresApproval/notRegistered/notFound 상태와 시스템 설정 열기 | [Sources/AfterSix/SettingsView.swift:250](../Sources/AfterSix/SettingsView.swift); [AppModel.swift:124](../Sources/AfterSix/AppModel.swift), `:443` | 자동 실행 등록과 출근 기록 분리; 시스템 승인 필요/앱 위치 오류 구분 |
| HL-GEN-003 | 설정 탐색·종료 | 일반/외관/근무/기록/업데이트/플러그인 관리, 설치된 모듈 상세. 종료 버튼. 창 닫기는 상주 앱 유지 | [Sources/AfterSix/SettingsView.swift:70](../Sources/AfterSix/SettingsView.swift); [main.swift:168](../Sources/AfterSix/main.swift) | 모듈 없음 상태 제공; 설정 접근·종료 경로 유지 |
| HL-APPEAR-001 | 외관→테마 | 소프트 민트·웜 스톤·블루 그레이·더스티 라벤더·차콜, 패널/설정 일관 적용 | [Sources/AfterSix/AppearanceSettingsView.swift:25](../Sources/AfterSix/AppearanceSettingsView.swift); [Sources/AfterSixCore/AppearancePreferences.swift:8](../Sources/AfterSixCore/AppearancePreferences.swift) | 다섯 테마·재실행·밝고 어두운 색상 적용; 개인 기록과 독립 저장 |
| HL-APPEAR-002 | 외관→세부 색상 | 배경·사이드바·카드·강조·본문 ColorPicker/#RRGGBB, 현재 테마 기본값 복원·미리보기·낮은 대비 경고 | [Sources/AfterSix/AppearanceSettingsView.swift:53](../Sources/AfterSix/AppearanceSettingsView.swift), `:110`; [Sources/AfterSixCore/AppearancePreferences.swift:48](../Sources/AfterSixCore/AppearancePreferences.swift) | 잘못된 HEX 기존 값 보존; 대비 경고가 선택 임의 덮어쓰기하지 않음; 포커스/오류 색 외 구분 |
| HL-APPEAR-003 | 외관→아이콘 | 기존·민트·블루·라벤더·그라파이트 5종, 사용자 PNG/JPEG(20 MB/8192 px) 가져오기·선택 | [Sources/AfterSix/AppearanceSettingsView.swift:80](../Sources/AfterSix/AppearanceSettingsView.swift); [Sources/AfterSixCore/AppearancePreferences.swift:99](../Sources/AfterSixCore/AppearancePreferences.swift) | 취소/잘못된 이미지/저장 실패 원본 보존; 실행 중 아이콘/미리보기만 변경, Finder 번들 아이콘 유지 |
| HL-PLUGIN-001 | 플러그인 관리 | 앱 포함 캘린더·다우오피스·휴가 자동 인식 설치/사용 토글, 개발자·빌드 미포함·설정 필요 상태 | [Sources/AfterSix/PluginSettingsView.swift:22](../Sources/AfterSix/PluginSettingsView.swift); [PluginManagerModel.swift:109](../Sources/AfterSix/PluginManagerModel.swift) | 기본 출퇴근 플러그인 없이 사용; 외부 플러그인 마켓으로 표현 금지 |
| HL-PLUGIN-002 | 모듈→기능 연결 | 일정/휴가 현황/반차 인식별 사용 가능한 출처 또는 연결 안 함 | [Sources/AfterSix/PluginSettingsView.swift:75](../Sources/AfterSix/PluginSettingsView.swift); [PluginManagerModel.swift:299](../Sources/AfterSix/PluginManagerModel.swift) | 끔→재시작→켬에 원래 선택 복원; 명시 연결 안 함 유지; 늦은 이전 응답 폐기 |
| HL-PLUGIN-003 | 기존 설정 이관 | 구 기본 캘린더·반차·다우 연결 이관, 기존 비활성/명시 연결 해제 보존. 모듈 없는 빌드는 기본으로 fallback | [Sources/AfterSix/PluginManagerModel.swift:147](../Sources/AfterSix/PluginManagerModel.swift); [docs/USER-GUIDE.md:150](../docs/USER-GUIDE.md) | 기존 기록·비밀번호·기능별 선택 보존; 신규는 모듈 없는 기본 앱 |
| HL-CAL-001 | 캘린더 모듈→일정 | 월별 일정, 날짜별 시간/종일/제목/장소·추가 N 건, source 시간대·마지막 성공·실패/범위 밖/없음 구분, 조회 새로고침 | [Sources/AfterSix/FeatureCalendarView.swift:20](../Sources/AfterSix/FeatureCalendarView.swift); [FeatureCalendarModel.swift:22](../Sources/AfterSix/FeatureCalendarModel.swift); [CalendarWorkspaceView.swift:32](../Sources/AfterSix/CalendarWorkspaceView.swift) | 새로고침만으로 원격/시스템 쓰기 금지; 반복·초대·여러날·자정 경계; 다우는 이번 달 coverage 표시 |
| HL-CAL-002 | 패널→오늘 일정 | 종일 우선/시작 순 최대 3개·+N/전체 보기; 연결 없음/로딩/실패/빈 목록 구분, 긴 제목 생략+도움말 | [Sources/AfterSix/TodayAgendaView.swift:21](../Sources/AfterSix/TodayAgendaView.swift); [Sources/AppPluginCore/DailyAgenda.swift](../Sources/AppPluginCore/DailyAgenda.swift) | 0/3/5건·여러날·자정 종료·DST; 연결 변경/새로고침 반영 |
| HL-CAL-003 | 휴가 자동 인식 모듈 | 명시 오전/오후 반차 제목만 읽음, 수동 유형 우선. 모호/없음은 시간 기준. 실패는 직전 성공 판단 보존 | [Sources/AfterSix/SettingsView.swift:294](../Sources/AfterSix/SettingsView.swift); [AppModel.swift:337](../Sources/AfterSix/AppModel.swift), `:379`; [Sources/AfterSixCore/HalfDayRecognition.swift:6](../Sources/AfterSixCore/HalfDayRecognition.swift) | 일반 연차 추정 금지; 공유 타인 일정 위험 안내; 권한 거부/새로고침/연결 변경 경계 |
| HL-SYNC-001 | 캘린더→동기화 설정→계정 | macOS 인터넷 계정/권한 설정 열기·목록 갱신·CalDAV 안내/주소 복사. 양방향에는 전체 접근 | [Sources/AfterSix/CalendarSyncSettingsView.swift:39](../Sources/AfterSix/CalendarSyncSettingsView.swift); [HalfDayCalendarReader.swift:10](../Sources/AfterSix/HalfDayCalendarReader.swift) | 계정 없음/권한 없음/읽기 전용/목록 불완전/복귀 후 권한 재확인 구분 |
| HL-SYNC-002 | 동기화 쌍·미리보기 | 다른 두 계정 캘린더 선택+사용자 계정 확인, 첫 미리보기 필수. 시작 후 쌍 잠금. 미리보기는 쓰지 않음 | [Sources/AfterSix/CalendarSyncSettingsView.swift:83](../Sources/AfterSix/CalendarSyncSettingsView.swift), `:141`, `:269`; [CalendarSyncModel.swift](../Sources/AfterSix/CalendarSyncModel.swift) | 같은 캘린더/계정 거부; 변경/오래된 미리보기 재검증; 중복방지 기록 보존 |
| HL-SYNC-003 | 양방향 추가/수정 | 약 1시간, 지금 동기화·일시중지·새 미리보기 후 재개. 일반 알림·종일 보존, 반복 회차 −30일~+365일 개별복사, 초대는 참석자 없는 개인복사 | [Sources/AfterSix/CalendarSyncSettingsView.swift:33](../Sources/AfterSix/CalendarSyncSettingsView.swift), `:222`; [CALENDAR.md](../CALENDAR.md); [Sources/CalendarSyncServices/SyncCoordinator.swift](../Sources/CalendarSyncServices/SyncCoordinator.swift) | 삭제 자동 전파 없음; 초대 원본 보호; 특수알림/범위 밖 보류; 로컬 저장과 서버 반영 구분 |
| HL-SYNC-004 | 상태·보류·충돌 해결 | 계획/실제 반영 수·제외·보류·충돌 사유·마지막 성공/실패/다음 예약; 다우/Google 쪽 선택해 최신 확인 후 반영 | [Sources/AfterSix/CalendarSyncSettingsView.swift:141](../Sources/AfterSix/CalendarSyncSettingsView.swift), `:171`, `:192`, `:222` | 양쪽 편집/수정대삭제/초기 중복/불확실 저장 재시도 보류; 최신 변경 시 재검토 |
| HL-DAOU-001 | 다우오피스 연결 | HTTPS 회사 주소·ID·비밀번호, Keychain 저장/기존 비밀번호 재사용, 저장 후 첫 조회·15분 갱신·수동 재조회 | [Sources/DaouOfficeIntegration/DaouOfficePluginSettingsView.swift:19](../Sources/DaouOfficeIntegration/DaouOfficePluginSettingsView.swift); [docs/PLUGINS.md:9](../docs/PLUGINS.md) | 계정 바뀌면 해당 비밀번호 요구; 인증/설정/네트워크/지원 응답 오류 구분; 자격 정보 노출 금지 |
| HL-DAOU-002 | CAPTCHA | 사람이 이미지 입력/확인·새 이미지·취소·이미지 재시도, 대기 중 자동 조회 중지; 메모리에만 유지 | [Sources/DaouOfficeIntegration/DaouOfficePluginSettingsView.swift:62](../Sources/DaouOfficeIntegration/DaouOfficePluginSettingsView.swift); [docs/PLUGINS.md:19](../docs/PLUGINS.md) | 같은 세션 지속·자격정보 변경 시 취소; 자동 풀이/SSO/2FA 처리로 확대 금지 |
| HL-DAOU-003 | 연차·휴가·일정 조회 | 잔여/사용/총 연차, 올해 과거/예정 휴가·결재 상태·기간/일수, 이번 달 일정, 마지막/다음 조회·진단 | [Sources/DaouOfficeIntegration/DaouOfficePluginSettingsView.swift:119](../Sources/DaouOfficeIntegration/DaouOfficePluginSettingsView.swift), `:164`; [FeatureCalendarView.swift:89](../Sources/AfterSix/FeatureCalendarView.swift) | 실패 시 마지막 성공 결과·주의 표시; 빈 결과와 실패 구분; 원격 휴가 신청/일정 쓰기 없음 |
| HL-DAOU-004 | 연결 실패·재시도 | 네트워크 1/5/15분 재시도, 인증/권한/미지원 응답 자동중단. 끔은 작업/메모리 결과/세션 해제, 저장 연결/Keychain 보존 | [docs/PLUGINS.md:15](../docs/PLUGINS.md); [Sources/DaouOfficeIntegration/DaouOfficePluginModel.swift](../Sources/DaouOfficeIntegration/DaouOfficePluginModel.swift) | 비활성 중 늦은 응답 무시; 다시 켜기 복원; 실제 회사 호환은 별도 검증 |
| HL-UPDATE-001 | 업데이트 | 버전·자동 확인·자동 다운로드/설치·지금 확인·시작 오류; 서명 업데이트, 시간당 확인 | [Sources/AfterSix/SettingsView.swift:319](../Sources/AfterSix/SettingsView.swift); [AppUpdater.swift:7](../Sources/AfterSix/AppUpdater.swift) | 자동 설정 독립 토글/재실행; 업데이트 서비스 비활성·오류 처리; 데이터 보존 |
| HL-UPDATE-002 | 안전한 자동 설치 | 준비된 설치는 편집 창 닫힘·앱 비활성·출근/플러그인/동기화 끝난 뒤 재시작. 준비 중 설정 잠금. 종료 직전 작업 시작하면 연기 | [Sources/AfterSix/AppUpdater.swift:62](../Sources/AfterSix/AppUpdater.swift); [main.swift:97](../Sources/AfterSix/main.swift), `:153` | 저장/외부작업 중 강제 재시작 금지; 실패/중단 상태 복구; 실제 교체·권한 유지 별도 증거 |
| HL-DEV-001 | 격리 개발·진단 | production ID 외에는 별도 프로필, 개인 기록/연결/동기화와 분리; 외부연결·자동 출근·자동업데이트·로그인 변경 금지. runtime-profile/status/calendar diagnostics | [Sources/AfterSixCore/AppRuntimeProfile.swift:3](../Sources/AfterSixCore/AppRuntimeProfile.swift); [Sources/AfterSix/main.swift:179](../Sources/AfterSix/main.swift) | 디자인 QA가 정식 개인 기록/계정을 건드리지 않음; 진단은 개인 payload를 문서에 복사하지 않음 |
| HL-BACKUP-001 | 운영 백업 경계 | 배포 절차에 기존 앱/프로필 백업·SHA 대조·교체 receipts 존재. 사용자 앱 내 백업/복원/CSV 내보내기 UI는 발견하지 못함 | [docs/USER-GUIDE.md:94](../docs/USER-GUIDE.md); [DEPLOYMENT.md](../DEPLOYMENT.md); [scripts/release_delivery.py](../scripts/release_delivery.py); source `backup/export/restore` 검색 | 운영 백업을 사용자 기능으로 잘못 표기하지 않음. 새 백업/내보내기는 별도 제안/승인 필요 |

### 1.2 Windows 기능·지원 경계

Windows는 Mac과 독립 UI·배포물을 가진다. 조건은 Windows 10/11 x64와 .NET10 Desktop Runtime x64다. Mac 조건은 macOS13+ Universal이며 Apple Silicon을 권장한다. Windows 코어가 같은 계산을 사용해도 Mac 신규 UI가 지원된다고 표기하지 않는다.

| 기능 ID | 기능 → 현재 UI | 기존 동작·근거 | 회귀 수용 기준(아직 실행하지 않음) |
| --- | --- | --- | --- |
| HL-WIN-001 | 트레이 → 오늘/설정/종료 | 좌클릭 오늘 창, 우클릭 메뉴. 창 닫기는 숨기고 상주. [TrayContext.cs](../windows/HappyLulu.Tray/TrayContext.cs), [TodayForm.cs](../windows/HappyLulu.Tray/TodayForm.cs) | 트레이 하나, 재열기·숨기기·종료 가능. 툴팁 63자 제한 안에서 실시간 카운트다운·추가 시간 표시 |
| HL-WIN-002 | 자동 출근 → 오늘 창 | 실행 중 첫 `SessionUnlock` 채택. 로그인 직후는 자동 기록하지 않음. 06시→08시 보정·허용 구간·첫 기록 보호. [Windows 소스](../windows/) | 후속 잠금 해제 덮어쓰기 금지, wake·수동 실행을 출근으로 추정하지 않음. HL-ATT-001/002와 공통 규칙 범위만 비교 |
| HL-WIN-003 | 수동 출근·유형 → 오늘/근무 | 일반·오전반차·오후반차, 수동 시각, 쉬는 날 확인·재개. [TodayForm.cs](../windows/HappyLulu.Tray/TodayForm.cs), [SettingsForm.cs](../windows/HappyLulu.Tray/SettingsForm.cs) | 잘못된 시각·미래시각 거부와 원본 보존. Mac 룰루데이 수동·연차/공가 보존·명시 일반 override가 있는 것처럼 표시하지 않음 |
| HL-WIN-004 | 근무 계산 → 오늘 창 | 근무·휴게·마지막 금요일·반차, **진행 막대 유지**, 추가 시간 카드. [TodayForm.cs](../windows/HappyLulu.Tray/TodayForm.cs) | 공통 fixture의 퇴근 계산 일치, 시간 경계·추가 시간·진행 막대 유지. Mac 제거와 함께 삭제하지 않음 |
| HL-WIN-005 | 일반 설정 → 언어·단위·자동 실행 | 시스템/한/영, 5개 단위, Windows로그인 시작 등록. [SettingsForm.cs](../windows/HappyLulu.Tray/SettingsForm.cs) | 즉시 반영·재시작 보존. Mac 퇴근 예정시각 토글을 Windows 옵션으로 설명하지 않음 |
| HL-WIN-006 | 최근 기록 → 설정 탭·로컬 파일 | 최근 30건·기록 파일 경로·로컬 저장 오류 보호. 일반/근무/최근기록 탭. [SettingsForm.cs](../windows/HappyLulu.Tray/SettingsForm.cs) | 기존 상태·오류 원본 보존. 월별 전체 달력·클라우드 동기화로 오인하지 않음 |
| HL-WIN-007 | Mac 전용 기능의 비지원 표시 | Mac 컴팩트 4자리 패널·5개 유형 확장·월별 출근달력·일정/반차 캘린더·플러그인·외관·앱 자체 업데이트 없음. [플랫폼 계획](superpowers/plans/2026-10-12-platform-parity.md) | 사이트·디자인·도움말의 모든 해당 기능에 지원 플랫폼 표시. Windows 동등성 확대는 별도 결정 |

### 1.3 소개 사이트 기능·URL·회귀 기준

소스 정본은 [site/dist](../site/dist/), 현행 계약은 [site/README](../site/README.md)와 [사이트 상세 명세](site-detail-pages-spec.md)다. 공개 기준 주소는 `https://happylulu.cy-choi-lulu.chatgpt.site`이며 아래 URL은 **보존할 주소 계약**이다. 이번 문서 작성에서 공개 응답·배포 동일성·다운로드 HTTP를 확인하지 않았다.

| 기능 ID | 기능 → UI/URL | 보존할 동작 | 회귀 수용 기준(아직 실행하지 않음) |
| --- | --- | --- | --- |
| HL-SITE-001 | 홈 → [한국어 /](https://happylulu.cy-choi-lulu.chatgpt.site/) / [영어 /en/](https://happylulu.cy-choi-lulu.chatgpt.site/en/) | 헤더·제품 소개·플랫폼 다운로드·핵심 4기능·시작 3단계·푸터 | `작은 번거로움은 덜고, 내 일에 집중.` 컨셉, 메뉴 기능/사용 방법/릴리즈/다운로드/언어 유지. 데모는 가상 출근·퇴근·일정임을 표시 |
| HL-SITE-002 | 사용 방법 → [/guide/](https://happylulu.cy-choi-lulu.chatgpt.site/guide/), `/en/guide/` | 설치·첫 실행·매일 사용·출근 수정·근무 유형·플러그인·외관·기록·업데이트·문제 해결·플랫폼 차이 | 사이트 안에서 완결. 사용 방법을 외부 GitHub 문서로 넘기지 않음 |
| HL-SITE-003 | 기능 목록 → [/features/](https://happylulu.cy-choi-lulu.chatgpt.site/features/), `/en/features/` | 12개 기능 상세, 동일한 좌측 내비·현재 항목 | 목록/각 상세의 항목·순서·위치 같음, 모바일 접이식 선택·JS 없는 링크 목록 유지 |
| HL-SITE-004 | 출근 자동 기록 → `/features/attendance/`, `/en/features/attendance/` | HL-ATT-001/002, 플랫폼별 이벤트 차이 | 개요·사용법·예시·지원/주의·관련 기능 모두 제공. 앱 미실행 과거 기록 생성이나 wake 기록으로 설명하지 않음 |
| HL-SITE-005 | 출근 수정 → `/features/arrival-time/`, `/en/features/arrival-time/` | HL-ATT-003/004 | Mac 4자리·유형/시간 제한·오류/취소 보존. Windows와 UI 구분 |
| HL-SITE-006 | 근무 유형 → `/features/workday-modes/`, `/en/features/workday-modes/` | HL-DAY-001~004, HL-WORK-002 | Mac 5개 유형, 연차 보존과 쉬는 날 삭제 구분. 원격 휴가 신청으로 설명하지 않음 |
| HL-SITE-007 | 시간 표시 → `/features/countdown/`, `/en/features/countdown/` | HL-TIME-001/002 | 한영 5개 단위·즉시 반영·재실행 저장·1초/밀리초 0.1초 갱신·퇴근 후 표시 설명 보존 |
| HL-SITE-008 | 출근 기록 → `/features/history/`, `/en/features/history/` | HL-HIST-001/002, HL-WIN-006 | Mac 월별 전체/Windows 최근 30건·기록 당시 날짜/시간대·로컬 저장 구분 |
| HL-SITE-009 | 캘린더 → `/features/calendar/`, `/en/features/calendar/` | HL-CAL-001/002, HL-SYNC-001~004 | 첫 조회의 읽기 권한·표시 선택·읽기 전용 새로고침을 선택적 양방향 동기화보다 먼저 안내 |
| HL-SITE-010 | 플러그인 → `/features/plugins/`, `/en/features/plugins/` | HL-PLUGIN-001~003 | 포함 모듈의 선택 설치/사용·출처·설정 필요·비활성 보존, 외부 마켓으로 설명하지 않음 |
| HL-SITE-011 | 다우오피스 → `/features/daouoffice/`, `/en/features/daouoffice/` | HL-DAOU-001~004 | 개발자 손정열, 해당 서비스 계정/권한/네트워크, 서버 조회와 별도 EventKit 쓰기 구분 |
| HL-SITE-012 | 반차 인식 → `/features/leave-recognition/`, `/en/features/leave-recognition/` | HL-CAL-003 | 명시 오전/오후 반차·수동 우선·실패 시 직전 성공 판단. 일반 연차 자동 추정으로 확장하지 않음 |
| HL-SITE-013 | 외관 → `/features/appearance/`, `/en/features/appearance/` | HL-APPEAR-001~003 | Mac 5개 테마/5색상/아이콘/복원·사용자 이미지 제한·대비 경고 유지 |
| HL-SITE-014 | 퇴근 이후 → `/features/overtime/`, `/en/features/overtime/` | HL-WORK-003 | 추가 시간·식대는 참고이며 공식 근태·승인으로 표현하지 않음 |
| HL-SITE-015 | 업데이트 → `/features/updates/`, `/en/features/updates/` | HL-UPDATE-001/002 | Mac 자동업데이트와 Windows 수동배포 구분, 저장/외부작업 중 재시작 연기 설명 |
| HL-SITE-016 | 릴리즈 목록·상세 → [/releases/](https://happylulu.cy-choi-lulu.chatgpt.site/releases/), `/en/releases/` | 로컬 1.5.17/1.5.16/1.5.15/1.5.14/Windows 1.5.13 순서의 카드 5개, 동일 내비 | 카드별 변화 3개·직접 다운로드. 상세 경로 `macos-1.5.17`, `macos-1.5.16`, `macos-1.5.15`, `macos-1.5.14`, `windows-1.5.13`와 대응 영어 유지. #53 메타데이터 반영 시 새 현재 버전과 과거 이력을 함께 보존 |
| HL-SITE-017 | 플랫폼 다운로드 → 홈/다운로드/릴리즈 | Mac DMG·ZIP·체크섬·macOS13+ Universal/Apple Silicon 권장. Windows ZIP·Windows 10/11x64·.NET10 Desktop Runtime x64 필요 | 앱 Info.plist의 현재 버전·빌드와 기본 Mac 자산 일치. 과거 다운로드/본문/서명 피드 바이트·해시 보존. source 표기를 HTTP 성공으로 간주하지 않음 |
| HL-SITE-018 | 기존 URL·앵커·외부 정본 | `/download/`, `/install/`, `/calendar/`, `/faq/`, 홈 `#features`, `#download`, `#overtime` 등 기존 앵커; 기존 경로 11개는 검사기 기준 | 로컬 한영 46개 HTML(#53 병합안은 1.5.18 한영 상세를 더한 48개 HTML)·로컬 링크/앵커·직접 주소/새로고침/뒤로 이동 보존. GitHub는 앱 바이너리·전체 변경 기록·체크섬·소스/라이선스의 정본 |
| HL-SITE-019 | 모바일·키보드·언어 전환 | 650 px이하 헤더메뉴, 900 px이하 문서 선택 메뉴. Escape·외부/링크 클릭 닫힘·포커스 복귀. [app.js](../site/dist/app.js), [style.css](../site/dist/style.css) | 390 px·데스크톱 한영, 접힘상태 aria-expanded·현재 aria-current·skip link·초점·reduced motion·넘침 확인 |
| HL-SITE-020 | 개인정보·공개 범위·크레딧 | 로컬 출근 기록과 선택 서비스 네트워크 구분, 회사 공식 근태 시스템 아님. 푸터 GitHub·릴리즈·사용 안내·라이선스·크레딧 | 개인 일정·계정·키 없음. 기존 `project_id`/공개 범위·라이선스 유지. 게시가 앱 설치 성공을 뜻하지 않음 |

기능 상세 12개는 모두 개요·사용 방법·예시·지원 범위와 주의점·관련 기능을 가진다. 모든 상대 URL은 위 공개 기준 주소에 붙이며 한영 대응 페이지로 전환한다. 사이트 시각 변경에서도 이 기능 ID와 URL을 그대로 사용한다.


## 2. 뺀 기능

### 2.1 실제 제거

| 이력 ID | 과거 기능·근거 | 현재 상태·영향 | 사유/승인·대체·회귀 기준 |
| --- | --- | --- | --- |
| HL-REM-001 | Mac 패널 `ProgressView(value: model.progress)`; commit `958e2f9ba3fe605e654e3e9d5006900193c52ba2`의 부모 `PanelView.swift:145` | 컴팩트 패널에서 진행 막대 UI 제거. [현행 PanelView](../Sources/AfterSix/PanelView.swift)에 없고 `AppModel.progress` 계산 잔존. Windows 진행 막대는 유지 | [컴팩트 명세](compact-panel-spec.md)는 2026-10-15 승인 UX5차의 구현으로 기록한다. 막대 단독 삭제 승인 근거는 별도 확인되지 않았다. 대체는 출근/퇴근 숫자·메뉴바 카운트다운이며 동일한 시각적 진행률은 아니다. 복원 여부는 `HL-DEC-001` 결정 필요. 미래 작업은 Mac/Windows 차이를 검사한다. |

### 2.2 진입점 이동: 기능은 유지

| 이력 ID | 이전 → 현재 UI | 근거·보존할 기능 | 회귀 수용 기준 |
| --- | --- | --- | --- |
| HL-MOVE-001 | 큰 패널의 달력/직접기록/동기화상태/휴가요약/최근 잠금 해제/추가 시간/종료 → 설정 각 영역 | `958e2f9` 전후. 출근달력=출근 기록, 직접기록·최근 잠금 해제·추가 시간/식대=근무, 연차 잔여=캘린더/다우 상세, 동기화=캘린더 설정, 종료=설정 사이드바. HL-HIST/ATT/WORK/CAL/SYNC/DAOU/GEN 연결 | 기능별 현재 진입점이 존재하고 상태/오류도 접근 가능. 예전 패널에 표시되는 것처럼 그리지 않음. 접근 깊이 개선은 별도 제안 |
| HL-MOVE-003 | 별도 캘린더창/동기화창 → 통합 설정의 캘린더 조회·동기화 탭 | commit `4c292d4cb642671384dcc7df1ee6a1cfbc4367b4`; [SettingsView](../Sources/AfterSix/SettingsView.swift), [CalendarWorkspaceView](../Sources/AfterSix/CalendarWorkspaceView.swift) | 창 통합을 조회/양방향 쓰기 기능 삭제로 분류하지 않음. 두 탭의 상태·권한/미리보기 경계 유지 |

### 2.3 대체된 흐름·복구된 회귀

| 이력 ID | 이전 흐름 → 현재 | 사유·근거·승인 상태 | 회귀 수용 기준 |
| --- | --- | --- | --- |
| HL-MOVE-002 | Mac 최근 7건 목록 → 월별 전체 출근 달력 | commit `dd056855592ac542adb68882de3be6e93ea3d01c`; [AttendanceCalendarView](../Sources/AfterSix/AttendanceCalendarView.swift). Windows 최근 30건 유지 | 기존 기록 삭제 아님. 저장 월 전체·여러 기록·출처·시간대 유지 |
| HL-MOVE-004 | 기본 내장 캘린더/반차·구 연결설정 → 선택 플러그인·기능별 출처 | commit `3951981`, 레거시 이관 [PluginManagerModel](../Sources/AfterSix/PluginManagerModel.swift), [사용 안내](USER-GUIDE.md). 기존 외관/플러그인 명세와 병합 작업에 근거 | 기존 비활성·명시 연결 안 함·Keychain·기능별 선택 보존. 미설치/빌드 미포함을 삭제로 오해하지 않음 |
| HL-MOVE-005 | 컴팩트화 시 메뉴바 단위 회귀 → 5개 단위 복구·퇴근 예정시각 옵션 | `0428139` / [이슈 #47](https://github.com/young221718/happylulu/issues/47) / [PR #49](https://github.com/young221718/happylulu/pull/49), `d6e42cc` / [이슈 #50](https://github.com/young221718/happylulu/issues/50) / [PR #51](https://github.com/young221718/happylulu/pull/51); [CountdownDisplay](../Sources/AfterSixCore/CountdownDisplay.swift) | 현재 있는 HL-TIME-001/002. 제거 목록을 근거로 다시 빼지 않음 |
| HL-MOVE-006 | 큰 패널의 다음날 퇴근·자동판단 출처·마지막 금요일 배지 → 컴팩트 패널에서 보조설명 축소 | `958e2f9` 부모 PanelView의 설명과 현행 비교. 계산·출처 상세는 보존 | 계산 삭제와 가시성 축소를 구분. 이유·출처는 근무/기록/안내에서 확인. 복원 제안은 승인 전 현행 화면에 넣지 않음 |

`PLUGINS.md`와 일부 플러그인 설명에는 메뉴 패널 휴가 요약 표현이 남아 있으나 현재 [PanelView](../Sources/AfterSix/PanelView.swift)는 `LeaveSummaryView`를 호출하지 않는다. 현재 UI는 코드 기준으로 명세화한다. 이 문서 차이는 후속 담당자가 소유 문서에서 정리하며 이번 두 명세 작업에서 다른 문서를 수정하지 않는다.


## 3. 추가할 기능

### 3.1 요청·기존 작업에 근거한 적용 대기

| 기능 ID | 상태·범위 | 예정 UI/변경 계약 | 완료 수용 기준(미실행) |
| --- | --- | --- | --- |
| HL-ADD-001 | [PR #54](https://github.com/young221718/happylulu/pull/54), OPEN DRAFT. 새 표준 편집 메뉴의 통합·실기 검증 대기 | `ApplicationMenu.swift`에 Undo/Redo/Cut/Copy/Paste/SelectAll 표준 action과 nil target responder chain. `main.swift`에서 메뉴 설치·언어 변경 시 재현지화. 새 소스는 baseline에 없음 | **native key-window Cmd+V 경로가 SKIP 된 상태**이므로 완료 아님. 설정 텍스트/출근입력/보안입력 각각에서 포커스된 입력에만 명령 적용. Undo/Redo 가능 여부·Cut/Copy/Paste/SelectAll 활성화·언어 전환·닫힌 패널·포커스 없는 창·Enter/Escape·편집 저장 실패·클립보드 형식 검증. 개인 계정 없이 격리 앱에서 실제 key window를 사용해 확인 후 병합 판단 |
| HL-ADD-002 | [이슈 #52](https://github.com/young221718/happylulu/issues/52), 2026-10-21 조사 당시 OPEN. 메뉴바 눈·부리 정교화. 34.1/34.2 적용 이력 이후 첨부 8상태 표에 맞춘 34.5 로컬 구현·검증·설치 완료 | [기존 선택안](../../../../디자인/올루루/happylulu-선택안/README.md)과 [v3 원본](../../../../디자인/올루루/happylulu-눈-심볼/v3/assets/eyes-owl.svg)은 이력으로 유지한다. 최신 [상태 자산](../../../../디자인/happylulu/2026-10-21-design-update/state-assets/README.md)의 첨부 표를 참조해 메뉴바는 26×18 pt template 벡터로 재구성한다. 앱+시계 합성 PNG는 눈 형태 마스터로 쓰지 않는다. 기본 앱/Dock PNG 변경은 HL-DEC-003의 별도 후속 승인에 따른다 | 1×/2×, 밝고 어두운 배경, 8종 구분성·template tint·클릭 영역·접근성 이름·열기/닫기·카운트다운 충돌·기존 사용자 아이콘 설정 보존을 확인한다. 원본 픽셀 추출·정확한 tracing 완료로 주장하지 않는다. 최신 자산의 외관·fixture 렌더 검사와 34.5 로컬 설치·보존 대조를 통과했다. 실제 메뉴 조작·VoiceOver는 미검증이며 원격 발행은 수행하지 않음 |
| HL-ADD-003 | 2026-10-21 사용자 피드백: 출근·퇴근 예정·룰루·반차의 상태 표정. 기존 로컬 적용 후 첨부 8상태 표로 메뉴바·컬러 패널 헤더를 동기화하는 34.5 로컬 구현·검증·설치 완료 | 기존 근무 유형과 출근 기록·예정 시각을 읽어 메뉴바 26×18 pt 단색 눈·부리와 패널 28×28 pt 컬러 얼굴 PNG를 같은 상태로 표시한다. [디자인 명세](DESIGN-SPEC.md)의 2축·8상태와 우선순위를 따른다. 5개 유형 캡슐 아래 중복 설명줄은 제거하고 출근 대기·예정 시각 경과·오늘 쉬는 날 설명을 유지한다. 계산·기록·상태 전이는 변경하지 않는다. 웹은 브랜드·가상 시연에만 사용한다 | 연차/공가→오늘 쉬는 날→출근 기록 없음→예정 퇴근 시각 경과→근무 유형 순으로 우선한다. 경과를 실제 퇴근 완료로 표시하지 않고 룰루데이를 휴일로 표현하지 않는다. 오전/오후 반차는 보는 사람 기준 왼쪽/오른쪽 윙크와 해당 유형 글자를 함께 표시한다. 연차 기록 보존·쉬는 날 확인 후 오늘 기록 삭제 계약을 유지한다. 8종 연결·1×/2×·한영 기본/펼침 패널·접근성 이름 연결·데이터 보존 검사와 34.5 로컬 설치를 확인했다. 실제 메뉴 조작·VoiceOver는 미검증 |

### 3.2 결정이 필요한 제안: 승인된 추가 기능 아님

| 결정 ID | 제안·연결 기능 | 필요한 결정 | 승인 전 처리 |
| --- | --- | --- | --- |
| HL-DEC-001 | Mac 진행 막대 복원, HL-REM-001 | 컴팩트 364×350 안 복원할지, 위치·밀도·접근성·기존 상태와 공존할지 | 제안으로만 유지. 임의 복원/현재 기능 표기 금지 |
| HL-DEC-002 | 이동한 기록/추가 시간/동기화 등의 탐색 단축, HL-MOVE-001 | 원래 패널 복원인지, 현재 전체 기능 접근 보장과 제한된 바로가기인지 | 새 버튼·메뉴·패널 확장을 승인 없이 구현하지 않음 |
| HL-DEC-003 | 선택 올루루 PNG의 적용 범위 | 2026-10-21 후속 승인: 34.2 패널·설정 헤더, 34.3 기본 앱/Dock 아이콘 적용·로컬 설치. 최신 첨부 표에 따른 메뉴바·패널의 8상태 동기화는 34.5 로컬 구현·검증·설치 완료 | 전체 올루루+시계 원본은 `Resources/HappyLuluIcon.png`·`HappyLuluBrand.png`에 보존하고 설정 사이드바는 정적 그림을 사용한다. 패널은 `Resources/OwlStates/`의 28 pt 컬러 얼굴로 상태에 따라 변경한다. 기존 개인 아이콘 선택은 유지한다. 사이트 PNG 교체만 별도 결정 대기. 최신 자산의 fixture 검증·설치는 확인했으며 실제 메뉴 조작·VoiceOver는 미검증 |
| HL-DEC-004 | Pretendard·색감 방향의 제품 적용 | 1차 민트/라벤더 권장은 이력으로 보존하며 2026-10-21 2차 피드백에 따라 [디자인 명세](DESIGN-SPEC.md)의 A 오프화이트·보라 / B 크림·보라·소량 앰버 후보로 재검토한다. 추천은 A이며 원본 색 추출값이 아니다 | 기존 5개 테마·개인화와 앱 시스템 글꼴을 보존한다. A는 사용자 승인 후 Mac 로컬 적용 완료. 사이트·웹 폰트 적용은 계속 대기 |

클라우드 기록·신규 계정·원격 근태/휴가 신청·일반 연차 자동 인식·위치/Wi-Fi 출근·CSV/PDF 내보내기·사용자 백업/복원 UI·플러그인 마켓·Windows 동등 기능 확대는 이번 범위에 승인된 추가 기능이 아니다. 배포용 백업 절차를 앱 사용자 백업 기능으로 격상하지 않는다.

### 3.3 디자인 변경 시 기능 누락 방지 절차

1. 변경 전 해당 `HL-*` 행과 현재 UI/오류·빈상태/지원 플랫폼을 변경 목록에 연결한다. 새 화면에는 연결 기능 ID를 기입한다.
2. 행을 없애지 않는다. 상태가 달라지면 기존 ID를 유지하고 `있는 기능`에서 `뺀 기능` 이력으로 옮긴다. 이유·사용자 승인 근거·날짜/커밋·대체 UI·데이터 영향·회귀 확인을 함께 기록한다. 이유나 승인 근거가 없으면 `결정 필요`로 남긴다.
3. 외관만 바꾸더라도 출근 첫 기록 보호, 연차 보존/쉬는 날 삭제 차이, 수동 우선, 저장 원자성, 날짜/시간대, 읽기/쓰기 분리, 개인 아이콘/설정·오류·장애 상태는 그대로 수용 기준에 연결한다.
4. 기존 안정 ID와 사이트 URL을 유지한다. 삭제/리다이렉트가 필요한 URL은 기존 링크·언어·앵커·다운로드/피드 호환성에 대한 별도 결정을 기록한다.
5. 실제 변경 런타임별로 아래 최소 관련 검사를 고르고 결과·revision·미실행 범위를 기록한다. 문서의 수용 기준 작성은 검사를 실행한 증거가 아니다.

| 변경 범위 | 기존 검증 진입점 | 별도 실기/배포 확인 |
| --- | --- | --- |
| Mac 계산·출근·유형·표시 | `swift run --build-system native AfterSixChecks`; 공통 규칙 변경은 `swift run --build-system native AfterSixParityChecks Tests/Shared/attendance.json` | 실제 로그인/잠금해제는 명시 허가 이후 별도. 강제 잠금·재부팅 금지 |
| Mac 패널/설정·외관/키보드 | 위 코어 검사와 `bash scripts/build-app.sh`, `bash -n scripts/build-app.sh`, `plutil -lint Resources/Info.plist`; 기존 `.github/workflows/macos.yml`의 관련 checks | 격리 프로필·364×350/820×620·한영·다크/라이트·포커스·실제 key window·오류 입력·캐시/클릭 영역 확인 |
| 캘린더/플러그인 | [PLUGINS](PLUGINS.md), [CALENDAR](../CALENDAR.md), [검증 기록](PLATFORM-VALIDATION.md)의 관련 코어·모델·서비스 검사 | 계정/권한/서버 왕복/동기화 쓰기는 별도 권한. 조회 검사와 양방향 쓰기 검사 구분 |
| Windows 계산·표시 | `dotnet run --project windows/HappyLulu.Checks/HappyLulu.Checks.csproj -c Release`; 공통 fixture 변경은 `dotnet run --project windows/HappyLulu.ParityChecks/HappyLulu.ParityChecks.csproj -c Release -- Tests/Shared/attendance.json` | Windows 사용자 세션의 트레이/실제 SessionUnlock/자동 실행·진행 막대. Mac 소스 조사로 대체 불가 |
| 사이트 | `python3 site/check-site.py`, `node --check site/dist/app.js`, `git diff --check` | 로컬 브라우저 한영 1280/390 px·모바일 메뉴/내비·다운로드·키보드·링크. 승인된 게시 후 공개 URL/자산 HTTP/피드해시 별도 |
| 이 두 명세 | 상대 파일 링크·기능 ID 중복/누락·PR 상태·범위 비교, `git diff --check` | 앱·사이트 동작 검증으로 주장하지 않음 |

### 3.4 이 문서의 증거 한계

이 문서는 기존 소스·가이드·디자인 선택 기록·Git 제거/이동 이력과 2026-10-21 원격 PR/이슈 확인 결과를 정리했다. 최초 명세 작성 시점에는 실행 검증을 하지 않았다. 이후 승인된 Mac 로컬 구현·검사·설치 결과는 문서 상단에 추가했다. 공개 릴리즈 HTTP·라이브 사이트·Windows·외부 계정/서버 쓰기는 검증하지 않았다. 문서 자체의 정합성 검사 결과는 최종 작업 보고에 별도로 남긴다.

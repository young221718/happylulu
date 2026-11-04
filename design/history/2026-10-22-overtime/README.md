# happylulu 야근 경과 시간 표시

2026-10-22. 예정 퇴근 이후 메뉴바가 고정 문구만 보여주던 문제를 고쳤다. 기존 30분 표시 시작과 120분 식대 기준은 유지한다. 메뉴바, 메인 패널, 근무 설정, 툴팁은 같은 경과 시간 문자열을 사용한다.

경과 시간은 완료한 단위까지 내림한다. 일반 설정의 밀리초·초·분·시·시/분을 따르며 밀리초는 0.1초마다 갱신한다. 예정 시각을 숨겨도 경과 시간은 표시한다. 다음 날 기록이 없으면 전날 경과 시간은 사라진다.

## 화면 확인

실제 SwiftUI/AppKit 뷰에 격리된 가상 기록을 넣어 렌더했다. 사용자 기록을 바꾼 화면이 아니다. 밝은 화면·어두운 화면 각각 예정 퇴근 90분과 91분 후를 비교했다. 전체 52개 PNG 중 야근 경과 비교는 20개다.

- [90분 후 패널](integration/overtime-90-light.png)
- [91분 후 패널](integration/overtime-91-light.png)
- [91분 후 어두운 패널](integration/overtime-91-dark.png)
- [90분 후 메뉴바](integration/overtime-90-status-button-owl-light-normal-on-surface.png)
- [91분 후 메뉴바](integration/overtime-91-status-button-owl-dark-normal-on-surface.png)

## 검증

- 작성자 회귀 검사: 기존 고정 문구에서 새 검사 실패(exit 133) 후 변경본 통과.
- 작성자 `AfterSixChecks`: 기존 33개 검사, 경과 시간 5단위·두 언어·내림 경계 통과.
- 작성자 `check-plugin-architecture.sh`: 30분 경계, 표시 on/off·재시작, 초·밀리초 전진, 날짜 전환, 연차·휴무·출근 없음, 저장 기록 보존 통과. 실제 타이머가 450ms 안에 반복 발행하는 검사 포함.
- 부모 `check-ai-usage-ui.sh`: 가상 시계 90분→91분, 메뉴바·패널 공유 문구와 기록 보존 통과. 밝은 화면·어두운 화면 이미지 직접 확인.
- 독립 읽기 검토: 조치할 확정 결함 없음. 관련 `git diff --check` 통과.
- UI 검사의 첫 두 제한 환경 실행은 캐시 쓰기와 중첩 sandbox 오류로 실패했다. 캐시 경로 지정 후 허용된 호스트 실행에서 exit 0으로 완료했다.

소유 소스: `app/happylulu/runner-system-monitor`, `codex/runner-system-monitor`, 기준 `f111c37e60c1aa22d045456f445359523b66c0d5`와 미커밋 변경. 기존 눈빛 회전·색상·Codex·시스템 지표 변경을 보존했다.

## 로컬 설치

`happylulu 1.5.19/build35.7`을 `/Users/chanyoungchoi/Applications/happylulu.app`에 설치하고 재실행했다. 로컬 구분값은 `2026-10-22-live-extra-time`이다. 소스 330개 파일과 후보 앱 119개 항목을 해시로 고정해 빌드·설치 사이 변경이 없음을 확인했다. 고정 인증서 서명과 `codesign --verify --deep --strict` 검사를 통과했다.

기존 앱 백업: `/Users/chanyoungchoi/Applications/.HappyLulu-backups/20261022-190337`.

설치 바이너리 SHA-256: `bac51edccedf16995cba726785d1aa7dc1aa117e1230017312c66ce735402dff`.

캘린더 권한, 출근·플러그인 기록, 캘린더 연결, 외관, 사용자 설정, 후보 앱 일치, 이전 바이너리 백업, 재실행의 8개 검사를 모두 통과했다. 설치 후 실제 설정 창에서 플러그인 관리 화면까지 읽었다. 이후 근무 항목 조작은 컴퓨터 제어 연결 종료로 확인하지 못했다. 야근 경과 시간의 연속 갱신 증거는 위의 격리된 타이머 검사와 실제 뷰 렌더 결과이다.

새 커밋·PR·머지·공개 릴리즈·사이트 배포는 하지 않았다. 로컬 후보는 자동 업데이트를 껐으며, Apple 공증 및 Sparkle 전체 업데이트 경로는 이번에 검증하지 않았다.

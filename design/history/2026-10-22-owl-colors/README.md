# happylulu 부엉이 눈빛 색상 선택

2026-10-22 사용자 확정 요청은 회전 효과를 유지하고 회전하는 빛의 색을 직접 조절하는 것이다. 눈 모양·회전 경로·CPU별 속도는 바꾸지 않는다.

## 사용 방법

설정 → 시스템 러너 → 부엉이 눈빛에서 시작색과 끝색을 고른다. 설정명·그라디언트 미리보기·색상 선택을 3칸으로 정렬했다. 변경한 색은 즉시 적용하고 재실행 후에도 저장한다. 기본색 복원으로 청록·보라로 돌아간다. 동물 표시에서는 색상 행을 숨긴다.

[동작 비교 미리보기](http://127.0.0.1:8769/preview.html)에서 기본색과 주황·노랑 예시를 실제 네이티브 프레임으로 비교할 수 있다. 웹의 색 선택은 두 예시 비교이며 실제 앱에는 자유 색상 선택이 있다.

- [실제 앱 설정 렌더](integration/owl-settings-light.png)
- [커스텀 색상 설정 렌더](integration/owl-colors-custom-light.png)
- [기본·커스텀 메뉴바 비교](owl-colors-comparison.png)
- [브라우저 캡처](preview-browser.png)

검사 화면의 CPU·메모리·시각 등은 합성값이다. 기존 `2026-10-22-owl-orbit/`의 35.5 결과는 그대로 보존했다.

## 검증

- `CPURunnerChecks --render-dir`: 색 저장·복원, 엄격한 #RRGGBB 읽기, 잘못된 원본 값 보존, 같은 색 무변경, 즉시 출력, Reduce Motion 정적 색 변경, 타이머·phase 유지 포함 6개 그룹 통과. 설정 16장과 요약 8장 렌더. 500×580 한국어 밝음·영어 어두움 화면에서 잘림 없음.
- `scripts/check-owl-orbit.sh`: 색 변경을 무시하던 구현에서 새 검사가 실패하는 것을 확인한 뒤 최종 20,574개 검사 통과. 팔레트별 캐시 갱신, 각 endpoint 독립 반영, 강도·위치·알파·눈·장식 유지 검증.
- 기본 팔레트 192개 PNG는 35.5 원본과 바이트 단위로 동일. 커스텀 192개 프레임은 1×/2×로 생성했다.
- `scripts/check-ai-usage-ui.sh`: 최종 통합 네이티브 화면 32장 통과. 기본·커스텀 색상 설정, 기존 Codex·메뉴바·기록 보존 경로 포함.
- `scripts/check-appearance-model.sh`, `scripts/check-vacation-appearance.sh`: 기존 외관·휴가 장식 검사 통과. 팔레트 타입의 모듈 의존성에 맞춰 두 독립 검사 링크를 보완했다.
- 최종 Debug·Release 앱 빌드, 서명 검증, 셸 구문·diff 검사 통과. 독립 검토에서 조치할 확정 결함 없음.

## 로컬 설치

`happylulu 1.5.19 / build 35.6`를 `/Users/chanyoungchoi/Applications/happylulu.app`에 설치·재실행했다. 기존 앱과 데이터 백업은 `/Users/chanyoungchoi/Applications/.HappyLulu-backups/20261022-185021`에 보존했다. 기존 기록·캘린더 연결·권한·외관·사용자 설정, 후보 번들 일치, 백업 보존, 재실행의 8개 검사 통과. 설치본 설정 화면에서 부엉이 눈빛, 시작색·끝색, 기본색 복원과 켜진 플러그인 상태를 직접 읽어 확인했다.

소스는 `app/happylulu/runner-system-monitor`, `codex/runner-system-monitor`, 기준 `f111c37e60c1aa22d045456f445359523b66c0d5`의 미커밋 변경이다. 빌드 전 소스 330개 파일을 고정하고 후보 번들 119개 항목과 설치본을 대조했다. 설치 실행 파일 SHA-256: `ccd5d58185ff689dc8be24bf3d2feea4c0f2a4c25e3f515a1639acc66406090d`. 비공개 상세 설치 증거는 작업 폴더 `.build/owl-colors-install/`에 있다.

새 커밋·PR·머지·공개 릴리즈·배포는 하지 않았다. 실제 시스템 색상 패널 내부의 편집은 도구로 확인하지 못했으며, 변경·저장·복원 경로는 실행형 검사와 네이티브 렌더로 확인했다. 기존 전체 XCTest 환경 오류(`no such module 'XCTest'`), macOS 13 실기기, Sparkle 자동 업데이트 전체 경로 및 Apple 공증은 이번에 검증하지 않았다.

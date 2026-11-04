# happylulu Codex 메뉴바 심볼

2026-10-22. 앱 아이콘 전체를 14pt로 줄여 내부 기호가 뭉개져 보이던 문제를 수정한다. 배경과 그림자가 없는 Codex 공식 단색 심볼을 사용하고, 메뉴바의 글자와 같은 명암으로 표시한다. 글자·아이콘·퍼센트 선택, 접근성, 부엉이 눈빛과 야근 시간 기능은 유지한다.

## 원본

설치된 공식 앱 `/Applications/ChatGPT.app`의 `Contents/Resources/app.asar`에서 SVG를 읽었다. 번들 ID는 `com.openai.codex`, 앱 버전은 `26.1016.51333`, 빌드는 `21161`이다. 설치된 앱 파일은 수정하지 않았다.

선택 원본: `webview/assets/codex_new-f14177b03534.svg`. Codex 외곽과 `>_` 형태가 한 색으로 구성된 벡터다. [원본 SVG](codex_new-f14177b03534.svg)의 SHA-256은 `0b490f33f9c5b62c7db578f5101497efb87b774720f91b9e878243e761952c52`다.

이전 원형 심볼 `webview/assets/codex-d905da579253.svg`도 참고 이력으로 보존했으며 적용 대상이 아니다.

## 화면 확인

실제 SwiftUI/AppKit 뷰를 가상 사용량·출근 기록으로 렌더했다. 사용자 기록을 바꾼 화면이 아니다. 전체 PNG는 54개다.

- [밝은 메뉴바](integration/overtime-91-status-button-owl-light-normal-on-surface.png)
- [어두운 메뉴바](integration/overtime-91-status-button-owl-dark-normal-on-surface.png)
- [메인 패널](integration/panel-light.png)
- [밝은 설정 미리보기](integration/usage-settings-icon-light.png)
- [어두운 설정 미리보기](integration/usage-settings-icon-dark.png)

## 검증 결과

- 기존 앱 아이콘의 투명 심볼 조건 검사 실패(exit 133)를 재현했다.
- Debug·Release 빌드, `scripts/check-codex-symbol.sh`, `scripts/check-ai-usage-ui.sh`, 관련 diff·셸 문법 검사가 통과했다.
- 1× 16px 심볼의 실제 영역은 x/y 1…14, 잉크 픽셀 97개다. 2× 32px는 x/y 2…29, 잉크 픽셀 296개다. 투명 배경·비어 있는 중앙·단색을 검사했다.
- 밝음/어두움 × 일반/선택 4가지 색상, 16pt 정렬, 일반 플러그인의 원색·14pt 크기 보존, 글자/아이콘/% 선택·접근성·캐시·실패 시 텍스트 대체를 확인했다.
- 부모와 독립 검토자가 밝은/어두운 실제 메뉴바 이미지를 확인했다. 조치할 확정 결함은 없었다. 기존 부엉이 애니메이션 경로와 야근 경과 시간은 유지했다.
- XCTest 전체 실행은 하지 않았다. 선택 배경은 시스템 창이 그리므로 캐시 캡처에 포함되지 않는다. 선택 상태의 심볼 색상 자체는 네이티브 픽셀 검사로 확인했다.

## 로컬 설치

`happylulu 1.5.19/build35.8`을 `/Users/chanyoungchoi/Applications/happylulu.app`에 설치하고 재실행했다. 로컬 구분값은 `2026-10-22-clean-codex-symbol`이다. 기준 커밋 `f111c37e60c1aa22d045456f445359523b66c0d5`에 미커밋 변경을 포함한 빌드다.

소스 파일 332개와 후보 앱 항목 119개를 고정해 빌드·설치 중 변경이 없음을 확인했다. 고정 인증서 서명과 `codesign --verify --deep --strict` 검사가 통과했다. 바이너리 SHA-256: `d78c991d2dcb21e20dc58cf4db03df2c92f86ec6cf59ca7a555616e95217b8f2`.

기존 앱 백업: `/Users/chanyoungchoi/Applications/.HappyLulu-backups/20261022-191630`. 캘린더 권한·출근 및 플러그인 기록·캘린더 연결·외관·사용자 설정·후보 앱 일치·이전 바이너리 백업·재실행의 8개 검사를 통과했다.

설치본 설정 창은 직접 캡처했으나 AI 사용량 항목 클릭은 컴퓨터 제어 연결 종료로 확인하지 못했다. 위 화면 자료는 동일 소스의 격리된 실제 뷰 검사 결과다. 로컬 후보는 자동 업데이트를 끈 상태이며 새 커밋·PR·머지·공개 릴리즈·사이트 배포는 하지 않았다.

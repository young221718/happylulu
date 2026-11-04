# HappyLulu 헤더 아이콘 적용본 · 2026-10-21

사용자 후속 승인에 따라 패널·설정 좌상단에 선택 HappyLulu 캐릭터 PNG를 적용하고, 근무유형 옆 부엉이 장식은 제거했다. 기능과 상태 문구, 메뉴바의 8상태 눈은 유지한다.

- 로컬 설치: `/Users/chanyoungchoi/Applications/HappyLulu.app`, 1.5.18 / build 34.2 / `2026-10-21-header`.
- 원본: [선택 PNG](../../../../../../../design/올루루/앱-브랜딩-제안/icons/happylulu.png). 원본과 앱 내 `HappyLuluBrand.png`의 SHA256은 `82a8ba2d30478b3a68a25a9b74071c4d01706263734494e2e8a40a26a55fa084`로 같다.
- 패널 헤더 28×28 pt, 설정 사이드바 헤더 24×24 pt. 기본 앱/Dock 아이콘과 사용자 아이콘 미리보기는 기존 설정을 따른다.
- [기능 명세](../../../../../design-refresh-local/docs/FEATURE-SPEC.md) · [디자인 명세](../../../../../design-refresh-local/docs/DESIGN-SPEC.md) · [이전 34.1 화면](../local-app/README.md).

## 적용 화면

개인 기록이 없는 고정 테스트 데이터로 실제 뷰를 렌더링했다. 사용자 데스크톱 캡처가 아니다.

![기본 패널](render/panel-korean-regular.png)

- [영어 근무유형 펼침](expanded/panel-english-morningHalf.png)
- [설정 최소 크기](render/settings-korean-minimum.png)
- 한영 8상태의 기본/펼침 패널과 설정, 메뉴바 눈 보드를 `render/`, `expanded/`에 보존했다. [파일 해시](sha256.json).

## 확인 결과

3시간대 패널 입력, 설정 28/28 클릭, 한영 기본/펼침 렌더, 설정 최소 820×620 렌더와 arm64 빌드를 통과했다. 독립 검토에서 발견한 설정 검사 소스 목록 누락은 실패 재현 후 수정·재검증했다.

설치본과 빌드 산출물 일치, 기존 인증서의 엄격한 서명, 단일 프로세스 재실행을 확인했다. 이전 34.1 앱과 데이터를 복구 보관했으며 재실행 후 출근/플러그인·외관 전체·일반 설정·캘린더 DB/WAL이 유지됐다. SQLite 임시 공유 메모리는 영구 데이터 보존 비교에서 제외했다.

자동 업데이트 서비스는 로컬 번들에서 비활성이다. 원격 commit/push/PR/릴리즈·사이트 배포는 하지 않았다. 실제 메뉴 조작·VoiceOver·잠금해제/재부팅·Windows·원격 CI는 별도 미검증이다.

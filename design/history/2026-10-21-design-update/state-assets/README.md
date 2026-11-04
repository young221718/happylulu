# HappyLulu 상태별 부엉이 적용 자료

2026-10-21 사용자 첨부 [8상태 표](user-reference.png)를 최신 시각 기준으로 사용한다. 메뉴바에는 단색 눈·부리 심볼, 패널 좌상단에는 같은 상태의 컬러 부엉이 얼굴을 표시한다. Dock과 설정 사이드바는 선택한 전체 HappyLulu 캐릭터 아이콘을 사용한다.

## 상태 대응

| 코드 상태 | 사용자 표 | 컬러 얼굴·단색 심볼의 핵심 표현 |
| --- | --- | --- |
| waiting | 출근대기 | 양쪽 눈을 뜬 기본 표정 |
| regular | 남은시간 | 양쪽 눈을 뜨고 살짝 집중한 표정 |
| luluDay | 룰루데이 | 양쪽 웃는 눈, 열린 부리 |
| morningHalf | 오전반차 | 화면 기준 왼쪽 윙크 |
| afternoonHalf | 오후반차 | 화면 기준 오른쪽 윙크 |
| readyToLeave | 예정퇴근시각경과 | 양쪽 웃는 눈, 닫힌 부리 |
| annualLeave | 연차·공가 | 편안한 웃는 눈, 작은 부리 |
| dayOff | 오늘쉬는날 | 양쪽 반쯤 감은 눈 |

기존 판정 우선순위는 연차/공가 → 오늘 쉬는 날 → 출근 기록 없음 → 예정 시각 경과 → 근무유형이다. 예정 시각 경과는 실제 퇴근 완료 기록을 뜻하지 않는다. 근무유형 아래 반복 문구는 제거하며, 출근 대기·오늘 쉬는 날·예정 시각 경과처럼 다른 정보가 있을 때만 안내한다.

## 자산 제작과 보존

컬러 얼굴은 내장 imagegen으로 첨부 표를 참조해 투명 배경으로 재구성했다. [요청문 8개](prompts.json), [생성 기록](generation-record.json), [자산 SHA256 목록](manifest.json)을 보존한다. 생성된 1280×1280 PNG 8종을 직접 검토했으며 제품의 `Resources/OwlStates/` 사본과 바이트 일치를 확인했다. 원본 픽셀의 무변형 추출은 아니다. 단색 메뉴바 심볼은 같은 표를 참조한 AppKit 벡터다.

## 로컬 적용 결과 · 1.5.18 / build 34.5

`app/happylulu/design-refresh-local`의 `8a4a538` 기준 로컬 변경을 `/Users/chanyoungchoi/Applications/HappyLulu.app`에 설치하고 재실행했다. `HappyLuluLocalDesignRevision=2026-10-21-state-icons`이며 자동 업데이트 서비스는 이 로컬 번들에서 꺼져 있다. 기존 인증서·bundle ID를 유지했다. 원격 commit/push/PR/릴리즈·사이트 배포는 없다.

- 메뉴바 26×18 pt 단색 심볼과 패널 28×28 pt 컬러 얼굴이 같은 8상태를 따른다. 1×/2× 이미지는 캐시한다.
- 일반근무 등 5개 근무유형의 중복 설명줄을 제거했다. 출근 대기·예정 시각 경과·오늘 쉬는 날 안내는 유지했다.
- Dock·기본 앱 아이콘은 전체 올루루+시계 PNG이며 설정 사이드바도 이 정적 브랜드 그림을 사용한다. 개인 아이콘·테마 선택은 보존했다.
- 외관/8상태 자산 검사, 3시간대 패널 입력, 설정 28/28 클릭, 한영 기본/펼침 패널 각 16장과 설정 각 4장, 밝고 어두운 1×/2× 보드, arm64 빌드·서명 검사를 통과했다.
- 비교 보드의 색공간 변환 때문에 심볼이 빈칸으로 나오는 문제를 재현했다. 제품 심볼은 정상이었으며 검사 쪽 색상 처리를 고쳤다. 64개 영역의 실제 대비와 비어 있지 않은 심볼 경계를 검사한다. 수정 전 실패·수정 후 통과를 확인했다.
- 설치 후보와 설치본 전체 일치·엄격한 서명·단일 실행 프로세스를 확인했다. 재실행 후 출근/플러그인·외관 전체·일반 설정·캘린더 DB/WAL의 보존 대조가 모두 통과했다. 이전 앱과 데이터 복구본은 `~/Applications/.HappyLulu-backups/20261021-173213`에 있다.

실제 데스크톱 메뉴 클릭·VoiceOver는 CUA 연결 오류로 확인하지 못했다. 아래는 개인 데이터가 없는 **앱 코드의 격리 렌더**이며 실제 데스크톱 캡처가 아니다. Windows·로그인/재부팅·원격 CI는 이번 후속 검증 범위가 아니다.

## 적용 화면

![일반근무 패널 예시](render/panel-korean-regular.png)

- [8상태 밝은 배경 1×](render/eyes-light-1x.png) · [2×](render/eyes-light-2x.png)
- [8상태 어두운 배경 1×](render/eyes-dark-1x.png) · [2×](render/eyes-dark-2x.png)
- [룰루데이](render/panel-korean-luluDay.png) · [오전반차](render/panel-korean-morningHalf.png) · [오후반차](render/panel-korean-afternoonHalf.png)
- [출근 대기](render/panel-korean-waiting.png) · [예정 시각 경과](render/panel-korean-readyToLeave.png) · [연차·공가](render/panel-korean-annualLeave.png) · [쉬는 날](render/panel-korean-dayOff.png)
- [근무유형 펼침](expanded/panel-korean-afternoonHalf.png) · [영문 설정 최소 크기](render/settings-english-minimum.png)
- [48개 렌더 파일 SHA256](render-manifest.json)

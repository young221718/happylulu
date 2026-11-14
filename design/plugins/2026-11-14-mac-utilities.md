# Mac 유틸리티 플러그인과 팝업 버튼

## 확정 범위

2026-11-14 사용자 요청: 업데이트의 자동 확인/설치 토글을 숨긴다. 메뉴바 팝업의 점 세 개 메뉴는 설정·종료 아이콘 두 개로 바꾼다. 화면 꺼짐 방지와 마우스 휠 반전을 독립 플러그인으로 제공한다. 트랙패드 스크롤은 유지한다.

기존 업데이트 저장값과 자동 업데이트 동작은 유지한다. 버전·수동 확인 버튼·실제 동작 안내는 남긴다. 팝업 버튼은 각각 28pt 클릭 영역, 14pt SF Symbol, 한영 접근성 이름과 도움말을 사용한다. 종료는 앱의 정상 종료 경로를 호출한다.

## 플러그인 계약

- `MacUtilitiesIntegration`의 `keep-awake`와 `scroll-reverse`는 기존 카탈로그에서 설치하고 사용을 켠다. 설치만 하면 꺼진 상태다. 생성자·등록·화면 진입은 시스템 효과나 권한 요청을 시작하지 않는다.
- 화면 꺼짐 방지는 `PreventUserIdleDisplaySleep` assertion을 사용한다. 사용 중 자동 화면 꺼짐을 방지하고 끄기·종료·등록 해제 때 해제한다. 잠자기 메뉴·덮개 닫기·수동 잠금을 변경하지 않는다. 배터리를 더 사용할 수 있음을 안내한다.
- 스크롤 반전은 손쉬운 사용 권한이 있을 때만 scroll-wheel event tap을 시작한다. 사용자가 권한 설정 버튼을 누를 때만 시스템 설정을 연다. 권한 부족·tap 실패·중단 상태를 실제 성공 상태와 구분한다.
- 일반 마우스 휠의 line-based 수직·수평 delta만 반전한다. 연속 스크롤, scroll phase, momentum 이벤트는 그대로 통과시킨다. 공개 필드로 물리 장치를 완전히 구분할 수 없으므로 부드러운/연속 스크롤을 보내는 일부 마우스에는 적용되지 않음을 표시한다. 키보드·클릭 이벤트를 감시하거나 입력을 기록하지 않는다.
- 실행 가능 여부와 사용 설정, 실제 효과 상태를 분리한다. Dev의 외부 연동 차단은 유지하고, 두 로컬 모듈 ID만 고정 Dev에서 추가 허용한다. 합성 테스트는 별도 데이터와 가짜 드라이버를 사용한다.
- 상시 효과는 업데이트를 막는 진행 중 작업(`isRunning`)이 아니다. 실패 후 다시 확인할 수 있으며 반복 start/stop은 자원을 중복 생성/해제하지 않는다.

## 구현 계획

Goal: 위 동작을 고정 Mac Dev에 설치하고 운영 앱·사용자 데이터를 보존한다.
Architecture: 기존 PluginModule/PluginController 호스트에 두 모듈을 추가한다. SwiftUI 설정 화면과 공통 수명주기 제어기는 공유하고, IOKit assertion과 CoreGraphics event tap은 각각 주입 가능한 드라이버로 분리한다.
Tech stack: Swift 6, SwiftUI/AppKit, IOKit, ApplicationServices/CoreGraphics, 기존 Swift Package. 최소 macOS 13.

- [x] `SettingsView.swift`, `PanelView.swift`: 토글 제거, 설명 정합성, 독립 설정/종료 버튼.
- [x] `Sources/MacUtilitiesIntegration/`: 모듈·설정 UI·제어기·두 네이티브 드라이버. `Package.swift`, `BundledPlugins.swift`, `PluginManagerModel.swift`, `main.swift`에서 구성 및 좁은 로컬 허용 경계.
- [x] `Tests/MacUtilitiesTests/`: 설치 전 무효과, enable/start/stop, 실패/재시도, 권한 상태, 휠 반전과 연속/phase/momentum 원본 보존, 극단값 검사. 기존 호스트 검사에 로컬 허용/저장 실패 경계를 추가한다.
- [x] 기존 탐색/패널 검사를 새 UI에 맞춘다. 패널 검사는 앱 등록 없는 실행 파일로 전환한다. 수동 컴파일 스크립트의 새 타깃 링크를 반영한다.
- [x] `swift test --filter MacUtilitiesTests`, `swift run --build-system native AfterSixChecks`, 플러그인 호스트/설정 탐색/패널 검사, release·서명 확인. 실제 사용 권한은 자동 승인하지 않는다.
- [x] 독립 Astra 검수, 기존 Dev ZIP 보존, 동일 ID로 설치, 실제 설정·카탈로그 확인 및 팝업 검사 범위 기록. 물리 마우스/트랙패드와 장시간 화면 유지 검증 범위를 별도로 기록한다.

- [ ] 사용자 수락: 물리 마우스/트랙패드, 설치본 팝업 사용감, 실제 tap 권한 승인/철회 및 장시간 화면 유지.

## 검수·근거

Astra 사전 검수: 구현 전 확정 결함 없음. 실제 장치 구분의 한계, 등록 시 무효과, timeout/권한 철회 때 실제 상태, 좁은 Dev 실행 경계, 기존 자동 업데이트 설명 보존을 필수 확인 대상으로 선정했다.

- [Apple: 스크롤 연속성 필드](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventiscontinuous)
- [Apple: IOKit 화면 유지 assertion](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h)
- [Apple: event tap timeout](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout)

## 검증 결과 (설치 전)

- Swift Testing: 최초 무효과 stub에서 17 assertion 실패를 확인하고 실제 구현에서 통과했다. 최종 9개 검사에는 권한 부족/시작 실패/재시도/철회, tap 중단 복구·자원 해제, enable와 host start 경계, 반복 시작/종료, controller 해제, 연속/phase/momentum 원본 바이트 보존, 수직/수평·고정소수점·최소값 반전을 포함한다.
- `HAPPY_LULU_TEST_POWER_ASSERTION=1 swift test --build-system native --filter MacUtilitiesTests`: 실제 IOKit assertion을 검사 프로세스에서 잠깐 생성해 중복 생성 없이 1개가 존재하고 stop 후 없어지는 것을 확인했다. 사용자 Dev 설정은 변경하지 않았다. 이 검사는 기본 실행에서는 생략한다.
- `bash scripts/check-plugin-architecture.sh`: 기존 호스트 검사와 새 좁은 로컬 허용 ID·기본 off·저장 실패 시 효과 미시작·합성 프로필의 기존 활성 값 차단을 통과했다.
- `bash scripts/check-settings-navigation.sh`: 8테마·한영·최소창·합쳐진 설정·플러그인 사용 설정 검사를 통과했다. headless AX/키보드 수락은 별도다.
- `swift run --build-system native AfterSixChecks`: 33개 기본 검사 및 표시/로그인/프로필 후속 검사를 통과했다.
- Astra 1차 검수에서 Swift 6.2 전용 `isolated deinit` 문제를 발견해 제거했다. Swift 6.0 언어 경로를 유지했으며 별도 구형 compiler 실실행은 하지 않았다. native tap callback에는 Swift owner 포인터가 없다. tap 중단·권한은 약 3초마다 확인한다.
- 패널 검사는 별도 앱을 만들지 않는 CLI로 전환해 3시간대와 기존/arrowless 팝업의 28pt 설정·종료 버튼을 통과했다. 후속으로 편집 중 직접 종료의 저장 순서 실패를 실제 재현했다. 두 헤더 버튼은 action 전에 저장하며 잘못된 입력은 화면에 남긴다. 해당 회귀 검사와 무효 draft의 ESC 취소 후 편집 종료·오류 해제·기록 보존 assertion까지 3시간대×2호스트에서 통과했다.
- 실제 물리 마우스·트랙패드, OS 권한 승인/철회와 live event tap, 장시간 화면 유지 수락은 자동 검사와 별개다.

## 설치와 실제 UI

- 고정 `happylulu-dev` / `local.chanyoung.HappyLulu.Dev.manual-leave.20261015`, 로컬 1.5.20 build36에 설치했다. 최종 실행 파일 SHA-256: `79c367fc5ee473682df2c801dfd4efd942a4002dce93484546a9b9ca373b6b73`.
- release 빌드, SDK 27.0/minimum 13.0, ad-hoc 서명과 `codesign --verify --deep --strict`, 설치본 바이트 일치를 확인했다. Dev 프로필의 외부 통합·자동 활동·로그인 항목 변경 차단이 유지된다. SwiftPM의 native 빌드 옵션 및 macOS13 호환 onChange API 폐기 예정 경고는 남아 있다.
- 이전/최종 앱을 전체 파일 대조한 ZIP으로 보존했다. 임시 후보 `.app`은 같은 고정 ID만 사용했고, ZIP 확인 후 제거했다. 로컬 앱 이름은 운영 `happylulu`와 고정 `happylulu-dev`뿐이다.
- 실제 앱 재실행 후 일반 화면에 현재 버전·지금 업데이트 확인만 있고 자동 업데이트 토글이 없는 것을 AX로 확인했다. 플러그인 관리의 두 신규 설치 항목과 문구를 실제 화면에서 확인하고 해당 화면을 열어 두었다. 신규 플러그인을 실제 사용자 프로필에 설치/활성화하거나 손쉬운 사용 권한을 승인하지 않았다.
- 운영 실행 파일과 Dev의 출근 기록·플러그인 카탈로그·기능 연결·외관 파일 해시가 동일하다. 전체 preferences plist는 재실행 후 바이트가 달라 전체 동일성은 주장하지 않는다.
- Astra 최종 검수에서 추가 blocker가 없었다. 직접 Quit의 저장 순서 결함은 실패 재현 → 동기 저장 보완 → 유효/무효 입력 검사로 닫았다. 마지막 ESC 검증 보강은 앱 소스를 변경하지 않는다.
- 실제 설치본 메뉴바 팝업은 현재 CUA의 창 중심 접근으로 열지 못했다. 설정·종료 버튼 및 편집 경계는 실제 PanelView를 호스팅한 격리 CLI의 클릭/정상 종료 delegate 검사로 확인한 범위다. 물리 장치 스크롤과 live tap 권한 철회·장시간 화면 유지, 사용자 수락은 대기다.

로컬 증거: workspace `artifacts/happylulu-utilities-20261114.d6aswndj/`의 manifest, source hashes, 검사 로그와 두 검증된 ZIP. 사용자 데이터나 원시 로그를 공유 TODO에 복사하지 않는다. 커밋·푸시·공개 배포는 하지 않았다.

## PR 준비 중 CI 연결 보완

새 모듈을 기존 전체 QA 목록에 연결했다. `MacUtilitiesTests` 누락을 QA runner 검사에서 2건 실패로 재현한 뒤 보완해 22개 검사가 통과했다. 기본 유틸리티 경로는 8개 통과, 실제 전원 assertion 1개는 명시 실행 전까지 생략한다.

외부 Daouoffice/AI 소스를 제거하는 격리 검사는 로컬 기본 모듈 3개를 요구하도록 갱신했고 빌드·구성 진단·코어·호스트 검사가 통과했다. 렌더 프로브는 누락된 `MacUtilitiesIntegration` 링크로 실패하는 것을 재현하고 object 연결 후 컴파일을 통과했다. 로컬 고정 앱 식별자 규칙에 따라 렌더 GUI는 실행하지 않았다. Astra가 이 네 검사 스크립트를 별도 검토했고 추가 blocker가 없었다.

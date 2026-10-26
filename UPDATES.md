# HappyLulu 업데이트

2026-10-07 사용자 요청으로 보류를 재개했습니다. Mac 1.5.9 build17부터 서명된 자동 업데이트를 활성화합니다. 1.5.6 이하 비활성 설치본은 최초 한 번 활성화 버전으로 교체해야 하며, 이후 앱이 업데이트를 처리합니다. 로컬 검증용 활성화 부트스트랩은 1.5.8 build16입니다.

- 기본은 시작 시와 1시간 주기로 새 버전을 확인하고 자동 다운로드·설치합니다. 기존에 저장된 사용자 설정은 존중하며, 설정의 업데이트에서 자동 확인·자동 설치를 각각 바꿀 수 있습니다.
- 자동 재시작은 앱 창이 닫히고 앱이 비활성이며 출근 저장·캘린더 동기화가 진행 중이 아닐 때 수행합니다. 준비된 업데이트는 정상 종료 시에도 설치됩니다. 설치 준비가 끝나면 해당 설치는 취소하지 않으며 재시작까지 설정 변경을 잠시 막습니다.
- 출근·캘린더 연결 기록은 앱 bundle 밖에 보관하므로 교체 시 유지됩니다. 실제 교체 전후 파일 해시/버전/실행 확인은 별도 검증합니다.
- 앱 ZIP, 업데이트 목록과 릴리즈 노트를 Ed25519로 서명하고 앱은 서명과 변조를 검증합니다. 앱 공개키는 유지합니다. 1.5.10 build25 후보부터 feed는 GitHub Releases의 고정 주소를 사용합니다.
- 비밀키는 제작자 맥의 키체인 `happylulu-updates`에 있으며 내보내거나 Git/사이트에 저장하지 않습니다. 키체인 승인창이 표시되면 사용자가 직접 승인합니다.
- Developer ID 서명·Apple 공증은 미완료입니다. 자동 업데이트 서명과는 별개이며 다른 맥의 보안 정책/설치 권한에 따라 확인이 필요할 수 있습니다. Intel 실기기는 보류입니다.

## 로컬 고정 코드 서명

빌드·패키징은 `scripts/sign-app.sh`를 공유합니다. 이 Mac의 로그인 키체인에 고정된 자체 서명 인증서를 보관하고, 공개 인증서와 지문 기록은 `~/Library/Application Support/HappyLulu/Signing/`에서 읽습니다. 개인 키를 Git이나 사이트에 넣지 않습니다. 시스템 전체의 인증서 신뢰 설정은 변경하지 않습니다.

다른 인증서를 지정할 때는 `HAPPY_LULU_SIGNING_IDENTITY`에 인증서 SHA-1 지문을 넣습니다. 지정한 인증서가 없거나 기록이 불일치하면 실패하며 ad-hoc으로 몰래 전환하지 않습니다. 로컬 기록도 지정값도 없는 개발 환경에서는 기존 ad-hoc 방식을 유지하고 출력에 명시합니다. 명시적인 ad-hoc 시험은 값 `-`를 사용합니다.

자체 서명은 Apple Developer ID·공증을 대신하지 않습니다. 같은 인증서와 앱 식별자가 업데이트 간 유지되는지 `bash scripts/check-code-signing.sh`로 검사합니다. 격리 시험 앱에서는 같은 인증서의 두 빌드 사이에 실제 Sparkle 다운로드·교체·자동 재실행을 확인했습니다. 실제 HappyLulu의 캘린더 권한 지속은 별도 실험 결과로 기록합니다. 외부 Mac의 Gatekeeper 설치 경험도 별도 검증 대상입니다.

## 새 버전 배포 · Mac 1.5.20 build36

이번 공개 대상은 **Mac 1.5.20 build36**입니다. 선택형 부엉이 눈빛·시스템 지표·Codex 사용량, 야근 시간 갱신, 설정/종료 메뉴와 macOS 26 이상의 새 패널·재질을 제공합니다. Windows는 1.5.13을 유지합니다.

기존 서명 후보의 소스 `08e248a2cfe429d26ef5c00f32875880e33000e1`과 ZIP·DMG·노트·서명 appcast를 그대로 사용합니다. 제작자 Mac의 직접 설치·재실행·버전 표시는 확인했습니다. 실제 캘린더 연결/권한·회사 계정 왕복·외부 기기 수락과 자동 업데이트 경로의 설치 성공은 별도 미검증입니다. 공개 승인을 확인하지 않은 설치 증거의 true로 대신하지 않습니다. 이번 명시적 공개는 [DEPLOYMENT.md](DEPLOYMENT.md)의 별도 수동 공개 절차를 따르며, 실제 설치 증거를 요구하는 `promote`의 조건은 유지합니다.

공개할 고정 GitHub feed와 기존 Site `/updates/appcast.xml`은 **후보 build36의 동일한 서명 XML 바이트**로 맞춥니다. 작업 전 확인한 기존 Site feed는 Mac 1.5.19 build35입니다. 이전 build35 feed는 비공개 `receipts/`에 보존하고, 기존 버전 바이너리·서명 노트·릴리즈 자산을 다시 쓰지 않습니다. 두 주소의 게시·서명·공개 HTTP 바이트 일치를 각각 확인하며, 실제 이전 설치본의 다운로드·교체·재실행 성공과 구분합니다. 이 절은 공개 대상과 절차 설명이며 게시 성공을 미리 기록한 것이 아닙니다.

### 이전 배포·검증 이력

아래 1.5.19 설명과 설치 경로는 당시의 배포 준비 기록입니다. 현재 공개 대상과 절차는 위 1.5.20 절을 따릅니다.

**Mac 1.5.19 build35**는 소문자 앱 이름과 부엉이 상태 디자인, 표준 복사·붙여넣기, 휴가 전날 표시, 일반 설정의 3열 정렬과 사용 설명서 링크를 제공합니다. 메뉴바 퇴근 시각 표시 옵션·시간 단위·기존 기록과 설정을 유지합니다. Windows는1.5.13을 유지합니다.

이번 공개는 최종 후보를 이 Mac에 설치하고 재실행한 뒤 기록·캘린더 연결·권한 보존을 검증하는 경로입니다. 기존 자체 서명 인증서와 Sparkle 키로 패키지·서명 피드를 검증하고, 후보 ZIP 해시에 연결된 실제 설치 증거가 충족된 뒤 [DEPLOYMENT.md](DEPLOYMENT.md)의 `promote` 절차로 공개합니다. 설치 증거와 공개 파일 확인은 별도 결과로 기록합니다.

공개 Mac 1.5.14 build30은 앱 내부 플러그인·기능 어댑터와 다우오피스 일반 계정·CAPTCHA 로그인, 올해 휴가·이번 달 일정 조회를 추가합니다. 원격 등록·수정·삭제는 수행하지 않습니다. 이 버전의 실제 설치·권한 유지 시험은 수행하지 않았으며 사용자가 직접 업데이트합니다. 1.5.11 build27의 아래 설치 검증 이력과 구분합니다.

배포 절차와 승격 조건의 정본은 [DEPLOYMENT.md](DEPLOYMENT.md)입니다. **1.5.11 build27을 공개했고** 로컬 설치본 교체·재실행과 기록·연결·캘린더 전체 권한 보존, 공개 파일·서명 피드 바이트 일치를 확인했습니다. 이 Mac의 직접 교체 검증이며 모든 외부 Mac 또는 이전 Site 피드 앱의 자동 이전 성공을 뜻하지 않습니다.

### 공통 준비와 피드 게시

- 앱 feed: `https://github.com/young221718/happylulu-app/releases/download/macos-update-feed/appcast.xml`
- 이번 배포 보관 태그: `macos-v1.5.20-build36`; 이전 공개 `macos-v1.5.19-build35`·`macos-v1.5.18-build34`·`macos-v1.5.17-build33`·`macos-v1.5.16-build32`·`macos-v1.5.15-build31` 자산도 보존
- `macos-update-feed`는 mutable prerelease이며 Latest로 표시하지 않습니다. 서명한 XML을 수정하지 않고 그대로 올립니다.
- 소스의 LICENSE와 THIRD_PARTY_NOTICES.md를 앱 Resources, ZIP 내부 앱, DMG와 릴리스 자산에 동봉합니다. 과거 바이너리는 다시 포장하거나 새 라이선스가 소급 동봉된 것으로 표시하지 않습니다.
- 공개 CI는 검증과 ad-hoc Universal 패키지 artifact만 만듭니다. 로컬 서명키나 키체인 정보를 GitHub Secrets에 넣지 않습니다.

```sh
bash scripts/prepare-release.sh
python3 scripts/release_delivery.py check dist/releases/1.5.20-build36
python3 scripts/release_delivery.py draft dist/releases/1.5.20-build36 --dry-run
```

위 준비 명령은 신규 후보를 만들 때 사용합니다. 이미 준비한 build36 폴더는 다시 만들거나 덮어쓰지 않습니다. `prepare-release.sh`는 사용자가 승인한 로컬 키체인 서명만 사용합니다. 실제 GitHub 쓰기는 별도 `draft`·`promote` 또는 명시적으로 승인된 수동 공개 단계에서 수행합니다. `check`와 `--dry-run`은 GitHub에 접속하지 않습니다. 실제 HappyLulu 교체·재실행, 캘린더 권한·출근 기록·캘린더 연결 보존 증거가 이 ZIP 해시와 일치하지 않으면 승격하지 못합니다.

기존 설치본은 종전 사이트의 `/updates/appcast.xml`을 계속 읽습니다. 이번 공개에서는 그 주소와 GitHub 고정 feed에 같은 build36 서명 appcast를 제공합니다. 이전 build35 서명본과 원래 다운로드 파일은 보존합니다. 두 주소의 게시 readback만으로 기존 설치본의 자동 이전 성공을 주장하지 않으며, 실제 다운로드·교체·재실행 및 기록·연결·권한 보존은 별도 확인합니다.

검사 범위는 설정/서명·변조 거부, 서버 응답의 XML/Content-Type/해시, 이전 설치본에서 다운로드·교체·재실행 및 기록 보존입니다. 서버 게시만으로 실제 설치 성공을 주장하지 않습니다.

공식 계약: [Sparkle 설정](https://sparkle-project.org/documentation/), [자동 설치](https://sparkle-project.org/documentation/customization/), [유휴 시 설치](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html), [배포](https://sparkle-project.org/documentation/publishing/).

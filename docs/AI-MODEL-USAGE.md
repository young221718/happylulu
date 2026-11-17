# AI 사용량 연결

Mac 1.5.21 공개판은 Codex 기능을 유지합니다. 이 문서의 **새 연결 프로필·Claude·Antigravity는 로컬 개발 후보 기능**이며 아직 공개 배포를 뜻하지 않습니다.

## 지원 범위

| 연결 | 사용량 출처 | 로그인·갱신 | 관측 이력·알림 |
| --- | --- | --- | --- |
| 기존 공개 Codex | 설치된 Codex의 `app-server` | 기존 연결 유지. 로그인 버튼을 누를 때만 브라우저 인증 | 계정 지문이 있는 주간 한도 |
| 새 Codex 프로필 | 명시적으로 선택한 계정 폴더의 Codex `app-server` | 실행 파일·전용 계정 폴더 선택. 해당 폴더의 로그인만 사용 | 프로필·계정별 분리 |
| Claude | 공식 statusLine의 `rate_limits.seven_day`를 최소 파일로 내보내기 | 사용자가 statusLine을 연결. 앱은 파일만 읽으며 CLI나 로그인을 실행하지 않음 | 계정 식별자가 없어 사용하지 않음 |
| Antigravity | 공식 statusLine의 `quota.gemini-weekly`를 최소 파일로 내보내기 | Claude와 같은 수동 연결. API 키나 비공개 엔드포인트 사용 없음 | 공식 데이터에 이메일이 있을 때 지문으로 계정 구분 |

공식 계약: [Codex app-server](https://developers.openai.com/codex/app-server), [Claude statusLine](https://code.claude.com/docs/en/statusline), [Antigravity statusLine](https://antigravity.google/docs/cli/statusline/). 2026-11-17 문서를 확인했습니다. Antigravity의 과거 `agy -p /usage --output-format json` 구현은 복원하지 않았습니다. 모델 추론을 사용량 조회로 대체하지 않습니다.

표시 값은 **주간 잔여 한도**입니다. API 요금·컨텍스트 잔여량·토큰 속도가 아닙니다. 주간 한도가 없으면 `—`이며 단기 한도나 다른 모델 한도로 대체하지 않습니다. Claude의 한도 필드는 지원되는 구독과 응답 이후에만 생길 수 있습니다. Antigravity도 계정·제품에 따라 `gemini-weekly`가 없으면 표시하지 않습니다.

## 프로필과 기존 연결

플러그인 관리에서 AI 사용량을 설치하고 **사용량 보기**를 켭니다. 최초 기본값은 꺼짐입니다. 설정의 **사용량 연결**에서 기존 공개 Codex를 유지하거나 연결을 추가합니다. 연결 이름·표시 형식·갱신 주기·알림 설정은 새 프로필마다 보관합니다. 새 Codex 연결은 전용 계정 폴더를 선택하기 전에는 조회나 로그인을 시작하지 않습니다. 기존 CLI 폴더를 직접 선택하면 그 폴더의 계정을 공유합니다.

연결을 전환하거나 끄면 진행 중인 조회·로그인을 취소하고 늦은 완료를 무시합니다. 연결 제거는 목록에서만 제거하며 계정 폴더·사용량 파일·이전 관측 자료는 삭제하지 않습니다. 초기화 시각이나 계정이 바뀌면 연속 소모율을 다시 계산합니다.

## Claude·Antigravity 연결

앱은 기존 statusLine 설정을 자동으로 수정하지 않습니다. 두 제품의 기존 출력도 유지할 수 있도록 아래 작업을 직접 적용합니다. 설치된 Python 3가 필요하며 HappyLulu가 Python이나 CLI를 설치하지 않습니다.

1. **연결 추가**에서 공급자를 선택하고 **내보내기 도우미 저장**으로 `export-ai-usage.py`를 저장합니다. 도우미는 앱 리소스에 포함됩니다.
2. 각 계정·앱 환경에 서로 다른 전용 폴더를 만듭니다. 아래 경로는 예시입니다.

   ```sh
   mkdir -p "$HOME/.local/state/happylulu-ai/claude-personal"
   chmod 700 "$HOME/.local/state/happylulu-ai/claude-personal"
   ```

3. 기존 statusLine이 있다면 그 명령을 아래 래퍼의 마지막 줄에 그대로 연결합니다. `/absolute/path`는 실제 저장한 경로, `python3`는 설치된 인터프리터 경로로 바꿉니다. Antigravity에서는 `--provider antigravity`와 별도 출력 폴더를 사용합니다.

   ```sh
   #!/bin/sh
   input=$(cat)
   printf '%s' "$input" | python3 /absolute/path/export-ai-usage.py \
     --provider claude \
     --output "$HOME/.local/state/happylulu-ai/claude-personal/usage.json"
   printf '%s' "$input" | /absolute/path/existing-statusline.sh
   ```

   기존 명령이 없으면 마지막 줄을 `printf '%s\n' 'HappyLulu 사용량 연결'`로 바꿉니다. 도우미는 stdout을 출력하지 않습니다. 래퍼의 마지막 명령이 기존 statusLine의 출력을 담당합니다. 입력을 원본 JSON 파일로 저장하지 마세요.
4. 공급자의 공식 statusLine 설정 방법에 따라 이 래퍼를 연결합니다. CLI가 다음 statusLine 데이터를 내보내면 HappyLulu의 **사용량 파일 선택**에서 생성된 `usage.json`을 선택합니다. 여러 계정은 별도 CLI 설정·래퍼·파일·HappyLulu 프로필로 구분하세요. 운영 앱과 Dev 앱도 파일 경로를 분리하세요.

도우미는 주간/단기 한도 숫자·초기화 시각·관측 시각만 저장합니다. Antigravity 계정 구분용 이메일은 SHA-256 지문으로 바꾸며 이메일·프롬프트·대화·작업 경로·인증 정보는 저장하지 않습니다. 소유자만 접근하는 폴더에 `0600` 파일을 원자적으로 교체하고, 심볼릭 링크·공용 폴더·손상 입력은 거부합니다. 오류에 입력이나 파일 경로를 기록하지 않습니다.

**지금 새로고침**은 파일을 다시 읽습니다. CLI 서버에서 새로 조회했다는 뜻이 아닙니다. 앱은 파일의 관측 시각을 그대로 표시하며 15분이 지난 데이터·미래 시각·만료된 한도·다른 공급자의 파일을 거부합니다. CLI를 사용하지 않으면 새 값이 없을 수 있습니다. 조회 실패 시 실제 계정에 자동 로그인하지 않습니다.

## 표시와 알림

공급자 이름+%, 아이콘+%, %만 중에서 선택합니다. Codex 이외에는 아이콘이 없으면 이름으로 표시합니다. 기본은 이름+%·5분·알림 끔입니다. 갱신 주기는 1/5/10/15/30분, 알림 기준은 10/20/30%입니다. 알림은 시스템 권한·활성화·현재 연결·계정 식별 여부를 확인합니다. 시간당 소모율은 같은 계정·주간 경계의 실제 연속 관측에만 기반하며 알려지지 않은 구간을 추정하지 않습니다.

## 저장 호환과 개발 앱

이전 `HappyLuluAIUsage.preferences.v1`과 공개 `codex-release` 설정·이력·알림 공간을 새 프로필 저장소로 덮어쓰지 않습니다. 새 프로필은 `HappyLuluAIUsage.providers.v2`에 명시적으로 추가할 때만 생성하며 이전 개발판의 공급자나 프로필을 자동 실행·이관하지 않습니다. 기존 단일 Codex 또는 명확히 선택된 Codex 연결의 공개 호환 경로도 유지합니다.

알 수 없는 버전·공급자·손상된 새 설정은 원본을 보존하고 읽기 전용으로 중지합니다. 손상 이력·알림은 해당 저장 내용을 보존합니다. 새 어댑터는 `UsageProviderRegistry`에 공급자 설명·연결 방식·팩터리를 함께 등록하며 UI와 계정 이력 처리를 공유합니다.

고정 `happylulu-dev` / `local.chanyoung.HappyLulu.Dev.manual-leave.20261015`만 기존 개발 실행 예외를 사용합니다. 출퇴근·운영 앱 데이터·다른 플러그인의 실행 권한은 바꾸지 않습니다. CLI의 기본 로그인을 공유할 수 있는 기존 공개 연결과 명시적으로 선택한 계정 폴더의 차이에 주의하세요.

## 검증 범위

`swift test --build-system native --jobs 2 --filter AIUsageTests`는 합성 app-server, 공식 statusLine 형식의 합성 입력, 앱에 포함된 도우미→최소 파일→실제 리더 경로, 프로필 전환·취소·늦은 로그인 완료·저장 호환·손상 설정을 검사합니다. `python3 -B -m unittest discover -s Tests/AIUsageExporterTests -v`는 필터링·파일 권한·링크 거부·원자적 교체·실패 시 보존을 검사합니다. 전체 QA의 AI 검사에도 포함됩니다.

실제 계정·브라우저 인증·공급자 서버 응답·사용자의 statusLine 구성·실제 알림 전달은 이 fixture 검사로 확인되지 않습니다.

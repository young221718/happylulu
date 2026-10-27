# HappyLulu 자동 검증 계약

이 폴더는 HappyLulu가 유지해야 하는 동작과 자동 검증의 연결을 관리한다. 기존 [기능 명세](../docs/FEATURE-SPEC.md), [상세 동작 명세](../SPEC.md), [디자인 기준](../docs/DESIGN-SPEC.md)은 원문과 이력을 유지한다. 아래는 이미 존재하는 검사에 연결한 계약이며, 전체 기능·실기기 수락을 자동 검증했다는 결과표가 아니다.

## 계약과 검증

| 식별자 | 관찰 가능한 통과 조건 | 자동 검증 근거 |
| --- | --- | --- |
| HL-CONTRACT-001 | 같은 날의 나중 잠금 해제가 최초 출근이나 사용자의 수동 수정 기록을 덮어쓰지 않는다. | [AttendanceTests](../Tests/AfterSixCoreTests/AttendanceTests.swift)의 `testLaterUnlockDoesNotReplaceFirstArrival`, `testManualCorrectionSurvivesLaterUnlock` |
| HL-CONTRACT-002 | 출근 파일이 없으면 기록을 만들지 않고, 손상 파일·유효하지 않은 입력·알 수 없는 스키마를 기존 데이터 위에 덮어쓰지 않는다. | 같은 테스트의 `testMissingFileDoesNotInventAttendanceOrWrite`, `testCorruptFileIsPreserved`, `testInvalidArrivalCannotOverwriteFile`, `testInvalidSettingsCannotOverwriteFile`, `testUnknownSchemaIsRejected` |
| HL-CONTRACT-003 | 저장된 출근은 재시작 후 유지되고, 날짜 경계·저장된 시간대·DST를 반영한다. | 같은 테스트의 `testPersistenceAndRestartDoNotOverwriteArrival`, `testNewDayHasIndependentFirstUnlock`, `testLocalDayDoesNotUseUTCDate`, `testCountdownUsesElapsedTimeAcrossDST` |
| HL-CONTRACT-004 | 일반 근무·마지막 금요일·반차의 예정 퇴근 계산과 30분/120분 경계가 유지된다. | 같은 테스트의 `testDepartureIncludesBreak`, `testMorningHalfAndLastFridayDoNotStack`, `testPostDepartureThirtyAndMealBoundaries`, `testPostDepartureUsesHalfDayAndLastFridayDeparture` |
| HL-CONTRACT-005 | 한영 5개 카운트다운 단위는 소수·0·만료 경계에서 정의된 문자열과 음수 방지 조건을 만족한다. | [검사 진입점](../Tests/AfterSixCoreTests/main.swift)의 `countdownSamples`와 경계 검사 |

위 계약은 [Package.swift](../Package.swift)에 정의된 `AfterSixChecks`에서 실행한다.

```sh
swift run --build-system native AfterSixChecks
```

기존 macOS Command Line Tools와 이미 준비된 의존성을 사용한다. 도구·의존성 부재는 차단 상태로 기록하며 설치나 네트워크 접근을 자동 승인하지 않는다. 실행 결과에는 checkout·revision·명령·환경·종료 코드와 검증하지 않은 범위를 남긴다.

## 추가 계약과 자동 검증의 경계

플러그인·캘린더·업데이트·사이트·Windows의 상세 검사 진입점은 [QA](../docs/QA.md), [플랫폼 검증](../docs/PLATFORM-VALIDATION.md), [기능 명세](../docs/FEATURE-SPEC.md), [사이트 문서](../site/README.md)에서 찾는다. 새 계약은 식별자·관찰 가능한 조건·정확한 테스트 또는 명령을 함께 추가한다. 기대 동작이 바뀌면 테스트와 해당 원문을 같은 변경에서 갱신한다.

실제 Keychain 승인, 개인 캘린더 접근, 잠금 해제·로그인, VoiceOver와 실기기 화면 수락은 기존 문서의 별도 검증 항목이다. 자동 검증이 없는 제안은 초안·미검증으로 표시하고 이 계약 표의 완료 항목으로 추가하지 않는다. 기존 날짜가 있는 결과는 해당 날짜와 revision의 증거로 보존한다.

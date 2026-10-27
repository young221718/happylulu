# HappyLulu 위키

HappyLulu 레포의 지식과 전체 문서를 찾는 목차다. 각 문서의 원문과 기존 날짜·결정·검증 기록은 원래 위치에서 유지한다. 이 위키는 HappyLulu 지식을 관리하며 여러 레포의 공통 지식은 workspace-chanyoung의 [통합 위키](../../../../wiki/index.md)로 연결한다. 작업 진행은 Space의 채팅별 목차와 주제 기록에 남기고, 유지할 제품 지식과 문서는 이 레포에서 갱신한다.

## 작업별 시작

| 목적 | 문서 |
| --- | --- |
| 에이전트 작업 시작·읽기 순서 | [AGENTS](../AGENTS.md) |
| 변경 방법·보존·게시 권한 | [작업 규칙](../rules/README.md), [개발·검증 세부 규칙](../rules/development.md) |
| 유지할 동작과 자동 검사 | [스펙 목차](../spec/README.md) |
| 화면·사용자 흐름·자산 | [디자인 목차](../design/README.md) |

## 사용과 제품 개요

- [소개와 다운로드](../README.md), [English overview](../README.en.md)
- [한국어 사용자 가이드](../docs/USER-GUIDE.md), [English user guide](../docs/USER-GUIDE.en.md)
- [캘린더 사용과 지원 범위](../CALENDAR.md)
- [Windows 안내](../windows/README.md), [Windows English guide](../windows/README.en.md)
- [라이선스](../LICENSE), [외부 구성요소 고지](../THIRD_PARTY_NOTICES.md)

## 기능과 구현 계약

- [기능 명세와 결정·변경 이력](../docs/FEATURE-SPEC.md)
- [시간 표시와 근무·일반 설정 상세 명세](../SPEC.md)
- [출근 입력 컨트롤](../docs/arrival-inline-controls-spec.md)
- [패널 구성](../docs/compact-panel-spec.md)
- [수동 근무 유형](../docs/manual-leave-today-spec.md)
- [휴가 전날 예고](../docs/vacation-eve.md)
- [Mac·Windows 기능 현황](../docs/PLATFORM-STATUS.md)

## 연결과 플러그인

- [플러그인](../docs/PLUGINS.md)
- [CPU 러너](../docs/CPU-RUNNER.md)
- [AI 모델 사용량](../docs/AI-MODEL-USAGE.md)
- [ChatGPT 통합](../docs/CHATGPT-INTEGRATION.md)
- [다우오피스 쓰기 계약](../docs/DAOUOFFICE-WRITE.md)

## 디자인과 사이트

- [디자인 명세와 선택·승인·구현 이력](../docs/DESIGN-SPEC.md)
- [브랜딩](../BRANDING.md), [Liquid Glass](../docs/liquid-glass.md)
- [AI 사용량 화면 지침](../.impeccable/surfaces/ai-usage.md)
- 로컬 보존 경로 `docs/design/ollulu/2026-10-19/README.md` (현재 원격 미게시)
- [사이트 개발](../site/README.md), [사이트 상세 페이지 명세](../docs/site-detail-pages-spec.md)

## 검증과 배포

- [QA 파이프라인과 고정 Dev 앱 실행 제한](../docs/QA.md)
- [설정 탐색 검사](../docs/settings-navigation-check.md)
- [Mac·Windows 검증과 남은 작업](../docs/PLATFORM-VALIDATION.md)
- [날짜별 검증 기록](../VALIDATION.md)
- [배포 절차](../DEPLOYMENT.md), [업데이트](../UPDATES.md)
- [Mac 릴리즈 노트](../RELEASE-NOTES.md), [Windows 릴리즈 노트](../windows/RELEASE-NOTES.md)

## 보존된 설계와 작업 계획

다음 문서는 당시 계획과 결정의 근거다. 현재 기능·지원 상태는 위 기능 명세와 소유 구현을 확인한다.

- [2026-10-12 플랫폼 기능 동등성 계획](../docs/superpowers/plans/2026-10-12-platform-parity.md)
- [2026-10-16 플러그인·설정·외관 계획](../docs/superpowers/plans/2026-10-16-plugin-settings-appearance.md)
- [2026-10-16 PR 44 후속 계획](../docs/superpowers/plans/2026-10-16-pr44-followup.md)
- [2026-10-16 플러그인·설정·외관 설계](../docs/superpowers/specs/2026-10-16-plugin-settings-appearance-design.md)

새 문서를 만들거나 경로를 바꿀 때는 이 목차의 해당 항목을 함께 갱신한다. 오래된 기록은 날짜와 원래 의미를 보존하고 현재 정본으로 연결한다. 독립 clone에서 작업공간 공통 링크를 읽을 수 없더라도 위 로컬 문서로 작업 범위와 검사·보존 제한을 확인할 수 있다.

# HappyLulu 개발과 검증 규칙

이 규칙은 HappyLulu의 소스·테스트·패키징·문서 변경에 적용한다. 기존 AGENTS의 유효한 개발·보존·게시 제한을 이 문서로 연결한다.

## 기능과 디자인 변경

Before feature or UI changes, read [FEATURE-SPEC](../docs/FEATURE-SPEC.md) and [DESIGN-SPEC](../docs/DESIGN-SPEC.md). Map affected screens and states to the existing feature IDs and their acceptance criteria. Keep existing, removed, and proposed features distinct; moving a control is not removing its capability. Record an intentional removal's reason, user decision, replacement, and data impact without deleting its history. Update the relevant specification with the change and report checks against the same revision. App and site design proposals are separate decks; [design navigation](../design/README.md) links the preserved shared sources.

## 작업과 데이터 보존

- Read the current Git status and checkout identity before editing. Preserve unrelated changes and user attendance data.
- Inside workspace-chanyoung, `develop/` is the baseline directory on `main`. New manually managed feature checkouts use direct sibling `<task>/` directories and `cy-agent/` branches; preserve existing checkout and branch names. Compare their common Git directory before reuse.
- Use the smallest useful workflow. Material behavior changes require an independent review after relevant checks; simple docs need no extra agents.
- Keep attendance on the local Mac. Do not add network collection or accounts without an explicit feature request.
- Preserve the existing `AfterSix` storage path and bundle identifier unless a migration is deliberately implemented and verified.
- Do not count wake or session activation as an unlock event. Do not fabricate historical attendance when the app was not running.
- Never lock, log out, or reboot the user's Mac to run validation without explicit authorization.
- Keep `.build/`, `dist/`, app bundles, credentials, and personal state out of Git. `Resources/HappyLuluIcon.png` is the reviewed application source asset.
- Require an explicit user request for this repository and publication action before pushing, creating or updating a PR, releasing, or deploying. A request for local changes or successful checks alone does not authorize publication.
- User documentation and reports are normally Korean; keep AGENTS.md English.

## 개발 앱과 QA 정체성

User decision, 2026-10-26: keep production `happylulu` intact. Development and GUI QA may use only `happylulu-dev` with the fixed bundle ID `local.chanyoung.HappyLulu.Dev.manual-leave.20261015`. Never create or launch additional QA/Preview/Probe names or date/UUID bundle identifiers. Prefer headless tests without OS registration; inspect older scripts before running them. Synthetic tests must preserve real Dev preferences and attendance data, must not delete the fixed Dev defaults domain, and must reject concurrent Dev sessions. Use `scripts/check-ai-usage-ui.sh` for an authorized synthetic fixture after checking its identity and isolation, then verify that the menu-bar app list has no extra entries. Keep archived app backups non-runnable so they do not return as extra macOS app registrations.

[QA의 실행 제한](../docs/QA.md#자동-실행)을 먼저 확인한다. 개인 Mac에서 별도 GUI 앱을 만드는 오래된 검사와 이를 포함한 QA 실행기는 고정 정체성 전환이 확인되기 전 실행하지 않는다. 기존 검사를 삭제하거나 skip을 통과로 바꾸지 않는다.

## 검사 선택과 결과

Use the existing macOS Command Line Tools; do not install dependencies merely to run checks. Select the smallest relevant documented check from [automated contracts](../spec/README.md), [QA](../docs/QA.md) and the [macOS workflow](../.github/workflows/macos.yml). The workflow owns CI commands and prerequisites.

```sh
swift run --build-system native AfterSixChecks
bash -n scripts/build-app.sh
plutil -lint Resources/Info.plist
git diff --check
```

`bash scripts/build-app.sh` is the existing app build entrypoint. Inspect its identity, signing, output and side effects before running it; a documentation-only change does not require an app build or launch. Unit checks, build/signature validation, actual unlock detection, and login-after-reboot behavior are separate evidence. Record their limits.

## 안전한 유지보수와 완료

- Keep attention on the requested repository and demonstrated defects. Use small, testable changes; preserve the operator's data and unfinished work.
- Reproduce a defect with a failing check before fixing it. Run relevant regression checks and obtain independent review for behavior changes before claiming done.
- Inspect branch ancestry, dirty/ignored files, and active work before integration. Preserve unique commits and unfinished checkouts. Clean up only confirmed merged, clean, inactive task branches within explicit cleanup authorization.
- Report executed checks, review findings, commit/merge evidence, and remaining blockers. Completion requires verified results. Deployment needs its own request.

## 채팅과 접근 실패

Read the latest request, [AGENTS](../AGENTS.md), applicable nested guides and local rules before work. Space's [start guide](https://chatgpt.com/space/page_fc9829154fa08191afb97a2aacfe93c4) and [home](https://chatgpt.com/space/page_6abd33d7db1c819189336911027de558) route chat records; they do not replace this repository's rules or current technical documents.

Keep one chat index and separate topic records when the goal or deliverable changes. Reuse a topic for follow-up questions and corrections. Preserve ongoing goals, decisions, evidence and links when archiving older detail. If a Page is unavailable, record missing context in the permitted local task TODO, continue independent authorized local work, and leave evidence-dependent actions pending. Do not place credentials, personal attendance records or large logs in shared records.

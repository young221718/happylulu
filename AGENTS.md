# HappyLulu Agent Guide

## Scope and start

HappyLulu is a native Swift macOS menu bar utility. This Git repository owns its
source, tests, packaging and product documentation. Check the latest request,
actual checkout identity, branch and dirty state before editing.

Read [working rules](rules/README.md) and the applicable
[development and preservation rules](rules/development.md) before work.
Use [the repository Wiki](wiki/README.md) to find local knowledge and every document.
Read only the documents and ancestor guides relevant to the target path.

## Route by task

| Task | Read before changing |
| --- | --- |
| Feature or behavior | [Automated contracts](spec/README.md), [feature specification](docs/FEATURE-SPEC.md), then affected source/tests |
| UI, interaction or assets | [Design index](design/README.md), feature specification and existing acceptance criteria |
| Rules, docs or paths | [Working rules](rules/README.md), Wiki index and affected document owners |
| Validation and reporting | [Development checks](rules/development.md#검사-선택과-결과), [QA](docs/QA.md) and the [macOS workflow](.github/workflows/macos.yml) |
| Build, update or publication | [Publication restrictions](rules/development.md#작업과-데이터-보존), [QA identity](rules/development.md#개발-앱과-qa-정체성), [deployment](DEPLOYMENT.md) |
| Platform scope | [Mac/Windows status](docs/PLATFORM-STATUS.md), [validation limits](docs/PLATFORM-VALIDATION.md) |

## Critical local entrypoints

Preserve production `happylulu`, attendance data and existing dirty work.
Development/GUI QA may use only `happylulu-dev` with fixed bundle ID
`local.chanyoung.HappyLulu.Dev.manual-leave.20261015`; read the full
[identity and data restrictions](rules/development.md#개발-앱과-qa-정체성) before running scripts.
Do not run older GUI QA paths until their fixed-identity compliance is confirmed.
Local checks do not authorize a push, PR, release, installation or deployment.

## Common and nested guidance

In workspace-chanyoung, [common rules](../../../rules/README.md) apply to their
stated scope and [the root Wiki](../../../wiki/index.md) owns shared knowledge.
These workspace-relative paths may be absent in a standalone clone; the local
rules, spec, Wiki and design entrypoints above remain the execution contract.
Record missing common context without expanding the authorized scope.

Nested guides add only local differences; preserve applicable parent restrictions.
Independent Git roots must provide their own routes and must not assume automatic
loading of workspace-root instructions. See [recursive rules](rules/README.md#공통-규칙과-재귀-적용).
Keep AGENTS.md as navigation: 150 lines recommended, 200 lines maximum, no separate
byte cap. Put detailed rules, contracts and historical records in their owners.

## Chat records

Use the [Space start guide](https://chatgpt.com/space/page_fc9829154fa08191afb97a2aacfe93c4)
for one chat index and goal-based topic records under
[chat history](https://chatgpt.com/space/page_f2c1bdce022c8191b165e1a55e4edb07).
Space tracks work; repository rules and technical documents remain local owners.
If access fails, record the missing context in the permitted local task TODO,
continue independent authorized work and leave evidence-dependent actions pending.
Preserve ongoing goals, existing records and links; keep private data out of shared notes.

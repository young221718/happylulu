# HappyLulu user guide

[Overview](../README.en.md) · [Downloads](../README.en.md#downloads) · [한국어](USER-GUIDE.md)

Installation, workday calculations, settings, calendars, records and updates for **main `58fe8df`, 2026-10-23**. Repository download metadata lists **Mac 1.5.19 build35 and Windows 1.5.13**. System Runner, AI Usage, subsequent overtime refresh changes and Liquid Glass are merged follow-up features; this does not place them in public Mac 1.5.19 build35. Release notes define each published version. This documentation update does not verify download HTTP responses or publish a release.

[Getting started](#three-small-steps) · [Workday calculations](#how-a-day-is-calculated) · [Calendars](#calendars-when-you-need-them) · [Records and updates](#records-and-updates) · [Development and evidence](#development-and-evidence)

## A small app for a lighter day

- **Today, within reach.** Check your arrival and departure countdown. Enter an arrival manually if you have already started.
- **Your routine.** Set work and break hours, half days, five countdown formats, and Korean or English.
- **Two hours earlier on the last Friday.** Regular workdays get the monthly reduction automatically.
- **Your records, on your computer.** Attendance works without an account. Connect calendars on Mac when you need them.

HappyLulu is a personal convenience tool, not the company's official attendance or payroll system.

## Available downloads

| Edition | Version | Status |
| --- | --- | --- |
| [Public Mac download](https://github.com/young221718/happylulu-app/releases/tag/macos-v1.5.19-build35) | **1.5.19 · build35** | macOS 13+ · Universal DMG/ZIP · manual installation |
| [Public Windows download](https://github.com/young221718/happylulu-app/releases/tag/windows-v1.5.13) | **1.5.13** | Windows 10/11 x64 · .NET 10 Desktop Runtime required |

The guide below describes **the current Mac implementation on main**; publication of follow-up features is separate. Check the [Mac](../RELEASE-NOTES.md) and [Windows](../windows/RELEASE-NOTES.md) notes for features in each public version. Mac and Windows attendance records do not sync with each other.

## Three small steps

1. **Download and give it a home.** On Mac, move the app from the DMG or ZIP to Applications or ~/Applications. On Windows, install the Desktop Runtime and extract the entire ZIP to a permanent folder. Quit the old app before replacing it in the same location.
2. **Click happylulu.** Open the menu bar or tray panel. Enter your arrival and workday mode if you have already arrived.
3. **Make it yours.** Choose work and break hours, language and countdown format. Calendar setup is optional.

Mac first launch attempts login-item registration and may require system approval. A disabled preference stays disabled. Windows startup is enabled explicitly in settings. Follow the installation steps above and the [Windows README](../windows/README.en.md).

## Today in the menu bar. Settings in one place.

Mac puts settings in one window with a sidebar, including Calendar.

| View | Controls |
| --- | --- |
| Menu bar panel | Arrival, expected departure, workday choices, inline edits, today’s events, enabled usage/system summaries, and the `…` Settings/Quit menu |
| General | Language, time format, menu bar departure visibility, Show usage and login startup; label, preview and right-hand control columns |
| Appearance | Six color themes, Native Liquid Glass on supported systems, custom colors, five icons and image import |
| Work | Work and break hours, manual arrival and day off |
| Attendance | Monthly arrival calendar, date details and record folder |
| Plugin management | Install/enable bundled optional modules and view developers |
| Installed plugins | Calendar sync, Daouoffice, half-day recognition, System Runner and AI Usage when included in the build |
| Updates | Version and automatic check/install preferences |

In General settings, choose milliseconds, seconds, minutes, hours or hours/minutes for the remaining-time display in the menu bar and Work settings. Hours round up to one decimal: **90 minutes → 1.5 hours**, **30 minutes → 0.5 hours**. By default, the menu bar shows the expected departure time alongside the countdown (for example, `Leave 18:00 · 1.5 hr left`). With departure visibility on, only the expected departure time remains for the first 30 minutes after departure. Then it also shows elapsed time in the selected unit (for example, `Leave 18:00 · Extra 1 hr 1 min`). Elapsed time rounds down to completed units. Preferences survive a restart.

On Mac, **Show expected departure in menu bar** is on by default. Turn it off to hide the clock while keeping the countdown in your selected format (for example, `1.5 hr left`). Changes apply immediately and survive a restart. Once the expected departure time is reached with the option off, the menu bar shows `Ready to leave` for 30 minutes, then shows the elapsed time without the departure clock. The today panel's departure time and attendance records stay unchanged.

## Optional features merged into main

- **System Runner:** Settings → Plugin management → System Runner → Install, then enable it. Open its settings from Installed plugins. The default Owl orbit keeps the eye shapes fixed while light rotates around their outlines with CPU activity. Choose start/end colors or restore defaults. Animal mode offers a hamster, rabbit or cat. The panel and settings show CPU, memory, startup disk, physical-network transfer rates and battery; CPU alone controls animation speed. Reduce Motion stops movement. [Details (Korean)](CPU-RUNNER.md)
- **AI Usage:** Enable General → Show usage, or install and enable AI Usage in Plugin management. Open it from Installed plugins, Usage settings in General, or the panel usage row. Choose Codex text + %, icon + %, or % only. Defaults are text + %, a five-minute refresh, and notifications off. It reuses the Codex CLI ChatGPT sign-in; API-key accounts do not provide a weekly allowance. Signing in with another account also changes the CLI account. [Connection and display details (Korean)](AI-MODEL-USAGE.md)
- **Appearance and menus:** Supported builds on macOS 26+ apply glass materials, an arrowless panel and unified titlebar to existing themes. Native Liquid Glass separately follows system colors and appearance. Older macOS retains the previous UI; Reduce Transparency and Increase Contrast use opaque surfaces. The panel `…` menu contains Settings and Quit; the settings sidebar ends with a User guide link. [Material details (Korean)](liquid-glass.md)
- **Leave tomorrow:** A fresh source reading that confirms approved full-day leave tomorrow can add a hat/sunglasses decoration ten minutes before today’s scheduled departure. Readings must be at most fifteen minutes old. Half days and ambiguous dates are excluded. This never submits a leave request.

These optional Mac modules start disabled after installation. Show usage also installs and enables the available AI module when needed. Disabling a module preserves attendance, preferences and calendar/leave routing. Windows 1.5.13 does not include these modules.

## How a day is calculated

The default is eight work hours plus one break hour. Arrival windows include their final minute.

Automatic detection starts at **06:00 local time**. Regular or afternoon-off observations from 06:00 through 07:59:59 are recorded at **08:00 on the same day** (06:30 observed → 08:00 recorded → default departure 17:00). Earlier events are ignored; morning off retains 13:00–15:00. The table below describes manual input and recorded times; manual entries are not normalized.

| Mode | Arrival window | Default example |
| --- | --- | --- |
| Regular | 08:00–10:00 | 09:00 → 18:00 |
| Afternoon off | 08:00–10:00 | 09:00 → 13:00 |
| Morning off | 13:00–15:00 | 13:00 → 17:00 |

Regular days finish two hours earlier on the last calendar Friday of the month. Half days use four hours without a break or an extra Friday reduction. Holidays do not move this rule to another date.

Mac records the first valid **observed** login-item launch or screen unlock. Later unlocks preserve arrival, manual edits and day-off choices. Ordinary manual launch, wake and session activation do not create arrivals. The app does not reconstruct hours when it was closed or detect office location/Wi-Fi; an unlock at home may count.

Day off clears today's arrival after confirmation and suspends automatic recording. Saving a manual arrival resumes it. Elapsed time appears 30 minutes after scheduled departure in the menu bar, main panel, Work settings and tooltip. It follows the selected time unit; milliseconds refresh every 0.1 seconds. The meal time threshold remains two hours. These do not verify work or approve payment.

## Workday choices since Mac 1.5.15

**Mac 1.5.15 build31 introduced** a compact panel and four-digit HH:mm arrival editing. Type digits or use the +/− controls above and below each digit; clicking elsewhere or closing the panel saves the time. Editing only the time preserves automatic calendar recognition or an existing manual choice. Today’s regular, morning-off, afternoon-off, Lulu and leave choices work without a calendar connection and do not create an arrival by themselves. Invalid times, future times, stale dates and incompatible modes are rejected.

Lulu reduces the day by 120 minutes; explicitly choosing regular work overrides the reduction to zero, including on the last Friday. Leave pauses automatic recording and the countdown while retaining the arrival. The separate Day off action can still delete that retained record after confirmation. Windows remains at 1.5.13 without these new panel, Lulu, leave or explicit zero-reduction behaviors.

## Calendars, when you need them

On Mac, install and enable Calendar in **Settings → Plugin management**, then open **Calendar** in the sidebar. macOS Internet Accounts manages account login and credentials. Two-way sync requires **full calendar access**.

1. Connect your own Google and DaouOffice accounts in macOS.
2. Select test calendars from different accounts.
3. Review planned changes, holds and conflicts before starting.

Mac preserves ordinary display reminders. Recurring events are copied as individual occurrences within **30 days before through 365 days after today**. Invitations become personal copies without re-inviting attendees, and the original stays protected. Automatic deletion, out-of-range occurrences and special alarms remain held with a reason.

Resume a paused connection after a fresh preview. A successful local macOS calendar save is separate from confirmation on both web servers. [Calendar setup, supported fields and recovery (Korean)](../CALENDAR.md).

Optional half-day recognition reads accessible calendar titles. Shared events may be mistaken for yours; choose a manual mode or disable recognition. Manual selection takes priority.

## Records and updates

Since Mac 1.5.15 build31, releases use the publication path that backs up the existing production app and profile, then verifies replacement, relaunch and permission/record/connection preservation. Deployment receipts distinguish actual installation results from source and CI checks.

Mac attendance stays in `~/Library/Application Support/AfterSix/state.json`. The app identifier and existing storage path are retained. Never delete records to update the app. Calendar connection state is local; macOS manages credentials. No attendance telemetry, keyboard or screen collection is added.

Automatic checking, downloading, idle installation and fixed self-signing are available. The previous 1.5.11 build27 local replacement preserved records, connections and calendar permission, and its public files and signed feed matched the validated package. Version-specific installation and permission results are recorded separately in deployment validation. This does not verify automatic migration from the old Site feed or installation on every Mac. Older versions with updates disabled need one manual replacement with an enabled version. See [updates](../UPDATES.md) and [issue #3](https://github.com/young221718/happylulu-app/issues/3).

Apple Developer ID/notarization and Windows publisher signing are incomplete. Universal builds include Intel code, but Intel physical testing is pending. Follow managed-device policy. Older versions may preserve but stop writing records containing an unsupported login source; do not remove the records to downgrade.

## Development and evidence

Use Swift 6 and macOS Command Line Tools. Windows has its own [.NET build guide](../windows/README.en.md).

```sh
swift run --build-system native AfterSixChecks
swift run --build-system native CalendarSyncChecks
swift run --build-system native CalendarSyncServiceChecks
bash scripts/build-app.sh
```

Mac PR CI uses the [QA runner and reports (Korean)](QA.md) for core and isolated integration checks, followed by ad-hoc app packaging and Sparkle configuration without private signing keys. Partial automated coverage, actual clicks/paste, permissions and live services remain separate evidence. See [UPDATES.md](../UPDATES.md) for local fixed signing, signed installation tests and Universal release checks.

Automated checks, app builds, actual device behavior and web-server readback are separate evidence. Track [validation](../VALIDATION.md), [Mac device checks #4](https://github.com/young221718/happylulu-app/issues/4) and [login startup #13](https://github.com/young221718/happylulu-app/issues/13).

Changes follow **issue → task branch → checks and independent review → PR → merge → signing/deployment → readback**. Keep personal records, keys, credentials and generated apps out of Git.

## Releases and website

GitHub owns source, CI, release assets, checksums and the signed update feed. The [website](https://happylulu.cy-choi-lulu.chatgpt.site/) focuses on the product, an interactive demo and download links. See [DEPLOYMENT.md](../DEPLOYMENT.md) for preparation, verification, draft releases, promotion and readback. Website source lives in [site/](../site/README.md). Private signing keys stay in the maintainer’s local keychain; CI does not publish an unverified signed update. The GitHub feed migration requires a one-time installation for existing apps using the old Site feed.

## License

[HappyLulu Noncommercial Source-Sharing License 1.0](../LICENSE): commercial use is prohibited without separate written permission. Modifying or reusing the code requires publishing the complete corresponding source of the resulting work under the same license before first use, including private use and network services. Individuals may run the unmodified official app to track their own working hours, including at work. Personal data and signing keys are never subject to source publication. This is **source-available, not OSI open source**. [Third-party notices](../THIRD_PARTY_NOTICES.md) remain under their original licenses.

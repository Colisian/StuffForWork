# Phase 2 — Can a patron get out of Edge?

> [!warning] This decides whether the session-broker approach is viable.
> Phase 2 is usually framed as "does Edge run correctly as `libguestN`". That is the
> easy half. The half that decides the project is whether a patron sitting at the
> keyboard can leave the browser and reach the filesystem, another application, or
> the broker account's own data.
>
> If Edge cannot be contained, no amount of broker code fixes it, and the
> credential-provider approach becomes the right answer instead.

## Why the broker cannot solve this

The broker launches Edge and supervises its process tree. It has no visibility into
what happens *inside* Edge. Every escape below is Edge handing control to another
component — a file dialog, a protocol handler, a downloaded binary — and the broker
learns nothing about it.

Containment therefore comes from three layers, in increasing order of reliability:

| Layer | Mechanism | Weakness |
|---|---|---|
| Edge policy | `Set-EdgeContainmentPolicy.ps1`, then Intune Settings Catalog | Only blocks what you thought to block |
| No shell | Shell Launcher — `explorer.exe` never starts | `explorer.exe` still exists and can be launched |
| **Execution control** | **WDAC / App Control allowlist** | **The backstop that does not depend on enumeration** |

Treat Edge policy as surface reduction, not as the boundary. **You will not enumerate
every escape correctly.** WDAC is what makes the result actually contained, and the
parent README already requires it.

## Setup

Run as an administrator on the test device:

```powershell
cd <repo>\Intune\LibGuestCreation\EntraOnlyApproaches\SessionBroker\Containment
.\Set-EdgeContainmentPolicy.ps1
```

Then point the broker at Edge. In `Prototype\broker-settings.json`:

```json
"DefaultApplicationId": "Edge"
```

Sign in as a Guest, authenticate at the broker with a live `libguestN` credential,
and work the checklist below **as the patron would** — using only the mouse and
keyboard in front of you.

> [!important] Confirm the policy is actually in force first.
> In the patron's Edge session, browse to `edge://policy`. Every value from the
> script must appear with status **OK**. A policy name Edge does not recognise is
> ignored silently, which fails open — the script cannot detect this for you.

## A. Filesystem reach from inside Edge

| # | Attempt | Expected after containment | Result |
|---|---|---|---|
| A1 | `Ctrl+O` | No dialog appears | |
| A2 | `Ctrl+S` | No dialog appears | |
| A3 | Type `file:///C:/` in the address bar | Blocked by policy page | |
| A4 | Type `file:///C:/Users/` | Blocked; must not list other profiles | |
| A5 | Type `file:///C:/Windows/System32/` | Blocked | |
| A6 | Right-click an image → **Save image as** | No dialog | |
| A7 | Visit any page with a file-upload control and click it | No dialog | |
| A8 | Drag a file from another window onto Edge | Nothing opens (no other window should exist) | |
| A9 | `Ctrl+P` → inspect destination list | No **Save as PDF**; Pharos printers present | |
| A10 | `Ctrl+P` → **Print using system dialog** → printer **Properties** | No path browsing reachable | |

> [!note] A9 and A10 are the ones most likely to fail.
> Printing must keep working for a library, so the print path stays open by
> necessity. System print dialogs and driver property sheets have historically
> exposed file browsing. Spend real time here.

## B. Launching another application

| # | Attempt | Expected after containment | Result |
|---|---|---|---|
| B1 | Download any `.exe` | Download blocked entirely | |
| B2 | If a download succeeds: **Open** from the downloads bar | Must not execute | |
| B3 | If a download succeeds: **Show in folder** | Must not open Explorer | |
| B4 | `ms-settings:` in the address bar | Blocked | |
| B5 | `shell:startup` in the address bar | Blocked | |
| B6 | `search-ms:` in the address bar | Blocked | |
| B7 | A `mailto:` link | No external handler launches | |
| B8 | Site offering "Open in app" / custom protocol | No handler launches | |
| B9 | Edge menu → **More tools** → **Open in Internet Explorer mode** | Unavailable | |

## C. Edge's own surface

| # | Attempt | Expected after containment | Result |
|---|---|---|---|
| C1 | `F12` and `Ctrl+Shift+I` | Devtools unavailable | |
| C2 | `Ctrl+U` (view source) | Blocked | |
| C3 | `edge://settings` | Blocked | |
| C4 | `edge://extensions` | Blocked | |
| C5 | `edge://flags` | Blocked | |
| C6 | `Shift+Esc` (browser task manager) | Reachable, but must not end broker processes | |
| C7 | Sign in to Edge with a personal Microsoft account | Blocked | |
| C8 | `Ctrl+N`, `Ctrl+Shift+N` | New windows still inside the job object | |

## D. Escaping to the OS

These are not Edge problems — they are the reason Shell Launcher alone is not enough.
Record what happens even if it is out of scope for this pass.

| # | Attempt | Expected in the final design | Result |
|---|---|---|---|
| D1 | `Alt+Tab` | Nothing but Edge and the broker | |
| D2 | Windows key | No Start menu (no shell) | |
| D3 | `Win+E` | No Explorer window | |
| D4 | `Win+R` | No Run dialog | |
| D5 | `Ctrl+Shift+Esc` | Task Manager blocked by policy | |
| D6 | `Ctrl+Alt+Del` | Security screen appears; Task Manager and password change disabled | |
| D7 | `Win+U` / ease-of-access | No accessibility escape | |
| D8 | Close Edge | Broker dialog returns; desktop never visible | |

## E. Data left for the next patron

| # | Attempt | Expected | Result |
|---|---|---|---|
| E1 | Confirm the session is InPrivate | Forced by policy | |
| E2 | Sign in to a webmail account, end the session, start a new one, revisit | Not signed in | |
| E3 | Check `C:\Users\` for a `libguestN` profile after sign-out | Profile removed or cleared | |
| E4 | Check the Pharos print queue for the previous patron's jobs | Cleared | |

> [!warning] E3 is a known gap.
> `LOGON_WITH_PROFILE` creates and loads a real profile for each `libguestN`
> account, and nothing in the broker removes it yet. Profiles accumulate across
> patrons and contain browsing artifacts. This is a stated go/no-go criterion in the
> parent README and remains unimplemented.

## F. Process supervision under a real browser

Single-child cleanup was proven with `notepad.exe` on 2026-07-26. A browser is a
different problem: Chromium spawns a process tree, and some launchers deliberately
break away from job objects.

| # | Attempt | Expected | Result |
|---|---|---|---|
| F1 | With Edge running, count `msedge.exe` in Task Manager | Several | |
| F2 | Confirm each runs as `libguestN` | All of them | |
| F3 | Kill the broker process | Every `msedge.exe` dies with it | |
| F4 | Close Edge normally | Broker dialog returns within ~2s | |
| F5 | Let a session hit `SessionTimeoutMinutes` | Session ends, dialog returns | |

If F3 leaves survivors, the job object needs `JOB_OBJECT_LIMIT_BREAKAWAY_OK`
handling. That is fixable in `LibGuestBrokerNative.cs`, but it must be found now
rather than during Phase 3.

## Decision

Stop and reconsider the credential-provider approach if, after policy is confirmed
in force via `edge://policy`:

- any test in **A** or **B** reaches the filesystem or launches another program;
- **F3** leaves orphaned processes that cannot be cleaned up;
- printing cannot be kept working without also opening a file dialog.

Proceed to Phase 3 (Shell Launcher, dedicated broker account, session cleanup) if
A and B hold and F3 is clean.

## Findings

_Record results here as tests are run._

| Date | Tester | Tests run | Outcome |
|---|---|---|---|
| | | | |

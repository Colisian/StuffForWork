# CleanUsers.sh — Documentation

## Overview

**Purpose:** Bulk-deletes non-admin local user profiles on public macOS devices to recover disk space.

**Deployment:** Jamf Pro — scoped policy or Self Service.

**Version:** 1.1
**Author:** Oji
**Last Updated:** 2026-02-23

---

## How It Works

1. The script starts logging all output to `/var/log/bulk_profile_wipe.log`
2. Checks if anyone is currently logged into the Mac and protects their profile
3. Iterates through every folder in `/Users/`
4. For each user, it checks whether they should be skipped (excluded list, system account, or UID < 500)
5. For eligible users, it calculates the profile size and then deletes the account using `sysadminctl`
6. Prints a summary with counts and total storage freed

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DRY_RUN` | `false` | Set to `true` to preview which profiles would be deleted without actually removing them |
| `EXCLUDE_USERS` | `cmcleod1`, `jssadmin`, `libradmin`, `_mbsetupuser`, `Shared` | Admin and service accounts that should never be deleted |

---

## Functions

### `main()`

The primary entry point. Calls the other functions, then loops through `/Users/*` to process each profile. For each user it:

- Skips hidden folders (names starting with `.`)
- Skips users in the `EXCLUDE_USERS` list
- Skips system accounts with UID below 500
- Calculates profile size using `du -sk` (kilobytes)
- In DRY_RUN mode: logs what **would** be deleted
- In live mode: calls `sysadminctl -deleteUser -secure` and tracks success/failure

### `active_session_guard()`

Checks who currently owns `/dev/console` (the active GUI session). If a real user is logged in — even if the screen is locked — their username is added to `EXCLUDE_USERS` so their profile is never deleted while they have an active session.

Uses: `stat -f "%Su" /dev/console`

### `print_header()`

Outputs the run mode (DRY RUN or LIVE DELETION) and timestamp at the start of execution.

### `print_summary()`

Outputs final counts after the loop completes:

- Profiles deleted
- Profiles skipped (system accounts)
- Profiles failed (deletion errors)
- Total storage freed (only in live mode, converted from KB to GB)

---

## Shell Safety Options

### `set -u`

Causes the script to exit immediately if any **undefined variable** is referenced. This prevents silent bugs where a typo like `$USERNAM` (missing the `E`) would expand to an empty string instead of raising an error.

**Example without `set -u`:**
```bash
echo "Deleting $USERNAM"   # Typo — silently expands to empty string
# Output: "Deleting "       # No error, could cause unintended behavior
```

**With `set -u`:**
```bash
echo "Deleting $USERNAM"   # Typo — script exits with an error
# Output: "bash: USERNAM: unbound variable"
```

### `set -o pipefail`

By default, a pipeline (commands chained with `|`) only reports the exit code of the **last** command. With `pipefail`, the pipeline returns the exit code of the **first** command that fails.

**Example without `pipefail`:**
```bash
failing_command | awk '{print $1}'
# Exit code: 0 (awk succeeded, failure is hidden)
```

**With `pipefail`:**
```bash
failing_command | awk '{print $1}'
# Exit code: 1 (the failure from the first command is preserved)
```

This matters in the script because `du` output is piped through `awk` — if `du` fails, we want to know about it rather than silently getting an empty value.

### Why `set -e` Is Not Used

`set -e` would exit the script on **any** command failure. In this script, a single user failing to delete should not stop processing the remaining users. Instead, errors are handled per-user with an `if/else` block around `sysadminctl`, and failures are counted separately.

### `|| true` on Arithmetic

Bash arithmetic like `((count++))` returns exit code 1 when the value is 0 (because 0 is "false" in arithmetic context). Combined with `set -u` and the ERR trap, this would kill the script on the first increment. Appending `|| true` suppresses that false-positive failure.

---

## Log Output

All output is written to both stdout (for Jamf policy logs) and `/var/log/bulk_profile_wipe.log` on the Mac. Sample output:

```
===== Bulk Profile Wipe =====
Mode: LIVE DELETION
Started: Sun Feb 23 10:00:00 EST 2026

WARNING — student1 is currently logged in (console). Their profile will be skipped.
SKIP  _mbsetupuser (system account, UID: 248)
DELETING  patron42 — Profile size: 1.2G
DELETING  guest03 — Profile size: 340M
FAILED  Could not delete brokenuser

===== Summary =====
Profiles deleted   : 2
Profiles skipped   : 1
Profiles failed    : 1
Storage freed      : 1.53 GB
Completed: Sun Feb 23 10:00:15 EST 2026
```

---

## Verification

After running, confirm the results:

```bash
# Check remaining user profiles
ls -la /Users/

# Review the log
cat /var/log/bulk_profile_wipe.log

# Verify disk space recovered
diskutil info / | grep "Free Space"
```

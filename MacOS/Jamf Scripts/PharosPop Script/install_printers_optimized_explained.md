# Beginner Guide to `install_printers_optimized.sh`

This document explains how the optimized printer installation script works. It is written for someone who is still learning Bash, so it focuses on the shell patterns and methods used in the script, not just what the printer install does.

The script being explained is:

```text
install_printers_optimized.sh
```

Its main job is to:

1. Confirm the script is running as root.
2. Log all output to `/var/log/umd_printer_install.log`.
3. Run Canon driver cleanup tasks.
4. Verify the Pharos Popup backend exists.
5. Verify the Canon PPD printer driver exists.
6. Restart CUPS once after driver/backend setup.
7. Remove existing UMD Library printer queues.
8. Install all UMD Library printer queues.
9. Verify and summarize the result.

## The Shebang

```bash
#!/bin/bash
```

The first line is called a shebang. It tells macOS which program should run this file.

In this case, the script is run by Bash:

```text
/bin/bash
```

This matters because Bash supports features used later in the script, including arrays, functions, and process substitution.

## Variables

The script stores values in variables so they can be reused.

```bash
LOG_FILE="/var/log/umd_printer_install.log"
TARGET_VOLUME="${3:-}"
DISPLAY_TARGET_VOLUME="${TARGET_VOLUME:-/}"
```

`LOG_FILE` stores the log path.

`TARGET_VOLUME` stores the third argument passed to the script. In Jamf scripts, `$3` is commonly used as the target volume.

`DISPLAY_TARGET_VOLUME` uses a fallback value. This syntax:

```bash
${TARGET_VOLUME:-/}
```

means:

```text
If TARGET_VOLUME is empty or unset, use / instead.
```

That lets the script print `/` as the target volume when no third argument was provided.

## Root Check

```bash
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi
```

`$EUID` is the effective user ID.

On macOS and Linux:

```text
0 means root
```

The test:

```bash
[ "$EUID" -ne 0 ]
```

means:

```text
If EUID is not equal to 0
```

If the script is not running as root, it prints an error and exits.

`exit 1` means the script failed. A successful script usually exits with `0`.

## Redirecting Output to a Log File

```bash
exec &> >(tee -a "$LOG_FILE")
```

This is one of the more advanced Bash lines in the script.

It redirects both normal output and error output through `tee`.

`tee -a "$LOG_FILE"` does two things:

1. Prints output on screen.
2. Appends the same output to the log file.

The `-a` flag means append. Without `-a`, `tee` would overwrite the log file.

The `&>` part means:

```text
Redirect standard output and standard error
```

Standard output is normal text. Standard error is error text.

The `>(...)` part is called process substitution. Bash runs the command inside the parentheses and gives the script a special output path connected to that command.

In beginner terms, this line means:

```text
From this point forward, everything the script prints should go both to the screen and to the log file.
```

## Pipefail

```bash
set -o pipefail
```

This changes how Bash handles commands connected with pipes.

A pipe sends output from one command into another:

```bash
lpstat -p | awk '{print $2}'
```

Normally, Bash mostly cares whether the last command in the pipe succeeded.

With `pipefail`, the pipeline fails if any important command in the pipeline fails. This makes errors easier to catch.

## Command Substitution

The script often captures command output into variables.

```bash
current_os_version="$(sw_vers -productVersion)"
```

The `$(...)` syntax runs a command and substitutes its output.

This line means:

```text
Run sw_vers -productVersion and store the result in current_os_version.
```

For example, on a Mac this command might return:

```text
15.5
```

Command substitution is used throughout the script for things like OS version, PPD size, and discovered file paths.

## Functions

Bash functions let the script reuse logic.

Example:

```bash
wait_for_cups() {
    local max_wait="${1:-30}"
    local waited=0

    until lpstat -r >/dev/null 2>&1; do
        if [ "$waited" -ge "$max_wait" ]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done

    return 0
}
```

This function waits until CUPS is ready.

Functions reduce repeated code. Instead of writing the same polling loop multiple times, the script calls:

```bash
wait_for_cups 30
```

### Function Arguments

Inside a function:

```bash
$1
```

means the first argument passed to that function.

This line:

```bash
local max_wait="${1:-30}"
```

means:

```text
Use the first argument as max_wait. If no argument was provided, use 30.
```

So these calls behave differently:

```bash
wait_for_cups
wait_for_cups 10
```

The first waits up to 30 seconds. The second waits up to 10 seconds.

### Local Variables

Inside functions, the script often uses `local`:

```bash
local waited=0
```

`local` means the variable only exists inside that function.

This prevents one function from accidentally changing a variable used somewhere else.

## Return Codes

Functions return success or failure using numbers.

```bash
return 0
```

means success.

```bash
return 1
```

means failure.

This matches normal shell behavior:

```text
0 = success
non-zero = failure
```

The script checks return codes with `if`:

```bash
if wait_for_cups 30; then
    echo "   CUPS scheduler is running"
    return 0
fi
```

This means:

```text
If wait_for_cups succeeds, print that CUPS is running.
```

## Polling Instead of Fixed Sleep

One of the main performance improvements is polling.

A fixed sleep looks like this:

```bash
sleep 5
```

That always waits 5 seconds, even if the system was ready after 1 second.

The optimized script uses loops like this:

```bash
until lpstat -r >/dev/null 2>&1; do
    if [ "$waited" -ge "$max_wait" ]; then
        return 1
    fi
    sleep 1
    waited=$((waited + 1))
done
```

This means:

```text
Check whether CUPS is ready.
If it is not ready, wait 1 second and check again.
Stop early as soon as it is ready.
Give up after max_wait seconds.
```

This is usually faster than fixed sleeps because the script continues as soon as the system is ready.

## Redirecting Output to `/dev/null`

The script uses this pattern often:

```bash
lpstat -r >/dev/null 2>&1
```

`>/dev/null` discards normal output.

`2>&1` sends error output to the same place as normal output.

Together, this means:

```text
Run the command quietly. Do not print anything.
```

The script only cares whether the command succeeded or failed.

## Arithmetic

The script increments counters with Bash arithmetic:

```bash
waited=$((waited + 1))
```

The `$((...))` syntax performs math.

Other examples:

```bash
SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
FAIL_COUNT=$((FAIL_COUNT + 1))
```

This is how the script tracks successful and failed printer installations.

## Comparing Numbers

The script compares numbers with test operators.

```bash
if [ "$waited" -ge "$max_wait" ]; then
```

`-ge` means greater than or equal to.

Common numeric test operators:

```text
-eq  equal
-ne  not equal
-lt  less than
-le  less than or equal
-gt  greater than
-ge  greater than or equal
```

Example:

```bash
if [ "$FAIL_COUNT" -eq 0 ]; then
```

means:

```text
If FAIL_COUNT equals 0
```

## Comparing Strings

The script compares strings like this:

```bash
if [ "$printer_location" != "$CURRENT_GROUP" ]; then
```

`!=` means not equal.

String comparisons are used when grouping printers by location.

## Arrays

The optimized script uses arrays to store multiple values.

Example:

```bash
FAILED_PRINTERS=()
```

This creates an empty array.

The script adds an item like this:

```bash
FAILED_PRINTERS+=("$name")
```

It counts array items like this:

```bash
${#FAILED_PRINTERS[@]}
```

The `[@]` means all elements in the array.

## Data-Driven Printer List

The printer queues are stored in one array:

```bash
PRINTERS=(
    "LIB-ArchMobileBW|Architecture Library|Black & White"
    "LIB-ArchMobileColor|Architecture Library|Color"
    "LIB-ArtMobileBW|Art Library|Black & White"
)
```

Each line stores three pieces of information:

```text
printer name | printer location | printer type
```

The vertical bar character `|` is used as a separator.

This is easier to maintain than writing a separate `install_printer` line for every printer.

To add a printer, you add one new line to the array.

## Reading Split Values with `IFS`

The script splits each printer definition like this:

```bash
IFS='|' read -r printer_name printer_location printer_type <<< "$printer_def"
```

`IFS` means Internal Field Separator.

By setting:

```bash
IFS='|'
```

Bash splits the text wherever it sees `|`.

So this:

```text
LIB-ArchMobileBW|Architecture Library|Black & White
```

becomes:

```text
printer_name=LIB-ArchMobileBW
printer_location=Architecture Library
printer_type=Black & White
```

The `<<<` syntax is called a here-string. It sends the value of `$printer_def` into the `read` command.

The `-r` option tells `read` not to treat backslashes as special escape characters.

## For Loops

The script loops through arrays like this:

```bash
for printer_def in "${PRINTERS[@]}"; do
    IFS='|' read -r printer_name printer_location printer_type <<< "$printer_def"
    install_printer "$printer_name" "$printer_location" "$printer_type"
done
```

This means:

```text
For every item in the PRINTERS array, split the item into fields, then install that printer.
```

Quoting `"${PRINTERS[@]}"` is important. It preserves each array item as its own value, even when the value contains spaces.

## While Loops

The script reads command output into arrays with `while` loops:

```bash
while IFS= read -r printer; do
    if [ -n "$printer" ]; then
        EXISTING_PRINTERS+=("$printer")
    fi
done < <(get_library_printers)
```

This means:

```text
Run get_library_printers.
Read each line of output.
If the line is not empty, add it to EXISTING_PRINTERS.
```

The test:

```bash
[ -n "$printer" ]
```

means:

```text
The string is not empty.
```

The final part:

```bash
done < <(get_library_printers)
```

uses process substitution. It sends the output of `get_library_printers` into the loop.

## Why Use `awk`

The script defines:

```bash
get_library_printers() {
    lpstat -p 2>/dev/null | awk '$2 ~ /LIB-/ {print $2}'
}
```

`lpstat -p` lists printers.

Its output often looks like:

```text
printer LIB-ArchMobileBW is idle. enabled since ...
```

In that line, the second field is the printer name.

This `awk` expression:

```bash
$2 ~ /LIB-/ {print $2}
```

means:

```text
If the second field contains LIB-, print the second field.
```

So the function returns only UMD Library printer names.

## Quoting Variables

The script almost always quotes variables:

```bash
"$name"
"$CANON_PPD"
"$POPUP_BACKEND"
```

This is important because many paths contain spaces, such as:

```text
/Library/Application Support/Pharos/Popup.app
```

Without quotes, Bash would split that path into separate words:

```text
/Library/Application
Support/Pharos/Popup.app
```

That would break commands.

Beginner rule:

```text
Quote variables unless you have a specific reason not to.
```

## File Tests

The script checks files and directories with test operators.

Examples:

```bash
[ -x "$POPUP_BACKEND" ]
[ -r "$CANON_PPD" ]
[ -f "$TARGET_PPD" ]
[ -d "/Library/Application Support/Pharos" ]
[ -L "$POPUP_BACKEND" ]
```

Common file tests:

```text
-x  exists and is executable
-r  exists and is readable
-f  exists and is a regular file
-d  exists and is a directory
-L  exists and is a symbolic link
```

These checks let the script make decisions safely before running commands.

## Finding Files

The script first checks the most likely file paths directly:

```bash
if [ -r "$TARGET_PPD" ]; then
    CANON_PPD="$TARGET_PPD"
else
    CANON_PPD="$(find "$CANON_PPD_DIR" -type f -name "CNPZUIRAC5030ZU.ppd.gz" 2>/dev/null | head -n 1)"
fi
```

Direct checks are faster than broad searches.

Only if the direct check fails does the script use `find`.

This command:

```bash
find "$CANON_PPD_DIR" -type f -name "CNPZUIRAC5030ZU.ppd.gz"
```

means:

```text
Look inside CANON_PPD_DIR for regular files named CNPZUIRAC5030ZU.ppd.gz.
```

`head -n 1` keeps only the first result.

## Symbolic Links

The script creates a CUPS backend symlink:

```bash
ln -sf "$POPUP_BINARY" "$POPUP_BACKEND"
```

A symbolic link is like a pointer from one file path to another.

In this script:

```text
/usr/libexec/cups/backend/popup
```

points to the real Pharos Popup executable.

The options mean:

```text
-s  create symbolic link
-f  force replacement if something already exists
```

The script later checks:

```bash
if [ -L "$POPUP_BACKEND" ]; then
    readlink "$POPUP_BACKEND"
fi
```

`readlink` prints where the symlink points.

## Using `|| true`

The script uses this pattern:

```bash
launchctl stop org.cups.cupsd 2>/dev/null || true
```

`||` means:

```text
Run the command on the right only if the command on the left failed.
```

So:

```bash
some_command || true
```

means:

```text
If some_command fails, ignore the failure and keep going.
```

This is useful for cleanup commands where failure is acceptable.

For example, stopping CUPS may fail if it was not running. That should not stop the whole script.

## Restarting CUPS

The script restarts CUPS with:

```bash
launchctl stop org.cups.cupsd 2>/dev/null || true
launchctl start org.cups.cupsd 2>/dev/null || true
```

CUPS is the macOS printing system.

After creating the backend symlink and verifying the driver, the script restarts CUPS so the printing system sees the new setup.

The optimized script avoids restarting CUPS repeatedly. It restarts CUPS once before queue installation and only retries during final verification if the count looks wrong.

## Installing a Printer

The main printer install happens in the `install_printer` function.

Important variables:

```bash
local name="$1"
local location="$2"
local type="$3"
local uri="popup://$PHAROS_SERVER:$PHAROS_PORT/$name"
local description="$location - $type"
```

If the function is called like this:

```bash
install_printer "LIB-ArchMobileBW" "Architecture Library" "Black & White"
```

then:

```text
name=LIB-ArchMobileBW
location=Architecture Library
type=Black & White
uri=popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-ArchMobileBW
description=Architecture Library - Black & White
```

## Building Command Arguments with an Array

The script builds the `lpadmin` command using an array:

```bash
lpadmin_args=(
    -p "$name"
    -E
    -v "$uri"
    -P "$CANON_PPD"
    -D "$description"
    -L "$location"
    -o printer-is-shared=false
    -o printer-error-policy=retry-job
)
```

This is a strong Bash pattern.

It is safer than building one big string because each argument stays separate, even when values contain spaces.

The command is run like this:

```bash
install_output="$(lpadmin "${lpadmin_args[@]}" 2>&1)"
```

`"${lpadmin_args[@]}"` expands the array into separate command arguments.

That means this:

```text
Architecture Library
```

stays one argument, not two.

## Conditional Extra Options

The script adds extra printer options for Architecture printers:

```bash
if [[ "$name" == *"Arch"* ]]; then
    lpadmin_args+=(
        -o PageSize=Tabloid
        -o MediaType=Plain
        -o InputSlot=Auto
    )
fi
```

`[[ ... ]]` is Bash's extended test syntax.

This comparison:

```bash
[[ "$name" == *"Arch"* ]]
```

means:

```text
If the printer name contains Arch
```

The `*` characters are wildcards.

If the condition is true, the script appends more options to the `lpadmin_args` array.

## Capturing Command Output and Exit Code

The script captures both output and success/failure from `lpadmin`:

```bash
install_output="$(lpadmin "${lpadmin_args[@]}" 2>&1)"
exit_code=$?
```

`$?` means:

```text
The exit code of the previous command
```

So immediately after `lpadmin` runs, the script saves its exit code.

Then it checks:

```bash
if [ "$exit_code" -ne 0 ]; then
```

If the exit code is not zero, the command failed.

The captured output is printed only when there is an error:

```bash
echo "$install_output" | sed 's/^/         /'
```

The `sed` command adds indentation to each line, making the log easier to read.

## Counting Successes and Failures

The script tracks results:

```bash
SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_PRINTERS=()
```

When a printer succeeds:

```bash
SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
```

When a printer fails:

```bash
FAIL_COUNT=$((FAIL_COUNT + 1))
FAILED_PRINTERS+=("$name")
```

At the end, the script prints a summary and exits with success or failure depending on those counters.

## Final Exit Logic

The ending logic is:

```bash
if [ "$FAIL_COUNT" -eq 0 ] && [ "$SUCCESS_COUNT" -gt 0 ]; then
    exit 0
elif [ "$SUCCESS_COUNT" -gt 0 ]; then
    exit 1
fi

exit 1
```

This means:

```text
If no printers failed and at least one printer succeeded, report success.
If some printers succeeded but some failed, report failure.
If no printers succeeded, report failure.
```

Even partial success exits with `1` because Jamf and other management tools generally need a non-zero exit code to know something went wrong.

## Performance Improvements in the Optimized Script

The optimized script improves performance mainly by doing less waiting and less repeated work.

### 1. Polling Instead of Fixed Sleeps

The original style used fixed sleeps like:

```bash
sleep 5
```

The optimized script checks readiness repeatedly and moves on as soon as the condition is true.

This saves time on healthy machines.

### 2. Fewer CUPS Restarts

Restarting CUPS is expensive.

The optimized script restarts CUPS after the driver and backend setup, then avoids another restart unless final verification looks suspicious.

### 3. Fewer `lpadmin` Calls

Instead of creating the printer and then running separate `lpadmin` commands for options, the optimized script passes most options during the initial creation command.

That reduces process launches and CUPS queue mutations.

### 4. Direct Checks Before Searches

The script checks known file paths first.

Only if those checks fail does it use broader `find` searches.

This is faster because direct file checks are cheap.

### 5. Data-Driven Printer Installation

The printer definitions are stored in one array.

The loop uses that data to install each printer.

This reduces repeated code and makes changes less error-prone.

## Bash Concepts Used in This Script

This script is a good example of these Bash concepts:

```text
Variables
Quoting
Functions
Function arguments
Local variables
Arrays
For loops
While loops
If statements
Numeric comparisons
String comparisons
File tests
Command substitution
Process substitution
Here-strings
Exit codes
Output redirection
Pipelines
awk
sed
find
Symbolic links
Polling loops
```

## Suggested Learning Path

If you are using this script to learn Bash, study it in this order:

1. Start with variables and quoting.
2. Learn `if`, `[ ... ]`, and file tests.
3. Learn command substitution with `$(...)`.
4. Learn functions and function arguments.
5. Learn arrays and `for` loops.
6. Learn `while read` loops.
7. Learn exit codes and `$?`.
8. Learn redirection, especially `>/dev/null 2>&1`.
9. Learn process substitution with `< <(...)`.
10. Study how the `install_printer` function builds and runs `lpadmin`.

The most important beginner habit shown in this script is quoting variables. Paths on macOS often contain spaces, so safe quoting prevents many common Bash bugs.

#!/bin/bash
# CleanUsers.sh
# Wipes all non-admin user profiles to recover storage on public macOS devices
# Also removes leftover /Users/.pending_delete_* folders from earlier deletions
# Deploy via Jamf Self Service or as a one-time scoped policy
# Set DRY_RUN=true to preview which profiles would be deleted before running live
# Author: Oji
# Date: 2026-10-01
# Version: 1.2
#
# Changelog
# 1.2 - Added cleanup_pending_deletes (runs before the user loop, so it only
#       removes leftovers from previous runs, never ones still being deleted).
#     - du calls now end in "|| true" so a permission error can't trip the
#       ERR trap and stop the script mid-run.
#     - Summary reports pending-folder results and combined storage freed.
# 1.1 - Initial Jamf release.

set -u          # Exit on undefined variable
set -o pipefail # Catch errors in pipelines
# Note: set -e intentionally omitted — we handle errors per-user in the loop

# Logging
LOG_FILE="/var/log/bulk_profile_wipe.log"
exec &> >(tee -a "$LOG_FILE")

# Error handling
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --- Configuration ---
DRY_RUN=false   # Set to true to preview deletions without acting
CLEAN_PENDING=true  # Set to false to skip .pending_delete cleanup
EXCLUDE_USERS=("cmcleod1" "jssadmin" "libradmin" "_mbsetupuser" "Shared")

# --- Counters for pending-delete cleanup ---
pending_removed=0
pending_failed=0
pending_freed_kb=0

# --- Functions ---
function main() {
    active_session_guard
    print_header

    if [[ "$CLEAN_PENDING" = true ]]; then
        cleanup_pending_deletes
    fi

    local deleted=0
    local skipped=0
    local failed=0
    local total_freed_kb=0

    echo ""
    echo "----- User profiles -----"

    for user_home in /Users/*; do
        [[ -e "$user_home" ]] || continue
        [[ -d "$user_home" ]] || continue

        local username
        username=$(basename "$user_home")

        # Skip hidden/system folders
        if [[ "$username" == .* ]]; then
            echo "SKIP  $username (hidden/system folder)"
            ((skipped++)) || true
            continue
        fi
        if is_excluded_user "$username"; then
            echo "SKIP  $username (explicitly excluded)"
            ((skipped++)) || true
            continue
        fi

        # Skip system accounts (UID < 500)
        local uid
        uid=$(id -u "$username" 2>/dev/null) || true
        if [[ -z "$uid" || "$uid" -lt 500 ]]; then
            echo "SKIP  $username (system account, UID: ${uid:-unknown})"
            ((skipped++)) || true
            continue
        fi

        # Skip local admins; this script is intended to delete non-admin accounts only
        if is_admin_user "$username"; then
            echo "SKIP  $username (admin account)"
            ((skipped++)) || true
            continue
        fi

        # Calculate profile size before deletion (in KB for accurate math)
        local profile_size
        local profile_kb
        profile_size=$(du -sh "$user_home" 2>/dev/null | awk '{print $1}') || true
        profile_kb=$(du -sk "$user_home" 2>/dev/null | awk '{print $1}') || true
        profile_size="${profile_size:-unknown}"
        profile_kb="${profile_kb:-0}"

        if [[ "$DRY_RUN" = true ]]; then
            echo "WOULD DELETE  $username — Profile size: $profile_size"
            ((deleted++)) || true
        else
            echo "DELETING  $username — Profile size: $profile_size"
            if /usr/sbin/sysadminctl -deleteUser "$username" -secure 2>&1; then
                total_freed_kb=$((total_freed_kb + profile_kb))
                ((deleted++)) || true
            else
                echo "FAILED  Could not delete $username"
                ((failed++)) || true
            fi
        fi
    done

    print_summary "$deleted" "$skipped" "$failed" "$total_freed_kb"
}

function cleanup_pending_deletes() {
    # Removes /Users/.pending_delete_* folders left behind by earlier
    # sysadminctl -deleteUser runs. Called BEFORE the user loop so it
    # never races a deletion started by this run.
    local pending
    local name
    local kb
    local size
    local found=0

    echo "----- Leftover .pending_delete folders -----"

    for pending in /Users/.pending_delete_*; do
        [[ -d "$pending" ]] || continue
        found=1
        name=$(basename "$pending")

        kb=$(du -sk "$pending" 2>/dev/null | awk '{print $1}') || true
        size=$(du -sh "$pending" 2>/dev/null | awk '{print $1}') || true
        kb="${kb:-0}"
        size="${size:-unknown}"

        if [[ "$DRY_RUN" = true ]]; then
            echo "WOULD REMOVE  $name — Size: $size"
            ((pending_removed++)) || true
        else
            echo "REMOVING  $name — Size: $size"
            /usr/bin/chflags -R nouchg,noschg "$pending" 2>/dev/null || true
            if /bin/rm -rf "$pending" 2>&1; then
                pending_freed_kb=$((pending_freed_kb + kb))
                ((pending_removed++)) || true
            else
                echo "FAILED  Could not remove $name"
                ((pending_failed++)) || true
            fi
        fi
    done

    [[ "$found" -eq 1 ]] || echo "None found."
}

function active_session_guard() {
    local current_user
    current_user=$(stat -f "%Su" /dev/console 2>/dev/null || true)

    if [[ -n "$current_user" && "$current_user" != "root" && "$current_user" != "loginwindow" ]]; then
        if ! is_excluded_user "$current_user"; then
            EXCLUDE_USERS+=("$current_user")
        fi
        echo "WARNING — Console user $current_user is currently logged in. Their profile will be skipped."
    fi

    # Also protect users with active local/remote sessions (e.g., FUS/SSH).
    local session_user
    while read -r session_user _; do
        [[ -n "$session_user" ]] || continue
        [[ "$session_user" == "root" ]] && continue
        if ! is_excluded_user "$session_user"; then
            EXCLUDE_USERS+=("$session_user")
            echo "WARNING — Active session detected for $session_user. Their profile will be skipped."
        fi
    done < <(who 2>/dev/null || true)
}

function is_excluded_user() {
    local username="$1"
    local excluded

    for excluded in "${EXCLUDE_USERS[@]}"; do
        if [[ "$username" == "$excluded" ]]; then
            return 0
        fi
    done

    return 1
}

function is_admin_user() {
    local username="$1"
    local membership

    membership=$(/usr/sbin/dseditgroup -o checkmember -m "$username" admin 2>/dev/null || true)
    [[ "$membership" == *"yes"* ]]
}

function print_header() {
    echo "===== Bulk Profile Wipe ====="
    echo "Mode: $([ "$DRY_RUN" = true ] && echo 'DRY RUN' || echo 'LIVE DELETION')"
    echo "Started: $(date)"
    echo ""
}

function print_summary() {
    local deleted="$1"
    local skipped="$2"
    local failed="$3"
    local total_freed_kb="$4"
    local combined_kb=$((total_freed_kb + pending_freed_kb))

    echo ""
    echo "===== Summary ====="
    echo "Profiles deleted        : $deleted"
    echo "Profiles skipped        : $skipped"
    echo "Profiles failed         : $failed"
    echo "Pending folders removed : $pending_removed"
    echo "Pending folders failed  : $pending_failed"
    if [[ "$DRY_RUN" = false && "$combined_kb" -gt 0 ]]; then
        echo "Storage freed           : $(echo "$combined_kb" | awk '{printf "%.2f GB", $1/1048576}')"
    fi
    echo "Completed: $(date)"
}

# --- Execute ---
main "$@"
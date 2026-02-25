#!/bin/bash
# CleanUsers.sh
# Wipes all non-admin user profiles to recover storage on public macOS devices
# Deploy via Jamf Self Service or as a one-time scoped policy
# Set DRY_RUN=true to preview which profiles would be deleted before running live
# Author: Oji
# Date: 2026-02-23
# Version: 1.1

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
EXCLUDE_USERS=("cmcleod1" "jssadmin" "libradmin" "_mbsetupuser" "Shared")

# --- Functions ---
function main() {
    active_session_guard
    print_header

    local deleted=0
    local skipped=0
    local failed=0
    local total_freed_kb=0

    for user_home in /Users/*; do
        local username
        username=$(basename "$user_home")

        # Skip hidden/system folders
        [[ "$username" == .* ]] && continue
        [[ " ${EXCLUDE_USERS[*]} " =~ " ${username} " ]] && continue

        # Skip system accounts (UID < 500)
        local uid
        uid=$(id -u "$username" 2>/dev/null) || true
        if [[ -z "$uid" || "$uid" -lt 500 ]]; then
            echo "SKIP  $username (system account, UID: ${uid:-unknown})"
            ((skipped++)) || true
            continue
        fi

        # Calculate profile size before deletion (in KB for accurate math)
        local profile_size
        local profile_kb
        profile_size=$(du -sh "$user_home" 2>/dev/null | awk '{print $1}')
        profile_kb=$(du -sk "$user_home" 2>/dev/null | awk '{print $1}')

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

function active_session_guard() {
    local current_user
    current_user=$(stat -f "%Su" /dev/console 2>/dev/null)

    if [[ -n "$current_user" && "$current_user" != "root" && "$current_user" != "loginwindow" ]]; then
        echo "WARNING — $current_user is currently logged in. Their profile will be skipped."
        EXCLUDE_USERS+=("$current_user")
    fi
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

    echo ""
    echo "===== Summary ====="
    echo "Profiles deleted   : $deleted"
    echo "Profiles skipped   : $skipped"
    echo "Profiles failed    : $failed"
    if [[ "$DRY_RUN" = false && "$total_freed_kb" -gt 0 ]]; then
        echo "Storage freed      : $(echo "$total_freed_kb" | awk '{printf "%.2f GB", $1/1048576}')"
    fi
    echo "Completed: $(date)"
}

# --- Execute ---
main "$@"

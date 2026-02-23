#!/bin/bash
# bulk_profile_wipe.sh
# Wipes all non-admin user profiles to recover storage
# Deploy via JAMF Self Service or as a one-time scoped policy
# Review DRY_RUN output before setting to false

DRY_RUN=false   # Set to false when ready to delete for real
EXCLUDE_USERS=("cmcleod1" "jssadmin" "libradmin" "_mbsetupuser" "Shared")

# --- Active session guard ---
CURRENT_USER=$(stat -f "%Su" /dev/console 2>/dev/null)
if [[ -n "$CURRENT_USER" && "$CURRENT_USER" != "root" && "$CURRENT_USER" != "loginwindow" ]]; then
    echo "WARNING — $CURRENT_USER is currently logged in. Their profile will be skipped."
    # Add the logged-in user to the exclusion list dynamically
    EXCLUDE_USERS+=("$CURRENT_USER")
fi
echo "Proceeding with profile wipe..."
# ----------------------------

echo "===== Bulk Profile Wipe ====="
echo "Mode: $([ "$DRY_RUN" = true ] && echo 'DRY RUN' || echo 'LIVE DELETION')"
echo "Started: $(date)"
echo ""

DELETED=0
SKIPPED=0
TOTAL_FREED=0

for user_home in /Users/*; do
    username=$(basename "$user_home")

    # Skip hidden/system folders
    [[ "$username" == .* ]] && continue
    [[ " ${EXCLUDE_USERS[*]} " =~ " ${username} " ]] && continue

    uid=$(id -u "$username" 2>/dev/null)
    if [[ -z "$uid" || "$uid" -lt 500 ]]; then
        echo "SKIP  $username (system account, UID: $uid)"
        ((SKIPPED++))
        continue
    fi

    # Calculate profile size before deletion
    profile_size=$(du -sh "$user_home" 2>/dev/null | awk '{print $1}')
    profile_bytes=$(du -s "$user_home" 2>/dev/null | awk '{print $1}')

    if [[ "$DRY_RUN" = true ]]; then
        echo "WOULD DELETE  $username — Profile size: $profile_size"
        ((DELETED++))
    else
        echo "DELETING  $username — Profile size: $profile_size"
        /usr/sbin/sysadminctl -deleteUser "$username" -secure 2>&1
        TOTAL_FREED=$((TOTAL_FREED + profile_bytes))
        ((DELETED++))
    fi
done

echo ""
echo "===== Summary ====="
echo "Profiles processed : $DELETED"
echo "Profiles skipped   : $SKIPPED"
if [[ "$DRY_RUN" = false ]]; then
    echo "Storage freed      : $(echo "$TOTAL_FREED" | awk '{printf "%.2f GB", $1/1048576}')"
fi
echo "Completed: $(date)"
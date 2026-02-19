#!/bin/bash
# Delete macOS user profiles inactive for more than X days
# Deploy via JAMF as a recurring policy (e.g., weekly)

INACTIVE_DAYS=2  # Adjust threshold
EXCLUDE_USERS=("admin" "jssadmin" "localadmin" "_mbsetupuser")  # Never delete these

for user_home in /Users/*; do
    username=$(basename "$user_home")

    # Skip system/hidden accounts and excluded users
    [[ "$username" == .* ]] && continue
    [[ " ${EXCLUDE_USERS[*]} " =~ " ${username} " ]] && continue

    # Skip if not a real user (no UniqueID or UID < 500)
    uid=$(id -u "$username" 2>/dev/null)
    [[ -z "$uid" || "$uid" -lt 500 ]] && continue

    # Get last login time
    last_login=$(last -1 "$username" | awk 'NR==1{print $5, $6, $7, $8}')
    last_login_epoch=$(date -j -f "%a %b %d %H:%M" "$last_login" "+%s" 2>/dev/null)

    if [[ -z "$last_login_epoch" ]]; then
        echo "Skipping $username — no login record found"
        continue
    fi

    now=$(date "+%s")
    diff_days=$(( (now - last_login_epoch) / 86400 ))

    if [[ "$diff_days" -gt "$INACTIVE_DAYS" ]]; then
        echo "Deleting $username — inactive for $diff_days days"
        /usr/sbin/sysadminctl -deleteUser "$username" -secure 2>&1
    else
        echo "Keeping $username — last login $diff_days days ago"
    fi
done
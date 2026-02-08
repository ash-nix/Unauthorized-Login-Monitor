#!/bin/bash

check_unauthorized_login() {
    # Set allowed user (e.g., admin)
    local allowed_user=""
    
    show_notification() {
        local title="$1"
        local message="$2"
        local username="$3"
        if command -v notify-send &>/dev/null; then
            response=$(notify-send -u critical -A "kickout=Kickout" "$title" "$message")
            [[ "$response" == "kickout" ]] && kick_out_user "$username"
        fi
    }
    
    local system_users=("root" "reboot" "shutdown" "halt" "sync" "systemd-timesync")
    local last_output w_output
    declare -A seen
    
    is_system_user() {
        local u="$1"
        for s in "${system_users[@]}"; do
            [[ "$s" == "$u" ]] && return 0
        done
        return 1
    }

    is_remote_connection() {
        local username="$1"
        # Check for SSH, telnet, or non-local connections
        w -h | grep -E "$username.*\(|ssh|telnet" >/dev/null
    }

    is_sending_data() {
        local username="$1"
        # Check for established outbound connections
        ss -tupen 2>/dev/null | grep -E "ESTAB.*uid=$UID" | grep -v "127.0.0.1" >/dev/null
    }

    last_output=$(last -f /var/log/wtmp 2>/dev/null | grep -v '^$' || true)
    w_output=$(w -h 2>/dev/null || true)

    echo "=== Checking for unauthorized users ==="
    while read -r line; do
        local username=$(awk '{print $1}' <<<"$line")
        if [[ -z "$username" || "$username" == "$allowed_user" ]] || is_system_user "$username"; then
            continue
        fi
        seen["$username"]=1
        if is_remote_connection "$username" || is_sending_data "$username"; then
            echo "⚠️  UNAUTHORIZED LOGIN: $line"
        fi

        if is_remote_connection "$username"; then
            echo "  → Remote connection detected"
            show_notification "Remote Connection" "User $username connected remotely" "$username"
        fi

        if is_sending_data "$username"; then
            echo "  → Outbound data transmission detected"
            show_notification "Suspicious Activity" "User $username sending data to internet" "$username"
        fi
    done < <(printf '%s\n' "$last_output")

    [[ ${#seen[@]} -eq 0 ]] && echo "No unauthorized users detected." && return 0

    for username in "${!seen[@]}"; do
        if is_remote_connection "$username" || is_sending_data "$username"; then
            prompt_user_action "$username" "$last_output" "$w_output"
        fi
    done
}

prompt_user_action() {
    local username="$1" last_output="$2" w_output="$3"
    echo; echo "----"; echo "User: $username"; echo
    echo "Recent logins (last):"
    grep -E "\b$username\b" <<<"$last_output" || echo "  <none>"
    echo; echo "Active sessions (w):"
    grep -E "\b$username\b" <<<"$w_output" || echo "  <none>"
    echo; echo "Processes (ps -u $username):"
    ps -u "$username" -o pid,tty,cmd 2>/dev/null | sed -n '1,20p' || echo "  <none>"
    
    read -r -p "Kick out user '$username'? [y/N]: " reply
    [[ "$reply" =~ ^[yY]$ ]] && kick_out_user "$username"
}

kick_out_user() {
    local username="$1"
    # $EUID: Bash special parameter containing the numeric "effective user ID" of the current process.
    # The effective UID is used for permission checks (root has EUID 0). Comparing $EUID to 0
    # is a common way to determine whether the script is running with root privileges.
    # (UID is the real user ID; EUID may differ when a process has elevated/setuid privileges.)
    if [[ $EUID -ne 0 ]]; then
        echo "Must be root to kill user processes."
        return
    fi
    echo "Killing all processes for $username..."
    pkill -KILL -u "$username" 2>/dev/null || {
        pids=$(ps -u "$username" -o pid=)
        [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null || true
    }
    notify-send -u critical "User Kicked Out" "User $username has been kicked out."
}

check_unauthorized_login

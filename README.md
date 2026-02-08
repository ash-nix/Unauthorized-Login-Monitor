# Unauthorized Login Monitor

## Purpose

Detects non-authorized user logins and interactive sessions on the system, alerts the local user (via `notify-send` if available), and provides an option to forcibly terminate (kick out) a suspicious user.

## Overview

The script inspects recent login records and active sessions using `last` and `w`. It classifies users as allowed, system, or potentially unauthorized and performs additional checks for remote connections and outbound data transmission. For suspicious sessions it:

- Prints details to the terminal
- Sends desktop notifications (if `notify-send` exists)
- Prompts the operator to optionally kill all processes owned by the suspicious user

## Key functions

- `check_unauthorized_login()` — main entry point. Gathers `last` and `w` outputs, iterates found users, and triggers notifications and prompts.
- `show_notification(title, message, username)` — uses `notify-send` to display a notification with an action to trigger `kick_out_user` when available.
- `is_system_user(user)` — checks a small hard-coded list of system accounts to ignore.
- `is_remote_connection(username)` — heuristic using `w` output and pattern matching for `ssh`/`telnet` or remote TTYs.
- `is_sending_data(username)` — runs `ss -tupen` and looks for established connections that are not loopback.
- `prompt_user_action(username, last_output, w_output)` — interactive prompt showing recent `last` entries, `w` output, and `ps -u` for the user, then asks whether to kill the user.
- `kick_out_user(username)` — kills all processes for `username` (uses `pkill -KILL -u` or `kill -9` on listed PIDs) and sends a final notification. Requires root privileges to actually kill processes.

## Usage

Run the script from a shell (it executes automatically when run):

```bash
./unauth_login_monitor.sh
```

Behavior:

- If no suspicious users are found the script prints `No unauthorized users detected.` and exits with success.
- If suspicious users are found it prints details and for each suspicious user will ask `Kick out user 'username'? [y/N]:`.
- If you answer `y` and the script is running as root, it will terminate that user's processes.

## Requirements

- `bash`
- `last` (reads `/var/log/wtmp`)
- `w` (active sessions)
- `ss` (socket status) — used to detect established outbound connections
- `ps`, `pkill`, `kill` (process management)
- Desktop notification utility `notify-send` (optional) for GUI alerts

Notes:

- To actually kill processes the script must be run as `root` (or with `sudo`). If not root it will print `Must be root to kill user processes.` and skip killing.
- `is_sending_data` uses `ss` and a UID filter; depending on environment this may report activity for the current user rather than the inspected username. Review the implementation if you need per-user connection accuracy.

## Exit Codes

- Returns `0` if no unauthorized users are detected (or after normal completion).
- No special non-zero exit codes are set by the script for other conditions; errors are printed to stdout/stderr as they occur.

## Security & Operational Notes

- The script contains heuristics (pattern matching on `w`, `ss`) and may produce false positives or false negatives. Use it as a prompt/assistant, not as an automated enforcement tool.
- Consider restricting who can run the script and/or integrating with logging/alerting systems for production use.
- If you need automated remediation, ensure careful testing and consider adding an allowlist/denylist configuration external to the script.

## Suggested Improvements

- Make the allowed user(s) configurable via environment variable or CLI flag instead of hard-coded `allowed_user`.
- Fix per-user network checks so `is_sending_data` examines connections for the specific target user's UID rather than relying on the current run user's UID.
- Add a `--non-interactive` mode that can automatically log or quarantine suspicious sessions (use with caution).

## Note

- It is a hobby project and for learning purposes.
- It is not for production use. It may produce false positives or false negatives! 

## License

This project is licensed under the GNU General Public License v3.0 (GPLv3).
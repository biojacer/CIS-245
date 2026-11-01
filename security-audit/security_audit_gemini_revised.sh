#!/usr/bin/env bash
# Revised audit based on Gemini's original; changes require attribution.
# Bash reference: https://www.gnu.org/software/bash/manual/bash.html
set -uo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
umask 077
export LC_ALL=C
REPORT_DIR="${REPORT_DIR:-/home/rtavarez}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S) || exit 2
REPORT_FILE="$REPORT_DIR/security_report_${TIMESTAMP}_$$.txt"
STATUS=0
# Test pre-existing destination; avoid changing server configuration.
if [[ ! -d "$REPORT_DIR" || ! -w "$REPORT_DIR" ]]; then
  printf 'ERROR: report directory missing or not writable: %s\n' "$REPORT_DIR" >&2
  exit 2
fi
if ! ( set -C; : > "$REPORT_FILE" ) 2>/dev/null; then
  printf 'ERROR: cannot create report file\n' >&2
  exit 2
fi
# printf, redirection, and command substitution: GNU Bash manual above.
printf 'LINUX SECURITY AUDIT REPORT\nHost: %s\nDate: %s\n\n' "$(hostname)" "$(date)" >> "$REPORT_FILE"
log() { printf '%s\n' "$*" >> "$REPORT_FILE"; }
error() { log "ERROR: $*"; STATUS=2; }
issue() { log "WARNING: $*"; if (( STATUS == 0 )); then STATUS=1; fi; }
# journalctl: https://www.freedesktop.org/software/systemd/man/latest/journalctl.html
log '=== Failed SSH logins (last 24 hours) ==='
if ! command -v journalctl >/dev/null 2>&1; then
  error 'journalctl unavailable; cannot verify 24-hour SSH history'
else
  JOURNAL=$(journalctl --since '24 hours ago' -u ssh.service -u sshd.service --no-pager -o cat 2>&1)
  RC=$?
  if (( RC != 0 )); then
    error "journalctl failed (exit $RC): $JOURNAL"
  else
    # grep: https://www.gnu.org/software/grep/manual/grep.html
    MATCHES=$(printf '%s\n' "$JOURNAL" | grep -iE 'Failed password|Failed publickey|Invalid user|authentication failure|PAM: Authentication failure' || true)
    if [[ -n "$MATCHES" ]]; then
      log "$MATCHES"
      issue 'SSH authentication failures detected'
    else
      log 'No matching SSH failures in the accessible service journal; log coverage not guaranteed.'
    fi
  fi
fi
# passwd and shadow formats: https://man7.org/linux/man-pages/man5/passwd.5.html
# https://man7.org/linux/man-pages/man5/shadow.5.html
# awk: https://www.gnu.org/software/gawk/manual/gawk.html
log '=== UID 0 accounts ==='
if [[ ! -r /etc/passwd ]]; then
  error 'Cannot read /etc/passwd'
else
  UID0=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
  log "$UID0"
  if [[ -z "$UID0" ]]; then
    error 'No UID 0 account found; account inventory needs investigation'
  elif [[ "$UID0" != 'root' ]]; then
    issue 'UID 0 account inventory differs from root-only baseline'
  fi
fi
log '=== Empty password fields ==='
if [[ ! -r /etc/shadow ]]; then
  error 'Cannot read /etc/shadow (run as root)'
else
  EMPTY=$(awk -F: '$2 == "" {print $1}' /etc/shadow)
  if [[ -n "$EMPTY" ]]; then
    log "$EMPTY"
    issue 'Empty password fields detected'
  else
    log 'No empty password fields found'
  fi
fi
# ss: https://man7.org/linux/man-pages/man8/ss.8.html
log '=== Listening TCP and UDP sockets ==='
if ! command -v ss >/dev/null 2>&1; then
  error 'ss command unavailable'
else
  SOCKETS=$(ss -tuln 2>&1)
  RC=$?
  if (( RC != 0 )); then
    error "ss failed (exit $RC): $SOCKETS"
  else
    log "$SOCKETS"
  fi
fi
case "$STATUS" in
  0) log 'STATUS: PASS (no flagged findings in available evidence)' ;;
  1) log 'STATUS: SECURITY FINDINGS DETECTED' ;;
  2) log 'STATUS: AUDIT INCOMPLETE / EXECUTION ERROR' ;;
esac
printf 'Report: %s\nExit status: %s\n' "$REPORT_FILE" "$STATUS"
exit "$STATUS"

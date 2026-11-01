#!/bin/bash
# =============================================================================
# acme_security_audit.sh  -  Acme Corp, ticket ACME-1842 (version 1)
#
# Read-only security audit for CentOS/RHEL-family and Ubuntu/Debian-family
# servers. The same file runs unchanged on both.
#
# Usage:   sudo ./acme_security_audit.sh /absolute/path/to/report/directory
#
# Exit codes:
#   0 = audit completed, no security problem detected
#   1 = audit completed, at least one security problem detected
#   2 = the script could not run or could not finish (usage/permission/tool error)
#
# What it checks:
#   1. Failed SSH logins in the last 24 hours
#   2. Accounts with UID 0 (other than "root") and accounts with empty passwords
#   3. Listening TCP/UDP ports (via ss) - listed for review, not judged
#
# Documentation references are given in comments next to the code.
# man7.org hosts the upstream Linux man-pages project and many distro-neutral
# man pages; the Bash and gawk references are the official GNU manuals.
# =============================================================================

# --- Shell safety options ----------------------------------------------------
# set -u : treat use of an unset variable as an error.
# set -o pipefail : a pipeline fails if any command in it fails.
# (set -e is intentionally NOT used: grep returns 1 for "no match", which is a
#  normal result here and must not abort the script.)
# Ref: https://www.gnu.org/software/bash/manual/bash.html#The-Set-Builtin
set -u
set -o pipefail

# --- Environment for non-interactive (cron) use ------------------------------
# cron starts jobs with a very small PATH, so set one explicitly; ss lives in
# /usr/sbin or /usr/bin depending on the distribution.
# Ref: https://man7.org/linux/man-pages/man5/crontab.5.html  (ENVIRONMENT/PATH)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
# LC_ALL=C gives the same date/sort/grep behaviour on every host and in cron.
# Ref: https://man7.org/linux/man-pages/man7/locale.7.html
export LC_ALL=C

# umask 077: files this script creates (the report) are readable only by the
# owner. The report can contain usernames and IP addresses.
# Ref: https://www.gnu.org/software/bash/manual/bash.html#Bourne-Shell-Builtins (umask)
umask 077

# --- Settings ----------------------------------------------------------------
# Report a problem when the number of failed SSH logins in the last 24 hours is
# GREATER than this value. 0 means "any failed login is a problem".
SSH_FAIL_THRESHOLD=0

EXIT_OK=0
EXIT_FINDINGS=1
EXIT_ERROR=2

# Pattern for failed SSH authentication lines. sshd logs lines such as
# "Failed password for <user> from <ip> port <n> ssh2". Since OpenSSH 9.8 the
# logging process may be named "sshd-session" instead of "sshd", so both are
# matched.
# Ref (log text is produced by auth_log() in the OpenSSH source, it is not
#      specified in a man page - verify against your own logs):
#      https://github.com/openssh/openssh-portable/blob/master/auth.c
# Ref (LogLevel/SyslogFacility control what sshd logs):
#      https://man7.org/linux/man-pages/man5/sshd_config.5.html
SSH_FAIL_REGEX='(sshd|sshd-session)\[[0-9]+\]: Failed (password|publickey|keyboard-interactive/pam) for '

# --- Helper: print an error to stderr and stop with exit code 2 --------------
die() {
    echo "ERROR: $*" >&2
    exit "$EXIT_ERROR"
}

# =============================================================================
# SECTION 1: Pre-flight checks (no changes to the system are made here)
# =============================================================================

# Exactly one argument is required: the report directory. Nothing is ever
# asked interactively, so the script is safe under cron.
[ "$#" -eq 1 ] || die "usage: $0 /absolute/path/to/report/directory"

# Must be root: /etc/shadow and the SSH log files are not readable otherwise.
# Ref: https://man7.org/linux/man-pages/man1/id.1.html
#      https://man7.org/linux/man-pages/man5/shadow.5.html
[ "$(id -u)" -eq 0 ] || die "must be run as root (needed to read /etc/shadow and auth logs)"

# Make sure every external tool we rely on is present. Nothing is installed.
# Ref: https://www.gnu.org/software/bash/manual/bash.html#Bash-Builtins (command)
for tool in ss awk grep sort date uname readlink mkdir wc; do
    command -v "$tool" >/dev/null 2>&1 || die "required command not found: $tool"
done

# Report directory: must be an absolute path (cron's working directory is
# unpredictable), and must not be /tmp or inside it.
# readlink -m resolves symlinks and ".." even if the directory does not exist
# yet, so tricks like /var/../tmp or a symlink to /tmp are caught.
# Ref: https://man7.org/linux/man-pages/man1/readlink.1.html
case "$1" in
    /*) ;;
    *)  die "report directory must be an absolute path: $1" ;;
esac
OUT_DIR=$(readlink -m -- "$1") || die "cannot resolve report directory: $1"
case "$OUT_DIR" in
    /tmp|/tmp/*) die "report directory must not be /tmp (resolved to: $OUT_DIR)" ;;
esac

# Create the report directory if missing, then confirm it is writable.
# Ref: https://man7.org/linux/man-pages/man1/mkdir.1.html
mkdir -p -- "$OUT_DIR" || die "cannot create report directory: $OUT_DIR"
[ -d "$OUT_DIR" ] && [ -w "$OUT_DIR" ] || die "report directory is not writable: $OUT_DIR"

# Timestamped report file name: host name + date + time.
# uname -n prints the node name without needing the separate "hostname" tool.
# Ref: https://man7.org/linux/man-pages/man1/uname.1.html
#      https://man7.org/linux/man-pages/man1/date.1.html
HOST=$(uname -n)
STAMP=$(date '+%Y%m%d-%H%M%S')
REPORT="$OUT_DIR/security-audit-${HOST}-${STAMP}.txt"

# Findings are collected here; the exit code is derived from this counter.
FINDINGS=0
FINDING_LIST=""
add_finding() {
    FINDINGS=$((FINDINGS + 1))
    FINDING_LIST="${FINDING_LIST}  - $1
"
}

# =============================================================================
# SECTION 2: Collect data (everything is read-only)
# =============================================================================

# ---- 2a. Failed SSH logins, last 24 hours -----------------------------------
# CentOS/RHEL logs authentication messages to /var/log/secure; Ubuntu/Debian
# to /var/log/auth.log (distribution defaults, written by rsyslog).
# Ref: https://www.rsyslog.com/doc/
# If neither file is readable we fall back to the systemd journal.
SSH_SOURCE=""
for f in /var/log/auth.log /var/log/secure; do
    if [ -r "$f" ]; then
        SSH_SOURCE="$f"
        break
    fi
done

FAILED_SSH=""
if [ -n "$SSH_SOURCE" ]; then
    # Time window: compare "MMDDHHMMSS" keys. Log lines come in two formats:
    #   traditional : "Oct 31 04:05:06 host sshd[1]: ..."
    #   ISO 8601    : "2026-10-31T04:05:06.123456+00:00 host sshd[1]: ..."
    # Both are converted to the same key. If the window crosses New Year
    # (cutoff key > now key) the test becomes "key >= cutoff OR key <= now".
    # Only POSIX awk features are used, so it works with gawk (CentOS) and
    # mawk (Ubuntu default).
    # Ref: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/awk.html
    # Ref: https://man7.org/linux/man-pages/man1/date.1.html  (-d '24 hours ago')
    NOW_KEY=$(date '+%m%d%H%M%S')
    CUTOFF_KEY=$(date -d '24 hours ago' '+%m%d%H%M%S') \
        || die "date command does not support -d (GNU date required)"
    # Ref: https://man7.org/linux/man-pages/man1/grep.1.html  (-E extended regex)
    # "|| true": grep exits 1 when nothing matches, which is a normal result.
    FAILED_SSH=$(grep -E "$SSH_FAIL_REGEX" "$SSH_SOURCE" \
        | awk -v cutoff="$CUTOFF_KEY" -v now="$NOW_KEY" '
            BEGIN {
                n = split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ")
                for (i = 1; i <= n; i++) mon[m[i]] = sprintf("%02d", i)
            }
            {
                if ($1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/) {
                    key = substr($1,6,2) substr($1,9,2) substr($1,12,2) substr($1,15,2) substr($1,18,2)
                } else {
                    split($3, t, ":")
                    key = mon[$1] sprintf("%02d", $2) t[1] t[2] t[3]
                }
                if (cutoff <= now) keep = (key >= cutoff && key <= now)
                else               keep = (key >= cutoff || key <= now)
                if (keep) print
            }') || true
elif command -v journalctl >/dev/null 2>&1; then
    # Fallback: journald does its own time filtering.
    # Ref: https://man7.org/linux/man-pages/man1/journalctl.1.html (--since, -t, -q)
    # Ref: https://man7.org/linux/man-pages/man7/systemd.time.7.html ("24 hours ago")
    SSH_SOURCE="systemd journal (journalctl)"
    FAILED_SSH=$(journalctl --no-pager -q --since '24 hours ago' \
        -t sshd -t sshd-session 2>/dev/null \
        | grep -E "$SSH_FAIL_REGEX") || true
else
    die "no readable SSH log source (/var/log/auth.log, /var/log/secure, journalctl)"
fi

if [ -z "$FAILED_SSH" ]; then
    FAILED_SSH_COUNT=0
else
    # Ref: https://man7.org/linux/man-pages/man1/wc.1.html
    FAILED_SSH_COUNT=$(printf '%s\n' "$FAILED_SSH" | wc -l)
    FAILED_SSH_COUNT=$((FAILED_SSH_COUNT + 0))   # strip whitespace some wc versions add
fi

# ---- 2b. Accounts with UID 0 -------------------------------------------------
# /etc/passwd format: name:password:UID:GID:comment:home:shell
# Ref: https://man7.org/linux/man-pages/man5/passwd.5.html
UID0_ALL=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd) \
    || die "cannot read /etc/passwd"
# Any UID 0 account other than "root" is a problem.
UID0_EXTRA=$(awk -F: '$3 == 0 && $1 != "root" { print $1 }' /etc/passwd) \
    || die "cannot read /etc/passwd"

# ---- 2c. Accounts with an empty password ------------------------------------
# /etc/shadow format: name:encrypted-password:... ; an empty second field means
# the account can log in without a password. (A "!" or "*" means locked/no
# password login, which is fine.) The second field of /etc/passwd is also
# checked, because an empty value there overrides shadow on some systems.
# Ref: https://man7.org/linux/man-pages/man5/shadow.5.html
#      https://man7.org/linux/man-pages/man5/passwd.5.html
# Ref: https://man7.org/linux/man-pages/man1/sort.1.html  (-u: unique names)
EMPTY_PW=$(awk -F: '$2 == "" { print $1 }' /etc/shadow /etc/passwd | sort -u) \
    || die "cannot read /etc/shadow or /etc/passwd"

# ---- 2d. Listening ports -----------------------------------------------------
# -t TCP, -u UDP, -l listening sockets only, -n numeric (no DNS lookups),
# -p show owning process (root needed for other users' processes).
# Ref: https://man7.org/linux/man-pages/man8/ss.8.html
LISTEN_PORTS=$(ss -tulnp 2>&1) || die "ss command failed: $LISTEN_PORTS"

# =============================================================================
# SECTION 3: Decide what counts as a security problem
# =============================================================================
if [ "$FAILED_SSH_COUNT" -gt "$SSH_FAIL_THRESHOLD" ]; then
    add_finding "$FAILED_SSH_COUNT failed SSH login(s) in the last 24 hours (threshold: $SSH_FAIL_THRESHOLD)"
fi
if [ -n "$UID0_EXTRA" ]; then
    add_finding "non-root account(s) with UID 0: $(printf '%s' "$UID0_EXTRA" | tr '\n' ' ')"
fi
if [ -n "$EMPTY_PW" ]; then
    add_finding "account(s) with an empty password: $(printf '%s' "$EMPTY_PW" | tr '\n' ' ')"
fi

# =============================================================================
# SECTION 4: Write the report
# =============================================================================
# The { ... } group runs in the current shell and its combined output is
# redirected to the report file.
# Ref: https://www.gnu.org/software/bash/manual/bash.html#Command-Grouping
{
    echo "ACME CORP SECURITY AUDIT (ticket ACME-1842)"
    echo "Host:      $HOST"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Run by:    $(id -un) (uid $(id -u))"
    echo
    echo "=== 1. Failed SSH logins, last 24 hours ==="
    echo "Source: $SSH_SOURCE"
    echo "Count:  $FAILED_SSH_COUNT"
    if [ -n "$FAILED_SSH" ]; then
        echo "$FAILED_SSH"
    fi
    echo
    echo "=== 2a. Accounts with UID 0 ==="
    if [ -n "$UID0_ALL" ]; then echo "$UID0_ALL"; else echo "(none - unexpected, root should have UID 0)"; fi
    echo
    echo "=== 2b. Accounts with an empty password ==="
    if [ -n "$EMPTY_PW" ]; then echo "$EMPTY_PW"; else echo "(none)"; fi
    echo
    echo "=== 3. Listening ports (ss -tulnp) ==="
    echo "$LISTEN_PORTS"
    echo
    echo "=== SUMMARY ==="
    if [ "$FINDINGS" -gt 0 ]; then
        echo "RESULT: $FINDINGS security problem(s) detected"
        printf '%s' "$FINDING_LIST"
    else
        echo "RESULT: no security problems detected"
    fi
} > "$REPORT" || die "cannot write report: $REPORT"

# =============================================================================
# SECTION 5: Finish with a meaningful exit code
# =============================================================================
# One short line on stdout (cron will mail it if MAILTO is set).
if [ "$FINDINGS" -gt 0 ]; then
    echo "FINDINGS: $FINDINGS problem(s) detected. Report: $REPORT"
    exit "$EXIT_FINDINGS"
fi
echo "OK: no problems detected. Report: $REPORT"
exit "$EXIT_OK"

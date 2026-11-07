
#!/bin/bash
# CIS-245 - Linux Administration
# Automated Network Troubleshooting - CentOS Stream 10
# Purpose: Collect network and system diagnostics automatically.
# Designed to run without user input through cron.
#
# Bash reference:
# https://www.gnu.org/software/bash/manual/

# Save diagnostic results in the current user's home directory.
# Bash variables and redirection:
# https://www.gnu.org/software/bash/manual/
LOGFILE="$HOME/my_network_troubleshooting_auto.log"

{
    # Separate each execution and record its start time.
    # Reference: https://www.gnu.org/software/coreutils/manual/
    echo "========================================"
    echo "Troubleshooting started: $(date)"
    echo "Hostname: $(hostname)"
    echo

    # Display network interfaces and assigned IP addresses.
    # Reference: https://man7.org/linux/man-pages/man8/ip-address.8.html
    echo "=== Network Interfaces ==="
    ip -br addr
    echo

    # Display the IPv4 routing table and default gateway.
    # Reference: https://man7.org/linux/man-pages/man8/ip-route.8.html
    echo "=== IPv4 Routing Table ==="
    ip -4 route
    echo

    # Test connectivity to the external IP address 1.1.1.1.
    # Send four packets and allow a two-second reply timeout.
    # Reference: https://man7.org/linux/man-pages/man8/ping.8.html
    echo "=== Internet Connectivity ==="
    ping -c 4 -W 2 1.1.1.1
    echo

    # Check whether DNS can resolve google.com to IPv4 addresses.
    # Reference: https://man7.org/linux/man-pages/man1/getent.1.html
    echo "=== DNS Resolution ==="
    getent ahostsv4 google.com
    echo

    # Display the system's DNS resolver configuration.
    # Reference: https://man7.org/linux/man-pages/man5/resolv.conf.5.html
    echo "=== DNS Configuration ==="
    cat /etc/resolv.conf
    echo

    # Check for failed systemd units.
    # Reference: https://www.freedesktop.org/software/systemd/man/latest/systemctl.html
    echo "=== Failed Systemd Units ==="
    systemctl --failed --no-pager
    echo

    # Verify filesystem entries in /etc/fstab.
    # Some checks may produce permission warnings for regular users.
    # Reference: https://man7.org/linux/man-pages/man8/findmnt.8.html
    echo "=== Filesystem Verification ==="
    findmnt --verify --tab-file /etc/fstab
    echo

    # Record the completion time of this troubleshooting run.
    # Reference: https://www.gnu.org/software/coreutils/manual/
    echo "Troubleshooting finished: $(date)"
    echo "========================================"

# Append standard output and errors to the log file.
# Reference: https://www.gnu.org/software/bash/manual/
} >> "$LOGFILE" 2>&1

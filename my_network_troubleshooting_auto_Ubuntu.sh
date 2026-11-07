#!/bin/bash
# CIS-245 - Linux Administration
# Automated Network Troubleshooting - Ubuntu Server
# Purpose: Collect network and system diagnostics without user input.
# Designed for scheduled execution through cron.
# Bash reference: https://www.gnu.org/software/bash/manual/

# Save results in the current user's home directory.
# Bash variables and output redirection: https://www.gnu.org/software/bash/manual/
LOGFILE="$HOME/my_network_troubleshooting_auto.log"

{
    # Record when the test started and identify the server.
    # date, hostname and echo: https://www.gnu.org/software/coreutils/manual/
    echo "========================================"
    echo "Troubleshooting started: $(date)"
    echo "Hostname: $(hostname)"
    echo

    # Show network interfaces and their assigned addresses.
    # Reference: https://man7.org/linux/man-pages/man8/ip-address.8.html
    echo "=== Network Interfaces ==="
    ip -br addr
    echo

    # Show the IPv4 routes, including the default gateway.
    # Reference: https://man7.org/linux/man-pages/man8/ip-route.8.html
    echo "=== IPv4 Routing Table ==="
    ip -4 route
    echo

    # Test connectivity using four ICMP packets with a two-second timeout.
    # Reference: https://man7.org/linux/man-pages/man8/ping.8.html
    echo "=== Internet Connectivity ==="
    ping -c 4 -W 2 1.1.1.1
    echo

    # Check IPv4 name resolution for google.com.
    # Reference: https://man7.org/linux/man-pages/man1/getent.1.html
    echo "=== DNS Resolution ==="
    getent ahostsv4 google.com
    echo

    # Display the DNS resolver configuration.
    # Reference: https://man7.org/linux/man-pages/man5/resolv.conf.5.html
    # cat reference: https://www.gnu.org/software/coreutils/manual/
    echo "=== DNS Configuration ==="
    cat /etc/resolv.conf
    echo

    # List any failed systemd units.
    # Reference: https://www.freedesktop.org/software/systemd/man/latest/systemctl.html
    echo "=== Failed Systemd Units ==="
    systemctl --failed --no-pager
    echo

    # Verify /etc/fstab; some checks may warn about user permissions.
    # Reference: https://man7.org/linux/man-pages/man8/findmnt.8.html
    echo "=== Filesystem Verification ==="
    findmnt --verify --tab-file /etc/fstab
    echo

    # Record when the test finished.
    # date and echo reference: https://www.gnu.org/software/coreutils/manual/
    echo "Troubleshooting finished: $(date)"
    echo "========================================"

# Append normal output and errors to the log file.
# Bash redirection reference: https://www.gnu.org/software/bash/manual/
} >> "$LOGFILE" 2>&1

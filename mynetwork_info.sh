#!/bin/bash

# CIS-245 - Week 5 Networking Lab (Linux Administrator)
# Script: mynetwork_info.sh
# Author: Ruddy Tavarez
# Purpose: Display Linux system and network information on the terminal and save it to a report file.
# Compatible with: CentOS Stream 10 and Ubuntu Server 26.04 LTS

# Variables for the network information report
CURRENT_USER=$(whoami)
HOSTNAME=$(hostname)
REPORT_DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Save the report in the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="${SCRIPT_DIR}/${REPORT_DATE}_${CURRENT_USER}_mynetwork_info.txt"


# Display output on screen and save it to the report
exec > >(tee "$REPORT_FILE") 2>&1

# Report header
echo "==============================================================="
echo "			CIS-245 NETWORK INFORMATION"
echo "==============================================================="
echo "Date: $(date)"
echo "User: $CURRENT_USER"
echo "Hostname: $HOSTNAME"
echo "Report File: $REPORT_FILE"
echo "==============================================================="
echo

# Display operating system information
echo "============OPERATING SYSTEM ============"
echo "Command: cat /etc/os-release"
cat /etc/os-release
echo

# Display kernel and system information
echo "============SYSTEM INFORMATION==========="
echo "Command: uname -a"
uname -a
echo

# Display network interfaces and assigned IP addresses
echo "============NETWORK INTERFACES==========="
echo "Command: ip addr"
ip addr
echo

# Display IPv4 routing information and default gateway
echo "============ IPv4 ROUTING TABLE =========="
echo "Command: ip -4 route"
ip -4 route
echo

# Display DNS resolver configuration
echo "============ DNS CONFIGURATION ==========="
echo "Command: cat /etc/resolv.conf"
cat /etc/resolv.conf
echo

# display active DNS resolver information when available
echo "============ ACTIVE DNS SERVERS =========="
if systemctl is-active --quit systemd-resolved; then
    echo "Command: resolvectl status"
    resolvectl status
else
    echo "systemd-resolved is not active on this system."
    echo "DNS resolver configuration is shown in /etc/resolv.conf."
fi
echo

# Display network interface operational status
echo "============ NETWORK LINK STATUS ========="
echo "Command: ip -br link"
ip -br link
echo

# Test connectivity to the default gateway
echo "============ DEFAULT GATEWAY CONNECTIVITY ============="
echo "Command: ping -c 4 10.0.2.2"
ping -c 4 10.0.2.2
echo

# Test Internet connectivity and DNS name resolution
echo "============ INTERNET AND DNS CONNECTIVITY ============"
echo "Command: ping -c 4 google.com"
ping -c 4 google.com
echo

# Test connectivity to the other Linux server
echo "============ INTERNAL NETWORK CONNECTIVITY ============"
if [ "$HOSTNAME" = "cis245-centos" ]; then
   TARGET_IP="192.168.50.20"
else
   TARGET_IP="192.168.50.10"
fi
echo "Command: ping -c 4 $TARGET_IP"
ping -c 4 "$TARGET_IP"
echo

# Display report completion information
echo "========================================================"
echo "NETWORK INFORMATION REPORT COMPLETED"
echo "Completed: $(date)"
echo "Report saved to: $REPORT_FILE"
echo "========================================================"



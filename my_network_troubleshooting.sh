#!/bin/bash

# CIS-245 – Linux Administrator – Networking Lab
# Script: my_network_troubleshooting.sh
# Author: Ruddy Tavarez ®
# Purpose: Interactive Linux network troubleshooting
# Supported systems: CentOS Stream 10 and Ubuntu Server 26.04 LTS

# Pause after each diagnostic so the administrator can review results.
pause_menu() {
    echo
    read -rp "Press Enter to return to the troubleshooting menu..." _
}

# Reject empty, option-like, or whitespace-containing targets.
valid_target() {
    [[ -n "$1" && "$1" != -* && ! "$1" =~ [[:space:]] ]]
}

# Identify the default IPv4 gateway, if one is configured.
get_gateway() {
    ip -4 route show default | awk 'NR == 1 {print $3}'
}

# Option 1: Ping a host or IP address.
ping_host() {
    echo
    echo "========== PING A HOST OR IP ADDRESS =========="
    read -rp "Enter a hostname or IP address: " TARGET

    if ! valid_target "$TARGET"; then
        echo "Invalid destination. Enter one hostname or IP address."
        return
    fi

    echo "Command: ping -c 4 -- $TARGET"
    if ping -c 4 -- "$TARGET"; then
        echo "Result: At least one ICMP echo reply was received."
    else
        echo "Result: Ping did not succeed. Check routing, DNS, and firewall settings."
        echo "Note: Some reachable systems block ICMP echo requests."
    fi
}

# Option 2: Trace the route to a host or IP address.
trace_network_route() {
    echo
    echo "========== TRACE NETWORK ROUTE =========="
    read -rp "Enter a hostname or IP address: " TARGET

    if ! valid_target "$TARGET"; then
        echo "Invalid destination. Enter one hostname or IP address."
        return
    fi

    if command -v tracepath >/dev/null 2>&1; then
        echo "Command: tracepath $TARGET"
        tracepath "$TARGET"
    elif command -v traceroute >/dev/null 2>&1; then
        echo "Command: traceroute -m 15 -w 1 $TARGET"
        traceroute -m 15 -w 1 "$TARGET"
    else
        echo "Neither tracepath nor traceroute is installed."
        if [[ "$OS_CHOICE" == "1" ]]; then
            echo "CentOS: sudo dnf install traceroute"
        else
            echo "Ubuntu: sudo apt update && sudo apt install traceroute"
        fi
    fi
    echo "Note: Firewalls may hide intermediate hops."
}

# Option 3: Check interfaces, routes, gateway, and Internet access.
troubleshoot_internet() {
    echo
    echo "========== NO INTERNET CONNECTIVITY =========="
    echo
    echo "STEP 1: Check network interface addresses"
    echo "Command: ip -br addr"
    ip -br addr

    echo
    echo "STEP 2: Check IPv4 routing"
    echo "Command: ip -4 route"
    ip -4 route

    echo
    echo "STEP 3: Test the default gateway"
    local gateway
    gateway=$(get_gateway)
    if [[ -n "$gateway" ]]; then
        echo "Command: ping -c 4 $gateway"
        ping -c 4 "$gateway"
    else
        echo "No default IPv4 gateway was found. Check network configuration."
    fi

    echo
    echo "STEP 4: Test a public IP address (does not require DNS)"
    echo "Command: ping -c 4 1.1.1.1"
    ping -c 4 1.1.1.1

    echo
    echo "STEP 5: Test a hostname (requires DNS)"
    echo "Command: ping -c 4 google.com"
    ping -c 4 google.com

    echo
    echo "STEP 6: Check distribution-specific network management"
    if [[ "$OS_CHOICE" == "1" ]]; then
        if command -v nmcli >/dev/null 2>&1; then
            echo "Command: nmcli device status"
            nmcli device status
        else
            echo "NetworkManager's nmcli command is unavailable."
        fi
    else
        if command -v networkctl >/dev/null 2>&1; then
            echo "Command: networkctl list --no-pager"
            networkctl list --no-pager
        else
            echo "networkctl is unavailable."
        fi
    fi

    echo
    echo "Guidance: Check interface status, IP address, subnet, and gateway."
    echo "If the public IP responds but the hostname fails, investigate DNS."
    echo "A failed ping does not always prove that a destination is offline."
}

# Option 4: Inspect static IPv4 configuration without modifying it.
troubleshoot_static_ip() {
    echo
    echo "========== STATIC IP CONFIGURATION =========="
    echo
    echo "STEP 1: Display IPv4 addresses and subnet prefixes"
    echo "Command: ip -4 addr"
    ip -4 addr

    echo
    echo "STEP 2: Display IPv4 routes and default gateway"
    echo "Command: ip -4 route"
    ip -4 route

    echo
    echo "STEP 3: Display interface link status"
    echo "Command: ip -br link"
    ip -br link

    echo
    echo "STEP 4: Inspect distribution-specific configuration"
    if [[ "$OS_CHOICE" == "1" ]]; then
        echo "CentOS Stream 10: NetworkManager"
        if command -v nmcli >/dev/null 2>&1; then
            echo "Command: nmcli connection show"
            nmcli connection show
            echo "To inspect a connection: nmcli connection show 'CONNECTION_NAME'"
        else
            echo "nmcli is unavailable."
        fi
    else
        echo "Ubuntu Server 26.04 LTS: Netplan"
        echo "Command: ls -l /etc/netplan/"
        ls -l /etc/netplan/
        echo "Review the relevant YAML file with: sudo cat /etc/netplan/FILE.yaml"
        echo "To test a future change safely: sudo netplan try"
    fi

    echo
    echo "Guidance: Verify IP address, subnet prefix, gateway, and interface."
    echo "The CentOS and Ubuntu internal-network addresses must be in"
    echo "the same subnet to communicate directly in this lab."
    echo "This function makes no configuration changes."
}

# Option 5: Examine DNS configuration and test name resolution.
troubleshoot_dns() {
    echo
    echo "========== DNS RESOLUTION =========="
    echo
    echo "STEP 1: Show resolver configuration"
    echo "Command: cat /etc/resolv.conf"
    cat /etc/resolv.conf

    echo
    echo "STEP 2: Show active DNS resolver details when available"
    if command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet systemd-resolved &&
       command -v resolvectl >/dev/null 2>&1; then
        echo "Command: resolvectl status"
        resolvectl status
    else
        echo "systemd-resolved is not active or resolvectl is unavailable."
        echo "Consult /etc/resolv.conf and network management settings."
    fi

    echo
    echo "STEP 3: Test connectivity to a public IP address"
    echo "Command: ping -c 4 1.1.1.1"
    ping -c 4 1.1.1.1

    echo
    echo "STEP 4: Test hostname resolution"
    if command -v getent >/dev/null 2>&1; then
        echo "Command: getent ahostsv4 google.com"
        getent ahostsv4 google.com
    else
        echo "getent is unavailable."
    fi

    echo
    echo "STEP 5: Test connectivity using a hostname"
    echo "Command: ping -c 4 google.com"
    ping -c 4 google.com

    echo
    if [[ "$OS_CHOICE" == "1" ]]; then
        echo "CentOS: Check DNS settings in NetworkManager connections."
    else
        echo "Ubuntu: Check nameservers in Netplan and resolvectl status."
    fi
    echo "If IP access works but name resolution fails, DNS is a likely cause."
}

# Original operating-system selection menu.
echo "=========================================="
echo "      LINUX NETWORK TROUBLESHOOTING ®"
echo "=========================================="
echo
echo "Select your Linux operating system:"
echo "1) CentOS Stream 10"
echo "2) Ubuntu Server 26.04 LTS"
echo "3) Exit"
echo

read -rp "Enter your choice [1-3]: " OS_CHOICE

case "$OS_CHOICE" in
    1)
        OS_NAME="CentOS Stream 10"
        ;;
    2)
        OS_NAME="Ubuntu Server 26.04 LTS"
        ;;
    3)
        echo "Exiting the troubleshooting utility."
        exit 0
        ;;
    *)
        echo "Invalid selection. Please restart the script."
        exit 1
        ;;
esac

echo
echo "Selected operating system: $OS_NAME"

# The troubleshooting menu repeats until Exit is selected.
while true; do
    echo
    echo "============================================="
    echo "         NETWORK TROUBLESHOOTING MENU ®"
    echo "============================================="
    echo "1) Ping a host or IP address"
    echo "2) Trace network route"
    echo "3) Troubleshoot no Internet connectivity"
    echo "4) Troubleshoot static IP configuration"
    echo "5) Troubleshoot DNS resolution"
    echo "6) Exit"
    echo

    read -rp "Select a troubleshooting option [1-6]: " TROUBLE_CHOICE

    case "$TROUBLE_CHOICE" in
        1)
            ping_host
            pause_menu
            ;;
        2)
            trace_network_route
            pause_menu
            ;;
        3)
            troubleshoot_internet
            pause_menu
            ;;
        4)
            troubleshoot_static_ip
            pause_menu
            ;;
        5)
            troubleshoot_dns
            pause_menu
            ;;
        6)
            echo "Exiting the troubleshooting utility."
            exit 0
            ;;
        *)
            echo "Invalid selection. Please enter a number from 1 to 6."
            pause_menu
            ;;
    esac
done

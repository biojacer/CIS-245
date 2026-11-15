#!/bin/bash
# ===================================================
# Server Health Monitoring Script by me Ruddy Tavarez
# Checks CPU, memory, disk usage, and network reachability.
# Writes the report title, current date, and separator lines.
# ===================================================
# Global variables ?
LOGFILE="$HOME/server_health.log"
CPU_THRESHOLD=85
MEMORY_THRESHOLD=85
DISK_THRESHOLD=85

# Writes the report title, current date, and separator lines.
function headerWriter() {
{   
    echo "--------------------------------------"
    echo "Server Health Report - $(date)" 
    echo "--------------------------------------"
} >> "$LOGFILE"

}

# Calculates current CPU usage and checks it against the configured threshold.
function checkCPU() {
    echo "Checking CPU usage..." >> "$LOGFILE"

    cpu_usage=$(top -bn1 | grep "Cpu(s)" | \
        awk -F',' '{
            for (i = 1; i <= NF; i++) {
                if ($i ~ /[[:space:]]id[[:space:]]*$/) {
                    value = $i
                    sub(/^[[:space:]]*/, "", value)
                    split(value, parts, /[[:space:]]+/)
                    printf "%.1f\n", 100 - parts[1]
                }
            }
        
        }')
        echo "CPU Usage: ${cpu_usage}%" >> "$LOGFILE"
        if awk -v usage="$cpu_usage" -v threshold="$CPU_THRESHOLD" 'BEGIN {exit !(usage > threshold)}'; then
    echo "WARNING: CPU usage exceeds ${CPU_THRESHOLD}%." >> "$LOGFILE"
else
    echo "CPU usage is within the configured threshold." >> "$LOGFILE"
fi

    echo "" >> "$LOGFILE"
}
# Calculates memory usage and checks it against the configured threshold.
function checkMemory() {
    echo "Checking memory usage..." >> "$LOGFILE"
    mem=$(free -m | grep Mem | awk '{print $3}')
    total=$(free -m | grep Mem | awk '{print $2}')
    perc=$(awk "BEGIN {printf \"%.2f\",($mem/$total)*100}")
    echo "Memory Usage: ${perc}%" >> "$LOGFILE"
    if awk -v usage="$perc" -v threshold="$MEMORY_THRESHOLD" 'BEGIN {exit !(usage > threshold)}'; then
        echo "WARNING: Memory usage exceeds ${MEMORY_THRESHOLD}%." >> "$LOGFILE"
    else
        echo "Memory usage is within the configured threshold." >> "$LOGFILE"
    fi
    echo "" >> "$LOGFILE"
}

# Checks filesystem disk usage and compares it with the configured threshold.
function checkDisk() {
   {
    echo "Checking disk usage..."
        df -P | awk -v threshold="$DISK_THRESHOLD" '
    NR > 1 && $1 ~ /^\// {
        usage = $5
        sub(/%/, "", usage)
        print "Disk:", $1, "Used:", usage "%"
        if (usage > threshold)
            print "WARNING: Disk usage exceeds " threshold "%."
        else
            print "Disk usage is within the configured threshold."
    }
'
    echo ""
} >> "$LOGFILE"
}

# Tests network reachability using two external IP addresses.
function checkNetwork() {
    echo "Checking network reachability using two external IP addresses..." >> "$LOGFILE"
    if ping -c 1 -W 2 1.1.1.1 > /dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        echo "Network check: SUCCESS - At least one external IP address responded to ping." >> "$LOGFILE"
    else
        echo "Network check: WARNING - Neither external IP address responded to ping. Network connectivity could not be confirmed." >> "$LOGFILE"
    fi
    echo "" >> "$LOGFILE"
}

# Displays the completed server health report in the terminal.
function summarize() {
    echo "End of server health report." >> "$LOGFILE"
    cat "$LOGFILE"
}

# Runs the server health checks and generates the final report.
function main() {
	: > "$LOGFILE"
    echo "Starting server health checks..." >> "$LOGFILE"
    headerWriter
    checkCPU
    checkMemory
    checkDisk
    checkNetwork
    summarize
    echo "Server health check completed." >> "$LOGFILE"
}

# Executes the main function to start the health checks.
main
exit 0


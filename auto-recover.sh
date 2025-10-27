#!/bin/bash
#
# Cellular Auto-Recovery Daemon
#
# Monitors cellular connection and automatically recovers when it drops
# Runs continuously and reconnects on failure
#
# Usage: sudo ./auto-recover.sh [interval_seconds]
#        Default interval: 30 seconds
#
# To run as daemon:
# sudo nohup ~/speedcam/cellular/auto-recover.sh 30 > ~/speedcam/cellular/auto-recover.log 2>&1 &
#
# To monitor the log:
# tail -f ~/speedcam/cellular/auto-recover.log
#
# To stop daemon:
# sudo pkill -f auto-recover.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] $1"
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN ] $1"
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Get interval from argument or use default
INTERVAL=${1:-30}

# Determine log directory dynamically
# Priority: CELLULAR_LOG_DIR env var > script directory > /var/log/cellular
if [[ -n "$CELLULAR_LOG_DIR" ]]; then
    LOG_DIR="$CELLULAR_LOG_DIR"
elif [[ -w "$(dirname "${BASH_SOURCE[0]}")" ]]; then
    LOG_DIR="$(dirname "${BASH_SOURCE[0]}")"
else
    LOG_DIR="/var/log/cellular"
fi

LOG_FILE="$LOG_DIR/auto-recover.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Write startup message
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] Starting cellular auto-recovery daemon"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] Check interval: ${INTERVAL}s"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] PID: $$"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] Log file: $LOG_FILE"
    echo ""
} | tee -a "$LOG_FILE"

log_info "Starting cellular auto-recovery daemon"
log_info "Check interval: ${INTERVAL}s"
log_info "Press Ctrl+C to stop"
log_info "Log file: $LOG_FILE"
log_info "PID: $$"
echo ""

# Get modem and bearer IDs
get_ids() {
    MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
    if [[ -z "$MODEM_ID" ]]; then
        return 1
    fi
    BEARER_ID=$((MODEM_ID + 1))
    return 0
}

# Check if bearer is connected
is_bearer_connected() {
    if mmcli -b $BEARER_ID &>/dev/null; then
        CONNECTED=$(mmcli -b $BEARER_ID 2>/dev/null | grep -i "connected:" | awk '{print $NF}')
        if [[ "$CONNECTED" == "yes" ]]; then
            return 0  # Connected
        fi
    fi
    return 1  # Not connected
}

# Check if interface has IP
has_interface_ip() {
    if ip addr show wwan0 2>/dev/null | grep -q "inet "; then
        return 0  # Has IP
    fi
    return 1  # No IP
}

# Reconnect bearer
reconnect_bearer() {
    log_warn "Attempting to reconnect bearer..."
    
    # Disconnect if connected
    if mmcli -b $BEARER_ID &>/dev/null; then
        mmcli -b $BEARER_ID --disconnect 2>/dev/null || true
        sleep 2
    fi
    
    # Try to connect
    if mmcli -b $BEARER_ID --connect 2>/dev/null; then
        log_info "✓ Bearer reconnected"
        sleep 2
        return 0
    else
        log_error "Failed to reconnect bearer"
        return 1
    fi
}

# Recreate bearer
recreate_bearer() {
    log_warn "Recreating bearer..."
    
    # Disconnect existing bearer
    if mmcli -b $BEARER_ID &>/dev/null; then
        mmcli -b $BEARER_ID --disconnect 2>/dev/null || true
        sleep 1
    fi
    
    # Create new bearer
    BEARER_OUTPUT=$(mmcli -m $MODEM_ID --create-bearer="apn=ereseller,ip-type=ipv4v6" 2>&1)
    if [[ $? -eq 0 ]]; then
        NEW_BEARER_ID=$(echo "$BEARER_OUTPUT" | grep -oP 'Bearer/\K[0-9]+' | head -1)
        if [[ -n "$NEW_BEARER_ID" ]]; then
            BEARER_ID=$NEW_BEARER_ID
            log_info "✓ New bearer created: $BEARER_ID"
            sleep 2
            
            # Connect new bearer
            if mmcli -b $BEARER_ID --connect 2>/dev/null; then
                log_info "✓ New bearer connected"
                sleep 2
                return 0
            fi
        fi
    fi
    
    log_error "Failed to recreate bearer"
    return 1
}

# Configure interface
configure_interface() {
    log_info "Configuring interface..."
    
    # Get IP config from bearer
    MMCLI_OUTPUT=$(mmcli -b $BEARER_ID)
    
    IPV4_ADDRESS=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "address:" | head -1 | awk '{print $NF}')
    IPV4_PREFIX=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "prefix:" | head -1 | awk '{print $NF}')
    GATEWAY=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "gateway:" | head -1 | awk '{print $NF}')
    
    if [[ -z "$IPV4_ADDRESS" ]] || [[ -z "$IPV4_PREFIX" ]] || [[ -z "$GATEWAY" ]]; then
        log_error "Failed to get IP configuration"
        return 1
    fi
    
    # Bring up interface
    ip link set wwan0 up 2>/dev/null || true
    sleep 1
    
    # Flush existing IPs
    ip addr flush dev wwan0 2>/dev/null || true
    sleep 1
    
    # Add IP address
    if ip addr add "$IPV4_ADDRESS/$IPV4_PREFIX" dev wwan0 2>/dev/null; then
        log_info "✓ IP configured: $IPV4_ADDRESS/$IPV4_PREFIX"
    else
        log_warn "Could not add IP address"
    fi
    
    sleep 1
    
    # Flush existing routes
    ip route flush dev wwan0 2>/dev/null || true
    sleep 1
    
    # Add subnet route first (required before default route)
    # Calculate subnet from IP and prefix
    IFS='.' read -r a b c d <<< "$IPV4_ADDRESS"
    SUBNET_NETWORK="$a.$b.$c.$((d & 252))"  # /30 means last 2 bits are host bits
    SUBNET_ROUTE="$SUBNET_NETWORK/$IPV4_PREFIX"
    
    if ! ip route add "$SUBNET_ROUTE" dev wwan0 2>/dev/null; then
        :  # Subnet route may already exist, that's ok
    fi
    
    sleep 1
    
    # Add default route (remove conflicting routes first if needed)
    # Try to add route, if it fails due to existing route, replace it
    if ! ip route add default via $GATEWAY dev wwan0 2>/dev/null; then
        # Route add failed, try to replace existing default route
        if ip route replace default via $GATEWAY dev wwan0 2>/dev/null; then
            log_info "✓ Route replaced: via $GATEWAY"
        else
            log_warn "Could not add or replace route"
        fi
    else
        log_info "✓ Route configured: via $GATEWAY"
    fi
    
    # Configure DNS
    IPV4_DNS_RAW=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "dns:" | head -1 | sed 's/.*dns:[[:space:]]*//')
    IPV4_DNS=$(echo "$IPV4_DNS_RAW" | awk -F',' '{print $1}' | xargs)
    
    if [[ -z "$IPV4_DNS" ]]; then
        IPV4_DNS="8.8.8.8"
    fi
    
    # Check if systemd-resolved is running
    if systemctl is-active --quiet systemd-resolved; then
        # Configure via resolvectl
        resolvectl dns wwan0 "" 2>/dev/null || true
        if resolvectl dns wwan0 $IPV4_DNS 2>/dev/null; then
            log_info "✓ DNS configured: $IPV4_DNS"
        fi
    else
        # Configure /etc/resolv.conf directly
        if echo "nameserver $IPV4_DNS" > /etc/resolv.conf 2>/dev/null; then
            log_info "✓ DNS configured: $IPV4_DNS"
        fi
    fi
    
    sleep 1
    
    # Verify routes exist
    log_info "Checking routes for wwan0..."
    CURRENT_ROUTES=$(ip route show dev wwan0)
    log_info "Current routes: $CURRENT_ROUTES"
    
    if ! echo "$CURRENT_ROUTES" | grep -q "default"; then
        log_warn "⚠ Default route MISSING on wwan0, reconfiguring routes..."
        log_warn "IP: $IPV4_ADDRESS, Prefix: $IPV4_PREFIX, Gateway: $GATEWAY"
        
        # Recalculate subnet route based on prefix length
        IFS='.' read -r a b c d <<< "$IPV4_ADDRESS"
        
        # Calculate network mask based on prefix
        # /24 = 255.255.255.0 (mask 0)
        # /25 = 255.255.255.128 (mask 128)
        # /26 = 255.255.255.192 (mask 192)
        # /27 = 255.255.255.224 (mask 224)
        # /28 = 255.255.255.240 (mask 240)
        # /29 = 255.255.255.248 (mask 248)
        # /30 = 255.255.255.252 (mask 252)
        case $IPV4_PREFIX in
            24) MASK=0 ;;
            25) MASK=128 ;;
            26) MASK=192 ;;
            27) MASK=224 ;;
            28) MASK=240 ;;
            29) MASK=248 ;;
            30) MASK=252 ;;
            31) MASK=254 ;;
            32) MASK=255 ;;
            *) MASK=0 ;;  # Default for unknown prefix
        esac
        
        SUBNET_NETWORK="$a.$b.$c.$((d & MASK))"
        SUBNET_ROUTE="$SUBNET_NETWORK/$IPV4_PREFIX"
        
        log_warn "Calculated subnet route: $SUBNET_ROUTE (prefix /$IPV4_PREFIX, mask $MASK)"
        
        # Add subnet route
        log_warn "Adding subnet route: $SUBNET_ROUTE dev wwan0"
        if ip route add "$SUBNET_ROUTE" dev wwan0 2>&1; then
            log_info "✓ Subnet route added"
        else
            log_warn "Subnet route may already exist"
        fi
        
        sleep 1
        
        # Add default route
        log_warn "Adding default route via $GATEWAY dev wwan0"
        if ip route add default via $GATEWAY dev wwan0 2>&1; then
            log_info "✓ Default route added"
        else
            log_warn "Route add failed, attempting replace..."
            if ip route replace default via $GATEWAY dev wwan0 2>&1; then
                log_info "✓ Default route replaced"
            else
                log_error "✗ Failed to add or replace default route"
                log_error "Current routes after attempt:"
                ip route show dev wwan0 || true
            fi
        fi
        
        sleep 1
        
        # Verify routes were added
        ROUTES_AFTER=$(ip route show dev wwan0)
        log_info "Routes after reconfiguration: $ROUTES_AFTER"
        
        if echo "$ROUTES_AFTER" | grep -q "default"; then
            log_info "✓ Default route now present"
        else
            log_error "✗ Default route still missing after reconfiguration!"
        fi
    else
        log_info "✓ Routes OK"
    fi
    
    # Verify connectivity
    if ping -c 1 -I wwan0 -W 5 8.8.8.8 &>/dev/null; then
        log_info "✓ Connectivity verified"
        return 0
    else
        log_warn "Connectivity test failed"
        return 1
    fi
}

# Main loop
trap 'log_info "Stopping auto-recovery daemon"; exit 0' SIGINT SIGTERM

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get IDs
    if ! get_ids; then
        log_error "No modem found"
        sleep $INTERVAL
        continue
    fi
    
    # Check bearer status
    BEARER_CONNECTED=$(is_bearer_connected && echo "yes" || echo "no")
    HAS_IP=$(has_interface_ip && echo "yes" || echo "no")
    
    if is_bearer_connected && has_interface_ip; then
        # Check if routes are configured
        CURRENT_ROUTES=$(ip route show dev wwan0)
        
        if ! echo "$CURRENT_ROUTES" | grep -q "default"; then
            log_warn "⚠ Routes missing on wwan0, reconfiguring..."
            configure_interface
        fi
        
        # Check if DNS is configured
        if ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
            log_warn "⚠ DNS not configured, reconfiguring..."
            configure_interface
        fi
        
        # Test IP connectivity
        if ! ping -c 1 -I wwan0 -W 5 8.8.8.8 &>/dev/null; then
            log_warn "IP connectivity test failed, reconnecting..."
            reconnect_bearer
            configure_interface
        fi
        
        # Test DNS resolution using getent (available on all systems)
        DNS_OK=0
        
        # Try getent to resolve hostname
        if timeout 3 getent hosts google.com &>/dev/null; then
            DNS_OK=1
        fi
        
        # If getent failed, try ping (which does DNS lookup)
        if [[ $DNS_OK -eq 0 ]]; then
            if timeout 3 ping -c 1 -W 2 google.com &>/dev/null; then
                DNS_OK=1
            fi
        fi
        
        if [[ $DNS_OK -eq 0 ]]; then
            log_warn "⚠ DNS resolution failed"
            # Only reconfigure if we haven't tried recently
            LAST_DNS_FIX=$(stat -c %Y /etc/resolv.conf 2>/dev/null || echo 0)
            CURRENT_TIME=$(date +%s)
            TIME_SINCE_FIX=$((CURRENT_TIME - LAST_DNS_FIX))
            
            if [[ $TIME_SINCE_FIX -gt 120 ]]; then
                log_warn "DNS hasn't been fixed in ${TIME_SINCE_FIX}s, reconfiguring..."
                configure_interface
            fi
        fi
    else
        log_warn "⚠ Connection lost (bearer: $(is_bearer_connected && echo 'yes' || echo 'no'), IP: $(has_interface_ip && echo 'yes' || echo 'no'))"
        
        # Try simple reconnect first
        if reconnect_bearer; then
            configure_interface
        else
            # If that fails, recreate bearer
            if recreate_bearer; then
                configure_interface
            else
                log_error "Failed to recover connection, will retry in ${INTERVAL}s"
            fi
        fi
    fi
    
    sleep $INTERVAL
done

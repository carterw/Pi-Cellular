#!/bin/bash
#
# Recover Cellular Connection
#
# Reconnects to cellular network after signal loss or disconnection
#
# Usage: sudo ./recover-connection.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_section "CELLULAR CONNECTION RECOVERY"

# Get modem ID
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
if [[ -z "$MODEM_ID" ]]; then
    log_error "No modem found"
    exit 1
fi

BEARER_ID=$((MODEM_ID + 1))

log_info "Modem ID: $MODEM_ID"
log_info "Bearer ID: $BEARER_ID"

# Step 1: Check current signal
log_info ""
log_info "Step 1: Checking signal strength..."
SIGNAL=$(mmcli -m $MODEM_ID 2>/dev/null | grep -i "signal quality" | awk '{print $NF}')
log_info "Signal: $SIGNAL"

# Step 2: Check if bearer exists
log_info ""
log_info "Step 2: Checking bearer status..."
if mmcli -b $BEARER_ID &>/dev/null; then
    CONNECTED=$(mmcli -b $BEARER_ID 2>/dev/null | grep -i "connected:" | awk '{print $NF}')
    log_info "Bearer $BEARER_ID connected: $CONNECTED"
    
    if [[ "$CONNECTED" == "yes" ]]; then
        log_info "✓ Bearer is already connected"
        log_info "Checking interface..."
        
        if ip addr show wwan0 | grep -q "inet"; then
            log_info "✓ Interface has IP address"
            log_info "Connection is active!"
            exit 0
        else
            log_warn "Bearer connected but interface has no IP"
        fi
    else
        log_warn "Bearer exists but not connected, reconnecting..."
        if mmcli -b $BEARER_ID --connect; then
            log_info "✓ Bearer reconnected"
            sleep 2
        else
            log_warn "Failed to reconnect bearer, will recreate"
        fi
    fi
else
    log_warn "Bearer does not exist, will create new one"
fi

# Step 3: Disconnect existing bearer if needed
log_info ""
log_info "Step 3: Cleaning up old connections..."
if mmcli -b $BEARER_ID &>/dev/null; then
    log_info "Disconnecting bearer $BEARER_ID..."
    mmcli -b $BEARER_ID --disconnect 2>/dev/null || true
    sleep 2
fi

# Step 4: Disable modem
log_info ""
log_info "Step 4: Disabling modem..."
mmcli -m $MODEM_ID --disable
sleep 2
log_info "Modem disabled"

# Step 5: Enable modem
log_info ""
log_info "Step 5: Enabling modem..."
mmcli -m $MODEM_ID --enable
sleep 2
log_info "Modem enabled"

# Step 6: Create new bearer
log_info ""
log_info "Step 6: Creating bearer..."
BEARER_OUTPUT=$(mmcli -m $MODEM_ID --create-bearer="apn=ereseller,ip-type=ipv4v6" 2>&1)
if [[ $? -eq 0 ]]; then
    BEARER_ID=$(echo "$BEARER_OUTPUT" | grep -oP 'Bearer/\K[0-9]+' | head -1)
    if [[ -z "$BEARER_ID" ]]; then
        log_error "Bearer created but could not extract ID"
        exit 1
    fi
    log_info "✓ Bearer created: $BEARER_ID"
else
    log_error "Failed to create bearer"
    log_error "$BEARER_OUTPUT"
    exit 1
fi

sleep 2

# Step 7: Connect bearer
log_info ""
log_info "Step 7: Connecting bearer $BEARER_ID..."
if mmcli -b $BEARER_ID --connect; then
    log_info "✓ Bearer connected"
else
    log_error "Failed to connect bearer"
    exit 1
fi

sleep 2

# Step 8: Configure interface
log_info ""
log_info "Step 8: Configuring interface..."

# Bring up interface
if ip link set wwan0 up; then
    log_info "✓ Interface brought up"
else
    log_warn "Failed to bring up interface"
fi

sleep 1

# Get IP configuration from bearer
log_info "Retrieving IP configuration..."
MMCLI_OUTPUT=$(mmcli -b $BEARER_ID)

IPV4_ADDRESS=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "address:" | head -1 | awk '{print $NF}')
IPV4_PREFIX=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "prefix:" | head -1 | awk '{print $NF}')
GATEWAY=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "gateway:" | head -1 | awk '{print $NF}')

if [[ -z "$IPV4_ADDRESS" ]] || [[ -z "$IPV4_PREFIX" ]] || [[ -z "$GATEWAY" ]]; then
    log_error "Failed to retrieve IP configuration"
    exit 1
fi

log_info "IP: $IPV4_ADDRESS/$IPV4_PREFIX"
log_info "Gateway: $GATEWAY"

# Add IP address
if ip addr add "$IPV4_ADDRESS/$IPV4_PREFIX" dev wwan0 2>/dev/null; then
    log_info "✓ IP address configured"
else
    log_warn "IP address may already be configured"
fi

sleep 1

# Add default route
if ip route add default via $GATEWAY dev wwan0 2>/dev/null; then
    log_info "✓ Default route added"
else
    log_warn "Default route may already exist"
fi

sleep 1

# Step 9: Configure DNS
log_info ""
log_info "Step 9: Configuring DNS..."

IPV4_DNS_RAW=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "dns:" | head -1 | sed 's/.*dns:[[:space:]]*//')
IPV4_DNS=$(echo "$IPV4_DNS_RAW" | awk -F',' '{print $1}' | xargs)

IPV6_DNS_RAW=$(echo "$MMCLI_OUTPUT" | grep -A 10 "IPv6 configuration" | grep "dns:" | sed 's/.*dns:[[:space:]]*//')
IPV6_DNS=$(echo "$IPV6_DNS_RAW" | awk -F',' '{print $1}' | xargs)

if [[ -z "$IPV4_DNS" ]]; then
    IPV4_DNS="8.8.8.8"
    log_warn "Using default DNS: $IPV4_DNS"
fi

DNS_CONFIG="nameserver $IPV4_DNS"
if [[ -n "$IPV6_DNS" ]]; then
    DNS_CONFIG="$DNS_CONFIG"$'\n'"nameserver $IPV6_DNS"
fi

if echo -e "$DNS_CONFIG" > /etc/resolv.conf 2>/dev/null; then
    log_info "✓ DNS configured"
else
    log_warn "Failed to configure DNS"
fi

# Step 10: Verify connectivity
log_info ""
log_info "Step 10: Verifying connectivity..."
sleep 2

if ip addr show wwan0 | grep -q "$IPV4_ADDRESS"; then
    log_info "✓ Interface configured successfully"
else
    log_error "Interface configuration verification failed"
    exit 1
fi

# Test ping
if ping -c 1 -I wwan0 -W 5 8.8.8.8 &>/dev/null; then
    log_info "✓ Connectivity test PASSED"
else
    log_warn "Connectivity test FAILED"
fi

log_section "CONNECTION RECOVERED"

log_info "Cellular connection is now active!"
log_info ""
log_info "Interface: wwan0"
log_info "IP Address: $IPV4_ADDRESS/$IPV4_PREFIX"
log_info "Gateway: $GATEWAY"
log_info "DNS: $IPV4_DNS"
if [[ -n "$IPV6_DNS" ]]; then
    log_info "DNS (IPv6): $IPV6_DNS"
fi

exit 0

#!/bin/bash
#
# Setup DNS and Routes for Cellular
#
# Configures DNS and routes for wwan0 interface
# Useful when connect-cellular-dynamic.sh wasn't run or when WiFi is disabled
#
# Usage: sudo ./setup-dns-routes.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "Setting up DNS and routes for cellular..."

# Get modem ID
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
if [[ -z "$MODEM_ID" ]]; then
    log_error "No modem found"
    exit 1
fi

BEARER_ID=$((MODEM_ID + 1))

log_info "Modem ID: $MODEM_ID"
log_info "Bearer ID: $BEARER_ID"

# Step 1: Check if bearer is connected
log_info ""
log_info "Step 1: Checking bearer connection..."
if ! mmcli -b $BEARER_ID &>/dev/null; then
    log_error "Bearer $BEARER_ID not found"
    exit 1
fi

CONNECTED=$(mmcli -b $BEARER_ID 2>/dev/null | grep -i "connected:" | awk '{print $NF}')
if [[ "$CONNECTED" != "yes" ]]; then
    log_warn "Bearer is not connected, attempting to connect..."
    if mmcli -b $BEARER_ID --connect 2>/dev/null; then
        log_info "✓ Bearer connected"
        sleep 2
    else
        log_error "Failed to connect bearer"
        exit 1
    fi
fi

# Step 2: Get IP configuration
log_info ""
log_info "Step 2: Retrieving IP configuration..."
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

# Step 3: Configure routes
log_info ""
log_info "Step 3: Configuring routes..."

# Show current routes for debugging
log_info "Current IPv4 routes before configuration:"
ip route show || log_warn "No IPv4 routes found"

# Add IP address if not already present
if ! ip addr show wwan0 | grep -q "$IPV4_ADDRESS"; then
    log_info "Adding IP address..."
    ip addr add "$IPV4_ADDRESS/$IPV4_PREFIX" dev wwan0 2>/dev/null || log_warn "Could not add IP"
else
    log_info "IP address already configured"
fi

sleep 1

# Add subnet route first (this is required before adding default route)
# Calculate subnet from IP and prefix
IFS='.' read -r a b c d <<< "$IPV4_ADDRESS"

# Calculate network mask based on prefix length
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
    *) MASK=0 ;;
esac

SUBNET_NETWORK="$a.$b.$c.$((d & MASK))"
SUBNET_ROUTE="$SUBNET_NETWORK/$IPV4_PREFIX"

log_info "Calculating subnet from $IPV4_ADDRESS/$IPV4_PREFIX"
log_info "Adding subnet route: $SUBNET_ROUTE dev wwan0..."
if ! ip route add "$SUBNET_ROUTE" dev wwan0 2>/dev/null; then
    log_warn "Subnet route may already exist"
fi

sleep 1

# Remove any existing IPv4 default routes first (to avoid conflicts)
log_info "Removing conflicting IPv4 default routes..."
REMOVED_COUNT=0
while ip route del default 2>/dev/null; do
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
    log_info "Removed default route #$REMOVED_COUNT"
done

if [[ $REMOVED_COUNT -eq 0 ]]; then
    log_info "No conflicting default routes found"
fi

sleep 1

# Add default route
log_info "Adding default route via $GATEWAY..."
if ip route add default via $GATEWAY dev wwan0 2>/dev/null; then
    log_info "✓ Default route added: via $GATEWAY"
else
    log_error "Failed to add default route"
    log_error "Current routes:"
    ip route show || true
    exit 1
fi

sleep 1

# Verify route was added
log_info "Verifying route configuration..."
if ip route | grep -q "default.*wwan0"; then
    log_info "✓ Default route verified on wwan0"
else
    log_error "Default route not found on wwan0"
    log_error "Current routes:"
    ip route show || true
    exit 1
fi

# Step 4: Configure DNS
log_info ""
log_info "Step 4: Configuring DNS..."

IPV4_DNS_RAW=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "dns:" | head -1 | sed 's/.*dns:[[:space:]]*//')
IPV4_DNS=$(echo "$IPV4_DNS_RAW" | awk -F',' '{print $1}' | xargs)

if [[ -z "$IPV4_DNS" ]]; then
    IPV4_DNS="8.8.8.8"
    log_warn "Using default DNS: $IPV4_DNS"
else
    log_info "Using modem DNS: $IPV4_DNS"
fi

# Check if systemd-resolved is running
if systemctl is-active --quiet systemd-resolved; then
    log_info "systemd-resolved is running, configuring via resolvectl..."
    
    # Flush existing DNS for wwan0
    resolvectl dns wwan0 "" 2>/dev/null || true
    sleep 1
    
    # Set DNS for wwan0
    if resolvectl dns wwan0 $IPV4_DNS 2>/dev/null; then
        log_info "✓ DNS configured via resolvectl: $IPV4_DNS"
    else
        log_warn "Failed to configure DNS via resolvectl, trying /etc/resolv.conf"
        echo "nameserver $IPV4_DNS" > /etc/resolv.conf 2>/dev/null || log_warn "Failed to write /etc/resolv.conf"
    fi
else
    log_info "systemd-resolved not running, configuring /etc/resolv.conf..."
    
    # Write DNS directly
    if echo "nameserver $IPV4_DNS" > /etc/resolv.conf 2>/dev/null; then
        log_info "✓ DNS configured: $IPV4_DNS"
    else
        log_error "Failed to configure DNS"
        exit 1
    fi
fi

# Step 5: Verify
log_info ""
log_info "Step 5: Verifying configuration..."

# Check routes
if ip route show dev wwan0 | grep -q "default"; then
    log_info "✓ Routes configured"
else
    log_error "Routes not configured"
    exit 1
fi

# Check DNS
if grep -q "nameserver" /etc/resolv.conf; then
    log_info "✓ DNS configured"
else
    log_error "DNS not configured"
    exit 1
fi

# Test connectivity
if ping -c 1 -I wwan0 -W 5 8.8.8.8 &>/dev/null; then
    log_info "✓ Connectivity verified"
else
    log_warn "Connectivity test failed"
fi

log_info ""
log_info "DNS and routes configured successfully!"
log_info ""
log_info "Current configuration:"
ip addr show wwan0 | grep inet
echo ""
ip route show dev wwan0
echo ""
cat /etc/resolv.conf

exit 0

#!/bin/bash
#
# Dynamic Cellular Connection Script for SIMCOM SIM7600G-H on Raspberry Pi 4
# 
# This script automatically retrieves IP configuration from the modem
# instead of using hardcoded addresses, so it works after each reboot
# when the carrier assigns different IP addresses.
#
# Usage: sudo ./connect-cellular-dynamic.sh
#

set -e  # Exit on error

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/cellular-config.sh" ]]; then
    source "$SCRIPT_DIR/cellular-config.sh"
else
    echo "Error: cellular-config.sh not found in $SCRIPT_DIR"
    exit 1
fi

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

# Configuration (sourced from cellular-config.sh above)
# CELLULAR_APN, CELLULAR_IP_TYPE, CELLULAR_MTU, CELLULAR_INTERFACE are already set
TIMEOUT=30  # seconds to wait for connection
DEFAULT_DNS="8.8.8.8"  # Fallback only if modem doesn't provide DNS

# Auto-detect modem ID (handles re-enumeration after restart)
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
if [[ -z "$MODEM_ID" ]]; then
    log_error "No modem found. Check USB connection and ModemManager status."
    exit 1
fi

# Bearer ID will be detected after creation
BEARER_ID=""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "Starting cellular connection setup..."

# Step 1: Enable the modem
log_info "Step 1: Enabling modem $MODEM_ID..."
if mmcli -m $MODEM_ID --enable; then
    log_info "Modem enabled successfully"
else
    log_error "Failed to enable modem"
    exit 1
fi

sleep 2

# Step 2: Create bearer with APN
log_info "Step 2: Creating bearer with APN=$CELLULAR_APN, IP-Type=$CELLULAR_IP_TYPE..."
BEARER_OUTPUT=$(mmcli -m $MODEM_ID --create-bearer="apn=$CELLULAR_APN,ip-type=$CELLULAR_IP_TYPE" 2>&1)
if [[ $? -eq 0 ]]; then
    # Extract bearer ID from output like "/org/freedesktop/ModemManager1/Bearer/3"
    BEARER_ID=$(echo "$BEARER_OUTPUT" | grep -oP 'Bearer/\K[0-9]+' | head -1)
    if [[ -z "$BEARER_ID" ]]; then
        log_error "Bearer created but could not extract bearer ID"
        log_error "Output: $BEARER_OUTPUT"
        exit 1
    fi
    log_info "Bearer created successfully (bearer $BEARER_ID)"
else
    log_error "Failed to create bearer"
    log_error "Output: $BEARER_OUTPUT"
    exit 1
fi

sleep 2

# Step 3: Connect the bearer
log_info "Step 3: Connecting bearer $BEARER_ID..."
if mmcli -b $BEARER_ID --connect; then
    log_info "Bearer connected successfully"
else
    log_error "Failed to connect bearer"
    exit 1
fi

sleep 2

# Step 4: Bring up the interface
log_info "Step 4: Bringing up interface $CELLULAR_INTERFACE..."
if ip link set $CELLULAR_INTERFACE up; then
    log_info "Interface brought up"
else
    log_error "Failed to bring up interface"
    exit 1
fi

sleep 2

# Step 5: Retrieve IP configuration from modem
log_info "Step 5: Retrieving IP configuration from modem..."

# Parse mmcli output to extract IPv4 configuration
MMCLI_OUTPUT=$(mmcli -b $BEARER_ID)

# Extract IPv4 address and prefix
IPV4_ADDRESS=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "address:" | head -1 | awk '{print $NF}')
IPV4_PREFIX=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "prefix:" | head -1 | awk '{print $NF}')
GATEWAY=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "gateway:" | head -1 | awk '{print $NF}')

# Extract IPv4 DNS servers (may be comma-separated)
IPV4_DNS_RAW=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "dns:" | head -1 | sed 's/.*dns:[[:space:]]*//')
# Clean up whitespace and get first DNS server
IPV4_DNS=$(echo "$IPV4_DNS_RAW" | awk -F',' '{print $1}' | xargs)

# Extract IPv6 DNS servers (may be comma-separated)
IPV6_DNS_RAW=$(echo "$MMCLI_OUTPUT" | grep -A 10 "IPv6 configuration" | grep "dns:" | sed 's/.*dns:[[:space:]]*//')
# Clean up whitespace and get first DNS server
IPV6_DNS=$(echo "$IPV6_DNS_RAW" | awk -F',' '{print $1}' | xargs)

# Debug: Show raw extraction
if [[ -z "$IPV4_DNS" ]]; then
    log_warn "No IPv4 DNS extracted. Raw output:"
    echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" || true
fi

# Validate that we got the configuration
if [[ -z "$IPV4_ADDRESS" ]] || [[ -z "$IPV4_PREFIX" ]] || [[ -z "$GATEWAY" ]]; then
    log_error "Failed to retrieve IP configuration from modem"
    log_error "mmcli output:"
    echo "$MMCLI_OUTPUT"
    exit 1
fi

# Use default DNS if modem didn't provide IPv4 DNS or if it's a private IP
if [[ -z "$IPV4_DNS" ]] || [[ $IPV4_DNS =~ ^(172\.(1[6-9]|2[0-9]|3[01])|10\.|192\.168\.) ]]; then
    log_warn "Modem IPv4 DNS invalid or private, using default: $DEFAULT_DNS"
    IPV4_DNS=$DEFAULT_DNS
fi

# Validate IPv6 DNS - check if it's a private ULA (fc00::/7) or link-local (fe80::/10)
DEFAULT_IPV6_DNS="2001:4860:4860::8888"
if [[ -z "$IPV6_DNS" ]] || [[ $IPV6_DNS =~ ^(fc|fd|fe80) ]]; then
    if [[ -n "$IPV6_DNS" ]]; then
        log_warn "Modem IPv6 DNS invalid or private, using default: $DEFAULT_IPV6_DNS"
    fi
    IPV6_DNS=$DEFAULT_IPV6_DNS
fi

log_info "Retrieved configuration:"
log_info "  IPv4 Address: $IPV4_ADDRESS"
log_info "  Prefix: $IPV4_PREFIX"
log_info "  Gateway: $GATEWAY"
log_info "  IPv4 DNS: $IPV4_DNS"
if [[ -n "$IPV6_DNS" ]]; then
    log_info "  IPv6 DNS: $IPV6_DNS"
fi

# Step 6: Configure the interface with retrieved addresses
log_info "Step 6: Configuring interface with retrieved addresses..."

# Add IP address with prefix
if ip addr add "$IPV4_ADDRESS/$IPV4_PREFIX" dev $INTERFACE; then
    log_info "IP address configured: $IPV4_ADDRESS/$IPV4_PREFIX"
else
    log_warn "Failed to add IP address (may already be configured)"
fi

sleep 1

# Add default route via gateway
if ip route add default via $GATEWAY dev $INTERFACE 2>/dev/null; then
    log_info "Default route added: via $GATEWAY"
else
    log_warn "Default route may already exist"
fi

sleep 1

# Step 7: Configure MTU
log_info "Step 7: Setting MTU to $MTU..."
if ip link set mtu $MTU dev $INTERFACE; then
    log_info "MTU set to $MTU"
else
    log_warn "Failed to set MTU"
fi

# Step 8: Configure DNS
log_info "Step 8: Configuring DNS..."

# Debug: Show what we extracted
log_info "  Extracted IPv4 DNS: $IPV4_DNS"
log_info "  Extracted IPv6 DNS: $IPV6_DNS"

# Build resolv.conf with both IPv4 and IPv6 DNS servers
DNS_CONFIG="nameserver $IPV4_DNS"$'\n'"nameserver $IPV6_DNS"

# Check if NetworkManager is managing DNS
if systemctl is-active --quiet NetworkManager; then
    log_warn "NetworkManager is running and may override DNS settings"
    log_info "Attempting to configure DNS via nmcli..."
    
    # Try to set DNS via nmcli for the wwan0 connection
    if nmcli device set wwan0 autoconnect off 2>/dev/null; then
        log_info "Disabled autoconnect for wwan0"
    fi
fi

# Write DNS to /etc/resolv.conf (script already runs as root via sudo)
# Note: We don't make it immutable to allow WiFi DNS to work when cellular is not active
if echo -e "$DNS_CONFIG" > /etc/resolv.conf 2>/dev/null; then
    log_info "DNS configured:"
    log_info "  IPv4: $IPV4_DNS"
    if [[ -n "$IPV6_DNS" ]]; then
        log_info "  IPv6: $IPV6_DNS"
    fi
else
    # If direct write fails, try with explicit permissions
    if cat > /etc/resolv.conf << EOF 2>/dev/null
$DNS_CONFIG
EOF
    then
        log_info "DNS configured:"
        log_info "  IPv4: $IPV4_DNS"
        if [[ -n "$IPV6_DNS" ]]; then
            log_info "  IPv6: $IPV6_DNS"
        fi
    else
        log_warn "Failed to configure DNS (file may be managed by systemd-resolved or NetworkManager)"
        log_info "DNS may be managed by NetworkManager"
    fi
fi

# Step 9: Verify connectivity
log_info "Step 9: Verifying connectivity..."
sleep 2

if ip addr show $INTERFACE | grep -q "$IPV4_ADDRESS"; then
    log_info "Interface configured successfully"
else
    log_error "Interface configuration verification failed"
    exit 1
fi

# Test connectivity
if ping -c 1 -I $INTERFACE 8.8.8.8 &> /dev/null; then
    log_info "Connectivity test PASSED - can reach 8.8.8.8"
else
    log_warn "Connectivity test FAILED - cannot reach 8.8.8.8"
    log_info "This may be normal if external traffic is blocked by carrier"
fi

log_info ""
log_info "=========================================="
log_info "Cellular connection established!"
log_info "=========================================="
log_info "Interface: $INTERFACE"
log_info "IP Address: $IPV4_ADDRESS/$IPV4_PREFIX"
log_info "Gateway: $GATEWAY"
log_info "IPv4 DNS: $IPV4_DNS"
if [[ -n "$IPV6_DNS" ]]; then
    log_info "IPv6 DNS: $IPV6_DNS"
fi
log_info "MTU: $MTU"
log_info "=========================================="

# Show interface status
log_info ""
log_info "Interface status:"
ip addr show $INTERFACE
log_info ""
log_info "Route status:"
ip route show dev $INTERFACE
log_info ""
log_info "Modem status:"
mmcli -b $BEARER_ID | grep -E "(connected|IPv4|address|gateway|dns)"

exit 0

#!/bin/bash
#
# Robust Cellular Connection Script
#
# Handles various modem states and connection issues
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Get modem ID
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
if [[ -z "$MODEM_ID" ]]; then
    log_error "No modem found"
    exit 1
fi

BEARER_ID=$((MODEM_ID + 1))

log_section "ROBUST CELLULAR CONNECTION"
log_info "Modem ID: $MODEM_ID"
log_info "Bearer ID: $BEARER_ID"

# Step 1: Check current state
log_section "Step 1: Checking modem state"
MODEM_STATE=$(mmcli -m $MODEM_ID 2>/dev/null | grep "state:" | awk '{print $NF}')
log_info "Current state: $MODEM_STATE"

# Step 2: Enable modem if needed
log_section "Step 2: Ensuring modem is enabled"
if [[ "$MODEM_STATE" != "registered" ]] && [[ "$MODEM_STATE" != "connected" ]]; then
    log_info "Enabling modem..."
    if mmcli -m $MODEM_ID --enable 2>&1; then
        log_info "✓ Modem enabled"
    else
        log_warn "Enable command returned error, continuing..."
    fi
    
    sleep 3
    MODEM_STATE=$(mmcli -m $MODEM_ID 2>/dev/null | grep "state:" | awk '{print $NF}')
    log_info "New state: $MODEM_STATE"
fi

# Step 3: Wait for registration
log_section "Step 3: Waiting for network registration"
MODEM_STATE=$(mmcli -m $MODEM_ID 2>/dev/null | grep "state:" | head -1 | awk '{print $NF}')

if [[ "$MODEM_STATE" == "registered" ]] || [[ "$MODEM_STATE" == "connected" ]]; then
    log_info "✓ Modem already registered: $MODEM_STATE"
else
    log_warn "Modem state: $MODEM_STATE, waiting for registration..."
    for i in {1..30}; do
        MODEM_STATE=$(mmcli -m $MODEM_ID 2>/dev/null | grep "state:" | head -1 | awk '{print $NF}')
        
        if [[ "$MODEM_STATE" == "registered" ]] || [[ "$MODEM_STATE" == "connected" ]]; then
            log_info "✓ Modem registered: $MODEM_STATE"
            break
        fi
        
        if [[ $((i % 5)) -eq 0 ]]; then
            log_warn "Still waiting... ($i/30)"
        fi
        sleep 1
    done
fi

# Step 4: Check for existing bearers
log_section "Step 4: Checking for existing bearers"
EXISTING_BEARERS=$(mmcli -m $MODEM_ID 2>/dev/null | grep "bearer" | grep -oP "Bearer/\K[0-9]+" || true)

if [[ -n "$EXISTING_BEARERS" ]]; then
    log_warn "Found existing bearers: $EXISTING_BEARERS"
    for bearer in $EXISTING_BEARERS; do
        log_info "Disconnecting bearer $bearer..."
        mmcli -m $MODEM_ID --simple-disconnect 2>&1 || log_warn "Could not disconnect bearer $bearer"
    done
    sleep 2
fi

# Step 5: Create new bearer
log_section "Step 5: Creating bearer"
APN="ereseller"
log_info "Creating bearer with APN=$APN, IP-Type=ipv4v6..."

if mmcli -m $MODEM_ID --create-bearer="apn=$APN,ip-type=ipv4v6" 2>&1; then
    log_info "✓ Bearer created"
    sleep 2
else
    log_error "Failed to create bearer"
    exit 1
fi

# Step 6: Get new bearer ID
BEARER_ID=$(mmcli -m $MODEM_ID 2>/dev/null | grep -oP "Bearer/\K[0-9]+" | tail -1)
log_info "New bearer ID: $BEARER_ID"

# Step 7: Connect bearer
log_section "Step 6: Connecting bearer"
log_info "Connecting bearer $BEARER_ID..."

if mmcli -b $BEARER_ID --connect 2>&1; then
    log_info "✓ Bearer connected"
else
    log_error "Failed to connect bearer"
    log_error "Checking bearer status..."
    mmcli -b $BEARER_ID || true
    exit 1
fi

sleep 3

# Step 8: Verify connection
log_section "Step 7: Verifying connection"
BEARER_STATUS=$(mmcli -b $BEARER_ID 2>/dev/null | grep "connected:" | awk '{print $NF}')
log_info "Bearer connected: $BEARER_STATUS"

if [[ "$BEARER_STATUS" == "yes" ]]; then
    log_info "✓ Connection successful"
else
    log_error "Bearer not connected"
    exit 1
fi

# Step 8: Check interface
log_section "Step 8: Checking network interface"
if ip link show wwan0 &>/dev/null; then
    log_info "✓ wwan0 interface exists"
    
    # Bring interface up if it's down
    IFACE_STATE=$(ip link show wwan0 | grep -oP '(?<=state )\w+')
    if [[ "$IFACE_STATE" == "DOWN" ]]; then
        log_warn "wwan0 is DOWN, bringing it up..."
        ip link set wwan0 up
        sleep 2
    fi
    
    ip addr show wwan0 || true
else
    log_error "wwan0 interface not found"
    exit 1
fi

# Step 9: Configure routes and DNS
log_section "Step 9: Configuring routes and DNS"
log_info "Running setup-dns-routes.sh..."

# Determine script directory dynamically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find setup-dns-routes.sh in multiple possible locations
SETUP_SCRIPT=""
for path in \
    "$SCRIPT_DIR/setup-dns-routes.sh" \
    "$SCRIPT_DIR/../setup-dns-routes.sh" \
    "/opt/cellular/setup-dns-routes.sh" \
    "/usr/local/bin/setup-dns-routes.sh"; do
    if [[ -f "$path" ]]; then
        SETUP_SCRIPT="$path"
        log_info "Found setup-dns-routes.sh at: $SETUP_SCRIPT"
        break
    fi
done

if [[ -z "$SETUP_SCRIPT" ]]; then
    log_error "Could not find setup-dns-routes.sh"
    log_error "Searched in:"
    log_error "  - $SCRIPT_DIR/setup-dns-routes.sh"
    log_error "  - $SCRIPT_DIR/../setup-dns-routes.sh"
    log_error "  - /opt/cellular/setup-dns-routes.sh"
    log_error "  - /usr/local/bin/setup-dns-routes.sh"
    exit 1
fi

if bash "$SETUP_SCRIPT"; then
    log_info "✓ Routes and DNS configured"
else
    log_warn "setup-dns-routes.sh returned error, but connection may still work"
fi

# Step 10: Final verification
log_section "Step 10: Final verification"
if ping -c 1 -I wwan0 -W 5 8.8.8.8 &>/dev/null; then
    log_info "✓ IP connectivity verified"
else
    log_warn "IP connectivity test failed"
fi

if nslookup google.com &>/dev/null; then
    log_info "✓ DNS resolution verified"
else
    log_warn "DNS resolution failed"
fi

log_section "CONNECTION COMPLETE"
log_info "Cellular connection established successfully!"
log_info ""
log_info "Status:"
mmcli -m $MODEM_ID | grep -E "state:|signal"
log_info ""
log_info "Routes:"
ip route show dev wwan0
log_info ""
log_info "DNS:"
grep nameserver /etc/resolv.conf || echo "No nameserver configured"

exit 0

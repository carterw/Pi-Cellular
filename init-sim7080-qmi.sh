#!/bin/bash
#
# SIM7080 Modem Initialization via QMI
#
# Uses QMI protocol for more stable initialization
# This approach is more reliable than AT commands for the SIM7080
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

log_section "SIM7080 MODEM INITIALIZATION (QMI METHOD)"

# Step 1: Check if modem is on USB
log_info "Step 1: Checking if modem is on USB..."
if lsusb | grep -i "1e0e:9205" &>/dev/null; then
    log_info "✓ SIM7080 found on USB"
else
    log_error "✗ SIM7080 not found on USB"
    exit 1
fi

# Step 2: Check serial devices
log_info ""
log_info "Step 2: Checking serial devices..."
if ls /dev/ttyUSB* &>/dev/null; then
    log_info "✓ Serial devices found"
else
    log_error "✗ No /dev/ttyUSB devices found"
    exit 1
fi

# Step 3: Check if qmicli is installed
log_info ""
log_info "Step 3: Checking for qmicli..."
if ! command -v qmicli &> /dev/null; then
    log_warn "qmicli not found, installing libqmi-utils..."
    apt-get update
    apt-get install -y libqmi-utils
fi

# Step 4: Find QMI device
log_info ""
log_info "Step 4: Finding QMI device..."
QMI_DEVICE=$(ls /dev/cdc-wdm* 2>/dev/null | head -1)

if [[ -z "$QMI_DEVICE" ]]; then
    log_warn "No QMI device found yet, waiting for ModemManager to create it..."
    
    # Restart ModemManager to trigger device creation
    systemctl restart ModemManager
    sleep 5
    
    QMI_DEVICE=$(ls /dev/cdc-wdm* 2>/dev/null | head -1)
fi

if [[ -z "$QMI_DEVICE" ]]; then
    log_error "✗ QMI device not found"
    log_error "This may indicate a driver issue"
    exit 1
fi

log_info "✓ QMI device: $QMI_DEVICE"

# Step 5: Wait for modem detection
log_info ""
log_info "Step 5: Waiting for modem detection..."
RETRY=0
MAX_RETRIES=20
MODEM_ID=""

while [[ $RETRY -lt $MAX_RETRIES ]]; do
    MODEM_OUTPUT=$(mmcli -L 2>&1)
    MODEM_ID=$(echo "$MODEM_OUTPUT" | grep -oP 'Modem/\K[0-9]+' | head -1)
    
    if [[ -n "$MODEM_ID" ]]; then
        log_info "✓ Modem detected!"
        log_info "Modem ID: $MODEM_ID"
        break
    else
        RETRY=$((RETRY + 1))
        if [[ $RETRY -lt $MAX_RETRIES ]]; then
            log_warn "Modem not detected yet, retrying... ($RETRY/$MAX_RETRIES)"
            sleep 1
        fi
    fi
done

if [[ -z "$MODEM_ID" ]]; then
    log_error "✗ Modem detection failed"
    exit 1
fi

# Step 6: Enable modem
log_info ""
log_info "Step 6: Enabling modem..."
if mmcli -m $MODEM_ID --enable 2>&1; then
    log_info "✓ Modem enabled"
else
    log_warn "Enable command returned error, continuing..."
fi

sleep 3

# Step 7: Check modem status
log_info ""
log_info "Step 7: Checking modem status..."
MODEM_INFO=$(mmcli -m $MODEM_ID 2>/dev/null || echo "")

if [[ -n "$MODEM_INFO" ]]; then
    echo "$MODEM_INFO" | head -20
else
    log_warn "Could not retrieve modem info"
fi

# Step 8: Wait for network registration
log_info ""
log_info "Step 8: Waiting for network registration (this may take 30-60 seconds)..."
RETRY=0
MAX_RETRIES=60
STATE=""

while [[ $RETRY -lt $MAX_RETRIES ]]; do
    MODEM_INFO=$(mmcli -m $MODEM_ID 2>/dev/null || echo "")
    
    if [[ -n "$MODEM_INFO" ]]; then
        STATE=$(echo "$MODEM_INFO" | grep "state:" | head -1 | awk '{print $NF}')
        
        if [[ "$STATE" == "registered" ]] || [[ "$STATE" == "connected" ]]; then
            log_info "✓ Modem registered: $STATE"
            break
        fi
    fi
    
    RETRY=$((RETRY + 1))
    if [[ $((RETRY % 10)) -eq 0 ]]; then
        log_warn "Still waiting for registration... ($RETRY/$MAX_RETRIES) - State: $STATE"
    fi
    sleep 1
done

if [[ "$STATE" != "registered" ]] && [[ "$STATE" != "connected" ]]; then
    log_warn "Modem not registered after $MAX_RETRIES seconds"
    log_warn "Current state: $STATE"
    log_warn ""
    log_warn "Possible causes:"
    log_warn "  1. No cellular signal in area"
    log_warn "  2. SIM card not active or not inserted properly"
    log_warn "  3. Carrier restrictions or plan issues"
    log_warn "  4. Modem firmware issue"
    log_warn ""
    log_warn "Try:"
    log_warn "  - Check antenna connection"
    log_warn "  - Move to area with better signal"
    log_warn "  - Verify SIM is properly inserted"
    log_warn "  - Contact carrier to verify SIM is active"
fi

log_section "INITIALIZATION COMPLETE"

if [[ -n "$MODEM_ID" ]]; then
    log_info "SIM7080 modem initialized!"
    log_info ""
    log_info "Modem ID: $MODEM_ID"
    log_info "QMI Device: $QMI_DEVICE"
    log_info ""
    log_info "Modem status:"
    mmcli -m $MODEM_ID 2>/dev/null | grep -E "state:|signal|operator" || true
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run: sudo /opt/cellular/connect-cellular-robust.sh"
    log_info "  2. Or check status: sudo /opt/cellular/cellular-debug.sh status"
else
    log_error "Modem initialization failed"
    exit 1
fi

exit 0

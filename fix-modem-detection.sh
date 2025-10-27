#!/bin/bash
#
# Fix Modem Detection
#
# Recovers from "No modems were found" error by restarting ModemManager
# and forcing device re-enumeration
#
# Usage: sudo ./fix-modem-detection.sh
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

log_section "MODEM DETECTION FIX"

# Step 1: Verify modem is on USB
log_info "Step 1: Checking USB devices..."
if lsusb | grep -i "1e0e:9001" &>/dev/null; then
    log_info "✓ Modem found on USB: $(lsusb | grep -i 1e0e:9001)"
else
    log_error "✗ Modem NOT found on USB"
    log_error "Check USB cable connection"
    exit 1
fi

# Step 2: Check serial devices
log_info ""
log_info "Step 2: Checking serial devices..."
if ls /dev/ttyUSB* &>/dev/null; then
    log_info "✓ Serial devices found:"
    ls -la /dev/ttyUSB*
else
    log_error "✗ No /dev/ttyUSB devices found"
    log_warn "Modem may not be properly initialized"
fi

# Step 3: Check ModemManager status
log_info ""
log_info "Step 3: Checking ModemManager status..."
if systemctl is-active --quiet ModemManager; then
    log_info "✓ ModemManager is running"
else
    log_error "✗ ModemManager is not running"
    log_info "Starting ModemManager..."
    systemctl start ModemManager
    sleep 2
fi

# Step 4: Stop ModemManager
log_info ""
log_info "Step 4: Stopping ModemManager..."
systemctl stop ModemManager
sleep 2
log_info "ModemManager stopped"

# Step 5: Trigger udev rules
log_info ""
log_info "Step 5: Triggering udev rules..."
udevadm trigger
sleep 2
log_info "udev rules triggered"

# Step 6: Start ModemManager
log_info ""
log_info "Step 6: Starting ModemManager..."
systemctl start ModemManager
log_info "Waiting for ModemManager to initialize..."
sleep 5
log_info "ModemManager started"

# Step 7: Wait for modem detection
log_info ""
log_info "Step 7: Waiting for modem detection..."
RETRY=0
MAX_RETRIES=10
MODEM_ID=""

while [[ $RETRY -lt $MAX_RETRIES ]]; do
    # Try to extract modem ID from mmcli output
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
    log_error "✗ Modem detection failed after $MAX_RETRIES attempts"
    log_error ""
    log_error "Last mmcli output:"
    mmcli -L
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "1. Check USB cable connection"
    log_error "2. Try different USB port"
    log_error "3. Unplug modem, wait 10 seconds, plug back in"
    log_error "4. Check modem power supply"
    log_error "5. Run: sudo systemctl restart ModemManager"
    exit 1
fi

# Step 8: Check modem details
log_info ""
log_info "Step 8: Checking modem details..."
if mmcli -m $MODEM_ID &>/dev/null; then
    log_info "Modem $MODEM_ID status:"
    mmcli -m $MODEM_ID | head -15
else
    log_error "Could not access modem $MODEM_ID"
    exit 1
fi

log_section "MODEM DETECTION FIXED"

log_info "Modem is now detected and ready"
log_info ""
log_info "Next steps:"
log_info "  1. Run: sudo ~/speedcam/cellular/connect-cellular-dynamic.sh"
log_info "  2. Or run: sudo ~/speedcam/cellular/cellular-debug.sh status"

exit 0

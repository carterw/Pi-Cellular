#!/bin/bash
#
# SIM7080 Safe Initialization
#
# Uses a conservative approach to initialize the modem without crashing it
# Waits longer between steps and uses proper serial port configuration
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

log_section "SIM7080 SAFE INITIALIZATION"

# Step 1: Check if modem is on USB
log_info "Step 1: Checking if modem is on USB..."
if lsusb | grep -i "1e0e:9205" &>/dev/null; then
    log_info "✓ SIM7080 found on USB"
else
    log_error "✗ SIM7080 not found on USB"
    log_error "Please check USB cable connection"
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

# Step 3: Disable ModemManager to prevent interference
log_info ""
log_info "Step 3: Disabling ModemManager temporarily..."
systemctl stop ModemManager
sleep 3
log_info "✓ ModemManager stopped"

# Step 4: Reset USB device
log_info ""
log_info "Step 4: Resetting USB device..."
# Find the USB device path
USB_PATH=$(lsusb -t | grep "1e0e:9205" | head -1 | grep -oP '\d+-\d+' | head -1)

if [[ -n "$USB_PATH" ]]; then
    log_info "USB path: $USB_PATH"
    
    # Unbind and rebind the device
    DEVICE_PATH="/sys/bus/usb/devices/$USB_PATH"
    if [[ -d "$DEVICE_PATH" ]]; then
        log_info "Unbinding device..."
        echo "$USB_PATH" | tee /sys/bus/usb/drivers/usb/unbind > /dev/null 2>&1 || true
        sleep 2
        
        log_info "Rebinding device..."
        echo "$USB_PATH" | tee /sys/bus/usb/drivers/usb/bind > /dev/null 2>&1 || true
        sleep 3
    fi
else
    log_warn "Could not find USB device path, skipping reset"
fi

# Step 5: Wait for serial devices to reappear
log_info ""
log_info "Step 5: Waiting for serial devices..."
RETRY=0
MAX_RETRIES=10

while [[ $RETRY -lt $MAX_RETRIES ]]; do
    if ls /dev/ttyUSB* &>/dev/null; then
        log_info "✓ Serial devices available"
        break
    fi
    RETRY=$((RETRY + 1))
    if [[ $RETRY -lt $MAX_RETRIES ]]; then
        log_warn "Waiting for serial devices... ($RETRY/$MAX_RETRIES)"
        sleep 1
    fi
done

# Step 6: Configure serial port
log_info ""
log_info "Step 6: Configuring serial port..."
TTY_PORT="/dev/ttyUSB2"

if [[ -e "$TTY_PORT" ]]; then
    # Configure with proper settings for SIM7080
    stty -F "$TTY_PORT" 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts 2>/dev/null || true
    log_info "✓ Serial port configured: $TTY_PORT"
else
    log_warn "Serial port $TTY_PORT not found"
fi

# Step 7: Send minimal AT commands
log_info ""
log_info "Step 7: Sending initialization AT commands..."
log_info "Sending: AT (test connection)"

{
    echo -e "AT\r"
    sleep 1
} > "$TTY_PORT" 2>/dev/null || true

log_info "Sending: AT+CFUN=1 (enable full functionality)"
{
    echo -e "AT+CFUN=1\r"
    sleep 1
} > "$TTY_PORT" 2>/dev/null || true

log_info "Sending: AT+COPS=0 (automatic network selection)"
{
    echo -e "AT+COPS=0\r"
    sleep 1
} > "$TTY_PORT" 2>/dev/null || true

log_info "✓ AT commands sent"

# Step 8: Wait before restarting ModemManager
log_info ""
log_info "Step 8: Waiting before restarting ModemManager..."
sleep 5

# Step 9: Start ModemManager
log_info ""
log_info "Step 9: Starting ModemManager..."
systemctl start ModemManager
log_info "Waiting for ModemManager to initialize..."
sleep 8
log_info "✓ ModemManager started"

# Step 10: Wait for modem detection
log_info ""
log_info "Step 10: Waiting for modem detection..."
RETRY=0
MAX_RETRIES=30
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
        if [[ $((RETRY % 5)) -eq 0 ]]; then
            log_warn "Modem not detected yet, retrying... ($RETRY/$MAX_RETRIES)"
        fi
        sleep 1
    fi
done

if [[ -z "$MODEM_ID" ]]; then
    log_error "✗ Modem detection failed after $MAX_RETRIES attempts"
    log_error ""
    log_error "Last mmcli output:"
    mmcli -L || true
    exit 1
fi

# Step 11: Enable modem
log_info ""
log_info "Step 11: Enabling modem..."
if mmcli -m $MODEM_ID --enable 2>&1 | grep -q "successfully enabled"; then
    log_info "✓ Modem enabled"
else
    log_warn "Enable command returned message (may still be ok)"
fi

sleep 3

# Step 12: Check modem status
log_info ""
log_info "Step 12: Checking modem status..."
MODEM_INFO=$(mmcli -m $MODEM_ID 2>/dev/null || echo "")

if [[ -n "$MODEM_INFO" ]]; then
    echo "$MODEM_INFO" | head -25
else
    log_warn "Could not retrieve modem info"
fi

# Step 13: Wait for network registration
log_info ""
log_info "Step 13: Waiting for network registration..."
log_info "This may take 30-120 seconds depending on signal and carrier..."
RETRY=0
MAX_RETRIES=120
STATE=""
SIGNAL=""

while [[ $RETRY -lt $MAX_RETRIES ]]; do
    MODEM_INFO=$(mmcli -m $MODEM_ID 2>/dev/null || echo "")
    
    if [[ -n "$MODEM_INFO" ]]; then
        STATE=$(echo "$MODEM_INFO" | grep "state:" | head -1 | awk '{print $NF}')
        SIGNAL=$(echo "$MODEM_INFO" | grep "signal quality:" | head -1 | awk '{print $NF}')
        
        if [[ "$STATE" == "registered" ]] || [[ "$STATE" == "connected" ]]; then
            log_info "✓ Modem registered: $STATE"
            break
        fi
    fi
    
    RETRY=$((RETRY + 1))
    if [[ $((RETRY % 20)) -eq 0 ]]; then
        log_warn "Still waiting... ($RETRY/$MAX_RETRIES) - State: $STATE, Signal: $SIGNAL"
    fi
    sleep 1
done

log_section "INITIALIZATION COMPLETE"

if [[ -n "$MODEM_ID" ]]; then
    log_info "SIM7080 modem initialized!"
    log_info ""
    log_info "Modem ID: $MODEM_ID"
    log_info ""
    log_info "Modem status:"
    mmcli -m $MODEM_ID 2>/dev/null | grep -E "state:|signal|operator" || true
    log_info ""
    
    if [[ "$STATE" == "registered" ]] || [[ "$STATE" == "connected" ]]; then
        log_info "✓ Modem is registered and ready!"
        log_info ""
        log_info "Next step:"
        log_info "  Run: sudo /opt/cellular/connect-cellular-robust.sh"
    else
        log_warn "Modem detected but not yet registered"
        log_warn "State: $STATE"
        log_warn "Signal: $SIGNAL"
        log_warn ""
        log_warn "Troubleshooting:"
        log_warn "  - Check antenna connection"
        log_warn "  - Move to area with better signal"
        log_warn "  - Verify SIM card is active"
        log_warn "  - Check carrier coverage in your area"
    fi
else
    log_error "Modem initialization failed"
    exit 1
fi

exit 0

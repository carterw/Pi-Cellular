#!/bin/bash
#
# Reset Modem - Full hardware and software reset
#
# Handles cases where modem gets into a bad state and needs complete reset
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "Starting modem reset..."

# Step 1: Stop ModemManager
log_info "Step 1: Stopping ModemManager..."
systemctl stop ModemManager || log_warn "ModemManager not running"
sleep 2

# Step 2: Unbind USB device
log_info "Step 2: Finding and unbinding USB device..."
USB_DEVICE=$(lsusb | grep -i "sim\|modem\|sierra\|quectel" | head -1 | awk '{print $1":"$2}' | sed 's/:/-/')

if [[ -z "$USB_DEVICE" ]]; then
    log_warn "Could not find modem USB device, trying alternative method..."
    # Try to find by device name
    if [[ -e /sys/bus/usb/devices/1-1 ]]; then
        USB_PATH="/sys/bus/usb/devices/1-1"
        log_info "Found USB device at $USB_PATH"
    else
        log_error "Could not locate USB device"
        exit 1
    fi
else
    log_info "Found USB device: $USB_DEVICE"
    USB_PATH="/sys/bus/usb/devices/$USB_DEVICE"
fi

# Unbind the device
if [[ -e "$USB_PATH" ]]; then
    log_info "Unbinding USB device..."
    echo "1" > "$USB_PATH/remove" 2>/dev/null || log_warn "Could not unbind device"
    sleep 3
else
    log_warn "USB path not found: $USB_PATH"
fi

# Step 3: Rescan USB bus
log_info "Step 3: Rescanning USB bus..."
echo "1" > /sys/bus/usb/drivers/usb/bind 2>/dev/null || true
sleep 3

# Step 4: Start ModemManager
log_info "Step 4: Starting ModemManager..."
systemctl start ModemManager
sleep 3

# Step 5: Wait for modem to appear
log_info "Step 5: Waiting for modem to be detected..."
for i in {1..10}; do
    if mmcli -L 2>/dev/null | grep -q "Modem"; then
        log_info "✓ Modem detected"
        break
    fi
    log_warn "Waiting for modem... ($i/10)"
    sleep 2
done

# Step 6: Check modem status
log_info "Step 6: Checking modem status..."
if mmcli -L 2>/dev/null | grep -q "Modem"; then
    MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
    log_info "✓ Modem found: /org/freedesktop/ModemManager1/Modem/$MODEM_ID"
    
    log_info ""
    log_info "Modem status:"
    mmcli -m $MODEM_ID || true
else
    log_error "Modem not detected after reset"
    exit 1
fi

log_info ""
log_info "Modem reset complete!"
log_info "You can now run: sudo bash ./connect-cellular-dynamic.sh"

exit 0

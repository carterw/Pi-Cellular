#!/bin/bash
#
# SIM7080 Direct Serial Initialization
#
# Bypasses ModemManager to initialize the modem directly via serial port
# Then restarts ModemManager for proper device management
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

log_section "SIM7080 DIRECT SERIAL INITIALIZATION"

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
    log_info "✓ Serial devices found:"
    ls -la /dev/ttyUSB*
else
    log_error "✗ No /dev/ttyUSB devices found"
    exit 1
fi

# Step 3: Stop ModemManager
log_info ""
log_info "Step 3: Stopping ModemManager..."
systemctl stop ModemManager
sleep 2
log_info "✓ ModemManager stopped"

# Step 4: Create minicom script for initialization
log_info ""
log_info "Step 4: Creating minicom initialization script..."

MINICOM_SCRIPT=$(mktemp)
cat > "$MINICOM_SCRIPT" << 'EOF'
AT
ATE0
AT+CFUN=1
AT+CPIN?
AT+COPS=0
AT+CREG=1
AT+CGREG=1
AT+CGATT=1
AT+CGDCONT=1,"IP","ereseller"
AT+CGACT=1,1
AT+CGPADDR=1
quit
EOF

log_info "✓ Script created at $MINICOM_SCRIPT"

# Step 5: Send AT commands via minicom
log_info ""
log_info "Step 5: Sending AT initialization commands..."
log_info "Using port: /dev/ttyUSB2"

# Try to send commands to the modem
# minicom requires a terminal, so we'll use a different approach
# We'll use stty to configure the port and cat to send commands

TTY_PORT="/dev/ttyUSB2"

# Configure serial port
stty -F "$TTY_PORT" 115200 -crtscts cs8 -ixon -ixoff 2>/dev/null || true

# Send AT commands
log_info "Sending AT commands..."
{
    echo -e "AT\r"
    sleep 0.5
    echo -e "ATE0\r"
    sleep 0.5
    echo -e "AT+CFUN=1\r"
    sleep 0.5
    echo -e "AT+CPIN?\r"
    sleep 0.5
    echo -e "AT+COPS=0\r"
    sleep 0.5
    echo -e "AT+CREG=1\r"
    sleep 0.5
    echo -e "AT+CGREG=1\r"
    sleep 0.5
    echo -e "AT+CGATT=1\r"
    sleep 0.5
} > "$TTY_PORT" 2>/dev/null || true

sleep 2
log_info "✓ AT commands sent"

# Clean up
rm -f "$MINICOM_SCRIPT"

# Step 6: Start ModemManager
log_info ""
log_info "Step 6: Starting ModemManager..."
systemctl start ModemManager
log_info "Waiting for ModemManager to initialize..."
sleep 5
log_info "✓ ModemManager started"

# Step 7: Wait for modem detection
log_info ""
log_info "Step 7: Waiting for modem detection..."
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
    log_error ""
    log_error "Last mmcli output:"
    mmcli -L || true
    exit 1
fi

# Step 8: Enable modem
log_info ""
log_info "Step 8: Enabling modem..."
if mmcli -m $MODEM_ID --enable 2>&1; then
    log_info "✓ Modem enabled"
else
    log_warn "Enable command returned error, continuing..."
fi

sleep 3

# Step 9: Check modem status
log_info ""
log_info "Step 9: Checking modem status..."
MODEM_INFO=$(mmcli -m $MODEM_ID 2>/dev/null || echo "")

if [[ -n "$MODEM_INFO" ]]; then
    echo "$MODEM_INFO" | head -20
else
    log_warn "Could not retrieve modem info"
fi

# Step 10: Wait for network registration
log_info ""
log_info "Step 10: Waiting for network registration (this may take 30-60 seconds)..."
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
        log_info "✓ Modem is registered and ready to connect!"
        log_info ""
        log_info "Next step:"
        log_info "  Run: sudo /opt/cellular/connect-cellular-robust.sh"
    else
        log_warn "Modem detected but not yet registered"
        log_warn "This may take additional time or require better signal"
    fi
else
    log_error "Modem initialization failed"
    exit 1
fi

exit 0

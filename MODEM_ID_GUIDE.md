# Modem ID Re-enumeration Guide

## Problem: Modem Changes from 0 to 1 (or vice versa)

When ModemManager restarts or the USB connection resets, the modem may be re-enumerated with a different ID:

```bash
# Before restart
$ mmcli -L
/org/freedesktop/ModemManager1/Modem/0 [QUALCOMM INCORPORATED] SIMCOM_SIM7600G-H

# After restart
$ mmcli -L
/org/freedesktop/ModemManager1/Modem/1 [QUALCOMM INCORPORATED] SIMCOM_SIM7600G-H
```

## Solution: Auto-Detection

All scripts now **automatically detect** the current modem ID:

### Scripts with Auto-Detection

1. **connect-cellular-dynamic.sh** - Automatically finds modem ID
2. **cellular-debug.sh** - Automatically finds modem ID
3. **cellular-recover.sh** - Automatically finds modem ID
4. **get-modem-id.sh** - Returns current modem ID

### Usage

Just run the scripts normally - they handle the ID detection:

```bash
# These work regardless of modem ID (0, 1, 2, etc.)
sudo /opt/cellular/connect-cellular-dynamic.sh
sudo /opt/cellular/cellular-debug.sh status
sudo /opt/cellular/cellular-recover.sh
```

### Manual Modem ID Detection

If you need to know the current modem ID:

```bash
# Method 1: Using the helper script
./get-modem-id.sh

# Method 2: Using mmcli directly
mmcli -L | grep -oP 'Modem/\K[0-9]+'

# Method 3: List all modems
mmcli -L
```

### Bearer ID Relationship

The bearer ID is automatically calculated as:
```
BEARER_ID = MODEM_ID + 1
```

So:
- Modem 0 → Bearer 1
- Modem 1 → Bearer 2
- Modem 2 → Bearer 3

## How Auto-Detection Works

The scripts use this pattern:

```bash
# Find the first (and usually only) modem
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)

# If not found, default to 0
if [[ -z "$MODEM_ID" ]]; then
    MODEM_ID=0
fi

# Calculate bearer ID
BEARER_ID=$((MODEM_ID + 1))
```

## Troubleshooting

### "No modem found" Error

If auto-detection fails:

```bash
# Check if ModemManager is running
sudo systemctl status ModemManager

# Restart ModemManager
sudo systemctl restart ModemManager
sleep 3

# Try again
mmcli -L
```

### Multiple Modems

If you have multiple modems, the scripts will use the first one found. To use a specific modem:

```bash
# List all modems
mmcli -L

# Use specific modem (e.g., modem 2)
sudo mmcli -m 2
```

## Old Hardcoded Approach (Not Recommended)

Before auto-detection, scripts had hardcoded modem IDs:

```bash
# Old way (doesn't work after re-enumeration)
MODEM_ID=0
BEARER_ID=1

# New way (works with any modem ID)
MODEM_ID=$(mmcli -L | grep -oP 'Modem/\K[0-9]+' | head -1)
BEARER_ID=$((MODEM_ID + 1))
```

## When Modem ID Changes

Modem ID changes when:

1. **ModemManager restarts** - System reboot, service restart
2. **USB connection resets** - Unplugging/replugging USB cable
3. **Modem firmware update** - Modem updates its firmware
4. **Multiple modems** - Adding/removing other modems

The auto-detection handles all these cases automatically.

## Verification

To verify auto-detection is working:

```bash
# Run the debug script
sudo /opt/cellular/cellular-debug.sh status

# It will show the detected modem ID in the output
# Example output:
# [INFO] Modem 0 details:
# [INFO] Modem 0 status:
```

Or check the connection script output:

```bash
sudo /opt/cellular/connect-cellular-dynamic.sh

# Output will show:
# [INFO] Step 1: Enabling modem 1...
# [INFO] Step 2: Creating bearer with APN=ereseller, IP-Type=ipv4v6...
```

## Summary

✅ **All scripts now auto-detect modem ID**
✅ **Works with any modem ID (0, 1, 2, etc.)**
✅ **No manual configuration needed**
✅ **Handles re-enumeration automatically**

Just use the scripts normally - they handle the modem ID detection for you!

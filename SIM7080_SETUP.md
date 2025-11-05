# SIM7080 Modem Setup Guide

## Overview

The **SIM7080** (USB ID `1e0e:9205`) is a newer cellular modem from Qualcomm/Option SimTech. It requires specific initialization steps to work with ModemManager on Raspberry Pi.

## Quick Start

### 1. Verify Hardware Connection

```bash
# Check if modem appears on USB bus
lsusb | grep -i "1e0e:9205"
```

Expected output:
```
Bus 003 Device 010: ID 1e0e:9205 Qualcomm / Option SimTech SIM7080
```

### 2. Check for Serial Devices

```bash
# List serial devices
ls -la /dev/ttyUSB*
```

You should see `/dev/ttyUSB0`, `/dev/ttyUSB1`, `/dev/ttyUSB2`, etc.

### 3. Initialize ModemManager

```bash
# Restart ModemManager to detect the modem
sudo systemctl restart ModemManager
sleep 5

# Check if modem is detected
mmcli -L
```

If detected, you'll see:
```
/org/freedesktop/ModemManager1/Modem/0 [Qualcomm INCORPORATED] SIM7080
```

### 4. Run the Detection Fix Script

If the modem is not detected, use the automated fix:

```bash
sudo /opt/cellular/fix-modem-detection.sh
```

This script will:
- Verify the modem is on USB
- Check serial devices
- Restart ModemManager
- Trigger udev rules
- Wait for modem detection
- Verify modem is accessible

### 5. Connect to Cellular Network

Once detected, connect using:

```bash
sudo /opt/cellular/connect-cellular-robust.sh
```

## Troubleshooting

### Modem Not Detected After Restart

**Step 1: Check ModemManager logs**

```bash
sudo journalctl -u ModemManager -n 50 --no-pager
```

Look for errors like:
- `Failed to open device`
- `Permission denied`
- `Device not found`

**Step 2: Manual USB Reset**

```bash
# Stop ModemManager
sudo systemctl stop ModemManager
sleep 2

# Find USB device path (usually 1-1 or 1-2)
lsusb -t

# Unbind the device
echo "1-1" | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 3

# Bind the device back
echo "1-1" | sudo tee /sys/bus/usb/drivers/usb/bind
sleep 3

# Start ModemManager
sudo systemctl start ModemManager
sleep 5

# Check detection
mmcli -L
```

**Step 3: Check udev Rules**

```bash
# List udev rules for USB devices
ls -la /etc/udev/rules.d/ | grep -i usb

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### ModemManager Crashes

If ModemManager keeps crashing, check:

```bash
# Check system logs
sudo journalctl -xe | tail -50

# Check if there's a conflicting service
ps aux | grep -i modem

# Restart ModemManager with debug output
sudo systemctl stop ModemManager
sudo ModemManager --debug 2>&1 | head -100
```

### Serial Devices Not Appearing

If `/dev/ttyUSB*` devices don't appear:

```bash
# Check kernel messages
dmesg | tail -20

# Check if USB driver is loaded
lsmod | grep usb

# Try loading the driver
sudo modprobe usbserial
sudo modprobe option
```

## Configuration

### Update APN Settings

Edit `/home/bill/Pi-Cellular/cellular-config.sh`:

```bash
# For your carrier, set the correct APN
CELLULAR_APN="your-carrier-apn"
CELLULAR_IP_TYPE="ipv4v6"
```

Common APNs:
- **ereseller**: Default (IoT)
- **verizon**: Verizon
- **iot.1nce.net**: 1NCE
- **m2m.vodafone.com**: Vodafone

### Verify Connection

```bash
# Check modem status
sudo mmcli -m 0

# Check bearer status
sudo mmcli -b 1

# Test connectivity
ping -I wwan0 8.8.8.8

# Test DNS
nslookup google.com
```

## Advanced: Manual AT Commands

If you need to send AT commands directly to the modem:

```bash
# Connect to modem serial port
sudo minicom -D /dev/ttyUSB2

# Or use mmcli
sudo mmcli -m 0 --command='AT+CPIN?'
sudo mmcli -m 0 --command='AT+COPS?'
sudo mmcli -m 0 --command='AT+CSQ'
```

Common AT commands:
- `AT+CPIN?` - Check SIM status
- `AT+COPS?` - Check network registration
- `AT+CSQ` - Check signal strength
- `AT+CTEMP?` - Check modem temperature
- `ATI` - Get modem info

## Performance Tips

1. **Disable USB Autosuspend**

   Edit `/boot/firmware/cmdline.txt`:
   ```
   usbcore.autosuspend=-1
   ```

2. **Monitor Signal Strength**

   ```bash
   watch -n 5 'sudo mmcli -m 0 | grep -i signal'
   ```

3. **Enable Auto-Recovery**

   ```bash
   export CELLULAR_LOG_DIR=/var/log/cellular
   sudo mkdir -p /var/log/cellular
   sudo -E nohup /opt/cellular/auto-recover.sh 30 &
   ```

4. **Check Connection Stability**

   ```bash
   ping -I wwan0 -c 100 8.8.8.8
   ```

## Support

For issues, collect diagnostic information:

```bash
# Collect modem info
sudo mmcli -m 0 > modem_info.txt
sudo mmcli -b 1 >> modem_info.txt
lsusb >> modem_info.txt
dmesg | tail -50 >> modem_info.txt
sudo journalctl -u ModemManager -n 50 >> modem_info.txt
```

Then check:
1. Your carrier's APN and network settings
2. SIM card is active and has data plan
3. Signal strength is adequate (> -100 dBm)
4. Antenna is properly connected

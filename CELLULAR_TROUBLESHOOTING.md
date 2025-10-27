# Cellular Modem Troubleshooting Guide

## Common Issues and Solutions

### Issue 1: "couldn't find modem" Error

**Symptoms**:

```bash
$ sudo mmcli -m 0
error: couldn't find modem
```

**Causes**:

1. ModemManager crashed or lost connection to modem
2. USB connection interrupted
3. Modem firmware issue
4. Power supply problem

**Solutions**:

#### Automated Recovery (Try First)

Use the emergency reset script:

```bash
sudo /opt/cellular/reset-modem.sh
```

This script will:

- Stop ModemManager
- Rescan USB bus
- Restart ModemManager
- Re-detect the modem
- Verify modem is accessible

Then reconnect:

```bash
sudo /opt/cellular/connect-cellular-robust.sh
```

**Note**: Update paths to match your installation directory.

#### Manual Recovery Steps

**Step 1: Check if modem is on USB**

```bash
lsusb | grep -i "SimTech"
```

If you see output like `Bus 003 Device 003: ID 1e0e:9001 Qualcomm / Option SimTech`, the modem is detected by the system.

**Step 2: Check if ModemManager is running**

```bash
sudo systemctl status ModemManager
```

If not running, start it:

```bash
sudo systemctl start ModemManager
```

**Step 3: Restart ModemManager**

```bash
sudo systemctl restart ModemManager
sleep 3
mmcli -L
```

**Step 4: Check serial devices**

```bash
ls -la /dev/ttyUSB*
```

You should see `/dev/ttyUSB0`, `/dev/ttyUSB1`, `/dev/ttyUSB2`, etc.

**Step 5: Manual USB reset (Last Resort)**

```bash
# Unplug USB cable
# Wait 10 seconds
# Plug USB cable back in
# Wait 5 seconds
sudo systemctl restart ModemManager
sleep 3
mmcli -L
```

---

### Issue 2: Modem Detected but Cannot Connect

**Symptoms**:

```bash
$ mmcli -m 0
# Shows modem but connection fails
```

**Solutions**:

**Check modem status**:

```bash
sudo mmcli -m 0
```

Look for:

- `State: registered` (good)
- `State: searching` (bad - not finding network)
- `State: denied` (bad - SIM issue)

**Check SIM card**:

```bash
sudo mmcli -m 0 --command='AT+CPIN?'
```

Should return `+CPIN: READY`

**Check network registration**:

```bash
sudo mmcli -m 0 --command='AT+COPS?'
```

Should show registered network like `+COPS: 0,0,"Dark Star",7`

**Check signal strength**:

```bash
sudo mmcli -m 0 | grep -i signal
```

Signal should be > -100 dBm

---

### Issue 3: DNS Resolution Fails

**Symptoms**:

```bash
$ ping -I wwan0 www.google.com
ping: www.google.com: Temporary failure in name resolution
```

But IP-based ping works:

```bash
$ ping -I wwan0 8.8.8.8
# Works fine
```

**Causes**:

1. DNS not configured in `/etc/resolv.conf`
2. IPv6 DNS missing (if using IPv6)
3. DNS servers unreachable

**Solutions**:

**Check DNS configuration**:

```bash
cat /etc/resolv.conf
```

Should show something like:

```
nameserver 172.26.38.2
nameserver fc00:a:a::400
```

**Reconfigure DNS**:

```bash
# Get DNS from modem
sudo mmcli -b 1 | grep dns

# Manually set DNS to the address that was shown, like;
echo "nameserver 172.26.38.2" | sudo tee /etc/resolv.conf
echo "nameserver fc00:a:a::400" | sudo tee -a /etc/resolv.conf

# Test
nslookup google.com
```

**Check if systemd-resolved is interfering**:

```bash
sudo systemctl status systemd-resolved
```

If it's running and causing issues:

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

---

### Issue 4: Connection Drops After a While

**Symptoms**:

- Connection works initially
- Drops after 5-30 minutes
- Cannot reconnect without manual intervention

**Causes**:

1. Carrier timeout
2. Modem power management
3. USB autosuspend
4. Modem bearer instability

**Solutions**:

#### Automatic Recovery (Recommended)

Start the auto-recovery daemon to automatically detect and fix connection drops:

```bash
export CELLULAR_LOG_DIR=/var/log/cellular
sudo -E nohup /opt/cellular/auto-recover.sh 30 &
```

Monitor the daemon:

```bash
tail -f /var/log/cellular/auto-recover.log
```

The daemon will:

- Check connection every 30 seconds
- Detect connection loss automatically
- Reconfigure routes and DNS if needed
- Log all activity for debugging

#### Manual Solutions

**Disable USB autosuspend**:

Edit `/boot/firmware/cmdline.txt` (or `/boot/cmdline.txt` on older systems):

```bash
sudo nano /boot/firmware/cmdline.txt
```

Add at the end (on same line):

```
usbcore.autosuspend=-1
```

Reboot:

```bash
sudo reboot
```

**Check USB power settings**:

```bash
cat /sys/bus/usb/devices/*/power/autosuspend_delay_ms
```

Should show `-1` for the modem device.

**Monitor connection**:

```bash
watch -n 5 'sudo mmcli -m 0 | grep -E "(State|Signal)"'
```

**Emergency modem reset**:

If drops persist, perform a full modem reset:

```bash
sudo /opt/cellular/reset-modem.sh
sudo /opt/cellular/connect-cellular-robust.sh
export CELLULAR_LOG_DIR=/var/log/cellular
sudo -E nohup /opt/cellular/auto-recover.sh 30 &
```

---

### Issue 5: Slow or Intermittent Connection

**Symptoms**:

- High latency (>200ms)
- Packet loss
- Intermittent disconnections

**Causes**:

1. Poor signal strength
2. Network congestion
3. Modem thermal issues

**Solutions**:

**Check signal strength**:

```bash
sudo /opt/cellular/cellular-debug.sh signal
```

Signal quality should be > -100 dBm. If worse:

- Move antenna
- Check antenna connection
- Try different location

**Monitor latency**:

```bash
ping -I wwan0 -c 100 8.8.8.8 | tail -1
```

Look at `min/avg/max/mdev` values. Average should be < 150ms.

**Check packet loss**:

```bash
ping -I wwan0 -c 100 8.8.8.8 | grep "packet loss"
```

Should be 0% or very low (<5%).

**Check modem temperature** (if available):

```bash
sudo mmcli -m 0 --command='AT+CTEMP?'
```

If temperature is high (>60°C), modem may throttle.

---

### Issue 6: Cannot Reconnect After Disconnect

**Symptoms**:

```bash
$ sudo mmcli -b 1 --disconnect
$ sudo mmcli -b 1 --connect
# Hangs or fails
```

**Solutions**:

#### Automated Recovery (Recommended)

Use the robust connection script which handles reconnection properly:

```bash
sudo /opt/cellular/connect-cellular-robust.sh
```

This script will:

- Disconnect existing bearers
- Create a new bearer
- Connect properly
- Configure routes and DNS
- Verify connectivity

#### Manual Reconnection Sequence

If you need to manually reconnect:

```bash
# Disconnect bearer
sudo mmcli -b 1 --disconnect 2>/dev/null || true
sleep 2

# Disable modem
sudo mmcli -m 0 --disable
sleep 2

# Enable modem
sudo mmcli -m 0 --enable
sleep 2

# Create new bearer
sudo mmcli -m 0 --create-bearer="apn=ereseller,ip-type=ipv4v6"
sleep 2

# Connect bearer
sudo mmcli -b 1 --connect
sleep 2

# Verify
mmcli -b 1
```

#### Emergency Recovery

If manual reconnection fails:

```bash
sudo /opt/cellular/reset-modem.sh
sudo /opt/cellular/connect-cellular-robust.sh
```

---

## Diagnostic Commands

### Quick Status Check

```bash
sudo /opt/cellular/cellular-debug.sh status
```

### Comprehensive Diagnostics

```bash
# Modem info
sudo mmcli -m 0

# Bearer info
sudo mmcli -b 1

# Interface status
ip addr show wwan0

# Routes
ip route show dev wwan0

# DNS
cat /etc/resolv.conf

# Connectivity
ping -I wwan0 8.8.8.8
nslookup google.com

# Signal strength
sudo /opt/cellular/cellular-debug.sh signal

# Run all tests
sudo /opt/cellular/cellular-debug.sh test
```

### Logs

```bash
# ModemManager logs
sudo journalctl -u ModemManager -f

# System logs
sudo journalctl -xe

# Cellular connection logs
sudo journalctl -u cellular-connect.service -f

# Auto-recovery daemon logs
tail -f /var/log/cellular/auto-recover.log
```

---

## Prevention Tips

1. **Start auto-recovery daemon** at boot for automatic connection monitoring
2. **Disable USB autosuspend** (see Issue 4)
3. **Use systemd services** for automatic startup
4. **Monitor daemon logs** regularly for issues
5. **Keep antenna clear** of obstructions
6. **Ensure good power supply** to modem
7. **Use quality USB cable** (not too long)
8. **Keep modem firmware updated**

---

## When to Contact Support

If you've tried all troubleshooting steps and still have issues:

1. Collect diagnostic info:

   ```bash
   sudo mmcli -m 0 > modem_info.txt
   sudo mmcli -b 1 >> modem_info.txt
   ip addr show wwan0 >> modem_info.txt
   cat /etc/resolv.conf >> modem_info.txt
   lsusb | grep -i simcom >> modem_info.txt
   ```

2. Check carrier support for:
   - APN settings
   - DNS server addresses
   - Network coverage in your area

3. Verify:
   - SIM card is active and has data plan
   - No carrier restrictions on device
   - Account is in good standing

---

## Quick Reference

| Issue | Command |
|-------|---------|
| Modem not found | `sudo /opt/cellular/reset-modem.sh` |
| Check status | `sudo /opt/cellular/cellular-debug.sh status` |
| Test connectivity | `sudo /opt/cellular/cellular-debug.sh test` |
| Check signal | `sudo /opt/cellular/cellular-debug.sh signal` |
| View logs | `sudo /opt/cellular/cellular-debug.sh logs` |
| Reset modem | `sudo /opt/cellular/reset-modem.sh` |
| Connect (production) | `sudo /opt/cellular/connect-cellular-robust.sh` |
| Connect (troubleshoot) | `sudo /opt/cellular/connect-cellular-dynamic.sh` |
| Start auto-recovery | `export CELLULAR_LOG_DIR=/var/log/cellular && sudo -E nohup /opt/cellular/auto-recover.sh 30 &` |
| Monitor daemon | `tail -f /var/log/cellular/auto-recover.log` |
| Stop daemon | `sudo pkill -f auto-recover.sh` |

---

## Dynamic Path Troubleshooting

### Scripts can't find setup-dns-routes.sh

**Cause**: Script is not in expected location or installation paths are incorrect

**Solution**: Ensure all scripts are in the same directory, or install to `/opt/cellular/`:

```bash
# Check if script exists
ls -la /opt/cellular/setup-dns-routes.sh

# Or verify in current directory
ls -la ./setup-dns-routes.sh

# If missing, copy it to the correct location
sudo cp setup-dns-routes.sh /opt/cellular/
```

### Logs not being written

**Cause**: Log directory doesn't exist or is not writable

**Solution**: Check `CELLULAR_LOG_DIR` and ensure the directory is writable:

```bash
# Check directory exists and permissions
ls -ld /var/log/cellular

# Create if missing
sudo mkdir -p /var/log/cellular
sudo chown $USER:$USER /var/log/cellular

# Verify it's writable
touch /var/log/cellular/test.log && rm /var/log/cellular/test.log
```

### Permission denied on /opt/cellular

**Cause**: User doesn't have write permissions to installation directory

**Solution**: Use `sudo` or ensure your user has write permissions:

```bash
# Option 1: Use sudo (recommended for system-wide installation)
sudo /opt/cellular/connect-cellular-robust.sh

# Option 2: Change ownership to your user
sudo chown $USER:$USER /opt/cellular

# Option 3: Install to home directory instead
mkdir -p ~/cellular
cp *.sh ~/cellular/
chmod +x ~/cellular/*.sh
```

### Auto-recovery daemon not starting

**Cause**: Log directory permissions or environment variable not passed to sudo

**Solution**: Ensure environment variable is passed with `-E` flag:

```bash
# Correct way (with -E flag)
export CELLULAR_LOG_DIR=/var/log/cellular
sudo -E nohup ./auto-recover.sh 30 &

# Or in one command
CELLULAR_LOG_DIR=/var/log/cellular sudo -E nohup ./auto-recover.sh 30 &

# Check if daemon is running
ps aux | grep auto-recover.sh

# View logs
tail -f /var/log/cellular/auto-recover.log
```

# Cellular Modem Setup Guide - SIMCOM SIM7600G-H on Raspberry Pi 4

## Overview

This guide covers the complete cellular connection setup for your Raspberry Pi with SIMCOM SIM7600G-H modem. Three complementary scripts work together to provide reliable, automatic connection management.

---

## Problem: Dynamic IP Addresses After Reboot

Cellular carriers use DHCP-like assignment pools. Each time you reboot, the modem gets a **different IP address** from the carrier's pool. Hardcoded addresses become invalid, breaking connectivity.

### Why This Happens

1. **Carrier assigns addresses dynamically**: Unlike fixed broadband, cellular networks assign temporary IPs from a pool
2. **Each connection gets new addresses**: When you reconnect (reboot), you get different addresses
3. **Manual configuration breaks**: Hardcoded IPs from a previous session no longer work

---

## Solution: Three-Script System

The solution uses three complementary scripts:

1. **`connect-cellular-robust.sh`** (Recommended for production)
   - Handles modem state management
   - Disconnects existing bearers before creating new ones
   - Delegates DNS/routes to helper script
   - Works reliably after each reboot

2. **`connect-cellular-dynamic.sh`** (For troubleshooting)
   - Manually extracts and configures IP addresses
   - Shows detailed configuration information
   - Useful for understanding what the modem assigns

3. **`auto-recover.sh`** (For high availability)
   - Continuous monitoring daemon (every 30 seconds)
   - Automatically detects and recovers from connection loss
   - Checks routes, DNS, IP connectivity, and DNS resolution

### How They Work Together

The robust script handles initial connection:

1. **Connects to the modem** using ModemManager
2. **Queries the modem** for the assigned IP configuration
3. **Extracts the actual addresses** from `mmcli -b 1` output
4. **Configures the interface** with the correct addresses
5. **Works reliably after each reboot** because it uses whatever addresses the carrier assigns

### How It Works

```bash
# Step 1: Enable modem and create bearer
mmcli -m 0 --enable
mmcli -m 0 --create-bearer="apn=ereseller,ip-type=ipv4v6"

# Step 2: Connect the bearer
mmcli -b 1 --connect

# Step 3: Query modem for assigned configuration
mmcli -b 1
# Output shows:
#   IPv4 configuration |         method: static
#                      |        address: 10.19.145.184
#                      |         prefix: 28
#                      |        gateway: 10.19.145.185
#                      |            dns: 172.26.38.2

# Step 4: Extract and use the addresses
IPV4_ADDRESS="10.19.145.184"
IPV4_PREFIX="28"
GATEWAY="10.19.145.185"
DNS="172.26.38.2"

# Step 5: Configure interface with extracted values
ip addr add 10.19.145.184/28 dev wwan0
ip route add default via 10.19.145.185 dev wwan0
```

---

## Quick Start

### Step 1: Make scripts executable

```bash
# If scripts are in current directory
chmod +x ./connect-cellular-robust.sh
chmod +x ./connect-cellular-dynamic.sh
chmod +x ./auto-recover.sh
chmod +x ./setup-dns-routes.sh

# Or if installed in /opt/cellular
chmod +x /opt/cellular/*.sh
```

### Step 2: Connect the modem (Production)

For production use, run the robust script:

```bash
# If in current directory
sudo ./connect-cellular-robust.sh

# Or if installed in /opt/cellular
sudo /opt/cellular/connect-cellular-robust.sh
```

### Step 2 (Alternative): Connect the modem (Troubleshooting)

For troubleshooting and detailed inspection, run the dynamic script:

```bash
# If in current directory
sudo ./connect-cellular-dynamic.sh

# Or if installed in /opt/cellular
sudo /opt/cellular/connect-cellular-dynamic.sh
```

### Expected Output
```
[INFO] Starting cellular connection setup...
[INFO] Step 1: Enabling modem 0...
[INFO] Modem enabled successfully
[INFO] Step 2: Creating bearer with APN=ereseller, IP-Type=ipv4v6...
[INFO] Bearer created successfully
[INFO] Step 3: Connecting bearer 1...
[INFO] Bearer connected successfully
[INFO] Step 4: Bringing up interface wwan0...
[INFO] Interface brought up
[INFO] Step 5: Retrieving IP configuration from modem...
[INFO] Retrieved configuration:
[INFO]   IPv4 Address: 10.19.145.184
[INFO]   Prefix: 28
[INFO]   Gateway: 10.19.145.185
[INFO]   DNS: 172.26.38.2
[INFO] Step 6: Configuring interface with retrieved addresses...
[INFO] IP address configured: 10.19.145.184/28
[INFO] Default route added: via 10.19.145.185
[INFO] Step 7: Setting MTU to 1430...
[INFO] MTU set to 1430
[INFO] Step 8: Configuring DNS...
[INFO] DNS configured: 172.26.38.2
[INFO] Step 9: Verifying connectivity...
[INFO] Interface configured successfully
[INFO] Connectivity test PASSED - can reach 8.8.8.8

==========================================
Cellular connection established!
==========================================
Interface: wwan0
IP Address: 10.19.145.184/28
Gateway: 10.19.145.185
DNS: 172.26.38.2
MTU: 1430
==========================================
```

### Step 3: Start Auto-Recovery Daemon (Recommended)

For high availability, start the auto-recovery daemon:

```bash
# If in current directory
sudo nohup ./auto-recover.sh 30 > ./auto-recover.log 2>&1 &

# Or if installed in /opt/cellular
sudo nohup /opt/cellular/auto-recover.sh 30 > /var/log/cellular/auto-recover.log 2>&1 &

# Set custom log directory via environment variable
export CELLULAR_LOG_DIR=/var/log/cellular
sudo -E nohup ./auto-recover.sh 30 &
```

Monitor the daemon:

```bash
# Default location
tail -f ./auto-recover.log

# Or system log location
tail -f /var/log/cellular/auto-recover.log
```

---

## Automating at Boot Time

### Option 1: systemd Services (Recommended)

Create `/etc/systemd/system/cellular-connect.service`:

```ini
[Unit]
Description=Cellular Modem Connection
After=network.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/cellular/connect-cellular-robust.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Note**: Update `ExecStart` path to match your installation directory.

Create `/etc/systemd/system/cellular-auto-recover.service`:

```ini
[Unit]
Description=Cellular Auto-Recovery Daemon
After=cellular-connect.service
Wants=cellular-connect.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'exec /opt/cellular/auto-recover.sh 30'
Environment="CELLULAR_LOG_DIR=/var/log/cellular"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Note**: Update `ExecStart` path and `CELLULAR_LOG_DIR` to match your setup.

Enable and start both:

```bash
sudo systemctl daemon-reload
sudo systemctl enable cellular-connect.service cellular-auto-recover.service
sudo systemctl start cellular-connect.service cellular-auto-recover.service
```

Check status:

```bash
sudo systemctl status cellular-connect.service
sudo systemctl status cellular-auto-recover.service
sudo journalctl -u cellular-connect.service -f
sudo journalctl -u cellular-auto-recover.service -f
```

### Option 2: rc.local (Alternative)

Add to `/etc/rc.local` before `exit 0`:

```bash
/opt/cellular/connect-cellular-robust.sh >> /var/log/cellular-connect.log 2>&1 &
sleep 5
export CELLULAR_LOG_DIR=/var/log/cellular
nohup /opt/cellular/auto-recover.sh 30 >> /var/log/cellular-auto-recover.log 2>&1 &
```

**Note**: Update paths to match your installation directory.

---

## Troubleshooting

### Script fails with "Failed to retrieve IP configuration"

**Cause**: The modem hasn't finished connecting yet

**Solution**: Increase the sleep time after `mmcli -b $BEARER_ID --connect`:

```bash
sleep 5  # Increase from 2 to 5 seconds
```

### "Cannot reach 8.8.8.8" but other connectivity works

**Cause**: Carrier may block external traffic or have firewall rules

**Solution**: This is normal for some carriers. Test with your actual server instead:

```bash
ping -I wwan0 your-server-ip
```

### Interface shows "DOWN" after script completes

**Cause**: Interface needs to be brought up after configuration

**Solution**: The script already does this, but you can manually verify:

```bash
sudo ip link set wwan0 up
ip addr show wwan0
```

### DNS not resolving

**Cause**: DNS server may be unreachable or incorrect

**Solution**: Check `/etc/resolv.conf` and verify DNS:

```bash
cat /etc/resolv.conf
nslookup google.com
```

### Auto-recovery daemon not working

**Cause**: Daemon may have crashed or not started

**Solution**: Check daemon status and logs:

```bash
ps aux | grep auto-recover.sh
tail -f /var/log/cellular/auto-recover.log
```

Restart the daemon:

```bash
sudo pkill -f auto-recover.sh
export CELLULAR_LOG_DIR=/var/log/cellular
sudo -E nohup /opt/cellular/auto-recover.sh 30 &
```

### Connection drops periodically

**Cause**: Modem may need reset or bearer may be unstable

**Solution**: Use emergency modem reset:

```bash
sudo bash /opt/cellular/reset-modem.sh
sudo /opt/cellular/connect-cellular-robust.sh
```

**Note**: Update paths to match your installation directory.

Then start auto-recovery daemon to prevent future drops

---

## Monitoring the Connection

### Check modem status
```bash
mmcli -m 0
```

### Check bearer status
```bash
mmcli -b 1
```

### Check interface configuration
```bash
ip addr show wwan0
ip route show dev wwan0
```

### Monitor in real-time
```bash
mmcli -m 0 -w
```

### Test connectivity
```bash
ping -I wwan0 8.8.8.8
curl --interface wwan0 https://httpbin.org/ip
```

---

## Script Comparison

| Feature | Dynamic | Robust | Auto-Recover |
|---------|---------|--------|--------------|
| **IP Configuration** | Manual extraction | Delegated to helper | N/A |
| **Modem State Management** | Basic | Advanced | N/A |
| **Bearer Cleanup** | No | Yes | N/A |
| **DNS/Routes** | Manual | Delegated | Monitors |
| **Continuous Monitoring** | No | No | Yes |
| **Connection Recovery** | Manual | Manual | Automatic |
| **Best For** | Troubleshooting | Production | High Availability |
| **Reboot Reliability** | ✅ Works | ✅ Works | ✅ Works |
| **Error Handling** | Comprehensive | Comprehensive | Comprehensive |
| **Logging** | Detailed | Detailed | Continuous |

---

## Technical Details

### IP Address Format

The carrier assigns addresses using CIDR notation:
- **Address**: 10.19.145.184 (your device's IP)
- **Prefix**: 28 (network mask, /28 = 255.255.255.240)
- **Gateway**: 10.19.145.185 (carrier's gateway for this connection)

The `/28` prefix means:
- Network: 10.19.145.176/28
- Usable IPs: 10.19.145.177 - 10.19.145.190
- Broadcast: 10.19.145.191

### MTU Configuration

The MTU (Maximum Transmission Unit) of 1430 is typical for cellular:
- Standard Ethernet: 1500 bytes
- Cellular (with overhead): 1430 bytes
- Setting correct MTU prevents packet fragmentation

### DNS Configuration

The carrier provides DNS servers (172.26.38.2):
- These are the carrier's DNS resolvers
- May be different from public DNS (8.8.8.8)
- Script uses carrier's DNS for reliability

---

## Recommended Setup Path

### For Production Deployments

1. **Test the robust script**:

   ```bash
   sudo ~/speedcam/cellular/connect-cellular-robust.sh
   ```

2. **Verify connectivity**:

   ```bash
   ip addr show wwan0
   ping -I wwan0 8.8.8.8
   ```

3. **Start auto-recovery daemon**:

   ```bash
   sudo nohup ~/speedcam/cellular/auto-recover.sh 30 > ~/speedcam/cellular/auto-recover.log 2>&1 &
   ```

4. **Reboot and verify it still works**:

   ```bash
   sudo reboot
   # After reboot, check:
   ip addr show wwan0
   mmcli -m 0
   tail -f ~/speedcam/cellular/auto-recover.log
   ```

5. **Set up automatic startup** using systemd services (recommended)

6. **Monitor logs** to ensure it's working:

   ```bash
   sudo journalctl -u cellular-connect.service -f
   sudo journalctl -u cellular-auto-recover.service -f
   ```

### For Troubleshooting

1. **Test the dynamic script** for detailed inspection:

   ```bash
   sudo ~/speedcam/cellular/connect-cellular-dynamic.sh
   ```

2. **Check modem status**:

   ```bash
   mmcli -m 0
   mmcli -b 1
   ```

3. **Review logs**:

   ```bash
   sudo journalctl -xe
   ```

4. **Use debug script** for comprehensive diagnostics:

   ```bash
   sudo ~/speedcam/cellular/cellular-debug.sh status
   sudo ~/speedcam/cellular/cellular-debug.sh test
   ```

---

## Support

If you encounter issues:

1. **Check modem detection**:
   ```bash
   mmcli -L
   ```

2. **Verify ModemManager is running**:
   ```bash
   sudo systemctl status ModemManager
   ```

3. **Check system logs**:
   ```bash
   sudo journalctl -xe
   ```

4. **Test with minicom** (for AT commands):
   ```bash
   sudo minicom -D /dev/ttyUSB2
   AT+CPIN?
   AT+COPS?
   ```

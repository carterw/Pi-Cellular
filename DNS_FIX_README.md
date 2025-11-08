# DNS Resolution Fix for Pi-Cellular

## Problem

When the Raspberry Pi boots with the cellular modem online, `/etc/resolv.conf` may contain only the carrier's DNS server:

```text
nameserver 172.26.38.2
```

This carrier DNS server may not resolve all domains properly, causing DNS resolution failures for some websites and services.

## Symptoms

- Some domains resolve, others don't
- Intermittent DNS failures
- `nslookup` or `ping` fails for certain domains
- Works for `google.com` but fails for `github.com` or other domains

## Root Cause

Carrier DNS servers (like `172.26.38.2`) are provided by the cellular network operator. These servers:

1. May have limited domain coverage
2. Can be overloaded or slow
3. Might not resolve all public domains
4. May prioritize carrier-specific domains

## Solution

Add **fallback DNS servers** to `/etc/resolv.conf` so that if the carrier DNS fails to resolve a domain, the system automatically tries public DNS servers.

### Automatic Fix (Recommended)

Run the DNS fix script:

```bash
sudo /opt/cellular/fix-dns.sh
```

This will:
- Detect the carrier DNS from your modem
- Add Google DNS (8.8.8.8) and Cloudflare DNS (1.1.1.1) as fallbacks
- Test DNS resolution with multiple domains
- Configure both systemd-resolved and /etc/resolv.conf

### Manual Fix

Edit `/etc/resolv.conf` to add fallback DNS servers:

```bash
sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 172.26.38.2
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
```

### Updated Scripts

The connection scripts have been updated to automatically add fallback DNS servers:

- `connect-cellular-robust.sh` - Production script
- `connect-cellular-dynamic.sh` - Troubleshooting script
- `setup-dns-routes.sh` - DNS/route configuration helper

When you run these scripts, they will now configure `/etc/resolv.conf` with:

```text
nameserver 172.26.38.2    # Carrier DNS (tried first)
nameserver 8.8.8.8        # Google DNS (fallback)
nameserver 1.1.1.1        # Cloudflare DNS (fallback)
```

## How DNS Fallback Works

Linux resolvers try nameservers in order:

1. **First attempt**: Query `172.26.38.2` (carrier DNS)
2. **If timeout or failure**: Query `8.8.8.8` (Google DNS)
3. **If timeout or failure**: Query `1.1.1.1` (Cloudflare DNS)

This ensures:
- Carrier DNS is used when it works (may be faster for local content)
- Public DNS provides reliability for all domains
- No manual intervention needed

## Testing DNS Resolution

After applying the fix, test DNS resolution:

```bash
# Test multiple domains
nslookup google.com
nslookup github.com
nslookup cloudflare.com

# Test with specific DNS server
nslookup google.com 172.26.38.2  # Carrier DNS
nslookup google.com 8.8.8.8      # Google DNS
nslookup google.com 1.1.1.1      # Cloudflare DNS

# Test DNS resolution via wwan0 interface
ping -I wwan0 -c 3 google.com
ping -I wwan0 -c 3 github.com
```

## Verification

Check your current DNS configuration:

```bash
cat /etc/resolv.conf
```

Should show:

```text
nameserver 172.26.38.2
nameserver 8.8.8.8
nameserver 1.1.1.1
```

## Persistence

The DNS configuration will persist until:

1. **systemd-resolved** overwrites it (if enabled)
2. **NetworkManager** overwrites it (if managing the connection)
3. **System reboot** (if not using systemd services)

### Making it Persistent

To ensure DNS fallback is configured on every boot:

1. **Use systemd services** (recommended):

   ```bash
   sudo systemctl enable cellular-connect.service
   sudo systemctl enable cellular-auto-recover.service
   ```

2. **Or add to rc.local**:

   ```bash
   sudo nano /etc/rc.local
   # Add before 'exit 0':
   /opt/cellular/connect-cellular-robust.sh
   ```

## Troubleshooting

### DNS still not working

If DNS resolution still fails after adding fallback servers:

```bash
# Check if systemd-resolved is interfering
sudo systemctl status systemd-resolved

# If active, configure it directly
sudo resolvectl dns wwan0 172.26.38.2 8.8.8.8 1.1.1.1

# Or disable it
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

### NetworkManager overwriting DNS

If NetworkManager is managing the connection:

```bash
# Check NetworkManager status
systemctl status NetworkManager

# Configure DNS via nmcli
nmcli device show wwan0

# Or disable NetworkManager for wwan0
nmcli device set wwan0 managed no
```

### Verify which DNS is being used

```bash
# Show current DNS configuration
resolvectl status wwan0

# Or check resolv.conf
cat /etc/resolv.conf

# Test which DNS server responds
dig google.com
```

## Alternative DNS Servers

If you prefer different DNS servers, you can use:

**Google DNS:**
- Primary: 8.8.8.8
- Secondary: 8.8.4.4

**Cloudflare DNS:**
- Primary: 1.1.1.1
- Secondary: 1.0.0.1

**Quad9 DNS:**
- Primary: 9.9.9.9
- Secondary: 149.112.112.112

**OpenDNS:**
- Primary: 208.67.222.222
- Secondary: 208.67.220.220

Edit `/etc/resolv.conf` with your preferred servers:

```bash
sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 172.26.38.2
nameserver 9.9.9.9
nameserver 149.112.112.112
EOF
```

## Summary

- **Problem**: Carrier DNS (172.26.38.2) doesn't resolve all domains
- **Solution**: Add fallback DNS servers (8.8.8.8, 1.1.1.1)
- **Quick Fix**: Run `sudo /opt/cellular/fix-dns.sh`
- **Automatic**: Updated connection scripts now add fallback DNS
- **Result**: Reliable DNS resolution for all domains

The DNS fallback approach ensures your cellular connection works reliably for all internet services, not just those the carrier DNS can resolve.

# Broadcom BCM4360 WiFi Fix for MacBook Pro 2013 on Ubuntu 24.04 (Kernel 6.17+)

The MacBook Pro 2013 (MacBookPro11,x) uses a Broadcom BCM4360 802.11ac wireless chipset (PCI ID `14e4:43a0`). On Ubuntu 24.04 with kernel 6.17+, the packaged `broadcom-sta-dkms` driver fails to compile due to breaking kernel API changes.

This repository provides patches to fix the build and an install script to automate the process.

## The Problem

When you install `broadcom-sta-dkms` on kernel 6.17, the DKMS build fails with errors like:

```
src/shared/linux_osl.c:23:10: fatal error: typedefs.h: No such file or directory
```

and (if you work around that):

```
error: implicit declaration of function 'from_timer'
error: implicit declaration of function 'del_timer'
error: initialization of 'int (*)(struct wiphy *, int, u32)' from incompatible pointer type
```

This happens because kernel 6.17 introduced several breaking changes:

1. **`EXTRA_CFLAGS` removed** - The kernel build system no longer maps `EXTRA_CFLAGS` to compiler flags. Modules must use `ccflags-y` instead. Without this, the `-I` include paths are silently dropped, causing the `typedefs.h` not found error.

2. **Timer API changes** - `from_timer()` was removed in favor of `timer_container_of()`. `del_timer()` was renamed to `timer_delete()`.

3. **cfg80211 API signature changes** - `set_wiphy_params`, `set_tx_power`, and `get_tx_power` callbacks gained a new `int radio_idx` parameter.

### Why not use the open-source b43 driver?

The `b43` driver does not support the AC PHY on the BCM4360 rev 03. Loading it produces:

```
b43-phy0 ERROR: FOUND UNSUPPORTED PHY (Analog 12, Type 11 (AC), Revision 1)
```

The proprietary `broadcom-sta` (`wl`) driver is the only option for this chipset.

## Quick Start

```bash
git clone https://github.com/rgardam/mbp2013-ubuntu-broadcom.git
cd mbp2013-ubuntu-broadcom
./install.sh
```

The script will:
1. Install the `broadcom-sta-dkms` package
2. Apply the kernel compatibility patches
3. Build and install the module via DKMS
4. Blacklist conflicting open-source Broadcom modules
5. Load the `wl` driver and verify the wireless interface comes up

After running, connect to WiFi:

```bash
nmcli device wifi list
nmcli device wifi connect "YourSSID" password "YourPassword"
```

## Manual Steps

If you prefer to apply the patches manually:

### 1. Install the base package

```bash
sudo apt-get install broadcom-sta-dkms
# This will fail to build - that's expected
```

### 2. Apply patches

```bash
# Fix Makefile: EXTRA_CFLAGS -> ccflags-y, EXTRA_LDFLAGS -> ldflags-y
sudo patch -p0 -d / < patches/001-fix-makefile-ccflags.patch

# Fix linuxver.h: del_timer_sync -> timer_delete
sudo patch -p0 -d / < patches/002-fix-timer-api-linuxver.patch

# Fix wl_linux.c: from_timer -> timer_container_of, del_timer -> timer_delete
sudo patch -p0 -d / < patches/003-fix-timer-api-wl-linux.patch

# Fix wl_cfg80211_hybrid.c: add radio_idx parameter to cfg80211 callbacks
sudo patch -p0 -d / < patches/004-fix-cfg80211-api-signatures.patch
```

### 3. Rebuild with DKMS

```bash
sudo dkms remove broadcom-sta/6.30.223.271 --all
sudo dkms add /usr/src/broadcom-sta-6.30.223.271
sudo dkms build broadcom-sta/6.30.223.271
sudo dkms install broadcom-sta/6.30.223.271
```

### 4. Blacklist conflicting modules

```bash
cat <<'EOF' | sudo tee /etc/modprobe.d/broadcom-wl-blacklist.conf
blacklist b43
blacklist b43legacy
blacklist bcma
blacklist ssb
blacklist brcmfmac
blacklist brcmsmac
EOF

echo "wl" | sudo tee /etc/modules-load.d/wl.conf
```

### 5. Load the driver

```bash
sudo modprobe -r b43 bcma ssb 2>/dev/null
sudo modprobe wl
```

## What the Patches Fix

| Patch | File | Change | Why |
|-------|------|--------|-----|
| 001 | `Makefile` | `EXTRA_CFLAGS` -> `ccflags-y`, `EXTRA_LDFLAGS` -> `ldflags-y` | Kernel 6.17 dropped legacy `EXTRA_CFLAGS` support |
| 002 | `src/include/linuxver.h` | `del_timer()` -> `timer_delete()` | Timer API rename in kernel 6.17 |
| 003 | `src/wl/sys/wl_linux.c` | `from_timer()` -> `timer_container_of()`, `del_timer()` -> `timer_delete()` | Timer API removal/rename in kernel 6.17 |
| 004 | `src/wl/sys/wl_cfg80211_hybrid.c` | Add `int radio_idx` param to `set_wiphy_params`, `set_tx_power`, `get_tx_power` | cfg80211 callback signature change in kernel 6.17 |

## Tested On

- MacBook Pro 11,1 (Late 2013, 13")
- Ubuntu 24.04 LTS
- Kernel 6.17.0-20-generic
- Broadcom BCM4360 rev 03 (PCI ID 14e4:43a0)
- broadcom-sta-dkms 6.30.223.271-23ubuntu1.1

## Troubleshooting

**No wireless interface after install:**
```bash
sudo dmesg | grep -i wl     # Check for driver errors
lsmod | grep wl             # Verify module is loaded
lspci | grep -i broadcom    # Confirm hardware is detected
```

**Driver doesn't survive reboot:**
Ensure the blacklist and module load configs are in place:
```bash
cat /etc/modprobe.d/broadcom-wl-blacklist.conf
cat /etc/modules-load.d/wl.conf
```

**Kernel update breaks WiFi again:**
DKMS should auto-rebuild, but if the new kernel introduces further API changes, the patches may need updating. Re-run `./install.sh` after updating the patches.

## License

The patches modify Broadcom's proprietary driver source which is distributed under its own license. The patches and install script in this repository are provided as-is for convenience.

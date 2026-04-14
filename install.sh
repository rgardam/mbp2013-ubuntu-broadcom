#!/bin/bash
set -euo pipefail

# Broadcom BCM4360 wireless driver fix for MacBook Pro 2013 on Ubuntu 24.04
# with kernel 6.17+
#
# This script installs and patches the broadcom-sta (wl) driver to compile
# against newer kernels where the upstream DKMS package fails to build.

PATCHES_DIR="$(cd "$(dirname "$0")/patches" && pwd)"
KVER="${KVER:-$(uname -r)}"
SRC_DIR="/usr/src/broadcom-sta-6.30.223.271"

echo "==> Installing broadcom-sta-dkms package..."
sudo apt-get update -qq
sudo apt-get install -y broadcom-sta-dkms 2>/dev/null || true

if [ ! -d "$SRC_DIR" ]; then
    echo "ERROR: broadcom-sta source not found at $SRC_DIR"
    echo "       Try: sudo apt-get install broadcom-sta-dkms"
    exit 1
fi

echo "==> Applying kernel compatibility patches..."
for patch in "$PATCHES_DIR"/*.patch; do
    echo "    Applying $(basename "$patch")..."
    sudo patch -p0 -d / --forward < "$patch" || true
done

echo "==> Removing broken DKMS build (if any)..."
sudo dkms remove broadcom-sta/6.30.223.271 --all 2>/dev/null || true

echo "==> Building module with DKMS..."
sudo dkms add "$SRC_DIR" 2>/dev/null || true
sudo dkms build broadcom-sta/6.30.223.271 -k "$KVER"
sudo dkms install broadcom-sta/6.30.223.271 -k "$KVER"

echo "==> Blacklisting conflicting modules..."
sudo tee /etc/modprobe.d/broadcom-wl-blacklist.conf > /dev/null <<'BLACKLIST'
blacklist b43
blacklist b43legacy
blacklist bcma
blacklist ssb
blacklist brcmfmac
blacklist brcmsmac
BLACKLIST

echo "==> Configuring wl module to load at boot..."
echo "wl" | sudo tee /etc/modules-load.d/wl.conf > /dev/null

echo "==> Unloading conflicting modules and loading wl..."
sudo modprobe -r b43 b43legacy bcma ssb brcmfmac brcmsmac 2>/dev/null || true
sudo modprobe wl

echo ""
echo "==> Done! Checking for wireless interface..."
if ip link show | grep -q wlp; then
    IFACE=$(ip link show | grep wlp | awk -F: '{print $2}' | tr -d ' ')
    echo "    Wireless interface '$IFACE' is up."
    echo ""
    echo "    Connect to WiFi with:"
    echo "      nmcli device wifi list"
    echo "      nmcli device wifi connect \"YourSSID\" password \"YourPassword\""
else
    echo "    WARNING: No wireless interface detected."
    echo "    Try rebooting, or check: sudo dmesg | grep wl"
fi

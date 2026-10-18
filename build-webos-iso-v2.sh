#!/usr/bin/env bash
set -euo pipefail

HTML="${1:-WebOS10.html}"
[ -f "$HTML" ] || { echo "Usage: sudo $0 path/to/WebOS10.html"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo."; exit 1; }
HTML="$(readlink -f "$HTML")"
ARCH="${ARCH:-$(dpkg --print-architecture)}"
case "$ARCH" in
  amd64) BOOTLOADERS="syslinux,grub-efi" ;;
  arm64) BOOTLOADERS="grub-efi" ;;
  *) echo "Unsupported architecture: $ARCH (use amd64 or arm64)"; exit 1 ;;
esac
OUT="$(pwd)/WebOS10-boot-$ARCH.iso"

echo "==> Installing build tools"
apt-get update
apt-get install -y live-build debootstrap debian-archive-keyring squashfs-tools xorriso

START="$(pwd)"
BUILD="${BUILD_DIR:-/var/tmp/webos-iso-build}"
rm -rf "$START/webos-iso-build" "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"
trap 'cp "$BUILD/build.log" "$START/webos-build.log" 2>/dev/null || true' EXIT

echo "==> Configuring the live image"
lb config \
  --distribution bookworm \
  --architectures "$ARCH" \
  --linux-flavours "$ARCH" \
  --binary-images iso-hybrid \
  --bootloaders "$BOOTLOADERS" \
  --debian-installer none \
  --iso-application "WebOS 10" \
  --iso-volume "WEBOS10" \
  --bootappend-live "boot=live components quiet"

echo "==> Choosing packages"
mkdir -p config/package-lists
cat > config/package-lists/webos.list.chroot <<'PKGS'
xserver-xorg-core
xserver-xorg-input-all
xserver-xorg-video-all
xinit
x11-xserver-utils
openbox
chromium
fonts-noto-color-emoji
fonts-dejavu-core
pulseaudio
alsa-utils
network-manager
PKGS

echo "==> Adding WebOS 10 and the kiosk startup files"
mkdir -p config/includes.chroot/opt/webos config/includes.chroot/etc/skel
cp "$HTML" config/includes.chroot/opt/webos/index.html

cat > config/includes.chroot/etc/skel/.bash_profile <<'EOS'
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx
fi
EOS

cat > config/includes.chroot/etc/skel/.xinitrc <<'EOS'
xset s off
xset -dpms
xset s noblank
openbox &
exec chromium --kiosk --no-first-run --disable-features=Translate \
  --password-store=basic --user-data-dir=/tmp/webos-profile \
  --autoplay-policy=no-user-gesture-required \
  file:///opt/webos/index.html
EOS

echo "==> Building (this downloads about 1 GB and takes 10 to 30 minutes)"
lb build 2>&1 | tee build.log

ISO="$(ls -1 ./*.iso | head -n 1)"
cp "$ISO" "$OUT"
echo
echo "Done: $OUT"
echo "Next: attach it as the boot CD in UTM, VirtualBox or QEMU, or write it to a USB stick."

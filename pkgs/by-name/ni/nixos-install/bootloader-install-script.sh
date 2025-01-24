# shellcheck shell=bash

set -e
# Clear the cache for executable locations. They were invalidated by the chroot.
hash -r
# Create a bind mount for each of the mount points inside the target file
# system. This preserves the validity of their absolute paths after changing
# the root with `nixos-enter`.
# Without this the bootloader installation may fail due to options that
# contain paths referenced during evaluation, like initrd.secrets.
# when not root, re-execute the script in an unshared namespace
mount --rbind --mkdir / "$mountPoint"
mount --make-rslave "$mountPoint"
NIXOS_INSTALL_BOOTLOADER=1 /run/current-system/bin/switch-to-configuration boot
umount -R "$mountPoint" && (rmdir "$mountPoint" 2>/dev/null || true)

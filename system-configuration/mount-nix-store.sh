#!/bin/sh
set -eu

normal_dir="$1"
efi_var="/sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"

if [ ! -r "$efi_var" ]; then
  echo "Cannot select Nix store: LoaderEntrySelected is missing or unreadable" >&2
  exit 1
fi

entry=$(dd if="$efi_var" bs=1 skip=4 2>/dev/null | tr -d '\0')
case "$entry" in
nixos-a.efi) group="a" ;;
nixos-b.efi) group="b" ;;
*)
  echo "Cannot select Nix store: unsupported boot entry '$entry'" >&2
  exit 1
  ;;
esac

cat >"$normal_dir/sysroot-nix-store.mount" <<EOF
[Unit]
Description=Mount NixOS Store (group $group)
After=sysroot.mount
Before=initrd-fs.target

[Mount]
What=/dev/disk/by-partlabel/nix-store-$group
Where=/sysroot/nix/store
Type=squashfs
Options=ro
EOF

# Switching root requires the store selected by the booted UKI.
mkdir -p "$normal_dir/initrd-fs.target.requires"
ln -s ../sysroot-nix-store.mount "$normal_dir/initrd-fs.target.requires/"

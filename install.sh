#!/bin/bash
set -e

echo "Creating filesystems..."
mkfs.fat -F 32 /dev/xvda2
mkfs.btrfs -f /dev/xvda3 /dev/xvdb1 /dev/xvdc1 /dev/xvde1

echo "Creating Btrfs subvolumes..."
mount /dev/xvda3 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@data
cd /
umount /mnt

echo "Mounting filesystems..."
mount -o subvol=@ /dev/xvda3 /mnt
mkdir -p /mnt/{home,nix,data,boot}
mount -o subvol=@home /dev/xvda3 /mnt/home
mount -o subvol=@nix /dev/xvda3 /mnt/nix
mount -o subvol=@data /dev/xvda3 /mnt/data
mount /dev/xvda2 /mnt/boot

echo "Generating NixOS configuration..."
nixos-generate-config --root /mnt

echo "Copying configuration files..."
curl -o /mnt/etc/nixos/configuration.nix https://raw.githubusercontent.com/yourusername/nixos-install/main/configuration.nix

echo "Installing NixOS..."
nixos-install

echo "Installation complete! You can now reboot."

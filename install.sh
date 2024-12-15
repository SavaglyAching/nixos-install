#!/bin/bash
set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root"
fi

# Gather network configuration
log "Please enter network configuration:"
read -p "Enter IP address: " IP_ADDRESS
read -p "Enter gateway: " GATEWAY

# Validate inputs
if [[ ! $IP_ADDRESS =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid IP address format"
fi

if [[ ! $GATEWAY =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid gateway format"
fi

if [[ -z "$SSH_KEY" ]]; then
    error "SSH key cannot be empty"
fi

# Create filesystems
log "Creating filesystems..."
mkfs.fat -F 32 /dev/xvda2 || error "Failed to create FAT32 filesystem"
mkfs.btrfs -f /dev/xvda3 /dev/xvdb1 /dev/xvdc1 /dev/xvde1 || error "Failed to create Btrfs filesystem"

# Create and mount Btrfs subvolumes
log "Creating Btrfs subvolumes..."
mount /dev/xvda3 /mnt || error "Failed to mount btrfs"
btrfs subvolume create /mnt/@ || error "Failed to create @ subvolume"
btrfs subvolume create /mnt/@home || error "Failed to create @home subvolume"
btrfs subvolume create /mnt/@nix || error "Failed to create @nix subvolume"
btrfs subvolume create /mnt/@data || error "Failed to create @data subvolume"
cd /
umount /mnt

log "Mounting filesystems..."
mount -o subvol=@ /dev/xvda3 /mnt || error "Failed to mount @ subvolume"
mkdir -p /mnt/{home,nix,data,boot}
mount -o subvol=@home /dev/xvda3 /mnt/home || error "Failed to mount @home"
mount -o subvol=@nix /dev/xvda3 /mnt/nix || error "Failed to mount @nix"
mount -o subvol=@data /dev/xvda3 /mnt/data || error "Failed to mount @data"
mount /dev/xvda2 /mnt/boot || error "Failed to mount boot"

log "Generating NixOS configuration..."
nixos-generate-config --root /mnt || error "Failed to generate config"

# Create configuration.nix
log "Creating NixOS configuration..."
cat > /mnt/etc/nixos/configuration.nix << EOF
{ config, lib, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  boot.initrd.availableKernelModules = [ "xen_blkfront" "btrfs" ];
  boot.supportedFilesystems = [ "btrfs" ];
  boot.loader.grub = {
    enable = true;
    device = "/dev/xvda";
    efiSupport = false;
  };

  time.timeZone = "UTC";
  networking.networkmanager.enable = true;

  users.users.ham = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable 'sudo' for the user
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJKT1Y56T+DXeKyB1eJlgtttnUxv2X78k2LrRmWxNg1F ham@nixos-mini"
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    btrfs-progs
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "9.9.9.9" ];
    defaultGateway = "${GATEWAY}";
    interfaces = {
      enX0 = {
        useDHCP = false;
        ipv4.addresses = [{
          address = "${IP_ADDRESS}";
          prefixLength = 24;
        }];
      };
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  system.stateVersion = "24.11";
}
EOF

log "Installing NixOS..."
nixos-install || error "Installation failed"

success "Installation complete! You can now reboot."
success "Make sure to save these credentials:"
echo "IP Address: ${IP_ADDRESS}"
echo "Gateway: ${GATEWAY}"
echo "SSH key is configured for user 'ham'"

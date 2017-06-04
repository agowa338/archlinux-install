# Install ARCH Linux with encrypted file-system and UEFI
# The official installation guide (https://wiki.archlinux.org/index.php/Installation_Guide) contains a more verbose description.

# Download the archiso image from https://www.archlinux.org/
# Copy to a usb-drive
dd if=archlinux.img of=/dev/sdX bs=16M && sync # on linux

# Boot from the usb. If the usb fails to boot, make sure that secure boot is disabled in the BIOS configuration.

# Set german keymap
loadkeys de-latin1

# This assumes a wifi only system...
wifi-menu

# Create partitions
cgdisk /dev/sda
# 1 100MB EFI partition # Hex code ef00
# 2 250MB Boot partition # Hex code 8300
# 3 100% size partiton # (to be encrypted) Hex code 8300

mkfs.vfat -F32 /dev/sda1
mkfs.ext2 /dev/sda2

# Setup the encryption of the system
cryptsetup -c aes-xts-plain64 -y --use-random luksFormat /dev/sda3
cryptsetup luksOpen /dev/sda3 luks

# Create encrypted partitions
# This creates one partions for root, modify if /home or other partitions should be on separate partitions
pvcreate /dev/mapper/luks
vgcreate vg0 /dev/mapper/luks
lvcreate --size 8G vg0 --name swap
lvcreate -l +100%FREE vg0 --name root

# Create filesystems on encrypted partitions
mkfs.ext4 /dev/mapper/vg0-root
mkswap /dev/mapper/vg0-swap

# Mount the new system 
mount /dev/mapper/vg0-root /mnt # /mnt is the installed system
swapon /dev/mapper/vg0-swap # Not needed but a good thing to test
mkdir /mnt/boot
mount /dev/sda2 /mnt/boot
mkdir /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

# Install the system also includes stuff needed for starting wifi when first booting into the newly installed system
# Unless vim and zsh are desired these can be removed from the command
pacstrap /mnt base base-devel grub-efi-x86_64 zsh vim nano bash htop net-tools git efibootmgr dialog wpa_supplicant

# 'install' fstab
genfstab -pU /mnt >> /mnt/etc/fstab
# Make /tmp a ramdisk (add the following line to /mnt/etc/fstab)
tmpfs	/tmp	tmpfs	defaults,noatime,mode=1777	0	0
# Change relatime on all non-boot partitions to noatime (reduces wear if using an SSD)

# Enter the new system
arch-chroot /mnt /bin/bash

# Setup system clock
rm /etc/localtime
ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc --utc

# Set the hostname
echo MYHOSTNAME > /etc/hostname

# Set DNS-Server
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

# Update locale
echo LANG=en_US.UTF-8 >> /etc/locale.conf
echo LANGUAGE=en_US >> /etc/locale.conf
echo LC_ALL=C >> /etc/locale.conf

# Set password for root
passwd

# Configure mkinitcpio with modules needed for the initrd image
vi /etc/mkinitcpio.conf
# Add 'ext4' to MODULES
# Add 'encrypt' and 'lvm2' to HOOKS before filesystems

# Regenerate initrd image
mkinitcpio -p linux

# Setup grub
grub-install
vi /etc/default/grub # edit the line GRUB_CMDLINE_LINUX to GRUB_CMDLINE_LINUX="cryptdevice=/dev/sda3:luks:allow-discards" then run:
grub-mkconfig -o /boot/grub/grub.cfg

# Exit new system and go into the cd shell
exit

# Unmount all partitions
umount -R /mnt
swapoff -a

# Reboot into the new system, don't forget to remove the cd/usb
reboot

# Set keyboard layout
loadkeys de-latin1
localectl set-x11-keymap de pc105 de_nodeadkeys
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
echo 'de_DE.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen

# Install packages
pacman -S xorg-server xorg-xinit xorg-drivers xf86-input-synaptics xorg-fonts-75dpi xorg-fonts-100dpi
pacman -S plasma-meta kde-l10n-de kde-applications-meta sddm sddm-kcm plasma-wayland-session kde-applications-meta ttf-dejavu ttf-liberation
pacman -S acpid kdegraphics-thumbnailers ffmpegthumbs print-manager cups colord argyllcms chromium firefox kdeconnect sshfs
pacman -S networkmanager-dispatcher-sshd networkmanager-dispatcher-ntpd dnsmasq

# Enable kde networkmanager
systemctl enable NetworkManager.service

# Enable KDE Wallet unlock on logon
echo "auth            optional        pam_kwallet5.so" >> /etc/pam.d/sddm
echo "session         optional        pam_kwallet5.so auto_start" >> /etc/pam.d/sddm

# Add SSH Key to KDE Wallet
echo 'export SSH_ASKPASS="/usr/bin/ksshaskpass"' >> /etc/profile
echo '#!/bin/sh' > ~/.config/autostart-scripts/ssh-add.sh
echo 'ssh-add </dev/null' >> ~/.config/autostart-scripts/ssh-add.sh
mkdir /etc/skel/.config
mkdir /etc/skel/.config/autostart-scripts
echo '#!/bin/sh' > ~/.config/autostart-scripts/ssh-add.sh
echo 'ssh-add </dev/null' >> ~/.config/autostart-scripts/ssh-add.sh

# Add Multilib
echo '[multilib]' >> /etc/pacman.conf
echo 'Include = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf
pacman -Syu

# Enable acpi for notebooks
sudo systemctl enable acpid

# Install missing firmware and than
# Regenerate initrd image
mkinitcpio -p linux

# Allow sudo for group wheel
echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers

# Add real user remove -s flag if you don't whish to use zsh
useradd -m -g users -G wheel -s /bin/zsh user
passwd user

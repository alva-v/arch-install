#!/bin/bash
# This scrip installs an encrypted Arch linux system

set -e # Exit when encountering an error

check_efi(){
    if ls /sys/firmware/efi/efivars > /dev/null 2>&1; then
        echo "System is EFI"
    else
        echo "System is not EFI, script incompatible"
        exit 1
    fi
}

check_internet() {
    if curl -s --max-time 5 --head cloudflare.com > /dev/null 2>&1; then
        echo "Online"
    else
        echo "Offline, please connect to the internet"
        exit 1
    fi
}

delete_old_partitions() {
    local device="${1}"
    if lsblk -n "$device" | grep -q "part"; then
        echo "Deleting partitions on $device..."
        sfdisk --delete "$device"
    else
        echo "No partitions found on $device, skipping deletion."
    fi
}

get_name() {
    local name_type="${1}"
    name=$(whiptail --nocancel --inputbox "${name_type^}: " 8 35 3>&1 1>&2 2>&3)
    while ! echo "${name}" |grep -q "^[a-z][a-z0-9_-]*$"; do
	    name=$(whiptail --nocancel --inputbox "Invalid ${name_type}.\nGive a valid ${name_type} starting with a lowercase letter and only containing lowercase letters, digits, - or _" 10 60 3>&1 1>&2 2>&3)
    done
    echo "${name}"
}

get_password() {
    local password_type="${1}"
    password_value=$(whiptail --passwordbox "${password_type^} passphrase: " 8 35 3>&1 1>&2 2>&3)
    password_value2=$(whiptail --passwordbox "Repeat passphrase: " 8 35 3>&1 1>&2 2>&3)
    while [ "$password_value" != "$password_value2" ]; do
        password_value=$(whiptail --passwordbox "${password_type^} passphrases don't match.\nEnter your passphrase again: " 9 35 3>&1 1>&2 2>&3)
        password_value2=$(whiptail --passwordbox "Repeat passphrase: " 8 35 3>&1 1>&2 2>&3)
    done
    echo "${password_value}"
}

set_up_keyring() {
    echo "Initializing pacman keyring..."
    pacman --noconfirm --sync --refresh archlinux-keyring
    pacman-key --init
}

set_up_mirror_list() {
    echo "Setting up mirror list..."
    pacman --sync --refresh
    pacman --noconfirm --sync reflector
    reflector -c FR -f 12 -l 10 --save /etc/pacman.d/mirrorlist
}

check_internet
check_efi

username=$(get_name "username")
hostname=$(get_name "hostname")

cryptpass=$(get_password "drive decryption")
password=$(get_password "user")

device_list=$(lsblk -dplnx size -o name,size | grep -vE "boot|rpmb|loop"|tac)
device=$(whiptail --menu "Device: " 0 0 0 ${device_list} 3>&1 1>&2 2>&3)

if ! whiptail --yesno --defaultno "You are about to wipe ${device}\nContinue?" 8 35; then
    echo "Aborting installation."
    exit 1
fi


delete_old_partitions "$device" || error "Couldn't delete old partitions"
echo "Creating partitions..."
sfdisk "$device" << EOF
label:gpt
start=2048 size=512MB
,;
EOF
mkfs.fat -F32 "$device"1
echo "Encrypting ${device}2..."
echo -n "$cryptpass" | cryptsetup luksFormat "$device"2
echo "Setting up ${device}2 encrypted partition..."
echo -n "$cryptpass" | cryptsetup open "$device"2 cryptlvm
mkfs.btrfs /dev/mapper/cryptlvm

echo "Mounting partitions..."
mount /dev/mapper/cryptlvm /mnt
mount --mkdir "$device"1 /mnt/boot

set_up_keyring || error "Error initializing pacman keyring"
set_up_mirror_list || echo "Error setting up mirror list, using defaults."

echo "Installing packages on root..."
pacstrap -K /mnt base base-devel linux linux-firmware grub networkmanager cryptsetup lvm2 efibootmgr vim sudo man-db man-pages texinfo

echo "Setting up system clock..."
arch-chroot /mnt << EOF
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
systemctl enable systemd-timesyncd.service
EOF

echo "Setting up locales..."
arch-chroot /mnt << EOF
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf
EOF

echo "Setting up network..."
arch-chroot /mnt << EOF
echo "$hostname" > /etc/hostname
echo -e "127.0.1.1 \t $hostname.localdomain \t $hostname" >> /etc/hosts
systemctl enable NetworkManager.service
EOF

echo "Setting up user..."
custom_sudoers="/etc/sudoers.d/${hostname}"
arch-chroot /mnt << EOF
useradd -G wheel -m "$username"
echo -n "$password" | passwd --stdin "$username"
echo "%wheel ALL=(ALL:ALL) ALL" | EDITOR="tee -a" visudo --file="$custom_sudoers"
EOF

echo "Setting up boot loading..."
arch-chroot /mnt << EOF
sed -i "s/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard sd-vconsole block encrypt lvm2 filesystems)/" /etc/mkinitcpio.conf
mkinitcpio -p linux
EOF
genfstab -U /mnt >> /mnt/etc/fstab
cryptdevice=$(blkid "$device"2 -s UUID -o value)
cryptlvm=$(blkid /dev/mapper/cryptlvm -s UUID -o value)
sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=${cryptdevice}:cryptlvm root=UUID=${cryptlvm}\"/" /mnt/etc/default/grub

echo "Installing GRUB..."
arch-chroot /mnt << EOF
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation done, you can reboot!"
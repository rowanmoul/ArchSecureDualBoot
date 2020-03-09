#!/bin/bash

build() {
    local mod

    add_module "efivarfs"

    add_binary "efibootmgr"

    add_runscript
}

help() {
    cat <<HELPEOF
This hook can be used to create an initramfs that boots Windows
in a manner that will not break TPM backed Bitlocker encryption.
It sets the EFI bootnext variable to 0000 (The default location for Windows'
efi boot entry) and reboots the computer.
If your Windows boot entry is not 0000, specify 'win_boot_entry=0000'
on the kernel command line with the correct 4 digit entry number
HELPEOF
}

# vim: set ft=sh ts=4 sw=4 et:
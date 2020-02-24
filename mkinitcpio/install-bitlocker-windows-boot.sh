#!/bin/bash

build() {
    local mod

    add_module "efivars"

    add_binary "efibootmgr"

    add_runscript
}

help() {
    cat <<HELPEOF
This hook allows you to boot Windows in a manner that will not break TPM backed Bitlocker encryption.
It sets the EFI bootnext variable to 0000 (The default location for Windows efi boot entry) and reboots the computer.
If your Windows boot entry is not 0000, you can move it to the 0 slot with efibootmgr, or modify this hook to point to the entry of your choice.
HELPEOF
}

# vim: set ft=sh ts=4 sw=4 et:
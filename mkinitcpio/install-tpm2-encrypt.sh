#!/bin/bash

build() {
    local mod

    add_module "tpm"

    add_binary "tpm2-load" # and many others...

    add_runscript
}

help() {
    cat <<HELPEOF
This hook is an extension for the 'encrypt' hook that allows for an encrypted root device that can be unlocked with a TPM 2.0 device.
It MUST come before the 'encrypt' hook, and will generate a keyfile in the default location for the 'encrypt' hook to use.

Users should specify the device to be unlocked according the requirements of the 'enccrypt' hook.

For unlocking via TPM 2.0, 'cryptkeytpm=name:handle' should be specified on
the kernel cmdline, where 'name' represents the TPM Entity's name, and 'handle' is the location of the entity in
the tpm's NV storage.

Without specifying a TPM key, or if the TPM fails to unseal the key, you will be prompted for the password at runtime.
This means you must have a keyboard available to input it, and you may need
the keymap hook as well to ensure that the keyboard is using the layout you
expect.

In the case that the TPM fails to unseal the key, a list of PCR values that changed since the last seal will be shown,
and you will be asked if you want to re-seal on the new PCR values after unlocking the volume with a password.
HELPEOF
}

# vim: set ft=sh ts=4 sw=4 et:
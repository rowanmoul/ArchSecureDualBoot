#!/bin/bash

build() {
    local mod

    # Add the tpm kernel module so we can access the tpm
    add_module "tpm"

    # Add the multitude of tpm2-tools needed by this hook. Linked libraries will also be copied automatically.
    add_binary "tpm2_pcrread"
    add_binary "tpm2_verifysignature"
    add_binary "tpm2_startauthsession"
    add_binary "tpm2_policypcr"
    add_binary "tpm2_policycountertimer"
    add_binary "tpm2_readclock"
    add_binary "tpm2_policyauthorize"
    add_binary "tpm2_unseal"
    add_binary "tpm2_flushcontext"

    # Add the runtime hooks found in the hooks-tpm2-encrypt file.
    add_runscript
}

help() {
    cat <<HELPEOF
This hook is an extension for the 'encrypt' hook that allows for an encrypted root device that can be unlocked with a TPM 2.0 device.
It MUST come before the 'encrypt' hook, and will generate a keyfile in the default location for the 'encrypt' hook to use.

Users should specify the device to be unlocked according the requirements of the 'encrypt' hook.

For unlocking via TPM 2.0, this hook makes use of LUKS passphrase sealed in a TPM object that is restricted with a policy that requires a second policy signed with an authorization key. Intial setup is too lengthy for this help text. Please refer to the readme in this repo: https://github.com/rowanmoul/ArchSecureDualBoot

To specify the sealed TPM object's location in the TPM NVRAM, 'tpm_sealed_key=handle' can be specified on
the kernel command line, where 'handle' is either a hexidecimal value indicating the NVRAM location directly (in the form 0x81000000), or the path to a handle file on the EFI system partition.
If this argument is not specified the hook will look for a file called 'sealed-passphrase.handle' in /EFI/arch/tpm2-encrypt on the EFI system partition.

To specify the policy authorization key's location in the TPM NVRAM, 'tpm_policy_auth=name:handle' can be specified on the kernel command line.
'name' is the name of the key in the TPM, (typically a sha256 digest), or the path to a name file in on the EFI system partition.
'handle' is as above for the sealed key except is specifies the location of the policy authorization key.
If this argument is not specified, the hook will look for files called 'policy-authorization-key.name' and 'policy-authorization-key.handle' in /EFI/arch/tpm2-encrypt on the EFI system partition.

In order to access the EFI system partition, `efi_part=device` must be specified on the kernel command line, where 'device' can be a location in /dev or a uuid etc. Refer to documentation for specifying the `root=device` argument for formatting details.

If the handle of a TPM entity cannot be found, or if the TPM fails to unseal the key, you will be prompted for the passphrase.
This means you must have a keyboard available to input it, and you may need
the keymap hook as well to ensure that the keyboard is using the layout you
expect.

In the case that the TPM fails to unseal the key, a list of PCR values that changed since the last seal will be shown,
and you will be asked if you want to re-seal on the new PCR values after unlocking the volume with a password. The previous values are signed and verified with the policy authorization key to maintain integrity and trust.
HELPEOF
}

# vim: set ft=sh ts=4 sw=4 et:
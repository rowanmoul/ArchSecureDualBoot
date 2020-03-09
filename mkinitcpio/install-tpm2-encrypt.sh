#!/bin/bash

build() {
    local mod

    # Add the tpm kernel module so we can access the tpm
    add_module "tpm"

    # Add filesystem modules for fat and vfat so we can mount the efi partition
    add_module "fat"
    add_module "vfat"

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
    add_binary "tpm2_sign"

    # Add the runtime hooks found in the hooks-tpm2-encrypt file.
    add_runscript
}

help() {
    cat <<HELPEOF
This hook is an extension for the 'encrypt' hook that allows for an encrypted
root device that can be unlocked with a TPM 2.0 device.
It MUST come before the 'encrypt' hook, and will generate a keyfile in the
default location for the 'encrypt' hook to use.

Users should specify the device to be unlocked according to
the requirements of the 'encrypt' hook.

For unlocking via TPM 2.0, this hook makes use of LUKS passphrase sealed in a
TPM object that is restricted with a policy that requires a second policy signed
with an authorization key. Intial setup is too lengthy for this help text.
Please refer to the readme in this repo:
https://github.com/rowanmoul/ArchSecureDualBoot

required kernel command line arguments:

tpm_efi_part=device
    - Must be specified on the kernel command line in order to access
      the EFI system partition.
    - 'device' can be a location in /dev or a uuid etc.
    - Refer to documentation for specifying the 'root=device' argument for
      formatting details, but uuid is recommended.
    - Technicaly you could put any unencrypted  fat or vfat partition here.
      EFI is just the simplest and should always be available.

optional kernel command line arguments:

'tpm_file_dir=directory'
    - Specifies the directory in which to look for files needed by this hook
      such as authorized policy files, signatures, and key handle files.
    - 'directory' is the path to a directory on the partition given by
      'tpm_efi_part' and must begin with a / at the top level of that partition.
    - This directory should contain all of the files specified in the below
      optional arguments, as well as the authorized and temporary policies.
      Some of these policies are written by pacman hooks so their file names
      cannot be speciifed like the key handles below for simplicity.
      Please refer to the initial setup readme for further details.
    - If this argument is not specified, the hook will use
      "/EFI/arch/tpm2-encrypt" on the given partition as the default.

tpm_sealed_key=handle
    - Specifies the sealed TPM object's location in the TPM NVRAM.
    - 'handle' is the file name of a handle file in the directory given above.
    - If this argument is not specified the hook will look for a file called
    'sealed-passphrase.handle' in the directory given above.

'tpm_policy_auth=name:handle'
    - Specifies the policy auth key's name and location in the TPM NVRAM.
    - 'name' is the file name of a name file in the directory given above.
    - 'handle' is the file name of a handle file in the directory given above.
    - If this argument is not specified, the hook will look for files called
      'policy-authorization-key.name' and 'policy-authorization-key.handle'
      in the directory given above.

'tpm_pcr_bank=hashalg'
    - Specifies which PCR bank is used for policy creation and verification.
    - 'hashalg' is the type of hash used by the PCR bank. Eg 'sha256' or 'sha1'.
    - If this argument is not specified it will default to the sha256 bank.
    - Check the output of tpm2_pcrread to see what your tpm has allocated.

If any of the above files cannot be found, or if the TPM fails
to unseal the key, you will be prompted for the passphrase.
This means you must have a keyboard available to input it.

In the case that the TPM fails to unseal the key, a list of PCR values that
changed since the last time a policy was authorized will be shown, and you will
be asked if you want to create a new authorized policy on the new PCR values
after unlocking the volume with a password.
The previous values are signed and verified with the policy authorization key
to maintain integrity and trust.

NOTE: This hook is most secure when used with signed kernel and initramfs images
and secure boot turned on. If you cannot trust your initramfs and/or kernel
image this hook is not secure.
HELPEOF
}

# vim: set ft=sh ts=4 sw=4 et:
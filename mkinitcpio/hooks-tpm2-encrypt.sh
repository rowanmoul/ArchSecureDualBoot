#!/usr/bin/ash

run_earlyhook() {
    mkdir /efi
    if [ -n "$efi_part" ]; then
        if resolved_efi_part=$(resolve_device "$efi_part"); then
            if mount "$resolved_efi_part" /efi; then
                return
            fi
        fi
    fi
    echo "tpm2-encrypt could not mount EFI partition. Some features are not available. Set efi_part on kernel command line to avoid this message."
}

run_hook() {
    modprobe -a -q tpm >/dev/null 2>&1

    # Base Path
    base_key_path="/efi/EFI/arch/tpm2-encrypt/"

    # Validate input and get sealed key handle if specified
    if [ -n "$tpm_sealed_key" ] && \( [ -e $tpm_sealed_key ] || [ 1 ] \); then 
        sealed_key_handle=$tpm_sealed_key
    elif [ -e $base_key_path/sealed-passphrase.handle ]; then
        sealed_key_handle=$base_key_path/sealed-passphrase.handle
    else
        echo "something bad" # Do some fail/abort thing here.
    fi

    tpm2_verifysignature -c $base_key_path/policy-authorization-key.handle -g sha256 -m $base_key_path/authorized-policy.policy -s $base_key_path/authorized-policy.signature -t authorized-policy.tkt

    tpm2_startauthsession --policy-session -S sealed-auth-session.ctx

    tpm2_policypcr -S sealed-auth-session.ctx -l sha256:0,1,2,3

    tpm2_policycountertimer -S sealed-auth-session.ctx --eq resets=$(tpm2_readclock | sed -En "s/[[:space:]]*reset_count: ([0-9]+)/\1/p")

    tpm2_policyauthorize -S sealed-auth-session.ctx -i $base_key_path/authorized-policy.policy -n $base_key_path/policy-authorization-key.name -t authorized-policy.tkt

    tpm2_unseal -p "session:sealed-auth-session.ctx" -c $base_key_path/sealed_passphrase.handle > /crypto_keyfile.bin

    tpm2_flushcontext sealed-auth-session.ctx
}

run_cleanuphook() {
    # This is where we will optionally re-seal on the current PCR values.
    # This is done as a cleanup hook to ensure that the root FS is mounted already so we can use the auth key to change the TPM Policy.
    umount /efi
}

# vim: set ft=sh ts=4 sw=4 et:
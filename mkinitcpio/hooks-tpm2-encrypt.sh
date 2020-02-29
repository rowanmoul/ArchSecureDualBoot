#!/usr/bin/ash

run_earlyhook() {
    # make /efi if it doesn't exist
    mkdir /efi

    # Check for tpm_efi_part, resolve it, and mount it.
    if [ -n "$tpm_efi_part" ] && resolved_efi_part="$(resolve_device "$tpm_efi_part")" && mount "$resolved_efi_part" /efi; then
        return 0
    else
        echo "tpm2-encrypt could not mount partition. Some features will not be available. Set tpm_efi_part on kernel command line to avoid this message."
        return 1
    fi
}

run_hook() {
    # make sure the tpm module is loaded
    modprobe -a -q tpm >/dev/null 2>&1

    # Base Path
    base_key_path="/efi/EFI/arch/tpm2-encrypt/"

    # Validate input and get sealed key handle if specified
    if [ -n "$tpm_sealed_key" ] && [ -f "$tpm_sealed_key" ]; then 
        sealed_key_handle=$tpm_sealed_key
    elif [ -f $base_key_path/sealed-passphrase.handle ]; then
        sealed_key_handle=$base_key_path/sealed-passphrase.handle
    else
        echo "tpm_sealed_key not specified and default not available. Falling back to passphrase prompt."
        return 1
    fi

    # Check for tpm_policy_auth and get policy auth key name and handle
    if [ -n "$tpm_policy_auth" ]; then
        IFS=: read -r pa_name pa_handle <<EOF
$tpm_policy_auth
EOF
        # Validate name input and get file path if specified
        if [ -n "$pa_name" ] && [ -f "$pa_name" ]; then 
            policy_authorization_key_name=$pa_name
        elif [ -f $base_key_path/policy-authorization-key.name ]; then
            policy_authorization_key_name=$base_key_path/sealed-passphrase.handle
        fi

        # Validate handle input and get file path if specified
        if [ -n "$pa_handle" ] && [ -f "$pa_handle" ]; then 
            policy_authorization_key_handle=$pa_handle
        elif [ -f $base_key_path/policy-authorization-key.handle ]; then
            policy_authorization_key_handle=$base_key_path/sealed-passphrase.handle
        fi

        # Verify both name and handle were set
        if ! \( [ -f $policy_authorization_key_name ] && [ -f $policy_authorization_key_handle ] \); then
            echo "tpm_policy_auth could not be parsed and defaults not available. Falling back to passphrase prompt."
            return 1
        fi
    # Otherwise check for defaults
    elif [ -f $base_key_path/policy-authorization-key.name ] && [ -f $base_key_path/policy-authorization-key.handle ]; then
        policy_authorization_key_name=$base_key_path/policy-authorization-key.name
        policy_authorization_key_handle=$base_key_path/policy-authorization-key.handle
    else
        echo "tpm_policy_auth not specified and defaults not available. Falling back to passphrase prompt."
        return 1
    fi

    if [ -f $sealed_key_handle ] && [ -f $policy_authorization_key_name ] && [ -f $policy_authorization_key_handle ]; then
        tpm2_verifysignature -c $policy_authorization_key_handle -g sha256 -m $base_key_path/authorized-policy.policy -s $base_key_path/authorized-policy.signature -t authorized-policy.tkt

        tpm2_startauthsession --policy-session -S sealed-auth-session.ctx

        tpm2_policypcr -S sealed-auth-session.ctx -l sha256:0,1,2,3

        tpm2_policycountertimer -S sealed-auth-session.ctx --eq resets=$(tpm2_readclock | sed -En "s/[[:space:]]*reset_count: ([0-9]+)/\1/p")

        tpm2_policyauthorize -S sealed-auth-session.ctx -i $base_key_path/authorized-policy.policy -n $policy_authorization_key_name -t authorized-policy.tkt

        tpm2_unseal -p "session:sealed-auth-session.ctx" -c $sealed_key_handle > /crypto_keyfile.bin

        tpm2_flushcontext sealed-auth-session.ctx

        rm sealed-auth-session.ctx
        rm authorized-policy.tkt
    else
        echo ""
    fi
}

run_cleanuphook() {
    # This is where we will optionally re-seal on the current PCR values.
    # This is done as a cleanup hook to ensure that the root FS is mounted already so we can use the auth key to change the TPM Policy.
    umount /efi
}

# vim: set ft=sh ts=4 sw=4 et:
#!/usr/bin/ash

run_earlyhook() {
    # make /efi if it doesn't exist
    mkdir /efi

    # Check for tpm_efi_part, resolve it, and mount it.
    if [ -n "$tpm_efi_part" ] && resolved_efi_part="$(resolve_device "$tpm_efi_part")" && mount "$resolved_efi_part" /efi; then
        return 0
    else
        return 1
    fi
}

run_hook() {
    # make sure the tpm module is loaded
    modprobe -a -q tpm >/dev/null 2>&1

    if ! mountpoint -q "/efi"; then
        echo "tpm2-encrypt could not mount tpm_efi_part partition. Falling back to passphrase prompt."
        return 1 
    fi

    # Check for tpm_file_dir and validate input
    if [ -n "$tpm_file_dir" ] && [ -d "/efi$tpm_file_dir" ]; then
        base_file_path="/efi$tpm_file_dir"
    elif [ -d "/efi/EFI/arch/tpm2-encrypt" ]; then
        base_file_path="/efi/EFI/arch/tpm2-encrypt"
    else
        echo "tpm_file_dir and/or default file directory not available. Falling back to passphrase prompt."
        return 1
    fi

    # Check for tpm_sealed_key and validate input
    if [ -n "$tpm_sealed_key" ] && [ -f "$base_file_path/$tpm_sealed_key" ]; then 
        sealed_key_handle="$base_file_path/$tpm_sealed_key"
    elif [ -f "$base_file_path/sealed-passphrase.handle" ]; then
        sealed_key_handle="$base_file_path/sealed-passphrase.handle"
    else
        echo "tpm_sealed_key not specified and default not available. Falling back to passphrase prompt."
        return 1
    fi

    # Check for tpm_policy_auth and get policy auth key name and handle
    if [ -n "$tpm_policy_auth" ]; then
        IFS=: read -r pa_name pa_handle <<EOF
$tpm_policy_auth
EOF
        # Validate name input and get file name if specified
        if [ -n "$pa_name" ] && [ -f "$base_file_path/$pa_name" ]; then 
            policy_authorization_key_name="$base_file_path/$pa_name"
        elif [ -f "$base_file_path/policy-authorization-key.name" ]; then
            policy_authorization_key_name="$base_file_path/policy-authorization-key.name"
        fi

        # Validate handle input and get file name if specified
        if [ -n "$pa_handle" ] && [ -f "$base_file_path/$pa_handle" ]; then 
            policy_authorization_key_handle="$base_file_path/$pa_handle"
        elif [ -f "$base_file_path/policy-authorization-key.handle" ]; then
            policy_authorization_key_handle="$base_file_path/policy-authorization-key.handle"
        fi

        # Verify both name and handle were set
        if ! \( [ -f $policy_authorization_key_name ] && [ -f $policy_authorization_key_handle ] \); then
            echo "tpm_policy_auth file names not found and defaults not available. Falling back to passphrase prompt."
            return 1
        fi
    # Otherwise check for defaults
    elif [ -f "$base_file_path/policy-authorization-key.name" ] && [ -f "$base_file_path/policy-authorization-key.handle" ]; then
        policy_authorization_key_name="$base_file_path/policy-authorization-key.name"
        policy_authorization_key_handle="$base_file_path/policy-authorization-key.handle"
    else
        echo "tpm_policy_auth not specified and defaults not available. Falling back to passphrase prompt."
        return 1
    fi

    # Define some functions to reduce repetition below
    verify_policy_signature() {
        tpm2_verifysignature -c $policy_authorization_key_handle -g sha256 -m $authorized_policy -s $authorized_policy_signature -t authorized-policy.tkt
        return $?
    }

    create_authorized_policy_session() {
        tpm2_startauthsession --policy-session -S sealed-auth-session.ctx

        tpm2_policypcr -S sealed-auth-session.ctx -l sha256:0,1,2,3,4,5,7,8,9

        tpm2_policyauthorize -S sealed-auth-session.ctx -i $authorized_policy -n $policy_authorization_key_name -t authorized-policy.tkt
    }

    create_temporary_authorized_policy_session() {
        tpm2_startauthsession --policy-session -S sealed-auth-session.ctx

        tpm2_policypcr -S sealed-auth-session.ctx -l sha256:0,1,2,3

        tpm2_policycountertimer -S sealed-auth-session.ctx --eq resets=$(tpm2_readclock | sed -En "s/[[:space:]]*reset_count: ([0-9]+)/\1/p")

        tpm2_policyauthorize -S sealed-auth-session.ctx -i $authorized_policy -n $policy_authorization_key_name -t authorized-policy.tkt
    }

    unseal_passphrase() {
        tpm2_unseal -p "session:sealed-auth-session.ctx" -c $sealed_key_handle > /crypto_keyfile.bin
        return $?
    }

    if [ -f "$sealed_key_handle" ] && [ -f "$policy_authorization_key_name" ] && [ -f "$policy_authorization_key_handle" ]; then
        # Check for policy files
        if [ -f "$base_file_path/authorized-policy.policy" ] && [ -f "$base_file_path/authorized-policy.signature" ]; then
            authorized_policy="$base_file_path/authorized-policy.policy"
            authorized_policy_signature="$base_file_path/authorized-policy.signature"
            verify_policy_signature
            create_authorized_policy_session
            unseal_passphrase
        elif [ -f "$base_file_path/temporary-authorized-policy.policy" ] && [ -f "$base_file_path/temporary-authorized-policy.signature" ]; then
            authorized_policy="$base_file_path/temporary-authorized-policy.policy"
            authorized_policy_signature="$base_file_path/temporary-authorized-policy.signature"
            verify_policy_signature
            create_temporary_authorized_policy_session
            unseal_passphrase
        else
            echo "Could not find any policy files. Falling back to passphrase prompt."
            return 1
        fi
    else
        echo ""
    fi

    # end
    # below for reference while WIP

    if [ -f "$sealed_key_handle" ] && [ -f "$policy_authorization_key_name" ] && [ -f "$policy_authorization_key_handle" ]; then
        tpm2_verifysignature -c $policy_authorization_key_handle -g sha256 -m $default_file_path/authorized-policy.policy -s $default_file_path/authorized-policy.signature -t authorized-policy.tkt

        tpm2_startauthsession --policy-session -S sealed-auth-session.ctx

        tpm2_policypcr -S sealed-auth-session.ctx -l sha256:0,1,2,3

        tpm2_policycountertimer -S sealed-auth-session.ctx --eq resets=$(tpm2_readclock | sed -En "s/[[:space:]]*reset_count: ([0-9]+)/\1/p")

        tpm2_policyauthorize -S sealed-auth-session.ctx -i $default_file_path/authorized-policy.policy -n $policy_authorization_key_name -t authorized-policy.tkt

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
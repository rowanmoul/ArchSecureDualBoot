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

    # ==========================
    # Collect Input and Validate
    # ==========================

    # Check if partition is mounted at /efi. Abort if not.
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
        if ! \( [ -f "$policy_authorization_key_name" ] && [ -f "$policy_authorization_key_handle" ] \); then
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

    # Check for tpm_pcr_bank and validate input
    if [ -n "$tpm_pcr_bank" ]; then 
        case "$tpm_pcr_bank" in
            sha1|sha256|sha384|sha512|sm3_256|sha3_256|sha3_384|sha3_512)
                pcr_bank_alg="$tpm_pcr_bank"
            ;;
            *)
                echo "Unrecognized pcr bank algorithm [$tpm_pcr_bank]. Using default sha256"
                pcr_bank_alg="sha256"
            ;;
        esac
    else
        pcr_bank_alg="sha256"
    fi

    # ========================================================
    # Define functions for tpm operations to reduce repetition
    # ========================================================

    verify_policy_signature() {
        tpm2_verifysignature -c "$policy_authorization_key_handle" -g sha256 -m "$authorized_policy" -s "$authorized_policy_signature" -t authorized-policy.tkt
        return $?
    }

    create_authorized_policy_session() {
        ! tpm2_startauthsession --policy-session -S sealed-auth-session.ctx && return $?

        ! tpm2_policypcr -S sealed-auth-session.ctx -l "$pcr_bank_alg:0,1,2,3,4,5,7,8,9" && return $?

        tpm2_policyauthorize -S sealed-auth-session.ctx -i "$authorized_policy" -n "$policy_authorization_key_name" -t authorized-policy.tkt
        return $?
    }

    create_temporary_authorized_policy_session() {
        ! tpm2_startauthsession --policy-session -S sealed-auth-session.ctx && return $?

        ! tpm2_policypcr -S sealed-auth-session.ctx -l "$pcr_bank_alg:0,1,2,3,7" && return $?

        ! tpm2_policycountertimer -S sealed-auth-session.ctx --eq resets=$(tpm2_readclock | sed -En "s/[[:space:]]*reset_count: ([0-9]+)/\1/p") && return $?

        tpm2_policyauthorize -S sealed-auth-session.ctx -i "$authorized_policy" -n "$policy_authorization_key_name" -t authorized-policy.tkt
        return $?
    }

    unseal_passphrase() {
        tpm2_unseal -p "session:sealed-auth-session.ctx" -c "$sealed_key_handle" > /crypto_keyfile.bin
        return $?
    }

    create_reauthorize_policy() {
        ! tpm2_startauthsession -S reauthorize-policy-session.ctx && return $?

        ! tpm2_policypcr -S reauthorize-policy-session.ctx -l "$pcr_bank_alg:0,1,2,3,4,5,7,8,9" -L "reauthorize-policy.policy" && return $?

        tpm2_flushcontext reauthorize-policy-session.ctx

        # Also save new pcr values for later comparison
        tpm2_pcrread "$pcr_bank_alg:0,1,2,3,4,5,7,8,9" > reauthorize-pcr-values.txt
    }

    ask_reauthorize_policy() {
        if ! tpm2_verifysignature -c "$policy_authorization_key_handle" -g sha256 -m "REPLACEME-file" -s "REPLACEME-file-signature"; then
            echo "Failed to verify signature of previous PCR values. This could be a sign of tampering!"
        fi
        echo "The following PCR values have changed since the last time a policy was authorized."
        tpm2_pcrread "$pcr_bank_alg:0,1,2,3,4,5,7,8,9" | comm -13 "REPLACEME-file" -
        echo "If you expected these changes, you can authorize a new policy that uses them after entering your passphrase."
        echo "Would you like to authorize a new policy? (y/n)"
        read -r yn
        if [ "$yn" = "y" ]; then
            create_reauthorize_policy
        fi
    }

    try_unseal_with_authorized_policy() {
        # Check for authorized policy files
        if [ -f "$base_file_path/authorized-policy.policy" ] && [ -f "$base_file_path/authorized-policy.signature" ]; then
            authorized_policy="$base_file_path/authorized-policy.policy"
            authorized_policy_signature="$base_file_path/authorized-policy.signature"
            if verify_policy_signature && create_authorized_policy_session && unseal_passphrase; then
                # Success!
                tpm2_flushcontext sealed-auth-session.ctx
                return 0
            else
                # Failed to unseal. Ask about re-auth
                tpm2_flushcontext sealed-auth-session.ctx
                ask_reauthorize_policy
                return 1
            fi
        else
            # Could not find policy files. Ask about re-auth
            tpm2_flushcontext sealed-auth-session.ctx
            ask_reauthorize_policy
            return 1
        fi
    }

    try_unseal_with_temp_authorized_policy() {
        # Check for temporary authorized policy files
        if [ -f "$base_file_path/temporary-authorized-policy.policy" ] && [ -f "$base_file_path/temporary-authorized-policy.signature" ]; then
            authorized_policy="$base_file_path/temporary-authorized-policy.policy"
            authorized_policy_signature="$base_file_path/temporary-authorized-policy.signature"
            if verify_policy_signature && create_temporary_authorized_policy_session && unseal_passphrase; then
                # success!
                tpm2_flushcontext sealed-auth-session.ctx
                create_reauthorize_policy
                return 0
            else
                try_unseal_with_authorized_policy && return 0
            fi
        else
            try_unseal_with_authorized_policy && return 0
        fi
        tpm2_flushcontext sealed-auth-session.ctx
        return 1
    }

    # =====================
    # Unseal the passphrase
    # =====================

    # Final check of input variables
    if [ -f "$sealed_key_handle" ] && [ -f "$policy_authorization_key_name" ] && [ -f "$policy_authorization_key_handle" ] && [ -n "$pcr_bank_alg" ]; then
        # try to unseal
        if try_unseal_with_temp_authorized_policy; then
            return 0
        else
            echo "Failed to unseal passphrase. Falling back to passphrase prompt."
            return 1
        fi
    else
        echo "An unexpected input error occured. Falling back to passphrase prompt."
        return 1
    fi
}

run_latehook() {
    # This is where we will optionally re-seal on the current PCR values.
    # This is done as a late hook to ensure that the root FS is mounted already so we can use the auth key to change the TPM Policy.
    true
}

run_cleanuphook() {
    rm sealed-auth-session.ctx
    rm authorized-policy.tkt
    umount /efi
}

# vim: set ft=sh ts=4 sw=4 et:
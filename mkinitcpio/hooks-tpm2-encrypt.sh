#!/usr/bin/ash

run_hook() {
    modprobe -a -q tpm >/dev/null 2>&1

    # Base Path
    base_path="/some_mountpoint/EFI/arch/tpm2-encrypt/"

    # Get sealed object handle if specified
    if [ -n "$cryptkeytpm"]; then
        IFS=: read sealed_key_handle <<EOF
$cryptkeytpm
EOF
    else
        sealed_key_handle=$base_path/sealed-passphrase.handle
    fi

    tpm2_verifysignature -c $base_path/policy-authorization-key.handle -g sha256 -m $base_path/authorized-policy.policy -s $base_path/authorized-policy.signature -t authorized-policy.tkt

    tpm2_startauthsession --policy-session -S sealed-auth-session.ctx

    tpm2_policypcr -S sealed-auth-session.ctx -l sha256:0,1,2,3

    tpm2_policycountertimer -S sealed-auth-session.ctx --eq resets=$(tpm2_readclock | sed -En "s/[[:space:]]*reset_count: ([0-9]+)/\1/p")

    tpm2_policyauthorize -S sealed-auth-session.ctx -i $base_path/authorized-policy.policy -n $base_path/policy-authorization-key.name -t authorized-policy.tkt

    tpm2_unseal -p"session:sealed-auth-session.ctx" -c $base_path/sealed_passphrase.handle > /crypto_keyfile.bin

    tpm2_flushcontext sealed-auth-session.ctx
}

run_cleanuphook() {
    # This is where we will optionally re-seal on the current PCR values.
    # This is done as a cleanup hook to ensure that the root FS is mounted already so we can use the auth key to change the TPM Policy.
}

# vim: set ft=sh ts=4 sw=4 et:
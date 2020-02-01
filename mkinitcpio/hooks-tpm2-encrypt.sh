#!/usr/bin/ash

run_hook() {
    modprobe -a -q tpm >/dev/null 2>&1

    # Need to practice/test things out before I can write this. Will be a little more complicated than examples due to using tpm2_policyauthorize to create a flexible seal.
}

run_cleanuphook() {
    # This is where we will optionally re-seal on the current PCR values.
    # This is done as a cleanup hook to ensure that the root FS is mounted already so we can use the auth key to change the TPM Policy.
}

# vim: set ft=sh ts=4 sw=4 et:
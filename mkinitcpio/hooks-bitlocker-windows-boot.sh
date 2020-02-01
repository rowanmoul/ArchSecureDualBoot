#!/usr/bin/ash

run_hook() {
    modprobe -a -q efivars >/dev/null 2>&1
    efibootmgr -n 0000
    reboot
}


# vim: set ft=sh ts=4 sw=4 et:
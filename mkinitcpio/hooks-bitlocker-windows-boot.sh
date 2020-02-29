#!/usr/bin/ash

run_hook() {
    modprobe -a -q efivars >/dev/null 2>&1
    if [ -n "$win_boot_entry" ] && [ 11 -eq $(echo "$win_boot_entry" |  sed -En "s/[[:digit:]]{4}/1/p")1 ]; then
        efibootmgr -n $win_boot_entry
        reboot
    else
        echo "Booting default entry 0000..."
        efibootmgr -n 0000
        reboot
    fi
}


# vim: set ft=sh ts=4 sw=4 et:
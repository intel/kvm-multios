#!/bin/bash

# Copyright (c) 2023-2024 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------

script=$(realpath "${BASH_SOURCE[0]}")
#scriptpath=$(dirname "$script")
LOGTAG=$(basename "$script")
LOGD="logger -t $LOGTAG"
#LOGE="logger -s -t $LOGTAG"

#---------      Functions    -------------------
function setup_pm_mgmt_dep() {
    sudo apt install -y qemu-guest-agent
}

function setup_swap_update_service() {
    $LOGD "${FUNCNAME[0]} begin"

    tee swap-update.service &>/dev/null <<EOF
[Unit]
After=swap.target

[Service]
ExecStart=/usr/local/bin/setup_swap.sh

[Install]
WantedBy=default.target
EOF

    sudo chmod 644 swap-update.service
    sudo mv swap-update.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable swap-update.service

    $LOGD "${FUNCNAME[0]} end"
}

function setup_mem_sleep_mode() {
    local exist
    exist=$(sed -En "/^GRUB_CMDLINE_LINUX=.*mem_sleep_default=deep.*$/p" /etc/default/grub)
    if [[ -z "${exist}" ]]; then
        sudo sed -in "s/^\(GRUB_CMDLINE_LINUX=.*\)\"$/\1 mem_sleep_default=deep\"/g" /etc/default/grub
        sudo update-grub
    fi
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

setup_pm_mgmt_dep || exit 255
setup_swap_update_service || exit 255
setup_mem_sleep_mode || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

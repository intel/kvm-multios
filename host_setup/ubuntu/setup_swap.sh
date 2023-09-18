#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

LOG_FILE=${LOG_FILE:="host_setup_ubuntu.log"}
#---------      Functions    -------------------
declare -F "log_func" >/dev/null || log_func() {
    declare -F "$1" >/dev/null
    if [ $? -eq 0 ]; then
        start=`date +%s`
        echo -e "$(date)   start:   \t$1" >> $LOG_FILE
        $@
        end=`date +%s`
        echo -e "$(date)   end ($((end-start))s):\t$1" >> $LOG_FILE
    else
        echo "Error: $1 is not a function"
        exit -1
    fi
}

function setup_swapfile() {
    # The swap size needs to be larger than the total size of RAM

    # check RAM size
    local ram_total=$(free --giga | awk '{ if ($1 == "Mem:") { print $2 }}')

    # determine swap size needed
    # based on table from https://help.ubuntu.com/community/SwapFaq
    # key=ram size, value=swap size
    declare -A swap_tbl
    local swap_tbl=( ["1"]="2"
                     ["2"]="3"
                     ["3"]="5"
                     ["4"]="6"
                     ["5"]="7"
                     ["6"]="8"
                     ["8"]="11"
                     ["12"]="15"
                     ["16"]="20"
                     ["24"]="29"
                     ["32"]="38"
                     ["64"]="72"
                     ["128"]="139"
                     ["256"]="272"
                     ["512"]="535"
                     ["1024"]="1056"
                     ["2048"]="2094"
                     ["4096"]="4160"
                     ["8192"]="8283"
             )

    # swap.img is Ubuntu 22.04 default
    local swapfile_names=("/swap.img"
                          "/swapfile")
    local swapfile="${swapfile_names[0]}"

    for name in "${swapfile_names[@]}"; do
        if [ -f "$name" ]; then
             swapfile=$name
             break
        fi
    done


    for ram_sz in $(for k in ${!swap_tbl[@]}; do echo $k; done | sort -n); do
        if [ "$ram_total" -le "$ram_sz" ]; then
            swapfile_req=${swap_tbl[$ram_sz]}
            break
        fi
    done
    # check if current swap fulfills required size
    # check if current swapfile fulfills required size
    if [ -f "$swapfile" ]; then
        swapfile_cur=$(swapon --show | awk '{ if ($1 ~ "$swapfile") { print int($3) }}')
    else
        swapfile_cur=0
    fi
    if [[ "$swapfile_cur" -lt "$swapfile_req" ]]; then
        # setup swapfile with required size

        # check free disk space
        if [ $(df -h / | awk '{ if ($1 ~ "/dev") { print int($4) }}') -gt $swapfile_req ]; then
            echo "Setting up swapfile with size ${swapfile_req}G"

            if [ -f "$swapfile" ]; then
                # disable swapfile
                sudo swapoff "$swapfile"
                sudo rm "$swapfile"
            fi

            # allocate swapfile
            sudo fallocate -l ${swapfile_req}G "$swapfile"
            sudo chmod 600 "$swapfile"

            # create swapfile
            sudo mkswap "$swapfile"

            # start to use swapfile
            sudo swapon "$swapfile"
        else
            echo "Error: not enough free disk space for swapfile"
            exit
        fi
    fi

    # add swapfile to /etc/fstab if needed
    if ! grep -q "$swapfile" "/etc/fstab"; then
        echo "$swapfile       none            swap    sw              0       0" | sudo tee -a /etc/fstab &>/dev/null
    fi

    # check swapfile UUID
    swap_uuid=$(sudo findmnt -no UUID -T "$swapfile")

    # check swap file offset
    swap_file_offset=$(sudo filefrag -v "$swapfile" | awk '{ if($1=="0:"){print substr($4, 1, length($4)-2)} }')

    # set up resume parameters for kernel commandline
    local updated=0
    local cmds=("resume=UUID=$swap_uuid"
                "resume_offset=$swap_file_offset")
    local cmdline
    cmdline=$(sed -n -e "/.*\(GRUB_CMDLINE_LINUX=\).*/p" /etc/default/grub)
    cmdline=$(awk -F '"' '{ print $2 }' <<< $cmdline)

    for cmd in "${cmds[@]}"; do
        if ! grep -q "$cmd" <<< "$cmdline"; then
            if [[ $cmd == "resume=UUID=$swap_uuid" ]]; then
                cmdline=$(sed -r -e "s/\<resume=UUID=[A-Za-z0-9\-]*\>//g" <<< $cmdline)
                cmd="resume=UUID=$swap_uuid"
            fi
            if [[ "$cmd" == "resume_offset=$swap_file_offset" ]]; then
                cmdline=$(sed -r -e "s/\<resume_offset=[0-9]*\>//g" <<< $cmdline)
                cmd="resume_offset=$swap_file_offset"
            fi
            cmdline=$(echo "$cmdline" "$cmd")
            updated=1
        fi
    done

    if [[ "$updated" -eq "1" ]]; then
        sudo sed -i -r -e "s/(GRUB_CMDLINE_LINUX=).*/GRUB_CMDLINE_LINUX=\" $cmdline \"/" /etc/default/grub
        sudo update-grub
    fi

    # set resume overide
    if ! grep -Fq "resume=UUID=$swap_uuid" /etc/initramfs-tools/conf.d/resume; then
        echo "resume=UUID=$swap_uuid" | sudo tee /etc/initramfs-tools/conf.d/resume
        sudo update-initramfs -u -k all
    fi

    reboot_required=1
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

# Setup swapfile to allow for hibernate
log_func setup_swapfile || exit -1

echo "Done: \"$(realpath ${BASH_SOURCE[0]}) $@\""

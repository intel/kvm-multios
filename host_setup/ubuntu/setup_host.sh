#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
reboot_required=0
reboot_timeout=10
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

LOG_FILE="host_setup_ubuntu.log"
PLATFORM_NAME=""
#---------      Functions    -------------------

function check_os() {
    # Check OS
    local version=`cat /proc/version`
    if [[ ! $version =~ "Ubuntu" ]]; then
        echo "Error: Only Ubuntu is supported" | tee -a $LOG_FILE
        exit
    fi

    # Check Ubuntu version
    req_version="22.04"
    cur_version=$(lsb_release -rs)
    if [[ $cur_version != $req_version ]]; then
        echo "Error: Ubuntu $cur_version is not supported" | tee -a $LOG_FILE
        echo "Error: Please use Ubuntu $req_version" | tee -a $LOG_FILE
        exit
    fi
}

function host_set_ui() {
    if [[ $1 == "headless" ]]; then
        [[ $(systemctl get-default) == "multi-user.target" ]] && return 0
        sudo systemctl set-default multi-user.target
        reboot_required=1
    elif [[ $1 == "GUI" ]]; then
        [[ $(systemctl get-default) == "graphical.target" ]] && return 0
        sudo systemctl set-default graphical.target
        reboot_required=1
    else
        echo "${BASH_SOURCE[0]}: Unsupported mode: $1"
        return -1
    fi
}

function host_disable_auto_upgrade() {
    # Stop existing upgrade service
    sudo systemctl stop unattended-upgrades.service
    sudo systemctl disable unattended-upgrades.service
    sudo systemctl mask unattended-upgrades.service

    auto_upgrade_config=("APT::Periodic::Update-Package-Lists"
                         "APT::Periodic::Unattended-Upgrade"
                         "APT::Periodic::Download-Upgradeable-Packages"
                         "APT::Periodic::AutocleanInterval")

    # Disable auto upgrade
    for config in ${auto_upgrade_config[@]}; do
        if [[ ! `cat /etc/apt/apt.conf.d/20auto-upgrades` =~ "$config" ]]; then
            echo -e "$config \"0\";" | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades
        else
            sudo sed -i "s/$config \"1\";/$config \"0\";/g" /etc/apt/apt.conf.d/20auto-upgrades
        fi
    done

    reboot_required=1
}

function host_update_cmdline() {
    local updated=0
    local max_vfs=7
    local major_version
    local max_guc
    local cmdline

    # Workaround for MTL-P stepping below C0
    sudo apt install -y dmidecode
    stepping=$(sudo dmidecode --type processor | grep ID | awk '{ print "0x"$2 }');
    family=$(sudo dmidecode --type processor | grep ID | awk '{ print "0x"$3 }');
    model=$(sudo dmidecode --type processor | grep ID | awk '{ print "0x"$4 }');
    if [[ "$model" -eq "0x0A" && "$family" -eq "0x06" && "$stepping" -lt "0xA4" ]]; then
        echo "Limit max VFs for MTL-P less than C0 stepping"
        max_vfs=4
    else
        max_vfs=7
    fi

    # handle older than 6.x kernel
    major_version=$(uname -r | awk -F'.' '{ print $1 }')
    if [[ "$major_version" -le "5" ]]; then
        # using max_guc=7 to enable SRIOV
        max_guc=7
        cmds=("i915.force_probe=*"
              "udmabuf.list_limit=8192"
              "intel_iommu=on"
              "i915.enable_guc=(0x)?(0)*$max_guc"
              "mem_sleep_default=s2idle")
    else
        max_guc=3
        cmds=("i915.force_probe=*"
              "udmabuf.list_limit=8192"
              "intel_iommu=on"
              "i915.enable_guc=(0x)?(0)*$max_guc"
              "i915.max_vfs=(0x)?(0)*$max_vfs"
              "mem_sleep_default=s2idle")
    fi

    cmdline=$(sed -n -e "/.*\(GRUB_CMDLINE_LINUX=\).*/p" /etc/default/grub)
    cmdline=$(awk -F '"' '{print $2}' <<< $cmdline)

    for cmd in "${cmds[@]}"; do
        if [[ ! "$cmdline" =~ "$cmd" ]]; then
            # Special handling for i915.enable_guc
            if [[ "$cmd" == "i915.enable_guc=(0x)?(0)*$max_guc" ]]; then
                cmdline=$(sed -r -e "s/\<i915.enable_guc=(0x)?([A-Fa-f0-9])*\>//g" <<< $cmdline)
                cmd="i915.enable_guc=0x$max_guc"
            fi
            if [[ "$cmd" == "i915.max_vfs=(0x)?(0)*$max_vfs" ]]; then
                cmdline=$(sed -r -e "s/\<i915.max_vfs=(0x)?([0-9])*\>//g" <<< $cmdline)
                cmd="i915.max_vfs=$max_vfs"
            fi

            cmdline=$(echo $cmdline $cmd)
            updated=1
        fi
    done

    if [[ $updated -eq 1 ]]; then
        sudo sed -i -r -e "s/(GRUB_CMDLINE_LINUX=).*/GRUB_CMDLINE_LINUX=\" $cmdline \"/" /etc/default/grub
        sudo update-grub
        reboot_required=1
    fi
}

function host_customise_ubuntu() {
    # Switch to Xorg
    sudo sed -i "s/\#WaylandEnable=false/WaylandEnable=false/g" /etc/gdm3/custom.conf

    if ! grep -Fq 'kernel.printk = 7 4 1 7' /etc/sysctl.d/99-kernel-printk.conf; then
        echo 'kernel.printk = 7 4 1 7' | sudo tee -a /etc/sysctl.d/99-kernel-printk.conf
    fi
    if ! grep -Fq 'kernel.dmesg_restrict = 0' /etc/sysctl.d/99-kernel-printk.conf; then
        echo 'kernel.dmesg_restrict = 0' | sudo tee -a /etc/sysctl.d/99-kernel-printk.conf
    fi

    if [[ ! -f /etc/profile.d/mesa_driver.sh ]]; then
        sudo tee /etc/profile.d/mesa_driver.sh &>/dev/null <<EOF
if dmesg | grep -q "SR-IOV VF"; then
  export MESA_LOADER_DRIVER_OVERRIDE=pl111
else
  export MESA_LOADER_DRIVER_OVERRIDE=iris
fi
EOF
    fi

    if [[ -z ${SUDO_USER+x} || -z $SUDO_USER ]]; then
        # Disable screen blank
        gsettings set org.gnome.desktop.session idle-delay 0
        # Disable lock screen on suspend
        gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend 'false'
    else
        local user=$SUDO_USER;
        local user_id=$(id -u "$user")
        local environment=("DISPLAY=:0" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus")
        sudo -Hu "$user" env "${environment[@]}" gsettings set org.gnome.desktop.session idle-delay 0
        sudo -Hu "$user" env "${environment[@]}" gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend 'false'
    fi

    if ! grep -Fq 'source /etc/profile.d/mesa_driver.sh' /etc/bash.bashrc; then
        echo 'source /etc/profile.d/mesa_driver.sh' | sudo tee -a /etc/bash.bashrc
    fi
    reboot_required=1
}

function host_get_supported_platforms() {
    local -n arr=$1
    local platpaths=( $(find "$scriptpath/../../platform/" -maxdepth 1 -mindepth 1 -type d) )
    for p in "${platpaths[@]}"; do
        arr+=( $(basename $p) )
    done
}

function host_set_platform() {
    local platforms=()
    local platform

    platform=$1
    host_get_supported_platforms platforms

    for p in "${platforms[@]}"; do
        if [[ "$p" == "$platform" ]]; then
            PLATFORM_NAME="$platform"
            return
        fi
    done

    echo "Error: $platform is not a supported platform"
    return -1
}

function host_invoke_platform_setup() {
    local platform=$1
    local osname=$(basename $scriptpath)
    local platpath="$scriptpath/../../platform/$platform/host_setup/$osname"

    if [ -d $platpath ]; then
        platpath=$(realpath "$platpath")
        platscripts=( $(find "$platpath" -maxdepth 1 -mindepth 1 -type f -name "setup_*.sh") )
        for s in ${platscripts[@]}; do
            rscriptpath=$(realpath $s)
            echo "Invoking $platform script $s"
            source $rscriptpath
        done
    fi
}

#-------------    helper functions -------------
function log_func() {
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
export -f log_func

function log_clean() {
    # Clean up log file
    if [ -f "$LOG_FILE" ]; then
        rm $LOG_FILE
    fi
}

log_success() {
    echo "Success" | tee -a $LOG_FILE
}

function ask_reboot() {
    if [ $reboot_required -eq 1 ];then
        read -t $reboot_timeout -p "System reboot will take place in $reboot_timeout sec, do you want to continue? [Y/n]" res || (echo)
        if [[ "$res" == 'n' || "$res" == 'N' ]];  then
            echo "Warning: Please reboot system for changes to take effect"
        else
            echo "Rebooting system now..."
            sudo reboot
        fi
    fi
}

function show_help() {
    local platforms=()

    #printf "$(basename "${BASH_SOURCE[0]}") -d <dut> [-h] [-u]\n"
    printf "$(basename "${BASH_SOURCE[0]}") [-h] [-u]\n"
    printf "Options:\n"
    printf "\t-h\tshow this help message\n"
    printf "\t-u\tspecify Host OS's UI, support \"headless\" and \"GUI\" eg. \"-u headless\" or \"-u GUI\"\n"
    #printf "\t-d\tspecific dut to setup for, eg. \"-d mtlp \"\n"
    #printf "\t\tSupported platforms:\n"
    #host_get_supported_platforms platforms
    #for p in "${platforms[@]}"; do
    #    printf	"\t\t\t$(basename $p)\n"
    #done
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit
                ;;

            -u)
                host_set_ui $2 || return -1
                shift
                ;;

            #-d)
            #    host_set_platform $2 || return -1
            #    shift
            #    ;;

            -?*)
                echo "Error: Invalid option: $1"
                show_help
                return -1
                ;;
            *)
                echo "Error: Unknown option: $1"
                return -1
                ;;
        esac
        shift
    done
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit -1

log_clean
log_func check_os

#if [ -z $PLATFORM_NAME ]; then
#    show_help && exit -1
#fi

# Generic host setup
log_func host_disable_auto_upgrade
log_func host_update_cmdline
log_func host_customise_ubuntu

# Platform specific host setup
# invoke platform/<plat>/host_setup/<os>/setup_xxxx.sh scripts
#log_func host_invoke_platform_setup $PLATFORM_NAME

# Others
source "$scriptpath/setup_libvirt.sh"
source "$scriptpath/setup_swap.sh"
source "$scriptpath/setup_pm_mgmt.sh"

log_success
ask_reboot

echo "Done: \"$(realpath ${BASH_SOURCE[0]}) $@\""

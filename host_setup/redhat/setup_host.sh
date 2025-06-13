#!/bin/bash

# Copyright (c) 2024-2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
reboot_required=0
reboot_timeout=10
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

LOG_FILE="/tmp/host_setup_redhat.log"
#PLATFORM_NAME=""
#---------      Functions    -------------------
declare -F "check_non_symlink" >/dev/null || function check_non_symlink() {
    if [[ $# -eq 1 ]]; then
        if [[ -L "$1" ]]; then
            echo "Error: $1 is a symlink." | tee -a "$LOG_FILE"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}
export -f check_non_symlink

declare -F "check_dir_valid" >/dev/null || function check_dir_valid() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        if ! dpath=$(sudo realpath "$1") || sudo [ ! -d "$dpath" ]; then
            echo "Error: $dpath invalid directory" | tee -a "$LOG_FILE"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}
export -f check_dir_valid

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
     if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        if ! fpath=$(sudo realpath "$1") || sudo [ ! -f "$fpath" ] || sudo [ ! -s "$fpath" ]; then
            echo "Error: $fpath invalid/zero sized" | tee -a "$LOG_FILE"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}
export -f check_file_valid_nonzero

function check_os() {
    # Check OS
    local version
    version=$(cat /proc/version)
    if [[ ! "$version" =~ "Red Hat" ]]; then
        echo "Error: Only Red Hat is supported" | tee -a "$LOG_FILE"
        exit 255
    fi

    # Check Redhat version
    req_version="9.2"
    cur_version=$(distro | awk -F': ' '/Version:/ {print $2}')
    if [[ ! $cur_version =~ $req_version ]]; then
        echo "Error: Red Hat $cur_version is not supported" | tee -a "$LOG_FILE"
        echo "Error: Please use Red Hat $req_version" | tee -a "$LOG_FILE"
        exit 255
    fi
}

function host_set_ui() {
    if [[ "$1" == "headless" ]]; then
        [[ "$(systemctl get-default)" == "multi-user.target" ]] && return 0
        sudo systemctl set-default multi-user.target
        reboot_required=1
    elif [[ "$1" == "GUI" ]]; then
        [[ "$(systemctl get-default)" == "graphical.target" ]] && return 0
        sudo systemctl set-default graphical.target
        reboot_required=1
    else
        echo "${BASH_SOURCE[0]}: Unsupported mode: $1"
        return 255
    fi
}

function host_update_cmdline() {
    local updated=0
    local cmdline
    local intel_iommu_options="on"

    cmds=("intel_iommu=$intel_iommu_options")

    check_file_valid_nonzero "/etc/default/grub"
    cmdline=$(sed -n -e "/.*\(GRUB_CMDLINE_LINUX=\).*/p" /etc/default/grub)
    cmdline=$(awk -F '"' '{print $2}' <<< "$cmdline")

    for cmd in "${cmds[@]}"; do
        if [[ ! "$cmdline" =~ $cmd ]]; then
            cmdline="$cmdline $cmd"
            updated=1
        fi
    done

    if [[ $updated -eq 1 ]]; then
        sudo sed -i -r -e "s/(GRUB_CMDLINE_LINUX=).*/GRUB_CMDLINE_LINUX=\" $cmdline \"/" /etc/default/grub
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        reboot_required=1
    fi
}

function host_customise_redhat() {
    if ! grep -Fq 'kernel.printk = 7 4 1 7' /etc/sysctl.d/99-kernel-printk.conf; then
        echo 'kernel.printk = 7 4 1 7' | sudo tee -a /etc/sysctl.d/99-kernel-printk.conf
    fi
    if ! grep -Fq 'kernel.dmesg_restrict = 0' /etc/sysctl.d/99-kernel-printk.conf; then
        echo 'kernel.dmesg_restrict = 0' | sudo tee -a /etc/sysctl.d/99-kernel-printk.conf
    fi
    if [[ -z "${SUDO_USER+x}" || -z "$SUDO_USER" ]]; then
        # Disable screen blank
        gsettings set org.gnome.desktop.session idle-delay 0
        # Disable lock screen on suspend
        gsettings set org.gnome.desktop.screensaver lock-enabled 'false'
    else
        local user
        local user_id
        user="$SUDO_USER";
        user_id=$(id -u "$user")
        local environment=("DISPLAY=:0" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus")
        sudo -Hu "$user" env "${environment[@]}" gsettings set org.gnome.desktop.session idle-delay 0
        sudo -Hu "$user" env "${environment[@]}" gsettings set org.gnome.desktop.screensaver lock-enabled 'false'
    fi

    reboot_required=1
}

function host_set_pulseaudio() {
    if ! dnf list installed | grep -q alsa-plugins-pulseaudio; then
      echo "pulseaudio is not installed"
    fi
}

function host_get_supported_platforms() {
    local -n arr=$1
    local -a platpaths=()
    mapfile -t platpaths < <(find "$scriptpath/../../platform/" -maxdepth 1 -mindepth 1 -type d)

    for p in "${platpaths[@]}"; do
        arr+=( "$(basename "$p")" )
    done
}

#-------------    helper functions -------------
function log_func() {
    if declare -F "$1" >/dev/null; then
        start=$(date +%s)
        echo -e "$(date)   start:   \t$1" >> $LOG_FILE
        "$@"
        ec=$?
        end=$(date +%s)
        echo -e "$(date)   end ($((end-start))s):\t$1" >> $LOG_FILE
        return $ec
    else
        echo "Error: $1 is not a function"
        exit 255
    fi
}
export -f log_func

function log_clean() {
    # Clean up log file
    if [ -f "$LOG_FILE" ]; then
        rm "$LOG_FILE"
    fi
}

log_success() {
    echo "Success" | tee -a "$LOG_FILE"
}

function ask_reboot() {
    if [[ $reboot_required -eq 1 ]];then
        read -r -t "$reboot_timeout" -p "System reboot will take place in $reboot_timeout sec, do you want to continue? [Y/n]" res || (echo)
        if [[ "$res" == 'n' || "$res" == 'N' ]];  then
            echo "Warning: Please reboot system for changes to take effect"
        else
            echo "Rebooting system now..."
            sudo reboot
        fi
    fi
}

function show_help() {
    printf "%s [-h] [-u]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Options:\n"
    printf "\t-h\tshow this help message\n"
    printf "\t-u\tspecify Host OS's UI, support \"headless\" and \"GUI\" eg. \"-u headless\" or \"-u GUI\"\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit
                ;;

            -u)
                host_set_ui "$2" || return 255
                shift
                ;;

            -?*)
                echo "Error: Invalid option: $1"
                show_help
                return 255
                ;;
            *)
                echo "Error: Unknown option: $1"
                return 255
                ;;
        esac
        shift
    done
}

#-------------    main processes    -------------
trap 'echo "Error $(realpath ${BASH_SOURCE[0]}) line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

log_clean
log_func check_os || exit 255

#if [ -z $PLATFORM_NAME ]; then
#    show_help && exit 255
#fi

# Generic host setup
log_func host_update_cmdline || exit 255
log_func host_customise_redhat || exit 255
log_func host_set_pulseaudio || exit 255


# Platform specific host setup
# invoke platform/<plat>/host_setup/<os>/setup_xxxx.sh scripts
#log_func host_invoke_platform_setup $PLATFORM_NAME

# Others
echo "Setting up libvirt"
# shellcheck source-path=SCRIPTDIR
source "$scriptpath/setup_libvirt.sh"

log_success
ask_reboot

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

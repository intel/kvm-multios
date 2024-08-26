#!/bin/bash

# Copyright (c) 2023-2024 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
reboot_required=0
reboot_timeout=10
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

LOG_FILE="/tmp/host_setup_ubuntu.log"
#PLATFORM_NAME=""
DRM_DRV_SUPPORTED=('i915' 'xe')
DRM_DRV_SELECTED=""
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
        dpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -d "$dpath" ]]; then
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
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f "$fpath" || ! -s "$fpath" ]]; then
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
    local os_dist
    os_dist=$(cat /proc/version)
    if [[ ! "$os_dist" =~ "Ubuntu" ]]; then
        echo "Error: Only Ubuntu is supported" | tee -a "$LOG_FILE"
        return 255
    fi

    # Check Ubuntu version
    local -a req_versions=('22.04' '24.04')
    local version
    local supported_ver=0
    version=$(lsb_release -rs)
    for ver in "${req_versions[@]}"; do
      if [[ "$version" == "$ver" ]]; then
        supported_ver=1
        break
      fi
    done
    if [[ $supported_ver -ne 1 ]]; then
      echo "Error: Ubuntu $version is not supported" | tee -a "$LOG_FILE"
      echo "Error: Please use Ubuntu ${req_versions[*]}" | tee -a "$LOG_FILE"
      return 255
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

function host_set_drm_drv() {
    local drm_drv=""

    if [[ -z "${1+x}" || -z "$1" ]]; then
        echo "${BASH_SOURCE[0]}: invalid drm_drv param"
        return 255
    fi
    if ! lspci -D -k -s 00:02.0 | grep 'Kernel modules' | grep -q "$1"; then
        echo "ERROR: running kernel does not have kernel module for -drm option $drm_drv." | tee -a "$LOG_FILE"
        echo "Use lspci to check supported modules or check running kernel." | tee -a "$LOG_FILE"
        return 255
    fi
    for idx in "${!DRM_DRV_SUPPORTED[@]}"; do
        if [[ "$1" == "${DRM_DRV_SUPPORTED[$idx]}" ]]; then
            drm_drv="${DRM_DRV_SUPPORTED[$idx]}"
            break
        fi
    done
    if [[ -z "${drm_drv+x}" || -z "$drm_drv" ]]; then
        echo "ERROR: unsupported intel integrated GPU driver option $drm_drv." | tee -a "$LOG_FILE"
        return 255
    fi
    DRM_DRV_SELECTED="$drm_drv"
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
    check_dir_valid "/etc/apt/apt.conf.d"
    for config in "${auto_upgrade_config[@]}"; do
        if [[ ! "$(cat /etc/apt/apt.conf.d/20auto-upgrades)" =~ $config ]]; then
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
    local intel_iommu_options="on,sm_on"
    local version
    local drm_drv

    if [[ -z "${DRM_DRV_SELECTED+x}" || -z "$DRM_DRV_SELECTED" ]]; then
        drm_drv=$(lspci -D -k  -s 0000:00:02.0 | grep "Kernel driver in use" | awk -F ':' '{print $2}' | xargs)
        host_set_drm_drv "$drm_drv" || return 255
    else
        drm_drv="$DRM_DRV_SELECTED"
    fi

    version=$(lsb_release -rs)

    # Workaround for MTL-P stepping below C0
    which dmidecode > /dev/null || sudo apt install -y dmidecode
    stepping=$(sudo dmidecode --type processor | grep ID | awk '{ print "0x"$2 }');
    family=$(sudo dmidecode --type processor | grep ID | awk '{ print "0x"$3 }');
    model=$(sudo dmidecode --type processor | grep ID | awk '{ print "0x"$4 }');
    if [[ $model -eq $((0x0A)) && $family -eq $((0x06)) && $stepping -lt $((0xA4)) ]]; then
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
        cmds=("$drm_drv.force_probe=*"
              "udmabuf.list_limit=8192"
              "intel_iommu=$intel_iommu_options"
              "$drm_drv.enable_guc=(0x)?(0)*$max_guc"
              "mem_sleep_default=s2idle")
    else
        max_guc=3
        cmds=("$drm_drv.force_probe=*"
              "udmabuf.list_limit=8192"
              "intel_iommu=$intel_iommu_options"
              "$drm_drv.enable_guc=(0x)?(0)*$max_guc"
              "$drm_drv.max_vfs=(0x)?(0)*$max_vfs"
              "mem_sleep_default=s2idle")
    fi

    check_file_valid_nonzero "/etc/default/grub"
    cmdline=$(sed -n -e "/.*\(GRUB_CMDLINE_LINUX=\).*/p" /etc/default/grub)
    cmdline=$(awk -F '"' '{print $2}' <<< "$cmdline")

    if [[ "${#DRM_DRV_SUPPORTED[@]}" -gt 1 ]]; then
        for drv in "${DRM_DRV_SUPPORTED[@]}"; do
            cmdline=$(sed -r -e "s/\<modprobe\.blacklist=$drv\>//g" <<< "$cmdline")
        done
        for drv in "${DRM_DRV_SUPPORTED[@]}"; do
            if [[ "$drv" != "$drm_drv" ]]; then
                echo "INFO: force $drm_drv drm driver over others" | tee -a "$LOG_FILE"
                cmds+=("modprobe.blacklist=$drv")
            fi
        done
    fi

    for cmd in "${cmds[@]}"; do
        if [[ ! "$cmdline" =~ $cmd ]]; then
            # Special handling for drm driver params
            if [[ "$cmd" == "$drm_drv.force_probe=*" ]]; then
                for drv in "${DRM_DRV_SUPPORTED[@]}"; do
                    cmdline=$(sed -r -e "s/\<$drv\.force_probe=\*//g" <<< "$cmdline")
                done
            fi
            if [[ "$cmd" == "$drm_drv.enable_guc=(0x)?(0)*$max_guc" ]]; then
                for drv in "${DRM_DRV_SUPPORTED[@]}"; do
                    cmdline=$(sed -r -e "s/\<$drv.enable_guc=(0x)?([A-Fa-f0-9])*\>//g" <<< "$cmdline")
                done
                cmd="$drm_drv.enable_guc=0x$max_guc"
            fi
            if [[ "$cmd" == "$drm_drv.max_vfs=(0x)?(0)*$max_vfs" ]]; then
                for drv in "${DRM_DRV_SUPPORTED[@]}"; do
                    cmdline=$(sed -r -e "s/\<$drv\.max_vfs=(0x)?([0-9])*\>//g" <<< "$cmdline")
                done
                cmd="$drm_drv.max_vfs=$max_vfs"
            fi

            cmdline="$cmdline $cmd"
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
    check_file_valid_nonzero "/etc/gdm3/custom.conf"
    sudo sed -i "s/\#WaylandEnable=false/WaylandEnable=false/g" /etc/gdm3/custom.conf

    if ! grep -Fq 'kernel.printk = 7 4 1 7' /etc/sysctl.d/99-kernel-printk.conf; then
        echo 'kernel.printk = 7 4 1 7' | sudo tee -a /etc/sysctl.d/99-kernel-printk.conf
    fi
    if ! grep -Fq 'kernel.dmesg_restrict = 0' /etc/sysctl.d/99-kernel-printk.conf; then
        echo 'kernel.dmesg_restrict = 0' | sudo tee -a /etc/sysctl.d/99-kernel-printk.conf
    fi

    check_dir_valid "/etc/profile.d"
    if [[ ! -f /etc/profile.d/mesa_driver.sh ]]; then
        sudo tee /etc/profile.d/mesa_driver.sh &>/dev/null <<EOF
if dmesg | grep -q "SR-IOV VF"; then
  export MESA_LOADER_DRIVER_OVERRIDE=pl111
else
  export MESA_LOADER_DRIVER_OVERRIDE=iris
fi
EOF
    fi

    if [[ -z "${SUDO_USER+x}" || -z "$SUDO_USER" ]]; then
        # Disable screen blank
        gsettings set org.gnome.desktop.session idle-delay 0
        # Disable lock screen on suspend
        gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend 'false'
    else
        local user
        local user_id
        user="$SUDO_USER";
        user_id=$(id -u "$user")
        local environment=("DISPLAY=:0" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus")
        sudo -Hu "$user" env "${environment[@]}" gsettings set org.gnome.desktop.session idle-delay 0
        sudo -Hu "$user" env "${environment[@]}" gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend 'false'
    fi

    check_file_valid_nonzero "/etc/profile.d/mesa_driver.sh"
    # Add source mesa_driver.sh to first line of bash.bashrc so that it will be called even for non interactive shell
    sudo sed -i '$ s:source /etc/profile.d/mesa_driver.sh::g' /etc/bash.bashrc
    if ! grep -Fq 'source /etc/profile.d/mesa_driver.sh' /etc/bash.bashrc; then
        sudo sed -i '1s:^:source /etc/profile.d/mesa_driver.sh\n:' /etc/bash.bashrc
    fi
    reboot_required=1
}

function host_set_pulseaudio() {

    if grep -qF "load-module module-native-protocol-unix" /etc/pulse/default.pa; then
        # Check if "auth-anonymous=1" is included in the line
        if grep -qF "auth-anonymous=1 socket=/tmp/pulseaudio-socket" /etc/pulse/default.pa; then
            echo "auth-anonymous=1 socket=/tmp/pulseaudio-socket is already included in load-module module-native-protocol-unix."
        else
            # Append "auth-anonymous=1 socket=/tmp/pulseaudio-socket" to the line
            sudo sed -i "\|load-module module-native-protocol-unix| s/\$/ auth-anonymous=1 socket=\\/tmp\\/pulseaudio-socket/" /etc/pulse/default.pa
            echo "auth-anonymous=1 socket=/tmp/pulseaudio-socket appended to load-module module-native-protocol-unix."
        fi
    else
        echo "load-module module-native-protocol-unix not found in /etc/pulse/default.pa."
    fi

    # Check if the default pulseaudio server already exists in the file client.conf
    if grep -qF "default-server = unix:/tmp/pulseaudio-socket" "/etc/pulse/client.conf"; then
        echo "default pulseaudio server already exists in /etc/pulse/client.conf. Nothing to do."
    else
        # Add the default pulseaudio server define to the file client.conf
        echo "default-server = unix:/tmp/pulseaudio-socket" | sudo tee -a "/etc/pulse/client.conf" >/dev/null
        echo "default pulseaudio server added to /etc/pulse/client.conf."
    fi
    reboot_required=1
}

function host_set_pipewire_pulse() {
    if ! grep -qF '"unix:/tmp/pulseaudio-socket"' '/usr/share/pipewire/pipewire-pulse.conf'; then
        sudo sed -i '/"unix:native"/a \        "unix:/tmp/pulseaudio-socket"' '/usr/share/pipewire/pipewire-pulse.conf'
    fi
    reboot_required=1

}

function host_set_audio() {
    if which pulseaudio; then
        host_set_pulseaudio || return 255
    elif which pipewire; then
        if ! apt list --installed | grep -Fq 'pipewire-pulse'; then
            sudo apt install -y pipewire-pulse
        fi
        host_set_pipewire_pulse || return 255
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

#function host_set_platform() {
#    local -a platforms=()
#    local platform
#
#    platform=$1
#    host_get_supported_platforms platforms
#
#    for p in "${platforms[@]}"; do
#        if [[ "$p" == "$platform" ]]; then
#            PLATFORM_NAME="$platform"
#            return
#        fi
#    done
#
#    echo "Error: $platform is not a supported platform"
#    return 255
#}

#function host_invoke_platform_setup() {
#    local platform
#    local osname
#    platform=$1
#    osname=$(basename "$scriptpath")
#    local platpath="$scriptpath/../../platform/$platform/host_setup/$osname"
#
#    if [ -d "$platpath" ]; then
#        platpath=$(realpath "$platpath")
#        local -a platscripts=()
#        mapfile -t platscripts < <(find "$platpath" -maxdepth 1 -mindepth 1 -type f -name "setup_*.sh")
#        for s in "${platscripts[@]}"; do
#            check_file_valid_nonzero "$s"
#            rscriptpath=$(realpath "$s")
#            echo "Invoking $platform script $s"
#            # shellcheck source=/dev/null
#            source "$rscriptpath"
#        done
#    fi
#}

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
    return 255
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
    #local -a platforms=()

    #printf "$(basename "${BASH_SOURCE[0]}") -d <dut> [-h] [-u]\n"
    printf "%s [-h] [-u]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Options:\n"
    printf "\t-h\tshow this help message\n"
    printf "\t-u\tspecify Host OS's UI, support \"headless\" and \"GUI\" eg. \"-u headless\" or \"-u GUI\"\n"
    printf "\t-drm\tspecify drm driver to use for Intel gpu:\n"
    for d in "${DRM_DRV_SUPPORTED[@]}"; do
        printf '\t\t\t%s\n' "$(basename "$d")"
    done
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
                host_set_ui "$2" || return 255
                shift
                ;;

            -drm)
                host_set_drm_drv "$2" || return 255
                shift
                ;;
            #-d)
            #    host_set_platform "$2" || return 255
            #    shift
            #    ;;

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
log_func host_disable_auto_upgrade || exit 255
log_func host_update_cmdline || exit 255
log_func host_customise_ubuntu || exit 255
log_func host_set_audio || exit 255


# Platform specific host setup
# invoke platform/<plat>/host_setup/<os>/setup_xxxx.sh scripts
#log_func host_invoke_platform_setup $PLATFORM_NAME

# Others
echo "Setting up libvirt"
# shellcheck source-path=SCRIPTDIR
source "$scriptpath/setup_libvirt.sh"
echo "Setting up for power management"
# shellcheck source-path=SCRIPTDIR
source "$scriptpath/setup_swap.sh"
# shellcheck source-path=SCRIPTDIR
source "$scriptpath/setup_pm_mgmt.sh"
echo "Setting up for OpenVINO"
openvino_setup_cmd="source $scriptpath/setup_openvino.sh --neo"
if sudo journalctl -k -o cat --no-pager | grep 'Initialized intel_vpu [0-9].[0-9].[0-9] [0-9]* for 0000:00:0b.0 on minor 0'; then
    openvino_setup_cmd="$openvino_setup_cmd --npu"
fi
# shellcheck source-path=SCRIPTDIR
$openvino_setup_cmd

log_success
ask_reboot

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

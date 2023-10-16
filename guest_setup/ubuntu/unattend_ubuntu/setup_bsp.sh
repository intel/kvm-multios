#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
# PPA url for Intel overlay installation
# Add each required entry on new line
PPA_URLS=(
    "https://download.01.org/intel-linux-overlay/ubuntu jammy main non-free multimedia"
)
# corresponding GPG key to use for each PPA_URL entry above in same sequence.
# If GPG key is not set correctly,
# Set to either one of below options:
#   To auto use GPG key found in PPA entry (check PPA repository has required key available), set to: "auto"
#   To force download GPG key at stated url, set to: "url of gpg key file"
#   To force trusted access without GPG key (for unsigned PPA only), set to: "force"
PPA_GPGS=(
    "auto"
)
# Set corresponding to use proxy as set in host env variable or not for each PPA_URL entry above in same sequence.
# Set to either one of below options:
#   To use auto proxy, set to: ""
#   To not use proxy, set to: "--no-proxy"
PPA_WGET_NO_PROXY=(
    ""
)
# Set additional apt proxy configuration required to access PPA_URL entries set.
# Set to either one of below options:
#   For no proxy required for PPA access, set to: ""
#   For proxy required (eg. using myproxyserver.com at mynetworkdomain.com), set to:
#     'Acquire::https::proxy::myproxyserver.com "DIRECT";' 'Acquire::https::proxy::*.mynetworkdomain.com "DIRECT";'
#     where
#     Change myproxyserver.com to your proxy server
#     Change mynetworkdomain.com to your network domain
PPA_APT_CONF=(
    ""
)
# PPA APT repository pin and priority
# Reference: https://wiki.debian.org/AptConfiguration#Always_prefer_packages_from_a_repository
PPA_PIN="release o=intel-iot-linux-overlay"
PPA_PIN_PRIORITY=2000

# Add entry for each additional package to install into guest VM
PACKAGES_ADD_INSTALL=(
    ""
)

NO_BSP_INSTALL=0
KERN_PATH=""
KERN_INSTALL_FROM_PPA=0
KERN_PPA_VER=""
RT=0

script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")
LOGTAG=$(basename $script)
LOGD="logger -t $LOGTAG"
LOGE="logger -s -t $LOGTAG"

#---------      Functions    -------------------
function check_url() {
    local url=$1

    wget --timeout=10 --tries=1 $url -nv --spider
    if [ $? -ne 0 ]; then
		# try again without proxy
		wget --no-proxy --timeout=10 --tries=1 $url -nv --spider
    	if [ $? -ne 0 ]; then
        	$LOGE "Error: Network issue, unable to access $url"
        	$LOGE "Error: Please check the internet access connection"
			return -1
		fi
    fi
}

function install_kernel_from_deb() {
    $LOGD "${FUNCNAME[0]} begin"
    if [ -z $1 ]; then
        $LOGE "Error: empty path to kernel debs"
        return -1
    fi
    local path=$(realpath $1)
    if [ ! -d $path ]; then
        $LOGE "Error: invalid path to linux-header and linux-image debs given.($path)"
        return -1
    fi
    if [[ ! -f $path/linux-headers.deb || ! -f $path/linux-image.deb ]]; then
        $LOGE "Error: linux-headers.deb or linux-image.deb missing from ($path)"
        return -1
    fi
    # Install Intel kernel overlay
    sudo dpkg -i $path/linux-headers.deb $path/linux-image.deb

    # Update boot menu to boot to the new kernel
    kernel_version=$(dpkg --info $path/linux-headers.deb | grep "Package: " | awk -F 'linux-headers-' '{print $2}')
    sudo sed -i -r -e "s/GRUB_DEFAULT=.*/GRUB_DEFAULT='Advanced options for Ubuntu>Ubuntu, with Linux $kernel_version'/" /etc/default/grub
    sudo update-grub

    $LOGD "${FUNCNAME[0]} end"
}

function install_kernel_from_ppa() {
    $LOGD "${FUNCNAME[0]} begin"
    if [ -z $1 ]; then
        $LOGE "Error: empty kernel ppa version"
        return -1
    fi

    # Install Intel kernel overlay
    echo "kernel PPA version: $1"
    sudo apt install -y --allow-downgrades linux-headers-$1 linux-image-$1 || return -1

    # Update boot menu to boot to the new kernel
    local kernel_name=$(echo $1 | awk -F '=' '{print $1}')
    sudo sed -i -r -e "s/GRUB_DEFAULT=.*/GRUB_DEFAULT='Advanced options for Ubuntu>Ubuntu, with Linux $kernel_name'/" /etc/default/grub
    sudo update-grub

    $LOGD "${FUNCNAME[0]} end"
}

function setup_overlay_ppa() {
    $LOGD "${FUNCNAME[0]} begin"

    # Install Intel BSP PPA and required GPG keys
    cat /dev/null > /etc/apt/sources.list.d/ubuntu_bsp.list
    for i in "${!PPA_URLS[@]}"; do
        url=$(echo ${PPA_URLS[$i]} | awk -F' ' '{print $1}')
        check_url "$url" || return -1
        if [[ "${PPA_GPGS[$i]}" != "force" ]]; then
            echo deb ${PPA_URLS[$i]} | sudo tee -a /etc/apt/sources.list.d/ubuntu_bsp.list
            echo deb-src ${PPA_URLS[$i]} | sudo tee -a /etc/apt/sources.list.d/ubuntu_bsp.list

            if [[ "${PPA_GPGS[$i]}" == "auto" ]]; then
                ppa_gpg_key=$(wget ${PPA_WGET_NO_PROXY[$i]} -q -O - --timeout=10 --tries=1 $url | awk -F'.gpg">|&' '{ print $2 }' | awk -F '.gpg|&' '{ print $1 }' | xargs )
                if [[ -z "$ppa_gpg_key" ]]; then
                    $LOGE "Error: unable to auto get GPG key for PPG url ${PPA_URLS[$i]}"
                    return -1
                fi
                sudo wget ${PPA_WGET_NO_PROXY[$i]} "$url/$ppa_gpg_key.gpg" -O /etc/apt/trusted.gpg.d/$ppa_gpg_key.gpg
            else
                if [[ ! -z "${PPA_GPGS[$i]}" ]]; then
                    gpg_key_name=$(basename ${PPA_GPGS[$i]})
                    if [[ ! -f /etc/apt/trusted.gpg.d/$gpg_key_name ]]; then
                        sudo wget ${PPA_WGET_NO_PROXY[$i]} ${PPA_GPGS[$i]} -O /etc/apt/trusted.gpg.d/$gpg_key_name
                    fi
                fi
            fi
        else
            echo deb [trusted=yes] ${PPA_URLS[$i]} | sudo tee -a /etc/apt/sources.list.d/ubuntu_bsp.list
        fi
    done

    # Pin Intel BSP PPA
    echo -e "Package: *\nPin: $PPA_PIN\nPin-Priority: $PPA_PIN_PRIORITY" | sudo tee -a /etc/apt/preferences.d/priorities

    # Add PPA apt proxy settings if any
    if [[ ! -z "${ftp_proxy+x}" && ! -z "$ftp_proxy" ]]; then
        echo "Acquire::ftp::Proxy \"$ftp_proxy\";" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
    fi
    if [[ ! -z "${http_proxy+x}" && ! -z "$http_proxy" ]]; then
        echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
    fi
    if [[ ! -z "${https_proxy+x}" && ! -z "$https_proxy" ]]; then
        echo "Acquire::https::Proxy \"$https_proxy\";" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
    fi
    for line in "${PPA_APT_CONF[@]}"; do
        if [[ ! -z "$line" ]]; then
            echo "$line" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
        fi
    done

    sudo apt update -y
    sudo apt upgrade -y --allow-downgrades

    $LOGD "${FUNCNAME[0]} end"
}

function install_userspace_pkgs() {
    $LOGD "${FUNCNAME[0]} begin"

    # bsp packages as per Intel bsp overlay release
    local overlay_packages=(
    vim ocl-icd-libopencl1 curl openssh-server net-tools gir1.2-gst-plugins-bad-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gstreamer-1.0 gir1.2-gst-rtsp-server-1.0 gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-opencv gstreamer1.0-plugins-bad gstreamer1.0-plugins-bad-apps gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-pulseaudio gstreamer1.0-qt5 gstreamer1.0-rtsp gstreamer1.0-tools gstreamer1.0-vaapi gstreamer1.0-wpe gstreamer1.0-x intel-media-va-driver-non-free jhi jhi-tests itt-dev itt-staticdev libmfx1 libmfx-dev libmfx-tools libd3dadapter9-mesa libd3dadapter9-mesa-dev libdrm-amdgpu1 libdrm-common libdrm-dev libdrm-intel1 libdrm-nouveau2 libdrm-radeon1 libdrm-tests libdrm2 libegl-mesa0 libegl1-mesa libegl1-mesa-dev libgbm-dev libgbm1 libgl1-mesa-dev libgl1-mesa-dri libgl1-mesa-glx libglapi-mesa libgles2-mesa libgles2-mesa-dev libglx-mesa0 libgstrtspserver-1.0-dev libgstrtspserver-1.0-0 libgstreamer-gl1.0-0 libgstreamer-opencv1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-bad1.0-dev libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev libgstreamer-plugins-good1.0-0 libgstreamer-plugins-good1.0-dev libgstreamer1.0-0 libgstreamer1.0-dev libigdgmm-dev libigdgmm12 libigfxcmrt-dev libigfxcmrt7 libmfx-gen1.2 libosmesa6 libosmesa6-dev libtpms-dev libtpms0 libva-dev libva-drm2 libva-glx2 libva-wayland2 libva-x11-2 libva2 libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev libwayland-doc libwayland-egl-backend-dev libwayland-egl1 libwayland-egl1-mesa libwayland-server0 libweston-9-0 libweston-9-dev libxatracker-dev libxatracker2 linux-firmware mesa-common-dev mesa-utils mesa-va-drivers mesa-vdpau-drivers mesa-vulkan-drivers libvpl-dev libmfx-gen-dev onevpl-tools ovmf ovmf-ia32 qemu qemu-efi qemu-block-extra qemu-guest-agent qemu-system qemu-system-arm qemu-system-common qemu-system-data qemu-system-gui qemu-system-mips qemu-system-misc qemu-system-ppc qemu-system-s390x qemu-system-sparc qemu-system-x86 qemu-system-x86-microvm qemu-user qemu-user-binfmt qemu-utils va-driver-all vainfo weston xserver-xorg-core libvirt0 libvirt-clients libvirt-daemon libvirt-daemon-config-network libvirt-daemon-config-nwfilter libvirt-daemon-driver-lxc libvirt-daemon-driver-qemu libvirt-daemon-driver-storage-gluster libvirt-daemon-driver-storage-iscsi-direct libvirt-daemon-driver-storage-rbd libvirt-daemon-driver-storage-zfs libvirt-daemon-driver-vbox libvirt-daemon-driver-xen libvirt-daemon-system libvirt-daemon-system-systemd libvirt-dev libvirt-doc libvirt-login-shell libvirt-sanlock libvirt-wireshark libnss-libvirt swtpm swtpm-tools bmap-tools adb autoconf automake libtool cmake g++ gcc git intel-gpu-tools libssl3 libssl-dev make mosquitto mosquitto-clients build-essential apt-transport-https default-jre docker-compose ffmpeg git-lfs gnuplot lbzip2 libglew-dev libglm-dev libsdl2-dev mc openssl pciutils python3-pandas python3-pip python3-seaborn terminator vim wmctrl wayland-protocols gdbserver ethtool iperf3 msr-tools powertop linuxptp lsscsi tpm2-tools tpm2-abrmd binutils cifs-utils i2c-tools xdotool gnupg lsb-release intel-igc-core intel-igc-opencl intel-opencl-icd intel-level-zero-gpu ethtool iproute2 socat virt-viewer spice-client-gtk
    )

    # install bsp overlay packages
    for package in "${overlay_packages[@]}"; do
        if [[ ! -z ${package+x} && ! -z $package ]]; then
            sudo apt install -y --allow-downgrades $package
        fi
    done

    # other non overlay packages
    for package in "${PACKAGES_ADD_INSTALL[@]}"; do
        if [[ ! -z ${package+x} && ! -z $package ]]; then
            sudo apt install -y --allow-downgrades $package
        fi
    done

    $LOGD "${FUNCNAME[0]} end"
}

function disable_auto_upgrade() {
    $LOGD "${FUNCNAME[0]} begin"

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
    $LOGD "${FUNCNAME[0]} end"
}

function update_cmdline() {
    $LOGD "${FUNCNAME[0]} begin"
    local updated=0
    local major_version
    local max_guc
    local cmdline

    if [[ "$RT" == "0" ]]; then
        cmds=("i915.force_probe=*"
              "udmabuf.list_limit=8192"
              "i915.enable_guc=(0x)?(0)*3"
              "i915.max_vfs=(0x)?(0)*0")
    else
        cmds=("i915.force_probe=*"
              "udmabuf.list_limit=8192"
              "i915.enable_guc=(0x)?(0)*3"
              "i915.max_vfs=(0x)?(0)*0"
              "processor.max_cstate=0"
              "intel.max_cstate=0"
              "processor_idle.max_cstate=0"
              "intel_idle.max_cstate=0"
              "clocksource=tsc"
              "tsc=reliable"
              "nowatchdog"
              "intel_pstate=disable"
              "idle=poll"
              "noht"
              "isolcpus=1"
              "rcu_nocbs=1"
              "rcupdate.rcu_cpu_stall_suppress=1"
              "rcu_nocb_poll"
              "irqaffinity=0"
              "i915.enable_rc6=0"
              "i915.enable_dc=0"
              "i915.disable_power_well=0"
              "mce=off"
              "hpet=disable"
              "numa_balancing=disable"
              "igb.blacklist=no"
              "efi=runtime"
              "art=virtallow"
              "iommu=pt"
              "nmi_watchdog=0"
              "nosoftlockup"
              "console=tty0"
              "console=ttyS0,115200n8"
              "intel_iommu=on")
    fi
    cmdline=$(sed -n -e "/.*\(GRUB_CMDLINE_LINUX=\).*/p" /etc/default/grub)
    cmdline=$(awk -F '"' '{print $2}' <<< $cmdline)

    for cmd in "${cmds[@]}"; do
        if [[ ! "$cmdline" =~ "$cmd" ]]; then
            # Special handling for i915.enable_guc
            if [[ "$cmd" == "i915.enable_guc=(0x)?(0)*3" ]]; then
                cmdline=$(sed -r -e "s/\<i915.enable_guc=(0x)?([A-Fa-f0-9])*\>//g" <<< $cmdline)
                cmd="i915.enable_guc=0x3"
            fi
            if [[ "$cmd" == "i915.max_vfs=(0x)?(0)*0" ]]; then
                cmdline=$(sed -r -e "s/\<i915.max_vfs=(0x)?([0-9])*\>//g" <<< $cmdline)
                cmd="i915.max_vfs=0"
            fi

            cmdline=$(echo $cmdline $cmd)
            updated=1
        fi
    done

    if [[ $updated -eq 1 ]]; then
        sudo sed -i -r -e "s/(GRUB_CMDLINE_LINUX=).*/GRUB_CMDLINE_LINUX=\" $cmdline \"/" /etc/default/grub
        sudo update-grub
    fi
    $LOGD "${FUNCNAME[0]} end"
}

function update_ubuntu_cfg() {
    $LOGD "${FUNCNAME[0]} begin"
    # Enable reading of dmesg
    if ! grep -Fq 'kernel.dmesg_restrict = 0' /etc/sysctl.d/99-kernel-printk.conf; then
        echo 'kernel.dmesg_restrict = 0' | sudo tee -a /etc/sysctl.d/99-kernel-printk.conf
    fi

    # Setup SRIOV graphics
    # Switch to Xorg
    sudo sed -i "s/\#WaylandEnable=false/WaylandEnable=false/g" /etc/gdm3/custom.conf
    if ! grep -Fq 'source /etc/profile.d/mesa_driver.sh' /etc/bash.bashrc; then
        echo 'source /etc/profile.d/mesa_driver.sh' | sudo tee -a /etc/bash.bashrc
    fi
    if ! grep -Fq 'needs_root_rights=no' /etc/X11/Xwrapper.config; then
        echo 'needs_root_rights=no' | sudo tee -a /etc/X11/Xwrapper.config
    fi
    if ! grep -Fq 'MESA_LOADER_DRIVER_OVERRIDE=pl111' /etc/environment; then
        echo 'MESA_LOADER_DRIVER_OVERRIDE=pl111' | sudo tee -a /etc/environment
    fi
    # Enable for SW cursor
    if ! grep -Fq 'VirtIO-GPU' /usr/share/X11/xorg.conf.d/20-modesetting.conf; then
        # Enable SW cursor for Ubuntu guest
        echo -e "Section \"Device\"" | sudo tee -a /usr/share/X11/xorg.conf.d/20-modesetting.conf
        echo -e "Identifier \"VirtIO-GPU\"" | sudo tee -a /usr/share/X11/xorg.conf.d/20-modesetting.conf
        echo -e "Driver \"modesetting\"" | sudo tee -a /usr/share/X11/xorg.conf.d/20-modesetting.conf
        echo -e "#BusID \"PCI:0:4:0\" #virtio-gpu" | sudo tee -a /usr/share/X11/xorg.conf.d/20-modesetting.conf
        echo -e "Option \"SWcursor\" \"true\"" | sudo tee -a /usr/share/X11/xorg.conf.d/20-modesetting.conf
        echo -e "EndSection" | sudo tee -a /usr/share/X11/xorg.conf.d/20-modesetting.conf
    fi
    $LOGD "${FUNCNAME[0]} end"
}

function show_help() {
    printf "$(basename "${BASH_SOURCE[0]}") [-k | -kp] [--no-install-bsp] [--rt]\n"
    printf "Options:\n"
    printf "\t-h\tshow this help message\n"
    printf "\t-k\tpath to location of bsp kernel files linux-headers.deb and linux-image.deb\n"
    printf "\t-kp\tversion string of kernel overlay to select from Intel PPA. Eg \"6.3-intel\"\n"
    printf "\t--rt\tinstall for Ubuntu RT version\n"
    printf "\t--no-bsp-install\tDo not preform bsp overlay related install(kernel and userspace)\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit
                ;;

            -k)
                KERN_INSTALL_FROM_PPA=0
                KERN_PATH=$2
                shift
                ;;

            -kp)
                KERN_INSTALL_FROM_PPA=1
                KERN_PPA_VER=$2
                shift
                ;;

            --rt)
                RT=1
                ;;

            --no-bsp-install)
                NO_BSP_INSTALL=1
                ;;

            -?*)
                $LOGE "Error: Invalid option: $1"
                show_help
                return -1
                ;;
            *)
                $LOGE "Error: Unknown option: $1"
                return -1
                ;;
        esac
        shift
    done
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit -1

if [[ "$NO_BSP_INSTALL" -ne "1" ]]; then
    # Install PPA
    setup_overlay_ppa || exit -1

    # Install bsp kernel
    if [[ "$KERN_INSTALL_FROM_PPA" -eq "0" ]]; then
        install_kernel_from_deb "$KERN_PATH" || exit -1
    else
        install_kernel_from_ppa "$KERN_PPA_VER" || exit -1
    fi
    # Install bsp userspace
    install_userspace_pkgs || exit -1
fi
disable_auto_upgrade || exit -1
update_cmdline || exit -1
update_ubuntu_cfg || exit -1

echo "Done: \"$(realpath ${BASH_SOURCE[0]}) $@\""

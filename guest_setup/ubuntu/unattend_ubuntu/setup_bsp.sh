#!/bin/bash

# Copyright (c) 2023-2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
# PPA url for Intel overlay installation
# Add each required entry on new line
PPA_URLS=(
    "https://download.01.org/intel-linux-overlay/ubuntu noble main non-free multimedia kernels"
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
PPA_PIN="release o=intel-iot-linux-overlay-noble"
PPA_PIN_PRIORITY=2000

# Add entry for each additional package to install into guest VM
PACKAGES_ADD_INSTALL=(
    ""
)

# Version-specific PPA configuration alternates
# These will be applied if the detected Ubuntu version differs from the default above
# Each version can define: ppa_pin, ppa_pin_priority, ppa_urls, gpgs, wget_no_proxy, and apt_conf
# Format: ["version:index"] = "value"
# Multiple entries per version are supported by incrementing the index (0, 1, 2, ...)
declare -A PPA_ALT_URLS=(
    ["22.04:0"]="https://download.01.org/intel-linux-overlay/ubuntu jammy main non-free multimedia kernels"
)
declare -A PPA_ALT_GPGS=(
    ["22.04:0"]="auto"
)
declare -A PPA_ALT_WGET_NO_PROXY=(
    ["22.04:0"]=""
)
declare -A PPA_ALT_APT_CONF=(
    ["22.04:0"]=""
)
declare -A PPA_ALT_PIN=(
    ["22.04"]="release o=intel-iot-linux-overlay"
)
declare -A PPA_ALT_PIN_PRIORITY=(
    ["22.04"]=2000
)

NO_BSP_INSTALL=0
KERN_PATH=""
KERN_INSTALL_FROM_PPA=0
KERN_PPA_VER=""
LINUX_FW_PPA_VER=""
RT=0
DRM_DRV_SUPPORTED=('i915' 'xe')
DRM_DRV_SELECTED=""
FORCE_SW_CURSOR=0

script=$(realpath "${BASH_SOURCE[0]}")
#scriptpath=$(dirname "$script")
LOGTAG=$(basename "$script")
LOGD="logger -t $LOGTAG"

# Function to log errors and optionally send to host via netcat
function log_error() {
    local msg="$*"
    logger -s -t "$LOGTAG" "$msg"

    # If HOST_SERVER_IP and HOST_SERVER_NC_PORT are set, send error to host
    if [[ -n "${HOST_SERVER_IP:-}" && -n "${HOST_SERVER_NC_PORT:-}" ]]; then
        echo "ERROR: $LOGTAG: $msg" | nc -q1 "$HOST_SERVER_IP" "$HOST_SERVER_NC_PORT" 2>/dev/null || true
    fi
}

# For backward compatibility, LOGE can be used as a function
LOGE="log_error"

#---------      Functions    -------------------
declare -F "check_non_symlink" >/dev/null || function check_non_symlink() {
    if [[ $# -eq 1 ]]; then
        if [[ -L "$1" ]]; then
            $LOGE "Error: $1 is a symlink."
            exit 255
        fi
    else
        $LOGE "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f $fpath || ! -s $fpath ]]; then
            $LOGE "Error: $fpath invalid/zero sized"
            exit 255
        fi
    else
        $LOGE "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

declare -F "check_dir_valid" >/dev/null || function check_dir_valid() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        dpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -d $dpath ]]; then
            $LOGE "Error: $dpath invalid directory"
            exit 255
        fi
    else
        $LOGE "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

# Detect Ubuntu version and configure PPA settings accordingly
function setup_ubuntu_ppa_config() {
    # Get Ubuntu version and codename dynamically from system
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "24.04")
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")

    # Check if there's a version-specific alternate configuration
    if [[ -n "${PPA_ALT_PIN[$UBUNTU_VERSION]:-}" ]]; then
        # Apply PIN alternate
        PPA_PIN="${PPA_ALT_PIN[$UBUNTU_VERSION]}"

        # Apply PIN priority alternate if defined
        if [[ -n "${PPA_ALT_PIN_PRIORITY[$UBUNTU_VERSION]:-}" ]]; then
            PPA_PIN_PRIORITY="${PPA_ALT_PIN_PRIORITY[$UBUNTU_VERSION]}"
        fi

        # Load multi-value arrays from associative array using version:index pattern
        local temp_urls=()
        local temp_gpgs=()
        local temp_no_proxy=()
        local temp_apt_conf=()
        local idx=0

        # Iterate through indexed entries for this version
        while [[ -n "${PPA_ALT_URLS[$UBUNTU_VERSION:$idx]:-}" ]]; do
            temp_urls+=("${PPA_ALT_URLS[$UBUNTU_VERSION:$idx]}")
            temp_gpgs+=("${PPA_ALT_GPGS[$UBUNTU_VERSION:$idx]:-auto}")
            temp_no_proxy+=("${PPA_ALT_WGET_NO_PROXY[$UBUNTU_VERSION:$idx]:-}")
            temp_apt_conf+=("${PPA_ALT_APT_CONF[$UBUNTU_VERSION:$idx]:-}")
            idx=$((idx + 1))
        done

        # Apply the collected arrays if any entries were found
        if [[ ${#temp_urls[@]} -gt 0 ]]; then
            PPA_URLS=("${temp_urls[@]}")
            PPA_GPGS=("${temp_gpgs[@]}")
            PPA_WGET_NO_PROXY=("${temp_no_proxy[@]}")
            PPA_APT_CONF=("${temp_apt_conf[@]}")
        fi

        $LOGD "Applied version-specific PPA config for Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
    fi
    # If no alternate exists, global default settings are already configured
}

function check_url() {
    local url=$1

    if ! wget --timeout=10 --tries=1 "$url" -nv --spider; then
		# try again without proxy
    	if ! wget --no-proxy --timeout=10 --tries=1 "$url" -nv --spider; then
        	$LOGE "Error: Network issue, unable to access $url"
        	$LOGE "Error: Please check the internet access connection"
			return 255
		fi
    fi
}

function set_drm_drv() {
    $LOGD "${FUNCNAME[0]} begin"
    local drm_drv=""

    if [[ -z "${1+x}" || -z "$1" ]]; then
        $LOGE "${BASH_SOURCE[0]}: invalid drm_drv param"
        return 255
    fi
    for idx in "${!DRM_DRV_SUPPORTED[@]}"; do
        if [[ "$1" == "${DRM_DRV_SUPPORTED[$idx]}" ]]; then
            drm_drv="${DRM_DRV_SUPPORTED[$idx]}"
            break
        fi
    done
    DRM_DRV_SELECTED="$drm_drv"
    if [[ -z "${drm_drv+x}" || -z "$drm_drv" ]]; then
        $LOGE "ERROR: unsupported intel integrated GPU driver option $drm_drv."
        return 255
    fi

    $LOGD "${FUNCNAME[0]} end"
}

function install_kernel_from_deb() {
    $LOGD "${FUNCNAME[0]} begin"
    if [[ -z "${1+x}" || -z $1 ]]; then
        $LOGE "Error: empty path to kernel debs"
        return 255
    fi
    local path
    path=$(realpath "$1")
    if [ ! -d "$path" ]; then
        $LOGE "Error: invalid path to linux-header and linux-image debs given.($path)"
        return 255
    fi
    check_dir_valid "$1"
    if [[ ! -f "$path"/linux-headers.deb || ! -f "$path"/linux-image.deb ]]; then
        $LOGE "Error: linux-headers.deb or linux-image.deb missing from ($path)"
        return 255
    fi
    check_file_valid_nonzero "$path"/linux-headers.deb
    check_file_valid_nonzero "$path"/linux-image.deb
    # Install Intel kernel overlay
    sudo dpkg -i "$path"/linux-headers.deb "$path"/linux-image.deb

    # Update boot menu to boot to the new kernel
    kernel_version=$(dpkg --info "$path"/linux-headers.deb | grep "Package: " | awk -F 'linux-headers-' '{print $2}')
    sudo sed -i -r -e "s/GRUB_DEFAULT=.*/GRUB_DEFAULT='Advanced options for Ubuntu>Ubuntu, with Linux $kernel_version'/" /etc/default/grub
    sudo update-grub

    $LOGD "${FUNCNAME[0]} end"
}

function install_kernel_from_ppa() {
    $LOGD "${FUNCNAME[0]} begin"
    if [ -z "$1" ]; then
        $LOGE "Error: empty kernel ppa version"
        return 255
    fi

    # Install Intel kernel overlay
    echo "kernel PPA version: $1"
    if ! sudo apt-get install -y --allow-downgrades linux-headers-"$1" linux-image-"$1"; then
        $LOGE "Error: Failed to install kernel packages linux-headers-$1 and linux-image-$1"
        return 255
    fi

    # Update boot menu to boot to the new kernel
    local kernel_name
    kernel_name=$(echo "$1" | awk -F '=' '{print $1}')
    sudo sed -i -r -e "s/GRUB_DEFAULT=.*/GRUB_DEFAULT='Advanced options for Ubuntu>Ubuntu, with Linux $kernel_name'/" /etc/default/grub
    sudo update-grub

    $LOGD "${FUNCNAME[0]} end"
}

function setup_overlay_ppa() {
    $LOGD "${FUNCNAME[0]} begin"

    sudo apt-get update -y
    sudo apt-get upgrade -y

    $LOGD "Setting up Intel BSP PPA"

    # Install Intel BSP PPA and required GPG keys
    cat /dev/null > /etc/apt/sources.list.d/ubuntu_bsp.list
    for i in "${!PPA_URLS[@]}"; do
        url=$(echo "${PPA_URLS[$i]}" | awk -F' ' '{print $1}')
        check_url "$url" || return 255
        if [[ "${PPA_GPGS[$i]}" != "force" ]]; then
            echo deb "${PPA_URLS[$i]}" | sudo tee -a /etc/apt/sources.list.d/ubuntu_bsp.list
            echo deb-src "${PPA_URLS[$i]}" | sudo tee -a /etc/apt/sources.list.d/ubuntu_bsp.list

            if [[ "${PPA_GPGS[$i]}" == "auto" ]]; then
                ppa_gpg_key=$(wget "${PPA_WGET_NO_PROXY[$i]}" -q -O - --timeout=10 --tries=1 "$url" | awk -F'.gpg">|&' '{ print $2 }' | awk -F '.gpg|&' '{ print $1 }' | xargs )
                if [[ -z "$ppa_gpg_key" ]]; then
                    $LOGE "Error: unable to auto get GPG key for PPG url ${PPA_URLS[$i]}"
                    return 255
                fi
                sudo wget "${PPA_WGET_NO_PROXY[$i]}" "$url/$ppa_gpg_key.gpg" -O /etc/apt/trusted.gpg.d/"$ppa_gpg_key".gpg
            else
                if [[ -n "${PPA_GPGS[$i]}" ]]; then
                    gpg_key_name=$(basename "${PPA_GPGS[$i]}")
                    if [[ ! -f /etc/apt/trusted.gpg.d/$gpg_key_name ]]; then
                        sudo wget "${PPA_WGET_NO_PROXY[$i]}" "${PPA_GPGS[$i]}" -O /etc/apt/trusted.gpg.d/"$gpg_key_name"
                    fi
                fi
            fi
        else
            echo "deb [trusted=yes] ${PPA_URLS[$i]}" | sudo tee -a /etc/apt/sources.list.d/ubuntu_bsp.list
        fi
    done

    # Pin Intel BSP PPA
    echo -e "Package: *\nPin: $PPA_PIN\nPin-Priority: $PPA_PIN_PRIORITY" | sudo tee -a /etc/apt/preferences.d/priorities

    # Add PPA apt proxy settings if any
    if [[ -n "${ftp_proxy+x}" && -n "$ftp_proxy" ]]; then
        echo "Acquire::ftp::Proxy \"$ftp_proxy\";" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
    fi
    if [[ -n "${http_proxy+x}" && -n "$http_proxy" ]]; then
        echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
    fi
    if [[ -n "${https_proxy+x}" && -n "$https_proxy" ]]; then
        echo "Acquire::https::Proxy \"$https_proxy\";" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
    fi
    for line in "${PPA_APT_CONF[@]}"; do
        if [[ -n "$line" ]]; then
            echo "$line" | sudo tee -a /etc/apt/apt.conf.d/99proxy.conf
        fi
    done

    # Update package cache after adding PPA
    sudo apt-get update -y

    $LOGD "${FUNCNAME[0]} end"
}

function validate_packages_availability() {
    local package_list="$1"
    local log_file="$2"

    $LOGD "Validating package availability from repository..."
    echo "=== Package Availability Validation ===" >> "$log_file"

    # Update apt cache to get latest package information
    sudo apt-get update 2>&1 | sudo tee -a "$log_file" > /dev/null

    # Get all available packages once (much faster than checking each individually)
    # Use apt-cache pkgnames which is script-friendly and fast
    $LOGD "Building package availability cache..."
    declare -A pkg_cache
    while IFS= read -r pkg; do
        pkg_cache["$pkg"]=1
    done < <(apt-cache pkgnames 2>/dev/null)

    # Validate each package and build filtered list
    local validated_list=""
    local missing_packages=""
    local pkg_name
    local pkg_version

    for pkg in $package_list; do
        # Split package name and version if specified (e.g., package=version)
        if [[ "$pkg" == *"="* ]]; then
            pkg_name="${pkg%%=*}"
            pkg_version="${pkg#*=}"
        else
            pkg_name="$pkg"
            pkg_version=""
        fi

        # Check if package exists using O(1) hash lookup
        if [[ -z "${pkg_cache[$pkg_name]:-}" ]]; then
            $LOGD "WARNING: Package $pkg not available in repository, skipping"
            missing_packages+="$pkg "
            echo "WARNING: Package $pkg not available in repository, skipping installation" >> "$log_file"
            continue
        fi

        # Package name exists, now check version if specified
        if [[ -z "$pkg_version" ]]; then
            validated_list+="$pkg "
            continue
        fi

        # Version is specified, verify it's available
        if apt-cache madison "$pkg_name" 2>/dev/null | grep -q "$pkg_version"; then
            validated_list+="$pkg "
            continue
        fi

        # Specified version not available, try without version constraint
        $LOGD "WARNING: Package $pkg_name version $pkg_version not available, trying without version constraint"
        echo "WARNING: Package $pkg_name=$pkg_version not available with specified version" >> "$log_file"
        validated_list+="$pkg_name "
        echo "  -> Will install $pkg_name with default available version" >> "$log_file"
    done

    # Log missing packages summary
    if [[ -n "$missing_packages" ]]; then
        {
            echo ""
            echo "=== Missing Packages Summary ==="
            echo "The following packages are not available and will be skipped:"
            for pkg in $missing_packages; do
                echo "  - $pkg"
            done
            echo ""
        } >> "$log_file"
        $LOGD "WARNING: Some packages are not available in repository. See log for details: $log_file"
    fi

    {
        echo "=== Validated Packages to Install ==="
        echo "$validated_list"
        echo ""
    } >> "$log_file"

    # Return validated package list
    echo "$validated_list"
}

function install_userspace_pkgs() {
    $LOGD "${FUNCNAME[0]} begin"

    # Load bsp packages from configuration file
    local script_dir
    script_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

    if [[ ! -f "$script_dir/bsp_packages.sh" ]]; then
        $LOGE "Error: Package configuration file not found: $script_dir/bsp_packages.sh"
        return 255
    fi

    # Source the packages configuration
    # shellcheck source-path=SCRIPTDIR
    source "$script_dir/bsp_packages.sh"

    # Select the appropriate package list based on detected Ubuntu version
    $LOGD "Detected Ubuntu version: $UBUNTU_VERSION ($UBUNTU_CODENAME)"

    # Look up the package variable name for this version
    local package_var_name="${BSP_PACKAGE_VERSION_MAP[$UBUNTU_VERSION]:-$BSP_PACKAGE_DEFAULT}"

    # Use indirect variable expansion to get the package list
    local selected_packages="${!package_var_name}"
    $LOGD "Using package list: $package_var_name"

    # Process comma-separated string directly into space-separated string, removing empty entries and whitespace
    local package_list=""
    local old_ifs="$IFS"
    IFS=','
    for pkg in $selected_packages; do
        # Trim whitespace, newlines, and carriage returns, skip empty entries
        pkg=$(echo "$pkg" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$pkg" ]]; then
            package_list+="$pkg "
        fi
    done
    IFS="$old_ifs"

    # Add additional packages
    if [[ -n $LINUX_FW_PPA_VER ]]; then
        package_list+="linux-firmware=$LINUX_FW_PPA_VER "
    else
        package_list+="linux-firmware "
    fi

    # for SPICE with SRIOV cursor support
    package_list+="spice-vdagent "

    # install all bsp overlay packages in a single command
    if [[ -n "$package_list" ]]; then
        echo "Installing BSP overlay packages..."
        local log_file
        log_file="/var/log/bsp_install_$(date +%Y%m%d_%H%M%S).log"
        $LOGD "Logging package installation to: $log_file"
        {
            echo "=== BSP Package Installation Log ==="
            echo "Date: $(date)"
            echo "Initial packages requested:"
            echo "$package_list"
            echo ""
        } > "$log_file"

        # Validate package availability and get filtered list
        package_list=$(validate_packages_availability "$package_list" "$log_file")

        # Install validated packages
        if [[ -n "$package_list" ]]; then
            # shellcheck disable=SC2086
            if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades $package_list 2>&1 | tee -a "$log_file"; then
                $LOGD "BSP overlay packages installed successfully"
                echo "" >> "$log_file"
                echo "=== Installation completed successfully ===" >> "$log_file"
            else
                local exit_code=$?
                $LOGE "Error: Failed to install BSP overlay packages. Exit code: $exit_code. Check log: $log_file"
                echo "" >> "$log_file"
                echo "=== Installation FAILED with exit code: $exit_code ===" >> "$log_file"
                return 255
            fi
        else
            $LOGD "WARNING: No valid packages to install after validation"
            echo "WARNING: No valid packages to install after validation" >> "$log_file"
        fi
    fi

    # other non overlay packages
    for package in "${PACKAGES_ADD_INSTALL[@]}"; do
        if [[ -n ${package+x} && -n $package ]]; then
            echo "Installing package: $package"
            if ! sudo apt-get install -y --allow-downgrades "$package" 2>&1 | tee -a "$log_file"; then
                $LOGE "Error: Failed to install additional package: $package"
                return 255
            fi
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
    for config in "${auto_upgrade_config[@]}"; do
        if [[ ! $(cat /etc/apt/apt.conf.d/20auto-upgrades) =~ $config ]]; then
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
    local cmdline
    local drm_drv

    if [[ -z "${DRM_DRV_SELECTED+x}" || -z "$DRM_DRV_SELECTED" ]]; then
        drm_drv=$(lspci -D -k  -s 0000:00:02.0 | grep "Kernel driver in use" | awk -F ':' '{print $2}' | xargs)
        set_drm_drv "$drm_drv" || return 255
    else
        drm_drv="$DRM_DRV_SELECTED"
    fi

    if [[ "$RT" == "0" ]]; then
        cmds=("$drm_drv.force_probe=*"
              "$drm_drv.enable_guc=(0x)?(0)*3"
              "$drm_drv.max_vfs=(0x)?(0)*0"
              "udmabuf.list_limit=8192")
    else
        cmds=("$drm_drv.force_probe=*"
              "$drm_drv.enable_guc=(0x)?(0)*3"
              "$drm_drv.max_vfs=(0x)?(0)*0"
              "udmabuf.list_limit=8192"
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
              "$drm_drv.enable_rc6=0"
              "$drm_drv.enable_dc=0"
              "$drm_drv.disable_power_well=0"
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
    cmdline=$(awk -F '"' '{print $2}' <<< "$cmdline")

    if [[ "${#DRM_DRV_SUPPORTED[@]}" -gt 1 ]]; then
        for drv in "${DRM_DRV_SUPPORTED[@]}"; do
            cmdline=$(sed -r -e "s/\<modprobe\.blacklist=$drv\>//g" <<< "$cmdline")
        done
        for drv in "${DRM_DRV_SUPPORTED[@]}"; do
            if [[ "$drv" != "$drm_drv" ]]; then
                $LOGD "INFO: force $drm_drv drm driver over others"
                cmds+=("modprobe.blacklist=$drv")
            fi
        done
    fi

    for cmd in "${cmds[@]}"; do
        if [[ ! "$cmdline" =~ $cmd ]]; then
            # Special handling for drm driver
            if [[ "$cmd" == "$drm_drv.enable_guc=(0x)?(0)*3" ]]; then
                for drv in "${DRM_DRV_SUPPORTED[@]}"; do
                    cmdline=$(sed -r -e "s/\<$drv.enable_guc=(0x)?([A-Fa-f0-9])*\>//g" <<< "$cmdline")
                done
                cmd="$drm_drv.enable_guc=0x3"
            fi
            if [[ "$cmd" == "$drm_drv.max_vfs=(0x)?(0)*0" ]]; then
                for drv in "${DRM_DRV_SUPPORTED[@]}"; do
                    cmdline=$(sed -r -e "s/\<$drv.max_vfs=(0x)?([0-9])*\>//g" <<< "$cmdline")
                done
                cmd="$drm_drv.max_vfs=0"
            fi

            cmdline="$cmdline $cmd"
            updated=1
        fi
    done

    if [[ "$updated" -eq 1 ]]; then
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
    if ! grep -Fq 'needs_root_rights=no' /etc/X11/Xwrapper.config; then
        echo 'needs_root_rights=no' | sudo tee -a /etc/X11/Xwrapper.config
    fi
    if ! grep -Fq 'MESA_LOADER_DRIVER_OVERRIDE=pl111' /etc/environment; then
        echo 'MESA_LOADER_DRIVER_OVERRIDE=pl111' | sudo tee -a /etc/environment
    fi
    # Enable for SW cursor
    if ! grep -Fq 'VirtIO-GPU' /usr/share/X11/xorg.conf.d/20-modesetting.conf; then
        sudo tee -a "/usr/share/X11/xorg.conf.d/20-modesetting.conf" &>/dev/null <<EOF
Section "Device"
Identifier "VirtIO-GPU"
Driver "modesetting"
#BusID "PCI:0:4:0" #virtio-gpu
Option "SWcursor" "false"
EndSection
EOF
    fi
    # Add script to dynamically enable/disable SW cursor
    if ! grep -Fq '/dev/virtio-ports/com.redhat.spice.0' /usr/local/bin/setup_sw_cursor.sh; then
        sudo tee -a "/usr/local/bin/setup_sw_cursor.sh" &>/dev/null <<EOF
#!/bin/bash
if [[ -e /dev/virtio-ports/com.redhat.spice.0 ]]; then
    if grep -F '"SWcursor" "true"' /usr/share/X11/xorg.conf.d/20-modesetting.conf; then
        sed -i "s/Option \"SWcursor\" \"true\"/Option \"SWcursor\" \"false\"/g" /usr/share/X11/xorg.conf.d/20-modesetting.conf
    fi
else
    if grep -F '"SWcursor" "false"' /usr/share/X11/xorg.conf.d/20-modesetting.conf; then
        sed -i "s/Option \"SWcursor\" \"false\"/Option \"SWcursor\" \"true\"/g" /usr/share/X11/xorg.conf.d/20-modesetting.conf
    fi
fi
EOF
        sudo chmod 744 /usr/local/bin/setup_sw_cursor.sh
    fi
    # Add startup service to run script during boot up
    if ! grep -Fq 'ExecStart=/usr/local/bin/setup_sw_cursor.sh' /etc/systemd/system/setup_sw_cursor.service; then
        sudo tee -a "/etc/systemd/system/setup_sw_cursor.service" &>/dev/null <<EOF
[Unit]
Description=Script to dynamically enable/disable SW cursor for SPICE gstreamer
After=sysinit.target
[Service]
ExecStart=/usr/local/bin/setup_sw_cursor.sh
[Install]
WantedBy=default.target
EOF
        sudo chmod 664 /etc/systemd/system/setup_sw_cursor.service
        sudo systemctl daemon-reload
        if [[ "$FORCE_SW_CURSOR" == "1" ]]; then
            sudo systemctl enable setup_sw_cursor.service
        fi
    fi
    # Disable GUI for RT guest
    if [[ "$RT" == "1" ]]; then
        systemctl set-default multi-user.target
    fi
    $LOGD "${FUNCNAME[0]} end"
}

function show_help() {
    printf "%s [-k kern_deb_path | -kp kern_ver] [-fw fw_ver] [-drm drm_drv] [--no-install-bsp] [--rt]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Options:\n"
    printf "\t-h\tshow this help message\n"
    printf "\t-k\tpath to location of bsp kernel files linux-headers.deb and linux-image.deb\n"
    printf "\t-kp\tversion string of kernel overlay to select from Intel PPA. Eg \"6.3-intel\"\n"
    printf "\t-fw\tversion string of linux-firmware overlay to select from Intel PPA. Eg \"20240318.git3b128b60-0.2.7-1ppa1-noble1\"\n"
    printf "\t--rt\tinstall for Ubuntu RT version\n"
    printf "\t--no-bsp-install\tDo not preform bsp overlay related install(kernel and userspace)\n"
    printf "\t-drm\tspecify drm driver to use for Intel gpu:\n"
    for d in "${DRM_DRV_SUPPORTED[@]}"; do
        printf '\t\t\t%s\n' "$(basename "$d")"
    done
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit 0
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

            -fw)
                LINUX_FW_PPA_VER=$2
                shift
                ;;

            -drm)
                set_drm_drv "$2" || return 255
                shift
                ;;

            --rt)
                RT=1
                ;;

            --no-bsp-install)
                NO_BSP_INSTALL=1
                ;;

            --force-sw-cursor)
                FORCE_SW_CURSOR=1
                ;;

            -?*)
                $LOGE "Error: Invalid option: $1"
                show_help
                return 255
                ;;
            *)
                $LOGE "Error: Unknown option: $1"
                return 255
                ;;
        esac
        shift
    done
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

if [[ "$NO_BSP_INSTALL" -ne "1" ]]; then
    # Detect Ubuntu version and configure PPA settings
    setup_ubuntu_ppa_config

    # Install PPA
    setup_overlay_ppa || exit 255

    # Install bsp kernel
    if [[ "$KERN_INSTALL_FROM_PPA" -eq "0" ]]; then
        install_kernel_from_deb "$KERN_PATH" || exit 255
    else
        install_kernel_from_ppa "$KERN_PPA_VER" || exit 255
    fi
    # Install bsp userspace
    install_userspace_pkgs || exit 255
fi
disable_auto_upgrade || exit 255
update_cmdline || exit 255
update_ubuntu_cfg || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

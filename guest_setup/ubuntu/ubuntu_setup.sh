#!/bin/bash

# Copyright (c) 2023-2026 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
LIBVIRT_DEFAULT_IMAGES_PATH="/var/lib/libvirt/images"
OVMF_DEFAULT_PATH=/usr/share/OVMF
LIBVIRT_DEFAULT_LOG_PATH="/var/log/libvirt/qemu"
UBUNTU_DOMAIN_NAME=ubuntu
UBUNTU_IMAGE_NAME=$UBUNTU_DOMAIN_NAME.qcow2
UBUNTU_INSTALLER_ISO=ubuntu.iso
UBUNTU_SEED_ISO=ubuntu-seed.iso
declare -A UBUNTU_INSTALLER_ISO_URLS=(
  ['22.04']='https://cdimage.ubuntu.com/releases/jammy/release/inteliot/ubuntu-22.04-live-server-amd64+intel-iot.iso'
  ['24.04']='https://releases.ubuntu.com/noble/ubuntu-24.04.3-live-server-amd64.iso'
)
declare -A UBUNTU_INSTALLER_SHA256SUMS_URLS=(
  ['22.04']='https://cdimage.ubuntu.com/releases/jammy/release/inteliot/SHA256SUMS'
  ['24.04']='https://releases.ubuntu.com/noble/SHA256SUMS'
)
declare -A UBUNTU_INSTALLER_ISO_OLD_RELEASES_URLS=(
  ['22.04']='https://old-releases.ubuntu.com/releases/jammy/'
  ['24.04']='https://old-releases.ubuntu.com/releases/noble/'
)
declare -A UBUNTU_SNAP_GNOME_VERSIONS=(
  ['22.04']='gnome-3-38-2004'
  ['24.04']='gnome-42-2204'
)
UBUNTU_INSTALL_OS_TYPE=""

# files required to be in unattend_ubuntu folder for installation
REQUIRED_DEB_FILES=( "linux-headers.deb" "linux-image.deb" )
declare -a TMP_FILES
TMP_FILES=()

FORCECLEAN=0
VIEWER=0
SETUP_DISK_SIZE=60 # size in GiB
RT=0
KERN_INSTALL_FROM_LOCAL=0
FORCE_KERN_FROM_DEB=0
FORCE_KERN_APT_VER=""
FORCE_LINUX_FW_APT_VER=""
FORCE_UBUNTU_VER=""
SETUP_DEBUG=0
FORCE_SW_CURSOR=0

VIEWER_DAEMON_PID=
FILE_SERVER_DAEMON_PID=
FILE_SERVER_IP="192.168.122.1"
FILE_SERVER_PORT=8001
HOST_NC_DAEMON_PID=

# Global variables to store validated versions
VALIDATED_KERNEL_VER=""
VALIDATED_LINUX_FW_VER=""

# Global variables for guest PPA configuration
# These are populated by load_guest_ppa_configuration() to match what guest setup will use
# Sourced from either installer.sh OR setup_bsp.sh defaults
declare -a PPA_URLS=()
declare -a PPA_GPGS=()
PPA_PIN=""
PPA_PIN_PRIORITY=""
PPA_CONFIG_SOURCE="setup_bsp.sh"  # Tracks whether PPA config came from installer.sh or setup_bsp.sh

# Version-specific PPA alternates from setup_bsp.sh (used as fallback)
declare -A PPA_ALT_URLS=()
declare -A PPA_ALT_GPGS=()
declare -A PPA_ALT_PIN=()
declare -A PPA_ALT_PIN_PRIORITY=()

# Cache for Packages.gz content keyed by URL, populated on first access
# Avoids re-downloading the same file for each check_package_in_guest_ppa() call
declare -A _PPA_PACKAGES_CACHE=()

#---------      Functions    -------------------
declare -F "check_non_symlink" >/dev/null || function check_non_symlink() {
    if [[ $# -eq 1 ]]; then
        if [[ -L "$1" ]]; then
            echo "Error: $1 is a symlink."
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

declare -F "check_dir_valid" >/dev/null || function check_dir_valid() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        dpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -d $dpath ]]; then
            echo "Error: $dpath invalid directory"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f $fpath || ! -s $fpath ]]; then
            echo "Error: $fpath invalid/zero sized"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

function copy_setup_files() {
    # copy required files for use in guest
    local dest=$1
    local host_scripts=("setup_swap.sh" "setup_openvino.sh" )

    if [[ $# -ne 1 || -z "$dest" ]]; then
        echo "error: invalid params"
        return 255
    fi

    local script
    script=$(realpath "${BASH_SOURCE[0]}")
    local scriptpath
    scriptpath=$(dirname "$script")
    local host_scriptpath
    host_scriptpath=$(realpath "$scriptpath/../../host_setup/ubuntu")
    local guest_scriptpath
    guest_scriptpath=$(realpath "$scriptpath/unattend_ubuntu")
    local dest_path
    dest_path=$(realpath "$dest")

    if [[ ! -d "$dest_path" ]]; then
        echo "error: Dest location to copy setup required files is not a directory"
        return 255
    fi
    check_dir_valid "$dest_path"

    for script in "${host_scripts[@]}"; do
        check_file_valid_nonzero "$host_scriptpath/$script"
        cp -a "$host_scriptpath"/"$script" "$dest_path"/
    done

    local -a guest_files=()
    mapfile -t guest_files < <(find "$guest_scriptpath/" -maxdepth 1 -mindepth 1 -type f -not -name "linux-image*.deb" -not -name "linux-headers*.deb")
    for file in "${guest_files[@]}"; do
        check_file_valid_nonzero "$file"
        cp -a "$file" "$dest_path"/
    done

    for file in "${REQUIRED_DEB_FILES[@]}"; do
        dfile=$(echo "$file" | sed -r 's/-rt//')
        check_file_valid_nonzero "$guest_scriptpath"/"$file"
        cp -a "$guest_scriptpath"/"$file" "$dest_path"/"$dfile"
    done

    local -a dest_files=()
    mapfile -t dest_files < <(find "$dest_path/" -maxdepth 1 -mindepth 1 -type f)
    for file in "${dest_files[@]}"; do
        if grep -Eq 'sudo(\s)+(-[ABbEHnPS]\s)+' "$file"; then
            sed -i -r "s|sudo(\s)+(-[ABbEHnPS]\s)+||" "$file"
        fi
        if grep -Fq 'sudo' "$file"; then
            sed -i -r "s|sudo(\s)+||" "$file"
        fi
    done
}

function run_file_server() {
    local folder=$1
    local ip=$2
    local port=$3
    local -n pid=$4
    local existing_pid
    existing_pid=$(pgrep -f "python3 -m http.server -b $ip $port")
    if [[ -n "$existing_pid" ]]; then
      echo "Kill existing http.server $ip $port"
      kill_by_pid "$existing_pid"
    fi
    cd "$folder"
    python3 -m http.server -b "$ip" "$port" > /dev/null 2>&1 &
    sleep 5
    pid=$(pgrep -f "python3 -m http.server -b $ip $port")
    cd -
    if [[ -n "$pid" ]]; then
      return 0
    else
      echo "Error: fail to create http.server"
      return 255
    fi
}

function run_nc_server() {
    local ip=$1
    local port=$2
    local out_file=$3
    local -n pid=$4

    # Run nc in a loop to accept multiple connections
    # Each connection appends to the output file
    # Loop will run for up to 2 hours (120 iterations * 60 sec timeout)
    (
        local max_iterations=120
        local iteration=0
        while [[ $iteration -lt $max_iterations ]]; do
            nc -l -s "$ip" -p "$port" -w 60 >> "$out_file" 2>/dev/null || true
            iteration=$((iteration + 1))
        done
    ) &
    pid=$!
}

function kill_by_pid() {
    if [[ $# -eq 1 && -n "${1}" && -n "${1+x}" ]]; then
        local pid=$1
        if [[ -n "$(ps -p "$pid" -o pid=)" ]]; then
            # Try graceful termination first
            sudo kill "$pid" 1>/dev/null
            local count=0
            local maxcount=20
            while [[ -n "$(ps -p "$pid" -o pid=)" && $count -lt $maxcount ]]; do
                sleep 0.2
                count=$((count+1))
            done
            # If still running, force kill
            if [[ -n "$(ps -p "$pid" -o pid=)" ]]; then
                sudo kill -9 "$pid" 1>/dev/null
                count=0
                while [[ -n "$(ps -p "$pid" -o pid=)" && $count -lt $maxcount ]]; do
                    sleep 0.2
                    count=$((count+1))
                done
            fi
        fi
    fi
}

function install_dep() {
  which cloud-localds > /dev/null || sudo apt-get install -y cloud-image-utils
  which virt-install > /dev/null || sudo apt-get install -y virtinst
  which virt-viewer > /dev/null || sudo apt-get install -y virt-viewer
  which yamllint > /dev/null || sudo apt-get install -y yamllint
  which nc > /dev/null || sudo apt-get install -y netcat-openbsd
  which envsubst > /dev/null || sudo apt-get install -y gettext-base
  which sha256sum > /dev/null || sudo apt-get install -y coreutils
}

function clean_ubuntu_images() {
  echo "Remove existing ubuntu image"
  virsh destroy "$UBUNTU_DOMAIN_NAME" &>/dev/null || :
  sleep 5
  virsh undefine "$UBUNTU_DOMAIN_NAME" --nvram &>/dev/null || :
  sudo rm -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME}"
  sudo rm -f "${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log"

#  echo "Remove ubuntu.iso"
#  sudo rm -f ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}

#  echo "Remove ubuntu-seed.iso"
#  sudo rm -f ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_SEED_ISO}
}

function is_host_kernel_local_install() {
  if [[ $FORCE_KERN_FROM_DEB == "1" ]]; then
    KERN_INSTALL_FROM_LOCAL=1
    return
  elif [[ -n $FORCE_KERN_APT_VER ]]; then
    KERN_INSTALL_FROM_LOCAL=0
    return
  fi

  local kern_ver
  kern_ver=$(uname -r)
  local kern_header_ppa
  kern_header_ppa=$(dpkg -l "linux-headers-$kern_ver" 2>/dev/null | grep "^ii")
  local kern_image_ppa
  kern_image_ppa=$(dpkg -l "linux-image-$kern_ver" 2>/dev/null | grep "^ii")
  local kern_header_ppa_local
  kern_header_ppa_local=$(dpkg -l "linux-headers-$kern_ver" 2>/dev/null | awk '{print $3}' | grep "local")
  local kern_image_ppa_local
  kern_image_ppa_local=$(dpkg -l "linux-image-$kern_ver" 2>/dev/null | awk '{print $3}' | grep "local")

  if [[ -z "$kern_header_ppa" || -z "$kern_image_ppa" || -n "$kern_header_ppa_local" || -n "$kern_image_ppa_local" ]]; then
    KERN_INSTALL_FROM_LOCAL=1
  else
    KERN_INSTALL_FROM_LOCAL=0
  fi
}

function download_ubuntu_iso() {
  local maxcount=10
  local count=0

  if [[ -z "${1+x}" || -z "$1" ]]; then
    echo "Error: no ubuntu version provided"
    return 255
  fi
  local ubuntu_ver=$1
  if [[ -z "${2+x}" || -z "$2" ]]; then
    echo "Error: no dest tmp path provided"
    return 255
  fi
  local dest_tmp_path=$2
  local iso_fname
  iso_fname=$(basename "${UBUNTU_INSTALLER_ISO_URLS[$ubuntu_ver]}")
  while [[ $count -lt $maxcount ]]; do
    count=$((count+1))
    echo "$count: Download Ubuntu $ubuntu_ver iso to $dest_tmp_path"
    wget -O "$dest_tmp_path/${UBUNTU_INSTALLER_ISO}" "${UBUNTU_INSTALLER_ISO_URLS[$ubuntu_ver]}" \
    || wget -O "$dest_tmp_path/${UBUNTU_INSTALLER_ISO}" "${UBUNTU_INSTALLER_ISO_OLD_RELEASES_URLS[$ubuntu_ver]}$iso_fname" || return 255
    if verify_and_copy_ubuntu_iso "$ubuntu_ver" "$dest_tmp_path" "$dest_tmp_path/${UBUNTU_INSTALLER_ISO}"; then
      break
    else
      return 255
    fi
  done
  if [[ $count -ge $maxcount ]]; then
    echo "error: download exceeded max tries."
    return 255
  fi
  return 0
}

function verify_and_copy_ubuntu_iso() {
  local maxcount=10
  local count=0

  if [[ -z "${1+x}" || -z "$1" ]]; then
    echo "Error: no ubuntu version provided"
    return 255
  fi
  local ubuntu_ver=$1
  if [[ -z "${2+x}" || -z "$2" ]]; then
    echo "Error: no dest tmp path provided"
    return 255
  fi
  local dest_tmp_path=$2
  if [[ -z "${3+x}" || -z "$3" ]]; then
    echo "Error: no Ubuntu iso path provided"
    return 255
  fi
  local iso_to_check
  iso_to_check=$(realpath "$3")

  echo "INFO: Verifying $ubuntu_ver iso: $iso_to_check"
  wget -O "$dest_tmp_path/SHA256SUMS" "${UBUNTU_INSTALLER_SHA256SUMS_URLS[$ubuntu_ver]}" || return 255
  wget -O "$dest_tmp_path/SHA256SUMS_OLD_RELEASES" "${UBUNTU_INSTALLER_ISO_OLD_RELEASES_URLS[$ubuntu_ver]}SHA256SUMS" || return 255

  local isochksum
  isochksum=$(sha256sum "$iso_to_check" | awk '{print $1}')
  local verifychksum
  local iso_fname
  iso_fname=$(basename "${UBUNTU_INSTALLER_ISO_URLS[$ubuntu_ver]}")

  # Try main SHA256SUMS first
  echo "INFO: Trying verification against main releases SHA256SUMS"
  verifychksum=$(grep "$iso_fname" < "$dest_tmp_path/SHA256SUMS" | awk '{print $1}' | head -1)

  # If not found or doesn't match, try old releases SHA256SUMS
  if [[ -z "$verifychksum" || "$isochksum" != "$verifychksum" ]]; then
    echo "INFO: Falling back to old releases SHA256SUMS"
    verifychksum=$(grep "$iso_fname" < "$dest_tmp_path/SHA256SUMS_OLD_RELEASES" | awk '{print $1}' | head -1)
  fi

  if [[ "$isochksum" == "$verifychksum" ]]; then
    # downloaded iso is okay.
    echo "Verified Ubuntu $ubuntu_ver iso checksum as expected: $isochksum"
    sudo cp "$iso_to_check" "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
    sudo chown root:root "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
  else
    echo "ERROR: provided Ubuntu ISO $iso_to_check SHA256 checksum does not match expected checksum"
    echo "Expected: $verifychksum for file: $iso_fname"
    echo "Actual: $isochksum"
    return 255
  fi
}

# Check if a package is available in guest PPAs
# Validates against PPAs from either installer.sh OR setup_bsp.sh (whichever is loaded)
check_package_in_guest_ppa() {
  local pkg_name=$1
  local pkg_query=$2  # e.g., "linux-headers-6.12=1.2.3" or just "linux-headers-6.12"

  # Extract version if present in query
  local search_version=""
  if [[ "$pkg_query" =~ = ]]; then
    search_version="${pkg_query#*=}"
  fi

  # Get system architecture
  local arch
  arch=$(dpkg --print-architecture 2>/dev/null) || arch="amd64"

  # Check if PPA_URLS is available
  if [[ ${#PPA_URLS[@]} -eq 0 ]]; then
    echo "Warning: No guest PPAs available for HTTP validation" >&2
    return 1
  fi

  # Try each guest PPA (from installer.sh or setup_bsp.sh)
  for i in "${!PPA_URLS[@]}"; do
    local ppa_url="${PPA_URLS[$i]}"

    # Parse PPA URL format: "https://example.com/path/ release component1 component2 ..."
    local ppa_base
    ppa_base=$(echo "$ppa_url" | awk '{print $1}')
    # Remove trailing slash if present
    ppa_base="${ppa_base%/}"
    local ppa_release
    ppa_release=$(echo "$ppa_url" | awk '{print $2}')

    # Get all components (everything after release)
    local ppa_components
    ppa_components=$(echo "$ppa_url" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')

    # Try each component
    for component in $ppa_components; do
      # Construct Packages.gz URL
      local packages_url="${ppa_base}/dists/${ppa_release}/${component}/binary-${arch}/Packages.gz"

      # Use cached content if available, otherwise download and cache
      local packages_content
      if [[ -z "${_PPA_PACKAGES_CACHE[$packages_url]:-}" ]]; then
        local downloaded
        downloaded=$(curl -sSL --connect-timeout 10 --max-time 30 \
          --retry 2 "$packages_url" 2>/dev/null | gunzip 2>/dev/null) || continue
        _PPA_PACKAGES_CACHE[$packages_url]="$downloaded"
      fi
      packages_content="${_PPA_PACKAGES_CACHE[$packages_url]}"

      # Search for exact package name using here-string
      grep -q "^Package: ${pkg_name}$" <<< "$packages_content" || continue

      # Package found - check version if specified
      if [[ -z "$search_version" ]]; then
        # No version requirement - package exists
        return 0
      fi

      # Extract and verify version for this package
      local found_version
      found_version=$(awk -v pkg="$pkg_name" -v ver="$search_version" '
        /^Package:/ { if ($2 == pkg) in_pkg=1; else in_pkg=0 }
        in_pkg && /^Version:/ { if ($2 == ver) { print "match"; exit } }
      ' <<< "$packages_content")

      if [[ "$found_version" == "match" ]]; then
        return 0
      fi
    done
  done

  return 1
}

function validate_kernel_ppa_availability() {
  local kernel_ver=$1
  local is_forced=${2:-0}

  # Extract base version and package version
  local kern_base_ver
  local kern_pkg_ver
  if [[ "$kernel_ver" =~ ^([^=]+)=(.+)$ ]]; then
    kern_base_ver="${BASH_REMATCH[1]}"
    kern_pkg_ver="${BASH_REMATCH[2]}"
  else
    kern_base_ver="$kernel_ver"
    kern_pkg_ver=""
  fi

  # Build package queries based on whether version is specified
  local headers_query="linux-headers-${kern_base_ver}"
  local image_query="linux-image-${kern_base_ver}"
  if [[ -n "$kern_pkg_ver" ]]; then
    headers_query="${headers_query}=${kern_pkg_ver}"
    image_query="${image_query}=${kern_pkg_ver}"
  fi

  # Check if both packages are available in guest PPAs
  local headers_available=0
  local image_available=0

  # PPA_URLS must be populated by load_guest_ppa_configuration()
  if [[ ${#PPA_URLS[@]} -eq 0 ]]; then
    echo "ERROR: PPA configuration not loaded. Call load_guest_ppa_configuration() first." >&2
    return 255
  fi

  echo "  Validating: linux-{headers,image}-$kernel_ver..." >&2
  if check_package_in_guest_ppa "linux-headers-${kern_base_ver}" "$headers_query"; then
    headers_available=1
  fi

  if check_package_in_guest_ppa "linux-image-${kern_base_ver}" "$image_query"; then
    image_available=1
  fi

  # Version not available from guest PPAs
  if [[ $headers_available -eq 0 || $image_available -eq 0 ]]; then
    local missing_packages=""
    if [[ $headers_available -eq 0 ]]; then
      missing_packages+="    - linux-headers-${kernel_ver}
"
    fi
    if [[ $image_available -eq 0 ]]; then
      missing_packages+="    - linux-image-${kernel_ver}
"
    fi

    if [[ $is_forced -eq 1 ]]; then
      # For manual override, fail with error
      echo "  Error: Forced kernel version '$kernel_ver' is not available in guest PPAs" >&2
      echo "  Missing packages:" >&2
      # shellcheck disable=SC2001  # sed is appropriate for adding prefix to each line
      echo "$missing_packages" | sed 's/^/  /' >&2
      echo "  Please check available versions or remove --force-kern-apt-ver to use auto-detection" >&2
      return 255
    else
      # For host auto-detection, always fail - guest cannot use host-only packages
      local error_msg
      error_msg=$(cat <<EOF
==========================================
ERROR: Host Kernel Not Available in Guest PPAs
==========================================
Host kernel version: $kernel_ver

Missing packages:
${missing_packages}
The host kernel is not available in the PPAs that guest setup will use.
Guest installation cannot proceed with packages that aren't in guest repositories.

Options to resolve:
1. Use --force-kern-from-deb to install from local .deb files
   (Place linux-headers.deb and linux-image.deb in guest_setup/ubuntu/unattend_ubuntu/)
2. Use --force-kern-apt-ver to specify a kernel version available in guest PPAs
==========================================
EOF
)
      # shellcheck disable=SC2001  # sed is appropriate for adding prefix to each line
      echo "$error_msg" | sed 's/^/  /' >&2
      echo "" >&2
      return 255
    fi
  fi

  # Version is available, return it
  echo "$kernel_ver"
  return 0
}

function is_npu_supported() {
  local host_kern
  local allowed_kern

  # Only capture and compare kernel version x.y
  # Only allow kernel version 6.9 or above
  IFS=" " read -r -a host_kern <<< "$(uname -r | cut -d '-' -f1 | tr '.' ' ')"
  IFS=" " read -r -a allowed_kern <<< "$(echo "6.9" | tr '.' ' ')"

  for i in {0..1}; do
    if [[ ${allowed_kern[$i]} -lt ${host_kern[$i]} ]]; then
      return 0
    elif [[ ${allowed_kern[$i]} -gt ${host_kern[$i]} ]]; then
      return 1
    fi
  done

  return 0
}

function check_ppa_consistency() {
  # Compare guest PPA settings with host's current PPA configuration
  # Shows warning if they differ, but does not fail (allows intentional differences)
  # Uses PPA_CONFIG_SOURCE to identify the source (installer.sh or setup_bsp.sh)
  # Returns: 0 (always succeeds, only warns on mismatch)

  echo "  Checking PPA configuration consistency with host..."
  local host_ppa_sources
  host_ppa_sources=$(grep -h "^deb" /etc/apt/sources.list.d/*.list 2>/dev/null || true)

  if [[ -z "$host_ppa_sources" ]]; then
    echo "  Info: No PPA sources found on host for comparison"
    return 0
  fi

  local ppa_mismatch=0
  local guest_ppa_urls=""

  # Collect guest PPA URLs from current configuration
  for i in "${!PPA_URLS[@]}"; do
    local ppa_url="${PPA_URLS[$i]}"
    guest_ppa_urls+="    ${ppa_url}"$'\n'
  done

  # Check if guest PPAs match host configuration
  for i in "${!PPA_URLS[@]}"; do
    local ppa_url="${PPA_URLS[$i]}"
    local ppa_base
    ppa_base=$(echo "$ppa_url" | awk '{print $1}')

    # Extract key URL components for comparison (domain and major path)
    local ppa_key
    ppa_key=$(echo "$ppa_base" | sed -E 's|https?://||' | cut -d'/' -f1-3)

    # Check if this PPA base appears in host sources
    if ! echo "$host_ppa_sources" | grep -q "$ppa_key"; then
      ppa_mismatch=1
    fi
  done

  if [[ $ppa_mismatch -eq 1 ]]; then
    local warning_msg
    # Format host PPAs with indentation
    local formatted_host_ppas
    # shellcheck disable=SC2001  # sed is appropriate for multi-line indentation
    formatted_host_ppas=$(echo "$host_ppa_sources" | sed 's/^/    /')
    # Guest PPAs already have indentation from collection

    warning_msg=$(cat <<EOF
==========================================
WARNING: Guest/Host PPA Configuration Mismatch
==========================================
The guest PPA configuration differs from the host's current configuration.

Host PPAs (from /etc/apt/sources.list.d/):
$formatted_host_ppas

Guest PPAs (from $PPA_CONFIG_SOURCE):
$guest_ppa_urls
Note: This may cause the guest to use different package versions than the host.
If this is unintentional, update the guest's $PPA_CONFIG_SOURCE to match the host configuration.
==========================================
EOF
)
    # shellcheck disable=SC2001  # sed is appropriate for multi-line indentation
    echo "$warning_msg" | sed 's/^/  /' >&2
    echo "" >&2
    # Write to log file using here-string to handle multi-line content properly
    local install_log="${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log"
    sudo tee -a "$install_log" > /dev/null <<< "$warning_msg" 2>/dev/null || true
  else
    echo "  Guest PPA configuration matches host"
  fi

  return 0
}

function load_guest_ppa_configuration() {
  # Load baseline PPA configuration from setup_bsp.sh
  # This configuration mirrors what setup_bsp.sh will use in the guest
  #
  # This always loads the default/fallback configuration, which can later
  # be overridden by apply_installer_overrides() if installer.sh exists.
  #
  # Must be called before any package validation to ensure PPA_URLS arrays
  # have a valid baseline configuration.

  local script
  script=$(realpath "${BASH_SOURCE[0]}")
  local scriptpath
  scriptpath=$(dirname "$script")
  local setup_bsp_path="$scriptpath/unattend_ubuntu/setup_bsp.sh"

  # Get Ubuntu version for PPA alternate selection
  local ubuntu_ver
  if [[ -z "${FORCE_UBUNTU_VER+x}" || -z "${FORCE_UBUNTU_VER}" ]]; then
    ubuntu_ver=$(lsb_release -rs 2>/dev/null || echo "24.04")
  else
    ubuntu_ver=$FORCE_UBUNTU_VER
  fi

  # Verify setup_bsp.sh exists
  if [[ ! -f "$setup_bsp_path" ]]; then
    echo "Error: setup_bsp.sh not found at $setup_bsp_path" >&2
    return 255
  fi

  echo "  Loading baseline PPA configuration from setup_bsp.sh"

  # Extract default PPA configuration from setup_bsp.sh
  # Read the default values (lines between PPA_URLS=( and first closing ))
  local in_ppa_urls=0
  local ppa_url_line=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^PPA_URLS=\( ]]; then
      in_ppa_urls=1
      continue
    fi
    if [[ $in_ppa_urls -eq 1 ]]; then
      if [[ "$line" =~ ^\) ]]; then
        break
      fi
      # Extract quoted string
      if [[ "$line" =~ \"([^\"]+)\" ]]; then
        ppa_url_line="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$setup_bsp_path"

  if [[ -z "$ppa_url_line" ]]; then
    echo "Error: Failed to extract default PPA_URLS from setup_bsp.sh" >&2
    return 255
  fi

  # Extract other default values using grep
  local default_pin
  default_pin=$(grep -oP '^PPA_PIN="\K[^"]+' "$setup_bsp_path" | head -1)
  local default_priority
  default_priority=$(grep -oP '^PPA_PIN_PRIORITY=\K[0-9]+' "$setup_bsp_path" | head -1)

  # Set defaults
  PPA_URLS=("$ppa_url_line")
  PPA_GPGS=("auto")
  PPA_PIN="$default_pin"
  PPA_PIN_PRIORITY="$default_priority"

  # Load version-specific alternates from setup_bsp.sh
  # Extract PPA_ALT_* associative arrays
  local alt_section=0
  local current_array=""  # Track which array we're currently parsing

  # Define regex patterns (avoids issues with brackets in [[ ]] expressions)
  # Match lines with optional leading whitespace and array key format
  local regex_alt_urls='^[[:space:]]*\["'"$ubuntu_ver"':([0-9]+)"\]="([^"]+)"'
  local regex_alt_gpgs='^[[:space:]]*\["'"$ubuntu_ver"':([0-9]+)"\]="([^"]+)"'
  local regex_alt_pin='^[[:space:]]*\["'"$ubuntu_ver"'"\]="([^"]+)"'
  local regex_alt_pin_priority='^[[:space:]]*\["'"$ubuntu_ver"'"\]=([0-9]+)'

  while IFS= read -r line; do
    # Detect which PPA_ALT_ array declaration we're in
    if [[ "$line" =~ ^declare\ -A\ PPA_ALT_URLS ]]; then
      alt_section=1
      current_array="URLS"
      continue
    elif [[ "$line" =~ ^declare\ -A\ PPA_ALT_GPGS ]]; then
      alt_section=1
      current_array="GPGS"
      continue
    elif [[ "$line" =~ ^declare\ -A\ PPA_ALT_PIN[^_] ]]; then
      alt_section=1
      current_array="PIN"
      continue
    elif [[ "$line" =~ ^declare\ -A\ PPA_ALT_PIN_PRIORITY ]]; then
      alt_section=1
      current_array="PIN_PRIORITY"
      continue
    fi

    # Detect end of array declaration
    if [[ $alt_section -eq 1 && "$line" =~ ^\) ]]; then
      current_array=""
      continue
    fi

    # Extract version-specific entries based on current array
    if [[ $alt_section -eq 1 && -n "$current_array" && "$line" =~ \[\"$ubuntu_ver ]]; then
      # Only test against the pattern matching the current array
      case "$current_array" in
        URLS)
          if [[ "$line" =~ $regex_alt_urls ]]; then
            PPA_ALT_URLS["$ubuntu_ver:${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
          fi
          ;;
        GPGS)
          if [[ "$line" =~ $regex_alt_gpgs ]]; then
            PPA_ALT_GPGS["$ubuntu_ver:${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
          fi
          ;;
        PIN)
          if [[ "$line" =~ $regex_alt_pin ]]; then
            PPA_ALT_PIN["$ubuntu_ver"]="${BASH_REMATCH[1]}"
          fi
          ;;
        PIN_PRIORITY)
          if [[ "$line" =~ $regex_alt_pin_priority ]]; then
            PPA_ALT_PIN_PRIORITY["$ubuntu_ver"]="${BASH_REMATCH[1]}"
          fi
          ;;
      esac
    fi
  done < "$setup_bsp_path"

  # Apply version-specific alternates if available (matching setup_bsp.sh logic)
  if [[ -n "${PPA_ALT_PIN[$ubuntu_ver]:-}" ]]; then
    PPA_PIN="${PPA_ALT_PIN[$ubuntu_ver]}"

    if [[ -n "${PPA_ALT_PIN_PRIORITY[$ubuntu_ver]:-}" ]]; then
      PPA_PIN_PRIORITY="${PPA_ALT_PIN_PRIORITY[$ubuntu_ver]}"
    fi

    # Load multi-value arrays from associative array using version:index pattern
    local temp_urls=()
    local temp_gpgs=()
    local idx=0

    while [[ -n "${PPA_ALT_URLS[$ubuntu_ver:$idx]:-}" ]]; do
      temp_urls+=("${PPA_ALT_URLS[$ubuntu_ver:$idx]}")
      temp_gpgs+=("${PPA_ALT_GPGS[$ubuntu_ver:$idx]:-auto}")
      idx=$((idx + 1))
    done

    if [[ ${#temp_urls[@]} -gt 0 ]]; then
      PPA_URLS=("${temp_urls[@]}")
      PPA_GPGS=("${temp_gpgs[@]}")
      echo "  Applied Ubuntu $ubuntu_ver-specific PPA configuration"
    fi
  fi

  # Verify we have valid baseline configuration from setup_bsp.sh
  if [[ ${#PPA_URLS[@]} -eq 0 || -z "$PPA_PIN" || -z "$PPA_PIN_PRIORITY" ]]; then
    echo "Error: Failed to load valid PPA configuration from setup_bsp.sh" >&2
    return 255
  fi

  return 0
}

function apply_installer_overrides() {
  # Apply installer.sh overrides if the file exists. Extracts and applies:
  #   - PPA configuration (URLs, GPG keys, PIN) - overwrites load_guest_ppa_configuration() baseline
  #   - Kernel version (sets EXTRACTED_KERNEL_VER, used by validate_kernel_and_firmware())
  #   - Package list (sets EXTRACTED_PACKAGES, used by setup_bsp.sh install_userspace_pkgs())
  #
  # Prerequisites: load_guest_ppa_configuration() must be called first
  # to establish the baseline configuration.

  local script
  script=$(realpath "${BASH_SOURCE[0]}")
  local scriptpath
  scriptpath=$(dirname "$script")
  local installer_utils_path="$scriptpath/unattend_ubuntu/installer_utils.sh"
  local installer_path="$scriptpath/unattend_ubuntu/installer.sh"

  # Check if installer.sh exists
  if [[ ! -f "$installer_path" ]]; then
    echo "  No installer.sh found, using setup_bsp.sh defaults"
    return 0
  fi

  # Verify baseline configuration exists
  if [[ ${#PPA_URLS[@]} -eq 0 ]]; then
    echo "Error: Baseline PPA configuration not loaded. Call load_guest_ppa_configuration() first." >&2
    return 255
  fi

  # Source installer_utils.sh for extraction functions
  if [[ ! -f "$installer_utils_path" ]]; then
    echo "Error: installer_utils.sh not found at $installer_utils_path" >&2
    return 255
  fi

  # Set LOGD to suppress normal output
  export LOGD=":"  # Null command, suppresses output
  # shellcheck source-path=SCRIPTDIR disable=SC1090
  if ! source "$installer_utils_path"; then
    echo "Error: Failed to source installer_utils.sh" >&2
    return 255
  fi

  echo "  Found installer.sh, checking for PPA overrides..."
  if extract_ppa_from_installer "$installer_path"; then
    echo "  Applied PPA configuration from installer.sh (overrides setup_bsp.sh)"
    PPA_CONFIG_SOURCE="installer.sh"
  else
    echo "  Warning: Failed to extract PPA settings from installer.sh"
    echo "  Continuing with setup_bsp.sh defaults"
    return 0
  fi

  # Extract kernel version from installer.sh (optional, may not be present)
  # Skip if user explicitly chose local .deb files
  if [[ $FORCE_KERN_FROM_DEB != "1" ]]; then
    if extract_kernel_ver_from_installer "$installer_path" "$RT"; then
      if [[ -n "$EXTRACTED_KERNEL_VER" ]]; then
        echo "  Extracted kernel version: $EXTRACTED_KERNEL_VER"
      fi
    fi
  fi

  # Extract package list from installer.sh
  if extract_packages_from_installer "$installer_path"; then
    if [[ -z "$EXTRACTED_PACKAGES" ]]; then
      echo "  Warning: Package extraction returned empty list from installer.sh"
    fi
  else
    echo "  Warning: Failed to extract package list from installer.sh"
  fi

  # Verify configuration is still valid after override
  if [[ ${#PPA_URLS[@]} -eq 0 || -z "$PPA_PIN" || -z "$PPA_PIN_PRIORITY" ]]; then
    echo "Error: Invalid PPA configuration after applying installer.sh overrides" >&2
    return 255
  fi

  return 0
}

function validate_ppa_accessibility() {
  # Validate that guest PPA configuration is accessible via network
  # This provides early feedback on network/connectivity issues
  #
  # Prerequisites:
  #   - load_guest_ppa_configuration() must be called first
  #   - apply_installer_overrides() should be called first (if using installer.sh)
  #
  # This function validates network accessibility of PPAs, regardless of whether
  # they came from installer.sh or setup_bsp.sh defaults.
  # It does NOT extract/load settings - that's handled by load_guest_ppa_configuration()
  # and apply_installer_overrides().

  echo "Validating guest PPA configuration..."

  # Verify PPA configuration was loaded
  if [[ ${#PPA_URLS[@]} -eq 0 ]]; then
    echo "ERROR: PPA configuration not loaded. Call load_guest_ppa_configuration() first." >&2
    return 255
  fi

  # Compare guest and host PPA settings (info only)
  check_ppa_consistency

  # Validate PPA URLs are accessible (with retries)
  for i in "${!PPA_URLS[@]}"; do
    local ppa_url="${PPA_URLS[$i]}"
    local url_base
    url_base=$(echo "$ppa_url" | awk '{print $1}')

    if ! timeout 10 wget --spider --quiet -t 3 --waitretry=2 "$url_base" 2>/dev/null; then
      echo "  ERROR: PPA URL not accessible after 3 attempts: $url_base" >&2
      return 255
    fi
  done

  # Validate GPG keys are accessible (with retries)
  for i in "${!PPA_GPGS[@]}"; do
    local gpg_key="${PPA_GPGS[$i]}"
    if [[ "$gpg_key" != "auto" && "$gpg_key" != "force" ]]; then
      if ! timeout 10 wget --spider --quiet -t 3 --waitretry=2 "$gpg_key" 2>/dev/null; then
        echo "  ERROR: GPG key not accessible after 3 attempts: $gpg_key" >&2
        return 255
      fi
    fi
  done

  echo "  PPA accessibility validation complete"
  echo ""
  return 0
}

function validate_local_kernel_debs() {
  # Validate that required kernel .deb files exist and are valid
  # Must be called only when KERN_INSTALL_FROM_LOCAL == 1
  # Returns: 0 on success, 255 on error

  local script
  script=$(realpath "${BASH_SOURCE[0]}")
  local scriptpath
  scriptpath=$(dirname "$script")
  local missing_files=()

  echo "  Validating local kernel .deb files..."

  for file in "${REQUIRED_DEB_FILES[@]}"; do
    local rfile="$scriptpath/unattend_ubuntu/$file"
    if [[ -L "$rfile" ]]; then
      echo "  Error: The following file is a symlink:" >&2
      echo "    $rfile" >&2
      return 255
    fi
    if [[ ! -f "$rfile" || ! -s "$rfile" ]]; then
      missing_files+=("$file")
    fi
  done

  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "  Error: Missing required kernel .deb files for local installation." >&2
    echo "  Location: $scriptpath/unattend_ubuntu" >&2
    echo "  Missing files:" >&2
    for file in "${missing_files[@]}"; do
      echo "    - $file" >&2
    done
    echo "  Please place the required kernel .deb files in the location above before running." >&2
    return 255
  fi

  echo "  All required .deb files found and valid"
  echo ""
  return 0
}

function validate_kernel_and_firmware() {
  # Validate kernel and firmware availability before starting installation
  # This runs early to fail fast before cleaning any existing images
  # Sets global variables: VALIDATED_KERNEL_VER, VALIDATED_LINUX_FW_VER

  echo "Validating required packages..."

  # ===== Kernel Validation =====
  # Determine installation method: local .deb files or PPA
  is_host_kernel_local_install

  if [[ "$KERN_INSTALL_FROM_LOCAL" == "1" ]]; then
    # Path 1: Installing from local .deb files
    echo "  Kernel installation method: Local .deb files"
    validate_local_kernel_debs || return 255
  else
    # Path 2: Installing from PPA
    echo "  Kernel installation method: PPA"

    local kernel_ver
    local is_forced=0

    # Determine which version to check
    # Priority: --force-kern-apt-ver > installer.sh > host kernel
    if [[ -n $FORCE_KERN_APT_VER ]]; then
      kernel_ver=$FORCE_KERN_APT_VER
      is_forced=1
    elif [[ -n "${EXTRACTED_KERNEL_VER:-}" ]]; then
      # installer.sh specifies which kernel the guest will install — validate that,
      # not the host kernel (which may differ and may not exist in the guest PPA)
      kernel_ver=$EXTRACTED_KERNEL_VER
    else
      kernel_ver=$(uname -r)
      local kernel_pkg_ver
      kernel_pkg_ver=$(dpkg -l "linux-headers-$kernel_ver" 2>/dev/null | awk '/^ii/ {print $3}')
      if [[ -z "$kernel_pkg_ver" ]]; then
        echo "  Error: linux-headers package not found on host"
        return 255
      fi
      kernel_ver="${kernel_ver}=${kernel_pkg_ver}"
    fi

    # Validate and get final version from guest PPAs
    VALIDATED_KERNEL_VER=$(validate_kernel_ppa_availability "$kernel_ver" "$is_forced") || return 255

    if [[ -z "$VALIDATED_KERNEL_VER" ]]; then
      echo "  Error: kernel version validation returned empty result"
      return 255
    fi
    echo "  Validated: linux-{headers,image}-$VALIDATED_KERNEL_VER"
  fi

  # ===== Firmware Validation =====
  local linux_fw_ver
  local fw_ver_source="host"

  # Determine which version to check
  if [[ -n "$FORCE_LINUX_FW_APT_VER" ]]; then
    linux_fw_ver="$FORCE_LINUX_FW_APT_VER"
    fw_ver_source="forced"
  else
    # Get host's linux-firmware version
    linux_fw_ver="$(dpkg -l "linux-firmware" 2>/dev/null | awk '/^ii/ {print $3}')"
    if [[ -z "$linux_fw_ver" ]]; then
      echo "  Error: linux-firmware package not found on host"
      return 255
    fi
  fi

  # Validate version is available in guest PPAs via HTTP
  echo "  Validating: linux-firmware=$linux_fw_ver..."

  if check_package_in_guest_ppa "linux-firmware" "linux-firmware=$linux_fw_ver"; then
    # Version found in guest PPAs
    VALIDATED_LINUX_FW_VER="$linux_fw_ver"
    echo "  Validated: linux-firmware=$VALIDATED_LINUX_FW_VER"
  else
    # Version not available in guest PPAs
    if [[ "$fw_ver_source" == "forced" ]]; then
      # For manual override, fail with error - user explicitly requested this version
      echo "  Error: Forced linux-firmware version '$linux_fw_ver' is not available in guest PPAs"
      echo "  Please check available versions or remove --force-linux-fw-apt-ver to use auto-detection"
      return 255
    fi

    # For host auto-detection, use latest available version from PPAs
    echo "  WARNING: Host linux-firmware version $linux_fw_ver not found in guest PPAs"
    echo "  Will install latest available version from guest PPAs instead"

    # Verify linux-firmware package exists in guest PPAs
    if check_package_in_guest_ppa "linux-firmware" "linux-firmware"; then
      # Package exists - set empty version to install latest available
      VALIDATED_LINUX_FW_VER=""
      echo "  Will use latest available linux-firmware version from PPA"
    else
      echo "  Error: linux-firmware package not found in guest PPAs"
      return 255
    fi
  fi

  echo "  All required packages validated successfully"
  echo ""
  return 0
}

function install_ubuntu() {
  local script
  script=$(realpath "${BASH_SOURCE[0]}")
  local scriptpath
  scriptpath=$(dirname "$script")
  local dest_tmp_path
  dest_tmp_path=$(realpath "/tmp/${UBUNTU_DOMAIN_NAME}_install_tmp_files")
  local ubuntu_ver

  UBUNTU_INSTALL_OS_TYPE='desktop'
  if [[ -z "${FORCE_UBUNTU_VER+x}" || -z "${FORCE_UBUNTU_VER}" ]]; then
    ubuntu_ver=$(lsb_release -rs)
  else
    ubuntu_ver=$FORCE_UBUNTU_VER
  fi

  local auto_install_yaml_fname="auto-install-ubuntu-$UBUNTU_INSTALL_OS_TYPE"

  # install dependencies
  install_dep || return 255

  # check yaml file
  if ! yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}}}" "$scriptpath/$auto_install_yaml_fname.yaml"; then
    echo "Error: Yaml file $scriptpath/$auto_install_yaml_fname.yaml has formatting error!"
    return 255
  fi

  # KERN_INSTALL_FROM_LOCAL is already set by validate_kernel_and_firmware()
  if [[ "$KERN_INSTALL_FROM_LOCAL" != "1" ]]; then
    REQUIRED_DEB_FILES=()
  fi

  for file in "${REQUIRED_DEB_FILES[@]}"; do
    local rfile
    rfile=$(realpath "$scriptpath/unattend_ubuntu/$file")
    if [ ! -f "$rfile" ]; then
      echo "Error: Missing $file in $scriptpath/unattend_ubuntu required for installation!"
      return 255
    fi
  done

  if [[ -d "$dest_tmp_path" ]]; then
    rm -rf "$dest_tmp_path"
  fi
  mkdir -p "$dest_tmp_path"
  TMP_FILES+=("$dest_tmp_path")

  # Check if ISO exists in unattend_ubuntu, verify checksum, and copy to libvirt images path
  # Otherwise verify any existing ISO in libvirt path
  if [[ -f "$scriptpath/unattend_ubuntu/${UBUNTU_INSTALLER_ISO}" ]]; then
    check_file_valid_nonzero "$scriptpath/unattend_ubuntu/${UBUNTU_INSTALLER_ISO}"
    if ! verify_and_copy_ubuntu_iso "$ubuntu_ver" "$dest_tmp_path" "$scriptpath/unattend_ubuntu/${UBUNTU_INSTALLER_ISO}"; then
      echo "Checksum verification failed for provided ISO in unattend_ubuntu"
      sudo rm -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
    fi
  else
    # No ISO in unattend_ubuntu, check existing ISO in libvirt path
    if [[ -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}" ]]; then
      if ! verify_and_copy_ubuntu_iso "$ubuntu_ver" "$dest_tmp_path" "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"; then
        echo "Checksum verification failed for existing ISO in libvirt path"
        sudo rm -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
      fi
    fi
  fi

  # Download if not present after verification checks
  if [[ ! -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}" ]]; then
    download_ubuntu_iso "$ubuntu_ver" "$dest_tmp_path" || return 255
  fi

  copy_setup_files "$dest_tmp_path" || return 255
  run_file_server "$dest_tmp_path" "$FILE_SERVER_IP" "$FILE_SERVER_PORT" FILE_SERVER_DAEMON_PID || return 255

  local host_nc_port
  local max_shuf_tries=100
  for ((i=1; i <= max_shuf_tries; i++)); do
    host_nc_port=$(shuf -i 2000-65000 -n 1)
    if ! ss -tl | grep "$host_nc_port" | grep LISTEN; then
      break
    fi
  done
  if ss -tl | grep "$host_nc_port" | grep LISTEN; then
    echo "Error: Unable to get free tcp port after $max_shuf_tries tries!"
    return 255
  fi
  local host_nc_file_out="$dest_tmp_path/nc_output.log"
  run_nc_server "$FILE_SERVER_IP" "$host_nc_port" "$host_nc_file_out" HOST_NC_DAEMON_PID || return 255

  echo "Generate ubuntu-seed.iso"
  sudo rm -f meta-data
  touch meta-data
  # shellcheck disable=SC2016
  envsubst '$http_proxy,$ftp_proxy,$https_proxy,$socks_server,$no_proxy' < "$scriptpath/$auto_install_yaml_fname.yaml" > "$scriptpath/auto-install-ubuntu-parsed.yaml"
  # Update for RT install
  if [[ "$RT" == "1" ]]; then
    sed -i "s|\$RT_SUPPORT|--rt|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  else
    sed -i "s|\$RT_SUPPORT||g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  fi

  # update for kernel overlay install via PPA vs local deb
  if [[ "$KERN_INSTALL_FROM_LOCAL" != "1" ]]; then
    # Use the validated kernel version from early validation
    sed -i "s|\$KERN_INSTALL_OPTION|-kp \'$VALIDATED_KERNEL_VER\'|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  else
    sed -i "/wget --no-proxy -O \/target\/tmp\/setup_bsp.sh \$FILE_SERVER_URL\/setup_bsp.sh/i \    - wget --no-proxy -O \/target\/linux-headers.deb \$FILE_SERVER_URL\/linux-headers.deb\n    - wget --no-proxy -O \/target\/linux-image.deb \$FILE_SERVER_URL\/linux-image.deb" "$scriptpath/auto-install-ubuntu-parsed.yaml"
    sed -i "s|\$KERN_INSTALL_OPTION|-k \'\/\'|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  fi

  # Use the validated linux-firmware version from early validation
  # If version is empty, omit the -fw option to install latest available version
  if [[ -n "$VALIDATED_LINUX_FW_VER" ]]; then
    sed -i "s|\$LINUX_FW_INSTALL_OPTION|-fw \'$VALIDATED_LINUX_FW_VER\'|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  else
    sed -i "s|\$LINUX_FW_INSTALL_OPTION||g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  fi

  if [[ $SETUP_DEBUG -ne 1 ]]; then
    sed -i "/\# more error handling here/a\    - echo \"ERROR\" | nc -q1 \$HOST_SERVER_IP \$HOST_SERVER_NC_PORT\n    - shutdown" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  fi

  # update for drm driver selection install based on host
  drm_drv_target=""
  if lspci -D -k -s 0000:00:02.0 | grep -q "Kernel driver in use"; then
    drm_drv_target=$(lspci -D -k  -s 00:02.0 | grep "Kernel driver in use" | awk -F ':' '{print $2}' | xargs)
  fi
  sed -i "s|\$DRM_DRV_OPTION|-drm \'$drm_drv_target\'|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  local file_server_url="http://$FILE_SERVER_IP:$FILE_SERVER_PORT"
  sed -i "s|\$FILE_SERVER_URL|$file_server_url|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  sed -i "s|\$HOST_SERVER_IP|$FILE_SERVER_IP|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  sed -i "s|\$HOST_SERVER_NC_PORT|$host_nc_port|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  local openvino_install_opt="--neo"
  if [[ $SETUP_DEBUG -eq 1 ]]; then
    openvino_install_opt="$openvino_install_opt --debug"
  fi
  if grep -q 'Initialized intel_vpu [0-9].[0-9].[0-9]' < <(sudo journalctl -k -o cat --no-pager || true); then
    if  is_npu_supported ; then
      openvino_install_opt="$openvino_install_opt --npu"
    fi
  fi
  sed -i "s|\$OPENVINO_INSTALL_OPTIONS|$openvino_install_opt|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  local force_sw_cursor_opt=""
  if [[ $FORCE_SW_CURSOR -eq 1 ]]; then
    force_sw_cursor_opt="--force-sw-cursor"
  fi
  sed -i "s|\$FORCE_SW_CURSOR_OPTION|$force_sw_cursor_opt|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  sed -i "s|\$UBUNTU_SNAP_GNOME_VERSION|${UBUNTU_SNAP_GNOME_VERSIONS[$ubuntu_ver]}|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  sed -i "s|\$UBUNTU_VERSION|$ubuntu_ver|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  sudo cloud-localds -v "$dest_tmp_path"/${UBUNTU_SEED_ISO} "$scriptpath/auto-install-ubuntu-parsed.yaml" meta-data

  echo "$(date): Start ubuntu guest creation and auto-installation"
  if [[ "$VIEWER" -eq "1" ]]; then
    virt-viewer -w -r --domain-name "${UBUNTU_DOMAIN_NAME}" &>/dev/null &
    VIEWER_DAEMON_PID=$!
  fi
  sudo virt-install \
  --name="${UBUNTU_DOMAIN_NAME}" \
  --ram=4096 \
  --vcpus=4 \
  --cpu host \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5901 \
  --disk "path=${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME},format=qcow2,size=${SETUP_DISK_SIZE},bus=virtio,cache=none" \
  --disk "path=$dest_tmp_path/${UBUNTU_SEED_ISO},device=cdrom" \
  --location "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO},initrd=casper/initrd,kernel=casper/vmlinuz" \
  --os-variant "ubuntu${ubuntu_ver}" \
  --noautoconsole \
  --boot "loader=$OVMF_DEFAULT_PATH/OVMF_CODE_4M.fd,loader.readonly=yes,loader.type=pflash,nvram.template=$OVMF_DEFAULT_PATH/OVMF_VARS_4M.fd" \
  --extra-args "autoinstall" \
  --console "pty,target.type=virtio,log.file=${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log,log.append=on" \
  --serial pty \
  --extra-args 'console=ttyS0,115200n8 serial' \
  --events on_poweroff=destroy \
  --wait=-1

  if grep -Fq "ERROR" "$host_nc_file_out"; then
    echo "Error: Ubuntu guest install failed."
    echo ""
    echo "Errors reported from guest installation:"
    echo "=========================================="
    grep "^ERROR:" "$host_nc_file_out" || true
    echo "=========================================="
    echo ""
    echo "Check ${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log for full details."
    return 255
  fi

  echo "$(date): Waiting for restarted guest to complete installation and shutdown"
  local state
  state=$(virsh list | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
  local loop=1
  while [[ -n ${state+x} && $state == "running" ]]; do
    echo "$(date): $loop: waiting for running VM..."
    local count=0
    local maxcount=120
    while [[ count -lt $maxcount ]]; do
      state=$(virsh list --all | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
      if [[ -n ${state+x} && $state == "running" ]]; then
        if grep -Fq "ERROR" "$host_nc_file_out"; then
          echo "$(date): Error: Ubuntu guest install failed."
          echo ""
          echo "Errors reported from guest installation:"
          echo "=========================================="
          grep "^ERROR:" "$host_nc_file_out" || true
          echo "=========================================="
          echo ""
          echo "Check ${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log for full details."
          return 255
        else
          sleep 60
        fi
      else
        break
      fi
      count=$((count+1))
    done
    if [[ $count -ge $maxcount ]]; then
      echo "$(date): Error: timed out waiting for Ubuntu required installation to finish after $maxcount min."
      return 255
    fi
    loop=$((loop+1))
  done
}

function show_help() {
    printf "%s [-h] [--force] [--viewer] [--disk-size] [--rt] [--force-kern-from-deb] [--force-kern-apt-ver] [--force-linux-fw-apt-ver] [--force-ubuntu-ver] [--force-sw-cursor] [--debug]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Create Ubuntu vm required image to dest %s/ubuntu.qcow2\n" "${LIBVIRT_DEFAULT_IMAGES_PATH}"
    printf "Or create Ubuntu RT vm required image to dest %s/ubuntu_rt.qcow2\n" "${LIBVIRT_DEFAULT_IMAGES_PATH}"
    printf "Place Intel bsp kernel debs (linux-headers.deb,linux-image.deb,linux-headers-rt.deb,linux-image-rt.deb) in guest_setup/<host_os>/unattend_ubuntu folder prior to running if platform BSP guide requires linux kernel installation from debian files.\n"
    printf "Install console log can be found at %s_install.log\n" "${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}"
    printf "Options:\n"
    printf "\t-h                          show this help message\n"
    printf "\t--force                     force clean if Ubuntu vm qcow file is already present\n"
    printf "\t--viewer                    show installation display\n"
    printf "\t--disk-size                 disk storage size of Ubuntu vm in GiB, default is 60 GiB\n"
    printf "\t--rt                        install Ubuntu RT\n"
    printf "\t--force-kern-from-deb       force Ubuntu vm to install kernel from local deb kernel files\n"
    printf "\t--force-kern-apt-ver        force Ubuntu vm to install kernel from PPA with given version\n"
    printf "\t--force-linux-fw-apt-ver    force Ubuntu vm to install linux-firmware pkg from PPA with given version\n"
    printf "\t--force-ubuntu-ver          force Ubuntu vm version to install. E.g. \"24.04\" Default: same as host.\n"
    printf "\t--force-sw-cursor           force enable SW cursor\n"
    printf "\t--debug                     For debugging only. Does not remove temporary files.\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit
                ;;

            --force)
                FORCECLEAN=1
                ;;

            --viewer)
                VIEWER=1
                ;;

            --disk-size)
                if [[ -z ${2+x} || -z $2 ]]; then
                    echo "Error: --disk-size requires a value"
                    echo ""
                    show_help
                    return 255
                fi
                SETUP_DISK_SIZE="$2"
                shift
                ;;

            --rt)
                RT=1
                UBUNTU_DOMAIN_NAME=ubuntu_rt
                UBUNTU_IMAGE_NAME=ubuntu_rt.qcow2
                REQUIRED_DEB_FILES=( "linux-headers-rt.deb" "linux-image-rt.deb" )
                ;;

            --force-kern-from-deb)
                FORCE_KERN_FROM_DEB=1
                ;;

            --force-kern-apt-ver)
                if [[ -z ${2+x} || -z $2 ]]; then
                    echo "Error: --force-kern-apt-ver requires a kernel version value"
                    echo ""
                    show_help
                    return 255
                fi
                FORCE_KERN_APT_VER="$2"
                shift
                ;;

            --force-linux-fw-apt-ver)
                if [[ -z ${2+x} || -z $2 ]]; then
                    echo "Error: --force-linux-fw-apt-ver requires a version value"
                    echo ""
                    show_help
                    return 255
                fi
                FORCE_LINUX_FW_APT_VER="$2"
                shift
                ;;

            --force-ubuntu-ver)
                if [[ -z ${2+x} || -z $2 ]]; then
                  echo "Error: missing/null param for --force-ubuntu-ver"
                  echo ""
                  show_help
                  return 255
                else
                  local supported=0
                  for ver in "${!UBUNTU_INSTALLER_ISO_URLS[@]}"; do
                    if [[ "$ver" == "$2" ]]; then
                      supported=1
                      break
                    fi
                  done
                  if [[ $supported -eq 1 ]]; then
                    FORCE_UBUNTU_VER="$2"
                  else
                    echo "Error: $2 unsupported. Supported versions: ${!UBUNTU_INSTALLER_ISO_URLS[*]}"
                    echo ""
                    show_help
                    return 255
                  fi
                fi
                shift
                ;;

            --force-sw-cursor)
                FORCE_SW_CURSOR=1
                ;;

            --debug)
                SETUP_DEBUG=1
                ;;

            -?*)
                echo "Error: Invalid option $1"
                echo ""
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

function cleanup () {
    local state
    state=$(virsh list | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
    if [[ -n "${state+x}" && "$state" == "running" ]]; then
        echo "Shutting down running domain $UBUNTU_DOMAIN_NAME"
        virsh shutdown "$UBUNTU_DOMAIN_NAME" 1>/dev/null
        sleep 10
        state=$(virsh list | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
        if [[ -n "${state+x}" && "$state" == "running" ]]; then
            virsh destroy "$UBUNTU_DOMAIN_NAME" 1>/dev/null
        fi
        virsh undefine --nvram "$UBUNTU_DOMAIN_NAME" 1>/dev/null
    fi
    if virsh list --name --all | grep -q -w "$UBUNTU_DOMAIN_NAME"; then
        virsh undefine --nvram "$UBUNTU_DOMAIN_NAME" 1>/dev/null
    fi
    local poolname
    poolname="${UBUNTU_DOMAIN_NAME}_install_tmp_files"
    if virsh pool-list | grep -q "$poolname"; then
        virsh pool-destroy "$poolname" 1>/dev/null
        if virsh pool-list --all | grep -q "$poolname"; then
            virsh pool-undefine "$poolname" 1>/dev/null
        fi
    fi
    for f in "${TMP_FILES[@]}"; do
      if [[ $SETUP_DEBUG -ne 1 ]]; then
        local fowner
        fowner=$(stat -c "%U" "$f")
        if [[ "$fowner" == "$USER" ]]; then
            rm -rf "$f"
        else
            sudo rm -rf "$f"
        fi
      fi
    done
    kill_by_pid "$FILE_SERVER_DAEMON_PID"
    kill_by_pid "$HOST_NC_DAEMON_PID"
    kill_by_pid "$VIEWER_DAEMON_PID"
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

# Validate arguments
if ! [[ $SETUP_DISK_SIZE =~ ^[0-9]+$ ]]; then
    echo "Invalid input disk size"
    exit 255
fi

if [[ $FORCE_KERN_FROM_DEB == "1" && -n $FORCE_KERN_APT_VER ]]; then
    echo "--force-kern-from-deb and --force-kern-apt-version cannot be used together"
    exit 255
fi

if [[ $VIEWER == "1" && -z "${DISPLAY:-}" ]]; then
    echo "Error: No DISPLAY available. --viewer requires graphical display (X11/Wayland)."
    echo "Run without --viewer for headless installation, or enable X11 forwarding (ssh -X)."
    exit 255
fi

# Load baseline PPA configuration from setup_bsp.sh
load_guest_ppa_configuration || exit 255

# Apply installer.sh overrides if available
apply_installer_overrides || exit 255

# Validate PPA network accessibility
validate_ppa_accessibility || exit 255

# Validate required packages (kernel and firmware)
validate_kernel_and_firmware || exit 255

if [[ $FORCECLEAN == "1" ]]; then
    clean_ubuntu_images || exit 255
fi

if [[ -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME}" ]]; then
    echo "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME} present"
    echo "Use --force option to force clean and re-install ubuntu"
    exit 255
fi
trap 'cleanup' EXIT

install_ubuntu || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

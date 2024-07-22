#!/bin/bash

# Copyright (c) 2023-2024 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
LIBVIRT_DEFAULT_IMAGES_PATH="/var/lib/libvirt/images"
OVMF_DEFAULT_PATH=/usr/share/OVMF
LIBVIRT_DEFAULT_LOG_PATH="/var/log/libvirt/qemu"
UBUNTU_DOMAIN_NAME=ubuntu
UBUNTU_IMAGE_NAME=$UBUNTU_DOMAIN_NAME.qcow2
UBUNTU_INSTALLER_ISO_URL='https://cdimage.ubuntu.com/releases/jammy/release/inteliot/ubuntu-22.04-live-server-amd64+intel-iot.iso'
UBUNTU_INSTALLER_SHA256SUMS_URL='https://cdimage.ubuntu.com/releases/jammy/release/inteliot/SHA256SUMS'
UBUNTU_INSTALLER_ISO=ubuntu.iso
UBUNTU_SEED_ISO=ubuntu-seed.iso

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
SETUP_DEBUG=0

VIEWER_DAEMON_PID=
FILE_SERVER_DAEMON_PID=
FILE_SERVER_IP="192.168.122.1"
FILE_SERVER_PORT=8000
HOST_NC_DAEMON_PID=

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

    cd "$folder"
    python3 -m http.server -b "$ip" "$port" &
    pid=$!
    cd -
}

function run_nc_server() {
    local ip=$1
    local port=$2
    local out_file=$3
    local -n pid=$4

    nc -l -s "$ip" -p "$port" > "$out_file" &
    pid=$!
}

function kill_by_pid() {
    if [[ $# -eq 1 && -n "${1}" && -n "${1+x}" ]]; then
        local pid=$1
        if [[ -n "$(ps -p "$pid" -o pid=)" ]]; then
            sudo kill -9 "$pid"
        fi 
    fi
}

function install_dep() {
  which cloud-localds > /dev/null || sudo apt install -y cloud-image-utils
  which virt-install > /dev/null || sudo apt install -y virtinst
  which virt-viewer > /dev/null || sudo apt install -y virt-viewer
  which yamllint > /dev/null || sudo apt install -y yamllint
  which nc > /dev/null || sudo apt install -y netcat
  which envsubst > /dev/null || sudo apt install -y gettext-base
  which sha256sum > /dev/null || sudo apt install -y coreutils
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
  kern_header_ppa=$(apt list --installed | grep "linux-headers-$kern_ver")
  local kern_image_ppa
  kern_image_ppa=$(apt list --installed | grep "linux-image-$kern_ver")
  local kern_header_ppa_local
  kern_header_ppa_local=$(apt list --installed | grep "linux-headers-$kern_ver" | awk -F' ' '{print $4}'| grep "local")
  local kern_image_ppa_local
  kern_image_ppa_local=$(apt list --installed | grep "linux-image-$kern_ver" | awk -F' ' '{print $4}'| grep "local")

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
    echo "Error: no dest tmp path provided"
    return 255
  fi
  local dest_tmp_path=$1
  while [[ $count -lt $maxcount ]]; do
    count=$((count+1))
    echo "$count: Download Ubuntu 22.04 iso"
    #sudo wget -O ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO} https://releases.ubuntu.com/22.04.2/ubuntu-22.04.2-live-server-amd64.iso
    
    wget -O "$dest_tmp_path/${UBUNTU_INSTALLER_ISO}" "${UBUNTU_INSTALLER_ISO_URL}" || return 255
    wget -O "$dest_tmp_path/SHA256SUMS" "${UBUNTU_INSTALLER_SHA256SUMS_URL}" || return 255
    local isochksum
    isochksum=$(sha256sum "$dest_tmp_path/${UBUNTU_INSTALLER_ISO}" | awk '{print $1}')
    local verifychksum
    local iso_fname
    iso_fname=$(basename "${UBUNTU_INSTALLER_ISO_URL}")
    verifychksum=$(grep "$iso_fname" < "$dest_tmp_path/SHA256SUMS" | awk '{print $1}')
    if [[ "$isochksum" == "$verifychksum" ]]; then
      # downloaded iso is okay.
      echo "Verified Ubuntu iso checksum as expected: $isochksum"
      sudo mv "$dest_tmp_path/${UBUNTU_INSTALLER_ISO}" "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
      sudo chown root:root "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
      break
    fi
  done
  if [[ $count -ge $maxcount ]]; then
    echo "error: download exceeded max tries."
    return 255
  fi
  return 0
}

function verify_ubuntu_iso() {
  local maxcount=10
  local count=0

  if [[ -z "${1+x}" || -z "$1" ]]; then
    echo "Error: no dest tmp path provided"
    return 255
  fi
  local dest_tmp_path=$1
  if [[ -z "${2+x}" || -z "$2" ]]; then
    echo "Error: no Ubuntu iso path provided"
    return 255
  fi
  local iso_to_check
  iso_to_check=$(realpath "$2")

  wget -O "$dest_tmp_path/SHA256SUMS" "${UBUNTU_INSTALLER_SHA256SUMS_URL}" || return 255
  local isochksum
  isochksum=$(sha256sum "$iso_to_check" | awk '{print $1}')
  local verifychksum
  local iso_fname
  iso_fname=$(basename "${UBUNTU_INSTALLER_ISO_URL}")
  verifychksum=$(grep "$iso_fname" < "$dest_tmp_path/SHA256SUMS" | awk '{print $1}')
  if [[ "$isochksum" == "$verifychksum" ]]; then
    # downloaded iso is okay.
    echo "Verified Ubuntu iso checksum as expected: $isochksum"
    sudo mv "$iso_to_check" "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
    sudo chown root:root "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}"
  else
    echo "ERROR: provided Ubuntu ISO $iso_to_check SHA256 checksum does not match that of ${UBUNTU_INSTALLER_ISO_URL}"
    return 255
  fi
}

function install_ubuntu() {
  local script
  script=$(realpath "${BASH_SOURCE[0]}")
  local scriptpath
  scriptpath=$(dirname "$script")
  local dest_tmp_path
  dest_tmp_path=$(realpath "/tmp/${UBUNTU_DOMAIN_NAME}_install_tmp_files")

  # install dependencies
  install_dep || return 255

  # check yaml file
  if ! yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}}}" "$scriptpath/auto-install-ubuntu.yaml"; then
    echo "Error: Yaml file $scriptpath/auto-install-ubuntu.yaml has formatting error!"
    return 255
  fi

  # Check Intel overlay kernel is installed locally
  is_host_kernel_local_install

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

  if [[ -f "$scriptpath/unattend_ubuntu/${UBUNTU_INSTALLER_ISO}" ]]; then
    check_file_valid_nonzero "$scriptpath/unattend_ubuntu/${UBUNTU_INSTALLER_ISO}"
    verify_ubuntu_iso "$dest_tmp_path" "$scriptpath/unattend_ubuntu/${UBUNTU_INSTALLER_ISO}" || return 255
  fi

  if [[ ! -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}" ]]; then
    download_ubuntu_iso "$dest_tmp_path" || return 255
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
  envsubst '$http_proxy,$ftp_proxy,$https_proxy,$socks_server,$no_proxy' < "$scriptpath/auto-install-ubuntu.yaml" > "$scriptpath/auto-install-ubuntu-parsed.yaml"
  # Update for RT install
  if [[ "$RT" == "1" ]]; then
    sed -i "s|\$RT_SUPPORT|--rt|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  else
    sed -i "s|\$RT_SUPPORT||g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  fi

  # update for kernel overlay install via PPA vs local deb
  if [[ "$KERN_INSTALL_FROM_LOCAL" != "1" ]]; then
    local kernel_ver
    kernel_ver=$(uname -r)
    if [[ -n $FORCE_KERN_APT_VER ]]; then
      kernel_ver=$FORCE_KERN_APT_VER
    else
      kernel_ver="${kernel_ver}=$(apt list --installed | grep "linux-image-$(uname -r)" | awk '{print $2}')"
    fi
    sed -i "s|\$KERN_INSTALL_OPTION|-kp \'$kernel_ver\'|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  else
    sed -i "/wget --no-proxy -O \/target\/tmp\/setup_bsp.sh \$FILE_SERVER_URL\/setup_bsp.sh/i \    - wget --no-proxy -O \/target\/linux-headers.deb \$FILE_SERVER_URL\/linux-headers.deb\n    - wget --no-proxy -O \/target\/linux-image.deb \$FILE_SERVER_URL\/linux-image.deb" "$scriptpath/auto-install-ubuntu-parsed.yaml"
    sed -i "s|\$KERN_INSTALL_OPTION|-k \'\/\'|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  fi

  # update for linux-firmware overlay package install via PPA version
  if [[ -n "$FORCE_LINUX_FW_APT_VER" ]]; then
    # use forced version
    local linux_fw_ver="$FORCE_LINUX_FW_APT_VER"
  else
    # use version detected from host
    local linux_fw_ver
    linux_fw_ver="$(apt list --installed | grep linux-firmware | awk '{print $2}')"
  fi
  sed -i "s|\$LINUX_FW_INSTALL_OPTION|-fw \'$linux_fw_ver\'|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  if [[ $SETUP_DEBUG -ne 1 ]]; then
    sed -i "/\# more error handling here/a\    - echo \"ERROR\" | nc -q1 \$HOST_SERVER_IP \$HOST_SERVER_NC_PORT\n    - shutdown" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  fi

  local file_server_url="http://$FILE_SERVER_IP:$FILE_SERVER_PORT"
  sed -i "s|\$FILE_SERVER_URL|$file_server_url|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  sed -i "s|\$HOST_SERVER_IP|$FILE_SERVER_IP|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"
  sed -i "s|\$HOST_SERVER_NC_PORT|$host_nc_port|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  local openvino_install_opt="--neo"
  if [[ $SETUP_DEBUG -eq 1 ]]; then
    openvino_install_opt="$openvino_install_opt --debug"
  fi
  if sudo journalctl -k -o cat --no-pager | grep 'Initialized intel_vpu [0-9].[0-9].[0-9] [0-9]* for 0000:00:0b.0 on minor 0'; then
    local host_kern_version
    host_kern_version=$(uname -r | sed -re 's/-intel//' | sed -re 's/(^[0-9]*\.[0-9]*\.[0-9]*-[0-9]*)(.*)/\1/')
    if ! awk -v a="$host_kern_version" -v b="6.8" ' BEGIN { if (  a < b ) exit 0; else exit 1  } '; then
      openvino_install_opt="$openvino_install_opt --npu"
    fi
  fi
  sed -i "s|\$OPENVINO_INSTALL_OPTIONS|$openvino_install_opt|g" "$scriptpath/auto-install-ubuntu-parsed.yaml"

  sudo cloud-localds -v "$dest_tmp_path"/${UBUNTU_SEED_ISO} "$scriptpath/auto-install-ubuntu-parsed.yaml" meta-data

  echo "$(date): Start ubuntu guest creation and auto-installation"
  if [[ "$VIEWER" -eq "1" ]]; then
    virt-viewer -w -r --domain-name "${UBUNTU_DOMAIN_NAME}" &
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
  --os-variant ubuntu22.04 \
  --noautoconsole \
  --boot "loader=$OVMF_DEFAULT_PATH/OVMF_CODE_4M.fd,loader.readonly=yes,loader.type=pflash,nvram.template=$OVMF_DEFAULT_PATH/OVMF_VARS_4M.fd" \
  --extra-args "autoinstall" \
  --console "pty,target.type=virtio,log.file=${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log,log.append=on" \
  --serial pty \
  --extra-args 'console=ttyS0,115200n8 serial' \
  --events on_poweroff=destroy \
  --wait=-1

  if grep -Fq "ERROR" "$host_nc_file_out"; then
    echo "Error: Ubuntu guest install failed. Check ${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log for details."
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
          echo "$(date): Error: Ubuntu guest install failed. Check ${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log for details."
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
    printf "%s [-h] [--force] [--viewer] [--disk-size] [--rt] [--force-kern-from-deb] [--force-kern-apt-ver] [--force-linux-fw-apt-ver] [--debug]\n" "$(basename "${BASH_SOURCE[0]}")"
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
    printf "\t--debug                     Do not remove temporary files. For debugging only.\n"
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
                FORCE_KERN_APT_VER="$2"
                shift
                ;;

            --force-linux-fw-apt-ver)
                FORCE_LINUX_FW_APT_VER="$2"
                shift
                ;;

            --debug)
                SETUP_DEBUG=1
                ;;

            -?*)
                echo "Error: Invalid option $1"
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
    local state
    state=$(virsh list | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
    if [[ -n "${state+x}" && "$state" == "running" ]]; then
        echo "Shutting down running domain $UBUNTU_DOMAIN_NAME"
        virsh shutdown "$UBUNTU_DOMAIN_NAME"
        sleep 10
        state=$(virsh list | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
        if [[ -n "${state+x}" && "$state" == "running" ]]; then
            virsh destroy "$UBUNTU_DOMAIN_NAME"
        fi
        virsh undefine --nvram "$UBUNTU_DOMAIN_NAME"
    fi
    if virsh list --name --all | grep -q -w "$UBUNTU_DOMAIN_NAME"; then
        virsh undefine --nvram "$UBUNTU_DOMAIN_NAME"
    fi
    kill_by_pid "$VIEWER_DAEMON_PID"
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

if ! [[ $SETUP_DISK_SIZE =~ ^[0-9]+$ ]]; then
    echo "Invalid input disk size"
    exit 255
fi

if [[ $FORCE_KERN_FROM_DEB == "1" && -n $FORCE_KERN_APT_VER ]]; then
    echo "--force-kern-from-deb and --force-kern-apt-version cannot be used together"
    exit 255
fi

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

echo "$(basename "${BASH_SOURCE[0]}") done"

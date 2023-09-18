#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

LIBVIRT_DEFAULT_IMAGES_PATH="/var/lib/libvirt/images"
OVMF_DEFAULT_PATH=/usr/share/OVMF
LIBVIRT_DEFAULT_LOG_PATH="/var/log/libvirt/qemu"
UBUNTU_DOMAIN_NAME=ubuntu
UBUNTU_IMAGE_NAME=$UBUNTU_DOMAIN_NAME.qcow2
UBUNTU_INSTALLER_ISO=ubuntu.iso
UBUNTU_SEED_ISO=ubuntu-seed.iso

# files required to be in unattend_ubuntu folder for installation
REQUIRED_DEB_FILES=( "linux-headers.deb" "linux-image.deb" )

FORCECLEAN=0
VIEWER=0
RT=0
KERN_INSTALL_FROM_LOCAL=0

VIEWER_DAEMON_PID=
FILE_SERVER_DAEMON_PID=
FILE_SERVER_IP="192.168.122.1"
FILE_SERVER_PORT=8000

function copy_setup_files() {
    # copy required files for use in guest
    local dest=$1
    local host_scripts=("setup_swap.sh")

    if [[ $# -ne 1 || -z $dest ]]; then
        return -1
    fi

    local script=$(realpath "${BASH_SOURCE[0]}")
    local scriptpath=$(dirname "$script")
    local host_scriptpath=$(realpath "$scriptpath/../../host_setup/ubuntu")
    local guest_scriptpath=$(realpath "$scriptpath/unattend_ubuntu")
    local dest_path=$(realpath "$dest")

    if [[ ! -d $dest_path ]]; then
        echo "Dest location to copy setup required files is not a directory"
        return -1
    fi

    for script in ${host_scripts[@]}; do
        cp -a $host_scriptpath/$script $dest_path/
    done

    local guest_files=()
    readarray -d '' guest_files < <(find "$guest_scriptpath/" -maxdepth 1 -mindepth 1 -type f -not -name "linux-image*.deb" -not -name "linux-headers*.deb")
    for file in ${guest_files[@]}; do
        cp -a $file $dest_path/
    done

    for file in ${REQUIRED_DEB_FILES[@]}; do
        dfile=$(echo "$file" | sed -r 's/-rt//')
        cp -a $guest_scriptpath/$file $dest_path/$dfile
    done

    local dest_files=()
    readarray -d '' dest_files < <(find "$dest_path/" -maxdepth 1 -mindepth 1 -type f)
    for file in ${dest_files[@]}; do
        if grep -Fq 'sudo' $file; then
            sed -i -r "s|sudo(\s)+||" $file
        fi
    done
}

function run_file_server() {
    local folder=$1
    local ip=$2
    local port=$3
    local -n pid=$4
   
    cd $folder
    python3 -m http.server -b $ip $port &
    pid=$!
    cd -
}

function kill_by_pid() {
    if [[ $# -eq 1 && ! -z "${1+x}" ]]; then
        local pid=$1
        if [[ -n "$(ps -p $pid -o pid=)" ]]; then
            sudo kill -9 $pid
        fi 
    fi
}

function install_dep() {
  sudo apt install -y cloud-image-utils virtinst virt-viewer
}

function clean_ubuntu_images() {
  echo "Remove existing ubuntu image"
  sudo virsh destroy $UBUNTU_DOMAIN_NAME &>/dev/null || :
  sleep 5
  sudo virsh undefine $UBUNTU_DOMAIN_NAME --nvram &>/dev/null || :
  sudo rm -f ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME}
  sudo rm -f ${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log

#  echo "Remove ubuntu.iso"
#  sudo rm -f ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}

#  echo "Remove ubuntu-seed.iso"
#  sudo rm -f ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_SEED_ISO}
}

function is_host_kernel_local_install() {
  local kern_ver=$(uname -r)
  local kern_header_local=$(apt list --installed | grep linux-headers-$kern_ver | awk -F' ' '{print $4}'| grep "local")
  local kern_image_local=$(apt list --installed | grep linux-image-$kern_ver | awk -F' ' '{print $4}'| grep "local")

  if [[ ! -z "$kern_header_local" && ! -z "$kern_image_local" ]]; then
    KERN_INSTALL_FROM_LOCAL=1
  else
    KERN_INSTALL_FROM_LOCAL=0
  fi
}

function install_ubuntu() {
  local script=$(realpath "${BASH_SOURCE[0]}")
  local scriptpath=$(dirname "$script")
  local dest_tmp_path=$(realpath "/tmp/${UBUNTU_DOMAIN_NAME}_install_tmp_files")

  # Check Intel overlay kernel is installed locally
  is_host_kernel_local_install

  if [[ "$KERN_INSTALL_FROM_LOCAL" != "1" ]]; then
    REQUIRED_DEB_FILES=()
  fi

  for file in ${REQUIRED_DEB_FILES[@]}; do
	local rfile=$(realpath $scriptpath/unattend_ubuntu/$file)
	if [ ! -f $rfile ]; then
		echo "Error: Missing $file in $scriptpath/unattend_ubuntu required for installation!"
		return -1
	fi
  done

  if [[ ! -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO}" ]]; then
    echo "Download Ubuntu 22.04.2 iso"
    #sudo wget -O ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO} https://releases.ubuntu.com/22.04.2/ubuntu-22.04.2-live-server-amd64.iso
    sudo wget -O ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO} https://cdimage.ubuntu.com/releases/jammy/release/inteliot/ubuntu-22.04-live-server-amd64+intel-iot.iso
  fi

  install_dep || return -1
  if [[ -d "$dest_tmp_path" ]]; then
    rm -rf "$dest_tmp_path"
  fi
  mkdir -p "$dest_tmp_path"

  copy_setup_files "$dest_tmp_path" || return -1
  run_file_server "$dest_tmp_path" $FILE_SERVER_IP $FILE_SERVER_PORT FILE_SERVER_DAEMON_PID || return -1

  echo "Generate ubuntu-seed.iso"
  sudo rm -f meta-data
  touch meta-data
  envsubst '$http_proxy,$ftp_proxy,$https_proxy,$socks_server,$no_proxy' < $scriptpath/auto-install-ubuntu.yaml > $scriptpath/auto-install-ubuntu-parsed.yaml
  # Update for RT install
  if [[ $RT == "1" ]]; then
    sed -i "s|\$RT_SUPPORT|--rt|g" $scriptpath/auto-install-ubuntu-parsed.yaml
  else
    sed -i "s|\$RT_SUPPORT||g" $scriptpath/auto-install-ubuntu-parsed.yaml
  fi
  # update for kernel overlay install via PPA vs local deb
  if [[ "$KERN_INSTALL_FROM_LOCAL" != "1" ]]; then
    sed -i "s|\$KERN_INSTALL_OPTION|-kp \"$(uname -r)\"|g" $scriptpath/auto-install-ubuntu-parsed.yaml
  else
    sed -i "/wget --no-proxy -O \/target\/tmp\/setup_bsp.sh \$FILE_SERVER_URL\/setup_bsp.sh/i \    - wget --no-proxy -O \/target\/linux-headers.deb \$FILE_SERVER_URL\/linux-headers.deb\n    - wget --no-proxy -O \/target\/linux-image.deb \$FILE_SERVER_URL\/linux-image.deb" $scriptpath/auto-install-ubuntu-parsed.yaml
    sed -i "s|\$KERN_INSTALL_OPTION|-k \'\/\'|g" $scriptpath/auto-install-ubuntu-parsed.yaml
  fi
  local file_server_url="http://$FILE_SERVER_IP:$FILE_SERVER_PORT"
  sed -i "s|\$FILE_SERVER_URL|$file_server_url|g" $scriptpath/auto-install-ubuntu-parsed.yaml
  sudo cloud-localds -v $dest_tmp_path/${UBUNTU_SEED_ISO} $scriptpath/auto-install-ubuntu-parsed.yaml meta-data

  echo "$(date): Start ubuntu guest creation and auto-installation"
  if [[ "$VIEWER" -eq "1" ]]; then
    virt-viewer -w -r --domain-name ${UBUNTU_DOMAIN_NAME} &
    VIEWER_DAEMON_PID=$!
  fi
  sudo virt-install \
  --name=${UBUNTU_DOMAIN_NAME} \
  --ram=4096 \
  --vcpus=4 \
  --cpu host \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5901 \
  --disk path=${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME},format=qcow2,size=60,bus=virtio,cache=none \
  --disk path=$dest_tmp_path/${UBUNTU_SEED_ISO},device=cdrom \
  --location ${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_INSTALLER_ISO},initrd=casper/initrd,kernel=casper/vmlinuz \
  --os-variant ubuntu22.04 \
  --noautoconsole \
  --boot loader=$OVMF_DEFAULT_PATH/OVMF_CODE_4M.fd,loader.readonly=yes,loader.type=pflash,nvram.template=$OVMF_DEFAULT_PATH/OVMF_VARS_4M.fd \
  --extra-args "autoinstall" \
  --console pty,target.type=virtio,log.file=${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log,log.append=on \
  --serial pty \
  --extra-args 'console=ttyS0,115200n8 serial' \
  --events on_poweroff=destroy \
  --wait=-1

  echo "$(date): Waiting for restarted guest to complete installation and shutdown"
  local state=$(virsh list | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
  local loop=1
  while [[ ! -z ${state+x} && $state == "running" ]]; do
    echo "$(date): $loop: waiting for running VM..."
    local count=0
    local maxcount=120
    while [[ count -lt $maxcount ]]; do
      state=$(virsh list --all | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
      if [[ ! -z ${state+x} && $state == "running" ]]; then
        sleep 60
      else
        break
      fi
      count=$((count+1))
    done
    if [[ $count -ge $maxcount ]]; then
      echo "$(date): Error: timed out waiting for Ubuntu required installation to finish after $maxcount min."
      return -1
    fi
    loop=$((loop+1))
  done
}

function show_help() {
    printf "$(basename "${BASH_SOURCE[0]}") [-h] [--force] [--viewer] [--rt]\n"
    printf "Create Ubuntu vm required image to dest ${LIBVIRT_DEFAULT_IMAGES_PATH}/ubuntu.qcow2\n"
    printf "Or create Ubuntu RT vm required image to dest ${LIBVIRT_DEFAULT_IMAGES_PATH}/ubuntu_rt.qcow2\n"
    printf "Place Intel bsp kernel debs (linux-headers.deb,linux-image.deb,linux-headers-rt.deb,linux-image-rt.deb) in guest_setup/<host_os>/unattend_ubuntu folder prior to running if platform BSP guide requires linux kernel installation from debian files.\n"
    printf "Install console log can be found at ${LIBVIRT_DEFAULT_LOG_PATH}/${UBUNTU_DOMAIN_NAME}_install.log\n"
    printf "Options:\n"
    printf "\t-h        show this help message\n"
    printf "\t--force   force clean if Ubuntu vm qcow file is already present\n"
    printf "\t--viewer  show installation display\n"
    printf "\t--rt      install Ubuntu RT\n"
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

            --rt)
                RT=1
                UBUNTU_DOMAIN_NAME=ubuntu_rt
                UBUNTU_IMAGE_NAME=ubuntu_rt.qcow2
                REQUIRED_DEB_FILES=( "linux-headers-rt.deb" "linux-image-rt.deb" )
                ;;

            -?*)
                echo "Error: Invalid option $1"
                show_help
                return -1
                ;;
            *)
                echo "unknown option: $1"
                return -1
                ;;
        esac
        shift
    done
}

function cleanup () {
    local dest_tmp_path=$(realpath "/tmp/${UBUNTU_DOMAIN_NAME}_install_tmp_files")
    if [ -d "$dest_tmp_path" ]; then
        rm -rf $dest_tmp_path
    fi
    kill_by_pid $FILE_SERVER_DAEMON_PID
    local state=$(virsh list | awk -v a="$UBUNTU_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
    if [[ ! -z ${state+x} && "$state" == "running" ]]; then
        echo "Shutting down running domain $UBUNTU_DOMAIN_NAME"
        sudo virsh shutdown $UBUNTU_DOMAIN_NAME
        sleep 10
        sudo virsh destroy $UBUNTU_DOMAIN_NAME
    fi
    sudo virsh undefine --nvram $UBUNTU_DOMAIN_NAME || true
    kill_by_pid $VIEWER_DAEMON_PID
}

#-------------    main processes    -------------
parse_arg "$@" || exit -1

trap 'cleanup' EXIT
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

if [[ $FORCECLEAN == "1" ]]; then
    clean_ubuntu_images || exit -1
fi

if [[ -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME}" ]]; then
    echo "${LIBVIRT_DEFAULT_IMAGES_PATH}/${UBUNTU_IMAGE_NAME} present"
    echo "Use --force option to force clean and re-install ubuntu"
    exit
fi

install_ubuntu || exit -1

echo "$(basename "${BASH_SOURCE[0]}") done"

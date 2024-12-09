#!/bin/bash

# Copyright (c) 2024 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
LIBVIRT_DEFAULT_IMAGES_PATH="/var/lib/libvirt/images"
OVMF_DEFAULT_PATH=/usr/share/edk2/ovmf
LIBVIRT_DEFAULT_LOG_PATH="/var/log/libvirt/qemu"
REDHAT_DOMAIN_NAME=redhat
REDHAT_IMAGE_NAME=$REDHAT_DOMAIN_NAME.qcow2
REDHAT_INSTALLER_ISO=rhel-9.2.iso
REDHAT_GUEST_ISO=redhat_guest.iso
REDHAT_VER=rhel9.2
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")
guest_scriptpath=$(realpath "$scriptpath/unattend_redhat")
iso_path=$(realpath "$scriptpath/../../")

FORCECLEAN=0
SETUP_DISK_SIZE=120 # size in GiB
SETUP_DEBUG=0

VIEWER_DAEMON_PID=
GUEST_DISK_SIZE="${SETUP_DISK_SIZE}G"

#---------      Functions    -------------------
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

function update_kickstart_file() {
    ISO_DIR=$1
    CONFIG_FILE="$ISO_DIR/rh9.2-uefi.cfg"

    # Change behaviour after installation to shutdown
    sed -i "/reboot/cshutdown" "$CONFIG_FILE"

    # Change root and user password
    NEW_ROOT_PWD="rootpw --plaintext user1234"
    NEW_USR_PWD='user --name=user --password=user1234 --gecos="user"'

    sed -i "/rootpw --plaintext/c$NEW_ROOT_PWD" "$CONFIG_FILE"
    sed -i "/user --name=user --password/c$NEW_USR_PWD" "$CONFIG_FILE"

    # Change default login to be user
    sed -i "s/AutomaticLogin=root/AutomaticLogin=user/" "$CONFIG_FILE"

    # Change network default no active
    sed -i '/^network\ \ --bootproto=dhcp/ { /--no-activate/!s/--onboot=on/--onboot=on --no-activate/ }' "$CONFIG_FILE"

    # Change Disk limit check
    sed -i "s/if \[\[ \$value -gt 107374182400 \]\] ; then/if [[ \$value -gt 42949672960 ]] ; then/" "$CONFIG_FILE"

    # Change timezone to Singapore
    NEW_TIME_ZONE="timezone Asia/Singapore --utc"
    sed -i "/^timezone/c$NEW_TIME_ZONE" "$CONFIG_FILE"

    # Add user to sudo group
    CONFIG_VISUDO="user ALL=(ALL) NOPASSWD:ALL"

    if ! grep -F "$CONFIG_VISUDO" "$CONFIG_FILE"; then
      sed -i '/^systemctl enable AIconfig.service/ { a\
    # Add user to sudo group\
    echo "user ALL=(ALL) NOPASSWD:ALL" | EDITOR='\''tee -a'\'' visudo
      }' "$CONFIG_FILE"
    else
      echo "user already in sudoer group"
    fi

    # Setup Repo
    sed -i "/>> \/etc\/rc.d\/postinstall.sh/ { i\
    # Setup yum repo\
    cp \$postscrpath\/RHEL9-2.repo \/etc\/yum.repos.d\/
    }" "$CONFIG_FILE"

    RHEL_REPO="/etc/yum.repos.d/RHEL9-2.repo"
    DEST_REPO="$ISO_DIR/APP"

    if [ -e $RHEL_REPO ]; then
      sudo cp "$RHEL_REPO" "$DEST_REPO"
    else
      echo "$RHEL_REPO does not exist"
      exit 255
    fi

}

function kill_by_pid() {
    if [[ $# -eq 1 && -n "${1}" && -n "${1+x}" ]]; then
        local pid=$1
        if [[ -n "$(ps -p "$pid" -o pid=)" ]]; then
            sudo kill -9 "$pid"
        fi
    fi
}

function clean_redhat_images() {
  echo "Remove existing redhat image"
  sudo virsh destroy "$REDHAT_DOMAIN_NAME" &>/dev/null || :
  sleep 5
  sudo virsh undefine "$REDHAT_DOMAIN_NAME" --nvram &>/dev/null || :
  sudo rm -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${REDHAT_IMAGE_NAME}"
  echo "Remove ${LIBVIRT_DEFAULT_IMAGES_PATH}/${REDHAT_IMAGE_NAME}"
  sudo rm -f "${LIBVIRT_DEFAULT_LOG_PATH}/${REDHAT_DOMAIN_NAME}_install.log"

  echo "Remove ${guest_scriptpath}/${REDHAT_GUEST_ISO}"
  sudo rm -f "${guest_scriptpath}/${REDHAT_GUEST_ISO}"
  sudo rm -rf /mnt/mod
  if mountpoint -q "/mnt/rhel_vm_iso"; then
    echo "/mnt/rhel_vm_iso is a mount point. Unmounting..."

    # Attempt to unmount the path
    if sudo umount "/mnt/rhel_vm_iso"; then
        echo "Successfully unmounted /mnt/rhel_vm_iso"
    else
        echo "Failed to unmount /mnt/rhel_vm_iso"
        exit
    fi
  fi

}

function install_redhat() {

    local dest_tmp_path
    dest_tmp_path=$(realpath "/tmp/${REDHAT_DOMAIN_NAME}_install_tmp_files")

    if [[ -d "$dest_tmp_path" ]]; then
      rm -rf "$dest_tmp_path"
    fi
    echo "mkdir $dest_tmp_path"
    mkdir -p "$dest_tmp_path"

    if [[ -f "$guest_scriptpath/${REDHAT_GUEST_ISO}" ]]; then
      check_file_valid_nonzero "$guest_scriptpath/${REDHAT_GUEST_ISO}"
    elif [[ -f "$iso_path/${REDHAT_INSTALLER_ISO}" ]]; then
      check_file_valid_nonzero "$iso_path/${REDHAT_INSTALLER_ISO}"

      echo "Generate vm installer iso"

      sudo mkdir -p /mnt/rhel_vm_iso
      sudo mount -o loop "$iso_path/${REDHAT_INSTALLER_ISO}" /mnt/rhel_vm_iso
      sudo mkdir -p /mnt/mod
      sudo cp -aR /mnt/rhel_vm_iso /mnt/mod/
      sudo chmod a+rwx /mnt/mod/rhel_vm_iso
      update_kickstart_file /mnt/mod/rhel_vm_iso
      sudo mkisofs -o "$guest_scriptpath/$REDHAT_GUEST_ISO" \
      -b isolinux/isolinux.bin -J -R -l -c isolinux/boot.cat \
      -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot \
      -e images/efiboot.img -no-emul-boot -graft-points -V "OS" /mnt/mod/rhel_vm_iso

    else
      echo "$iso_path/${REDHAT_INSTALLER_ISO} not found"
      exit 255
    fi

    echo "create qcow2 disk"
    sudo qemu-img create -f qcow2 ${LIBVIRT_DEFAULT_IMAGES_PATH}/${REDHAT_IMAGE_NAME} $GUEST_DISK_SIZE
    sudo virt-install \
    --name "$REDHAT_DOMAIN_NAME" \
    --memory 4096 \
    --vcpus 4 \
    --os-variant "$REDHAT_VER" \
    --cdrom "$guest_scriptpath/$REDHAT_GUEST_ISO" \
    --network network=default,model=virtio \
    --graphics vnc,listen=0.0.0.0,port=5901 \
    --noautoconsole \
    --network network=default,model=virtio \
    --serial pty \
    --boot "loader=$OVMF_DEFAULT_PATH/OVMF_CODE.fd,loader.readonly=yes,loader.type=pflash,nvram.template=$OVMF_DEFAULT_PATH/OVMF_VARS.fd" \
    --disk ${LIBVIRT_DEFAULT_IMAGES_PATH}/${REDHAT_IMAGE_NAME},device=disk,bus=virtio,format=qcow2

	return 0
}

function show_help() {
    printf "%s [-h] [--force] [--disk-size] [--debug]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Create Redhat vm required image to dest %s/redhat.qcow2\n" "${LIBVIRT_DEFAULT_IMAGES_PATH}"
    printf "Install console log can be found at %s_install.log\n" "${LIBVIRT_DEFAULT_LOG_PATH}/${REDHAT_DOMAIN_NAME}"
    printf "Options:\n"
    printf "\t-h                          show this help message\n"
    printf "\t--force                     force clean if Redhat vm qcow file is already present\n"
    printf "\t--disk-size                 disk storage size of Redhat vm in GiB, default is 60 GiB\n"
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

            --disk-size)
                SETUP_DISK_SIZE="$2"
                GUEST_DISK_SIZE="${SETUP_DISK_SIZE}G"
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
    local state
    state=$(virsh list | awk -v a="$REDHAT_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
    if [[ -n "${state+x}" && "$state" == "running" ]]; then
        echo "Shutting down running domain $REDHAT_DOMAIN_NAME"
        virsh shutdown "$REDHAT_DOMAIN_NAME"
        sleep 10
        state=$(virsh list | awk -v a="$REDHAT_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
        if [[ -n "${state+x}" && "$state" == "running" ]]; then
            virsh destroy "$REDHAT_DOMAIN_NAME"
        fi
        virsh undefine --nvram "$REDHAT_DOMAIN_NAME"
    fi
    if virsh list --name --all | grep -q -w "$REDHAT_DOMAIN_NAME"; then
        virsh undefine --nvram "$REDHAT_DOMAIN_NAME"
    fi
    local poolname
    poolname="${REDHAT_DOMAIN_NAME}_install_tmp_files"
    if virsh pool-list | grep -q "$poolname"; then
        virsh pool-destroy "$poolname"
        if virsh pool-list --all | grep -q "$poolname"; then
            virsh pool-undefine "$poolname"
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

    kill_by_pid "$VIEWER_DAEMON_PID"
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

if ! [[ $SETUP_DISK_SIZE =~ ^[0-9]+$ ]]; then
    echo "Invalid input disk size"
    exit 255
fi


if [[ $FORCECLEAN == "1" ]]; then
    clean_redhat_images || exit 255
fi

if [[ -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${REDHAT_IMAGE_NAME}" ]]; then
    echo "${LIBVIRT_DEFAULT_IMAGES_PATH}/${REDHAT_IMAGE_NAME} present"
    echo "Use --force option to force clean and re-install redhat"
    exit 255
fi

trap 'cleanup' EXIT

install_redhat || exit 255

echo "$(basename "${BASH_SOURCE[0]}") done"

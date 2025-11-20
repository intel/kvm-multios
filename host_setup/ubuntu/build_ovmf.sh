#!/bin/bash

# Copyright (c) 2023-2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

#---------      Global variable     -------------------
WORK_DIR=$(pwd)
LIBVIRT_DEFAULT_IMAGES_PATH="/var/lib/libvirt/images"

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
        if [[ $? -ne 0 || ! -d "$dpath" ]]; then
            echo "Error: $dpath invalid directory"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

#-------------    main processes    -------------
check_dir_valid "$LIBVIRT_DEFAULT_IMAGES_PATH"

[ -d "$WORK_DIR/edk2" ] && rm -rf "$WORK_DIR/edk2"

sudo apt-get install -y uuid-dev
which git > /dev/null || sudo apt-get install -y git
which make > /dev/null || sudo apt-get install -y build-essential
which nasm > /dev/null || sudo apt-get install -y nasm
which acpidump > /dev/null || sudo apt-get install -y acpica-tools
which iasl > /dev/null || sudo apt-get install -y acpica-tools

git clone https://github.com/tianocore/edk2.git

cd "$WORK_DIR"/edk2
git checkout -b stable202205 edk2-stable202205
wget https://raw.githubusercontent.com/projectceladon/vendor-intel-utils/0269c099c69765dbfbbc621358bd37161fbdd77d/host/ovmf/0001-OvmfPkg-add-IgdAssignmentDxe.patch
patch -p1 < 0001-OvmfPkg-add-IgdAssignmentDxe.patch
git submodule update --init
set +u
# edksetup.sh is not included. Ignore.
# shellcheck disable=SC1091
source ./edksetup.sh
set -u
make -C BaseTools/
build -b DEBUG -t GCC5 -a X64 -p OvmfPkg/OvmfPkgX64.dsc -D NETWORK_IP4_ENABLE -D NETWORK_ENABLE -D SECURE_BOOT_ENABLE -D TPM_ENABLE
echo "Copy OVMF_CODE.fd OVMF_VARS.fd to $LIBVIRT_DEFAULT_IMAGES_PATH"
sudo cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd $LIBVIRT_DEFAULT_IMAGES_PATH/OVMF_CODE_custom_gvtd.fd
sudo cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd $LIBVIRT_DEFAULT_IMAGES_PATH/OVMF_VARS_custom_gvtd.fd
sudo cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF.fd $LIBVIRT_DEFAULT_IMAGES_PATH/OVMF_custom_gvtd.fd
# Also build 4M images
build -b DEBUG -t GCC5 -a X64 -p OvmfPkg/OvmfPkgX64.dsc -D NETWORK_IP4_ENABLE -D NETWORK_ENABLE -D SECURE_BOOT_ENABLE -D TPM_ENABLE -D FD_SIZE_4MB
sudo cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd $LIBVIRT_DEFAULT_IMAGES_PATH/OVMF_CODE_4M_custom_gvtd.fd
sudo cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd $LIBVIRT_DEFAULT_IMAGES_PATH/OVMF_VARS_4M_custom_gvtd.fd
sudo cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF.fd $LIBVIRT_DEFAULT_IMAGES_PATH/OVMF_4M_custom_gvtd.fd

# Clean up leftovers
cd -
rm -rf "$WORK_DIR/edk2"

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

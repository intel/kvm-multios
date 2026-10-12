#!/bin/bash

# Copyright (c) 2023-2026 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

#---------      Global variable     -------------------
WORK_DIR=$(pwd)
LIBVIRT_DEFAULT_IMAGES_PATH="/var/lib/libvirt/images"
IGD_ASSIGNMENT_PATCH="0001-OvmfPkg-add-IgdAssignmentDxe.patch"
IGD_ASSIGNMENT_PATCH_REPO="https://github.com/projectceladon/vendor-intel-utils.git"
IGD_ASSIGNMENT_PATCH_REVISION="0269c099c69765dbfbbc621358bd37161fbdd77d"
IGD_ASSIGNMENT_PATCH_PATH="host/ovmf/${IGD_ASSIGNMENT_PATCH}"
IGD_ASSIGNMENT_PATCH_SHA256="a1453505ea191e18c14c0c9c856ba4dc4303dbb509cdafa34ec474dcf38a12cf"

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

function ubuntu_version_id() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "${VERSION_ID:-}"
    fi
}

function download_igd_assignment_patch_with_git() {
    if [[ $# -ne 1 ]]; then
        return 255
    fi

    local output_file="$1"
    local temporary_repo

    temporary_repo=$(mktemp -d) || return 255
    if git -C "$temporary_repo" init -q && \
       git -C "$temporary_repo" fetch -q --depth=1 "$IGD_ASSIGNMENT_PATCH_REPO" "$IGD_ASSIGNMENT_PATCH_REVISION" && \
       git -C "$temporary_repo" show "FETCH_HEAD:${IGD_ASSIGNMENT_PATCH_PATH}" > "$output_file"; then
        rm -rf "$temporary_repo"
        return 0
    fi

    rm -rf "$temporary_repo"
    return 255
}

function download_igd_assignment_patch() {
    local temporary_patch

    temporary_patch=$(mktemp "${IGD_ASSIGNMENT_PATCH}.XXXXXX") || return 255

    download_igd_assignment_patch_with_git "$temporary_patch" || {
        rm -f "$temporary_patch"
        return 255
    }

    if ! echo "$IGD_ASSIGNMENT_PATCH_SHA256  $temporary_patch" | sha256sum -c -; then
        rm -f "$temporary_patch"
        return 255
    fi

    mv -f "$temporary_patch" "$IGD_ASSIGNMENT_PATCH"
}

function patch_basetools_for_ubuntu_2604() {
    local dlg_makefile="BaseTools/Source/C/VfrCompile/Pccts/dlg/makefile"

    if [[ "$(ubuntu_version_id)" != "26.04" ]]; then
        return 0
    fi

    # shellcheck disable=SC2016
    if ! grep -q '\$(COTHER)' "$dlg_makefile"; then
        # shellcheck disable=SC2016
        sed -i 's|-DUSER_ZZSYN -DZZLEXBUFSIZE=65536|-DUSER_ZZSYN $(COTHER) -DZZLEXBUFSIZE=65536|' "$dlg_makefile"
    fi
}

function build_basetools() {
    if [[ "$(ubuntu_version_id)" == "26.04" ]]; then
        make -C BaseTools/ COTHER="-std=gnu89" EXTRA_OPTFLAGS="-Wno-error=discarded-qualifiers"
    else
        make -C BaseTools/
    fi
}

#-------------    main processes    -------------
check_dir_valid "$LIBVIRT_DEFAULT_IMAGES_PATH"

[ -d "$WORK_DIR/edk2" ] && rm -rf "$WORK_DIR/edk2"

sudo apt-get install -y uuid-dev
sudo apt-get install -y ca-certificates
which git > /dev/null || sudo apt-get install -y git
which make > /dev/null || sudo apt-get install -y build-essential
which nasm > /dev/null || sudo apt-get install -y nasm
which acpidump > /dev/null || sudo apt-get install -y acpica-tools
which iasl > /dev/null || sudo apt-get install -y acpica-tools

git clone https://github.com/tianocore/edk2.git

cd "$WORK_DIR"/edk2
git checkout -b stable202205 edk2-stable202205
download_igd_assignment_patch
patch -p1 < "$IGD_ASSIGNMENT_PATCH"
git submodule update --init
patch_basetools_for_ubuntu_2604
set +u
# edksetup.sh is not included. Ignore.
# shellcheck disable=SC1091
source ./edksetup.sh
set -u
build_basetools
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

#!/bin/bash

# Copyright (c) 2024-2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error $(realpath ${BASH_SOURCE[0]}) line ${LINENO}: $BASH_COMMAND"' ERR

#---------      Global variable     -------------------
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

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

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f "$fpath" || ! -s "$fpath" ]]; then
            echo "Error: $fpath invalid/zero sized"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

function check_os() {
    # Check OS
    local version
    version=$(cat /proc/version)
    if [[ ! "$version" =~ "Ubuntu" ]]; then
        echo "Error: Only Ubuntu is supported"
        return 255
    fi
}

function check_libvirt_version() {
    if [[ -z "${1+x}" || -z "$1" ]]; then
        echo "ERROR: invalid libvirt version input to check for"
        return 255
    fi
    # Check current libvirt version is equal or greater than input argument
    local IFS=.
    local input_ver_array=()
    local current_ver_array=()
    read -r -a current_ver_array <<<"$(virsh --version)"
    read -r -a input_ver_array <<<"$1"
    local i
    for ((i=0; i<${#input_ver_array[@]}; i++)); do
        if ((10#${current_ver_array[i]} > 10#${input_ver_array[i]})); then
            return 0
        fi
        if ((10#${current_ver_array[i]} < 10#${input_ver_array[i]})); then
            return 255
        fi
    done
}

function install_dep() {
    which xmlstarlet > /dev/null || sudo apt install -y xmlstarlet
}

function setup_xml() {
    local xmlpath="$scriptpath/../../platform/client/libvirt_xml"
    check_dir_valid "$xmlpath"
    local -a xmlfiles=()
    mapfile -t xmlfiles < <(find "$xmlpath" -maxdepth 1 -mindepth 1 -type f -name "*.xml")

    local display
    display=$(who | { grep -o ' :.' || :; } | xargs)

    if [[ -n $display ]]; then
        for file in "${xmlfiles[@]}"; do
            check_file_valid_nonzero "$file"
            if grep -q 'name="DISPLAY" value="' "$file"; then
                sed -i -e "s/.*name=\"DISPLAY\" value=.*/    <qemu:env name=\"DISPLAY\" value=\"$display\"\/>/" "$file"
            fi
        done
    fi

    if check_libvirt_version '8.2'; then
        # Libvirt 8.2 and above does not support -set qemu:arg in qemu:commandline"
        for file in "${xmlfiles[@]}"; do
            check_file_valid_nonzero "$file"
            if grep -q "device.video0.blob=true" "$file"; then
                xmlstarlet ed -L -d '/domain/qemu:commandline/qemu:arg[@value="-set"]' "$file"
                xmlstarlet ed -L -d '/domain/qemu:commandline/qemu:arg[@value="device.video0.blob=true"]' "$file"
                xmlstarlet ed -L -d '/domain/qemu:commandline/qemu:arg[@value="device.video0.render_sync=true"]' "$file"
                # Insert the new <qemu:override> section
                sed -i '/<\/domain>/i \
  <qemu:override>\
    <qemu:device alias="video0">\
      <qemu:frontend>\
        <qemu:property name="blob" type="bool" value="true"/>\
        <qemu:property name="render_sync" type="bool" value="true"/>\
      </qemu:frontend>\
    </qemu:device>\
  </qemu:override>' "$file"
	    fi
            if grep -q "device.ua-igpu.x-igd-opregion=on" "$file"; then
                xmlstarlet ed -L -d '/domain/qemu:commandline/qemu:arg[@value="-set"]' "$file"
                xmlstarlet ed -L -d '/domain/qemu:commandline/qemu:arg[@value="device.ua-igpu.x-igd-opregion=on"]' "$file"
                xmlstarlet ed -L -d '/domain/qemu:commandline/qemu:arg[@value="device.ua-igpu.x-igd-gms=2"]' "$file"
                # Remove <qemu:commandline> section if it has no child nodes
                xmlstarlet ed -L -d '/domain/qemu:commandline[not(node())]' "$file"
                # Insert the new <qemu:override> section
                sed -i '/<\/domain>/i \
  <qemu:override>\
    <qemu:device alias="ua-igpu">\
      <qemu:frontend>\
        <qemu:property name="x-igd-opregion" type="bool" value="true"/>\
        <qemu:property name="x-igd-gms" type="unsigned" value="2"/>\
      </qemu:frontend>\
    </qemu:device>\
  </qemu:override>' "$file"
            fi
        done
    fi

    if check_libvirt_version '9.3.0'; then
        for file in "${xmlfiles[@]}"; do
            check_file_valid_nonzero "$file"
            # retrieve the address window
            aw=$(($((($(((0x$(cat /sys/devices/virtual/iommu/dmar0/intel-iommu/cap)) >> 16 ))) & 0x3F )) + 1))
            if grep -q "<cpu mode=\"host-passthrough\"/>" "$file"; then
                # add maxphysaddr element for fresh setup
                xmlstarlet ed -L -s '/domain/cpu' -t 'elem' -n 'maxphysaddr' \
                    -i '/domain/cpu/maxphysaddr' -t 'attr' -n 'mode' -v 'passthrough' \
                    -i '/domain/cpu/maxphysaddr' -t 'attr' -n 'limit' -v $aw "$file"
            else
                # keep the limit updated
                xmlstarlet ed -L -u '/domain/cpu/maxphysaddr/@limit' -v $aw "$file"
            fi
        done
    fi

}

#-------------    main processes    -------------

check_os || exit 255
install_dep || exit 255
setup_xml || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

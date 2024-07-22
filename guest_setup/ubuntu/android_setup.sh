#!/bin/bash

# Copyright (c) 2023-2024 Intel Corporation.
# All rights reserved.
#

set -Eeuo pipefail

#---------      Global variable     -------------------
LIBVIRT_DEFAULT_IMAGES_PATH=/var/lib/libvirt/images
RELFILE_OUT=$(realpath -L ./caas-releasefiles)
RELFILE=""
LIBVIRT_DOMAIN_NAME="android"
FLASHFILES_ZIP=""
NOINSTALL=0
FORCECLEAN=0
ENABLE_SUSPEND="false" # or true
ENABLE_QEMU_FROM_SRC=0 # do not overwrite BSP default qemu
DUPXML=0
PLATFORM_NAME=""
SETUP_DISK_SIZE=40 # size in GiB
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

function check_host_distribution() {
    local dist
    dist=$(lsb_release -d)

    if [[ ! $dist =~ "Ubuntu" ]]; then
        echo "Error: only Ubuntu is supported!"
        return 255
    fi
}

function print_info() {
    echo "caas-releasefiles archive decompress dest: $RELFILE_OUT"
    echo "caas-releasefiles archive: $RELFILE"
    echo "New Android VM domain name: $LIBVIRT_DOMAIN_NAME"
    echo "Android VM dest images folder: $LIBVIRT_DEFAULT_IMAGES_PATH/$LIBVIRT_DOMAIN_NAME"
    echo "Celadon flashfiles zip archive: $FLASHFILES_ZIP"
    if [[ -z $NOINSTALL ]]; then
        echo "No Celdaon dependencies installation"
    else
        echo "Run Celdaon dependencies installation"
    fi
    echo "Enable guest suspend: $ENABLE_SUSPEND"
}

function setup_relfiles_path() {

    check_file_valid_nonzero "$1"
    local rel_file
    rel_file=$(realpath -L "$1")

    if [[ -f "$rel_file" ]]; then
        RELFILE=$rel_file
    else
        echo "Error: Invalid releasefiles archive provided."
        return 255
    fi

    return 0
}

function uncompress_relfiles() {

    if [ -n "$RELFILE" ]; then
        if [[ -d "$RELFILE_OUT" ]]; then
            echo "Removing existing $RELFILE_OUT"
            sudo rm -rf "$RELFILE_OUT"
        fi
        mkdir -p "$RELFILE_OUT"
        echo "Uncompressing $RELFILE to $RELFILE_OUT"
        tar -xvf "$RELFILE" -C "$RELFILE_OUT" >& /dev/null
    fi

    return 0
}

function install_dep () {
    local working_dir
    working_dir=$(pwd)
    local target_qemu_version="7.1.0"

    if [[ ! -d "$RELFILE_OUT"  || ! -f "$RELFILE_OUT/scripts/setup_host.sh" ]]; then
        echo "Error: expected Celadon installation folder/files not found!"
        return 255
    fi 
    
    cd "$RELFILE_OUT"
    cat /dev/null > /tmp/setup_host.sh
    sed -n -e '/show_help/,$!p' ./scripts/setup_host.sh > /tmp/setup_host.sh
    echo "Ensure using QEMU $target_qemu_version..."
    sed -i -e "s/qemu-7.0.0/qemu-$target_qemu_version/" /tmp/setup_host.sh
    # wa for missing sudo in line
    sed -i -r "s/(count=\"\\$\()/&sudo /" /tmp/setup_host.sh
    if [[ $ENABLE_QEMU_FROM_SRC -eq "1" ]]; then
        # not required for qemu 7.1.0
        if [[ -f "patches/qemu/0005-ui-gtk-new-param-monitor-to-specify-target-monitor-f.patch" ]]; then
            rm "patches/qemu/0005-ui-gtk-new-param-monitor-to-specify-target-monitor-f.patch"
        fi
        # Add timeout for QEMU prompt so that setup auto continue without user intervention
        sed -i -e 's/read -p/read -t 10 -p/' /tmp/setup_host.sh
        # Ensure patched QEMU build has features as is default enabled by Ubuntu default
        # Do not allow auto remove packages
        sed -i -e 's/sudo apt autoremove -y/#&/' /tmp/setup_host.sh
        # Add Dependencies as per QEMU build wiki https://wiki.qemu.org/Hosts/Linux
        # Ubuntu qemu package: https://packages.ubuntu.com/jammy/qemu-system-x86
        sed -i -e '/sudo apt autoremove -y/a \
        sudo apt install -y git libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev ninja-build \
        sudo apt install -y libaio-dev libbluetooth-dev libcapstone-dev libbrlapi-dev libbz2-dev \
        sudo apt install -y libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev \
        sudo apt install -y libibverbs-dev libjpeg8-dev libncurses5-dev libnuma-dev \
        sudo apt install -y librbd-dev librdmacm-dev \
        sudo apt install -y libsasl2-dev libsdl2-dev libseccomp-dev libsnappy-dev libssh-dev \
        sudo apt install -y libvde-dev libvdeplug-dev libvte-2.91-dev libxen-dev liblzo2-dev \
        sudo apt install -y valgrind xfslibs-dev \
        sudo apt install -y libnfs-dev libiscsi-dev \
        sudo apt install -y git python3 ninja-build meson texinfo python3-sphinx python3-sphinx-rtd-theme libaio-dev libjack-dev libpulse-dev libasound2-dev libbpf-dev libbrlapi-dev libcap-ng-dev libcurl4-gnutls-dev libfdt-dev libfuse3-dev gnutls-dev libgtk-3-dev libvte-2.91-dev libiscsi-dev libncurses-dev libvirglrenderer-dev libva-dev libepoxy-dev libdrm-dev libgbm-dev libnfs-dev libnuma-dev libcacard-dev libpixman-1-dev librbd-dev libglusterfs-dev glusterfs-common libsasl2-dev libsdl2-dev libseccomp-dev libslirp-dev libspice-server-dev librdmacm-dev libibverbs-dev libibumad-dev liburing-dev libusb-1.0-0-dev libusbredirparser-dev libssh-dev libzstd-dev libxen-dev nettle-dev uuid-dev xfslibs-dev zlib1g-dev libudev-dev libjpeg-dev libpng-dev libpmem-dev \
        sudo apt install -y libdaxctl-dev libspice-protocol-dev' /tmp/setup_host.sh
    fi
    chmod +x /tmp/setup_host.sh

    # shellcheck source=/dev/null
    source /tmp/setup_host.sh
    if [[ "$ENABLE_QEMU_FROM_SRC" -eq "1" ]]; then
        if echo "$QEMU_REL" | grep -q "$target_qemu_version"; then
            echo "Incorrect QEMU version selected for install."
            return 255
        fi
    fi

    # need to ensure apt is updated to get required packages
    sudo apt update

    echo "Installing Celadon VM dependencies"
    check_os || return 255
    check_network || return 255
    check_kernel_version || return 255

    ubu_changes_require || return 255
    if [[ $ENABLE_QEMU_FROM_SRC -eq "1" ]]; then
        ubu_install_qemu_gvt || return 255
        installed_qemu_version=$(qemu-system-x86_64 -version | grep "$target_qemu_version")
        if [[ -z $installed_qemu_version ]]; then
            echo "Error: expected qemu-system-x86_64 version not present after install"
            return 255
        fi
    fi
    set +u
    ubu_build_ovmf_gvt || return 255
    set -u
    edk2_build_fv="$RELFILE_OUT"/edk2/Build/OvmfX64/DEBUG_GCC5/FV
    echo "$edk2_build_fv"
    if [[ ! -f "$edk2_build_fv/OVMF_CODE.fd" || ! -f $edk2_build_fv/OVMF_VARS.fd ]]; then
        echo "Error: expected OVMF files not present after install"    
        return 255
    fi

    prepare_required_scripts || return 255

    # check rpmb_dev is able to run
    # shellcheck disable=2143
    if [[ -n $("$RELFILE_OUT/scripts/rpmb_dev" 2>&1 | grep 'libcrypto.so.1.1') ]]; then
        # Note: Not required for latest CIV_13
        sudo add-apt-repository -y 'deb http://security.ubuntu.com/ubuntu focal-security main'
        sudo apt install -y libssl1.1
        sudo add-apt-repository -y --remove 'deb http://security.ubuntu.com/ubuntu focal-security main'
    fi

    ubu_update_bt_fw || return 255

    cd "$working_dir"
    return 0
}

function setup_zip_flashfiles_path() {

    check_file_valid_nonzero "$1"
    local zip_file
    zip_file=$(realpath -L "$1")
    local zip_test
    zip_test=$(file "$zip_file" | grep -i "Zip archive data")

    if [[ "$zip_test" != "" ]]; then
        echo "Checking $1 is valid flashfiles archive..."
        if ! unzip -tq "$zip_file"; then
            echo "Error: Invalid zip archive provided: $1"
            return 255
        fi
        local boot_img
        boot_img=$(unzip -l "$zip_file" | grep boot.img)
        if [[ -z "$boot_img" ]]; then
            echo "Error: No boot.img found in provide zip archive $1"
            return 255
        fi
        FLASHFILES_ZIP="$zip_file"
    else
        echo "Error: Invalid flashfiles zip archive provided $1"
        return 255
    fi

    return 0
}

function setup_android_images() {
    if [[ -z "${LIBVIRT_DOMAIN_NAME+x}" || -z "$LIBVIRT_DOMAIN_NAME" || -z "${FLASHFILES_ZIP+x}" || -z "$FLASHFILES_ZIP" ]]; then
        echo "Error: Missing required arguments."
        return 255
    fi
    if [[ ! -f "$RELFILE_OUT/scripts/rpmb_dev" ]]; then
        echo "Error: Missing rpmb_dev in releasefiles decompress dest folder: $RELFILE_OUT"
        return 255
    fi

    # setup per vm hook 
    if [[ -z "${SYSCONFDIR+x}" || -z "$SYSCONFDIR" ]]; then
        hook_path="/etc/libvirt/hooks"
    else
        hook_path="$SYSCONFDIR/libvirt/hooks"
    fi
    if [[ ! -d "$hook_path/qemu.d" ]]; then
        sudo mkdir -p "$hook_path/qemu.d"
    fi

    local folder_path="$LIBVIRT_DEFAULT_IMAGES_PATH/$LIBVIRT_DOMAIN_NAME"
    local tmp_folder_path="/tmp/libvirt-img-$LIBVIRT_DOMAIN_NAME"
    local flashfiles=$FLASHFILES_ZIP
    local decompress="$tmp_folder_path/flashfiles_decompress"

    if [[ -d "$folder_path" && "$FORCECLEAN" == "1" ]]; then
        echo "Force removing dest folder $folder_path..."
        sudo rm -rf "$folder_path"
    fi
    if [[ -d "$hook_path/qemu.d/$LIBVIRT_DOMAIN_NAME" && $FORCECLEAN == "1" ]]; then
        echo "Force removing dest vm hooks folder $hook_path/qemu.d/$LIBVIRT_DOMAIN_NAME..."
        sudo rm -rf "$hook_path/qemu.d/$LIBVIRT_DOMAIN_NAME"
    fi
    if [[ ! -d "$tmp_folder_path" ]]; then
        mkdir -p "$tmp_folder_path"
    fi
    echo "Create VM qcow2 image..."
    if [[ -f "$tmp_folder_path/android.qcow2" ]]; then
        rm "$tmp_folder_path/android.qcow2"
    fi
    if ! qemu-img create -f qcow2 "$tmp_folder_path/android.qcow2" ${SETUP_DISK_SIZE}G; then
        echo "Error: Unable to create qcow2 image."
        return 255
    fi

    if [[ ! -d "$tmp_folder_path/vtpm0" ]]; then
        mkdir -p "$tmp_folder_path/vtpm0"
    fi
    # update appamor rules to vtpm0 folder
    if ! grep -Fq "owner $folder_path/vtpm0/* rwk," /etc/apparmor.d/usr.bin.swtpm; then
        sudo sed -i -e "/^}$/i \
  owner $folder_path/vtpm0/* rwk," /etc/apparmor.d/usr.bin.swtpm
        sudo apparmor_parser -r /etc/apparmor.d/usr.bin.swtpm
    fi

    if [[ ! -d "$tmp_folder_path/aaf" ]]; then
        mkdir -p "$tmp_folder_path/aaf"
    fi
    touch "$tmp_folder_path/aaf/mixins.spec"
    if grep -q "suspend" "$folder_path/aaf/mixins.spec"; then
        echo "suspend:$ENABLE_SUSPEND" >> "$tmp_folder_path/aaf/mixins.spec"
    fi

    # copy rpmb_dev
    if [[ ! -f "$tmp_folder_path/rpmb_dev" ]]; then
        cp "$RELFILE_OUT/scripts/rpmb_dev" "$tmp_folder_path/"
    fi

    # Create per-VM CIV dependencies run script(s)
    # Begin civ dependency setup: rpmb_dev
    tee "$tmp_folder_path/run_civ_rpmb_dev.sh" &>/dev/null <<EOF
#!/usr/bin/env bash
#
# Copyright (c) 2023 Intel Corporation.
# All rights reserved.
#

set -Eeuo pipefail

RPMB_DATA_DIR=$folder_path
GUEST_RPMB_DEV_SOCK=\$RPMB_DATA_DIR/rpmb_sock

function setup_rpmb_dev() {
  local RPMB_DEV=\$RPMB_DATA_DIR/rpmb_dev
  local RPMB_DATA=\$RPMB_DATA_DIR/RPMB_DATA
  
  # RPMB_DATA is created and initialized with specific key, if this file
  # is deleted by accidently, create a new one without any data.
  if [ ! -f \$RPMB_DATA ]; then
    echo "Creating RPMB DATA..."
    \$RPMB_DEV --dev \$RPMB_DATA --init --size 2048
  fi

  # RPMB sock should be removed at cleanup, if there exists RPMB sock,
  # rpmb_dev cannot be launched succefully. Delete any exist RPMB sock,
  # rpmb_dev application creates RPMB sock by itself.
  if [ -S \$GUEST_RPMB_DEV_SOCK ]; then
    rm \$GUEST_RPMB_DEV_SOCK
  fi

  \$RPMB_DEV --dev \$RPMB_DATA --sock \$GUEST_RPMB_DEV_SOCK
} 

function cleanup_rpmb_dev() {
  # clean up socket after run
  if [ -S \$GUEST_RPMB_DEV_SOCK ]; then
    rm \$GUEST_RPMB_DEV_SOCK
  fi
}

trap 'cleanup_rpmb_dev' EXIT

setup_rpmb_dev
EOF

    # create per-VM dependencies systemd service
    service_file=libvirt-$LIBVIRT_DOMAIN_NAME-rpmb-dev.service
    sudo truncate -s 0 "/etc/systemd/system/$service_file"
    sudo tee "/etc/systemd/system/$service_file" &>/dev/null <<EOF
#
# Copyright (c) 2023 Intel Corporation.
# All rights reserved.
#

[Unit]
Description=CiV VM $LIBVIRT_DOMAIN_NAME dependencies (rpmb_dev)
After=multi-user.target

[Service]
Type=simple
WorkingDirectory=$folder_path
ExecStart=/bin/bash -E $folder_path/run_civ_rpmb_dev.sh

[Install]
WantedBy=
EOF
    # Allow manual start only
    sudo systemctl daemon-reload
    sudo systemctl disable $service_file

    # Create per-VM hooks for dependency
    per_vm_hook="$hook_path/qemu.d/$LIBVIRT_DOMAIN_NAME/prepare/begin"
    sudo mkdir -p "$per_vm_hook"
    sudo tee "$per_vm_hook/civ_rpmb_dev.sh" &>/dev/null <<EOF
#!/usr/bin/env bash
#
# Copyright (c) 2023-2024 Intel Corporation.
# All rights reserved.
#
systemctl start $service_file

wait_cnt=0
while [ -z \$(pgrep -f "$folder_path/rpmb_dev") ]
do
  sleep 1
  (( wait_cnt++ ))
  if [ \$wait_cnt -ge 10 ]; then
    echo "E: Failed to setup virtual RPMB device!" >&2
    exit 255
  fi
done
EOF
    sudo chmod +x "$per_vm_hook/civ_rpmb_dev.sh"

    # Create per-VM hook for stop dependencies
    per_vm_hook="$hook_path/qemu.d/$LIBVIRT_DOMAIN_NAME/release/end"
    sudo mkdir -p "$per_vm_hook"
    sudo tee "$per_vm_hook/civ_rpmb_dev.sh" &>/dev/null <<EOF
#!/usr/bin/env bash
#
# Copyright (c) 2023 Intel Corporation.
# All rights reserved.
#
systemctl stop $service_file
EOF
    sudo chmod +x "$per_vm_hook/civ_rpmb_dev.sh"
    # End civ dependency setup: rpmb_dev

    # Begin civ dependency setup: swtpm
    tee "$tmp_folder_path/run_civ_swtpm.sh" &>/dev/null <<EOF
#!/usr/bin/env bash
#
# Copyright (c) 2023 Intel Corporation.
# All rights reserved.
#

set -Eeuo pipefail

SWTPM_DATA_DIR=$folder_path/vtpm0
GUEST_SWTPM_SOCK=\$SWTPM_DATA_DIR/swtpm-sock
SWTPM_BIN=/usr/bin/swtpm

function setup_swtpm() {
  \$SWTPM_BIN socket --tpmstate dir=\$SWTPM_DATA_DIR --tpm2 --ctrl type=unixio,path=\$GUEST_SWTPM_SOCK
}

setup_swtpm
EOF

    service_file=libvirt-$LIBVIRT_DOMAIN_NAME-swtpm.service
    sudo truncate -s 0 "/etc/systemd/system/$service_file"
    sudo tee "/etc/systemd/system/$service_file" &>/dev/null <<EOF
#
# Copyright (c) 2023 Intel Corporation.
# All rights reserved.
#

[Unit]
Description=CiV VM $LIBVIRT_DOMAIN_NAME dependencies (swtpm)
After=multi-user.target

[Service]
Type=simple
WorkingDirectory=$folder_path
ExecStart=/bin/bash -E $folder_path/run_civ_swtpm.sh

[Install]
WantedBy=
EOF
    # Allow manual start only
    sudo systemctl daemon-reload
    sudo systemctl disable $service_file

    # Create per-VM hooks for dependency
    per_vm_hook="$hook_path/qemu.d/$LIBVIRT_DOMAIN_NAME/prepare/begin"
    sudo mkdir -p "$per_vm_hook"
    sudo tee "$per_vm_hook/civ_swtpm.sh" &>/dev/null <<EOF
#!/usr/bin/env bash
#
# Copyright (c) 2023 Intel Corporation.
# All rights reserved.
#
systemctl start $service_file

EOF
    sudo chmod +x "$per_vm_hook/civ_swtpm.sh"

    # Create per-VM hook for stop dependencies
    per_vm_hook="$hook_path/qemu.d/$LIBVIRT_DOMAIN_NAME/release/end"
    sudo mkdir -p "$per_vm_hook"
    sudo tee "$per_vm_hook/civ_swtpm.sh" &>/dev/null <<EOF
#!/usr/bin/env bash
#
# Copyright (c) 2023 Intel Corporation.
# All rights reserved.
#
systemctl stop $service_file
EOF
    sudo chmod +x "$per_vm_hook/civ_swtpm.sh"
    # End civ dependency setup: swtpm

    # copy Celadon built OVMF_4M if any
    edk2_build_fv="$RELFILE_OUT/edk2/Build/OvmfX64/DEBUG_GCC5/FV"
    if [[ -f "$edk2_build_fv/OVMF_CODE.fd" && \
          -f "$edk2_build_fv/OVMF_VARS.fd" ]]; then
        mkdir -p "$tmp_folder_path/OVMF"
        cp "$edk2_build_fv/OVMF_CODE.fd" "$edk2_build_fv/OVMF_VARS.fd" "$tmp_folder_path/OVMF/"
    else
        echo "No EDK2 build in releasefiles decompress dest folder: $RELFILE_OUT"
        return 255
    fi

    if [[ -z $(which mcopy) ]]; then
        sudo apt install -y mtools
    fi

    if [[ -d "$decompress" ]]; then
        rm -rf "$decompress"
    fi
    mkdir "$decompress"
    if ! unzip "$flashfiles" -d "$decompress"; then
        echo "Error: Unable to unzip flashfiles archive provided."
        return 255
    fi

    if [[ -f "$decompress/boot.img" ]]; then
        G_size=$((1<<32))
        local -a decompress_files=()
        mapfile -t decompress_files < <(find "$decompress" -maxdepth 1 -type f -printf "%f\n")
        for i in "${decompress_files[@]}"; do
            size=$(stat -c %s "$decompress/$i")
            if [[ $size -gt $G_size ]]; then
                echo "Split $i due to its size bigger than 4G"
                split --bytes=$((G_size-1)) --numeric-suffixes "$decompress/$i" "$decompress/$i.part"
                rm "$decompress/$i"
            fi
        done

        dd if=/dev/zero of="$tmp_folder_path/flash.vfat" bs=63M count=160
        mkfs.vfat "$tmp_folder_path/flash.vfat"
        if ! mcopy -i "$tmp_folder_path/flash.vfat" "$decompress"/* ::; then
            echo "Error: unable to create flash.vfat image."
            return 255
        fi
        
    else
        echo "Error: no boot.img found in decompressed archive"
        return 255
    fi

    rm -rf "$decompress"

    # Copy created img folder to dest
    sudo mkdir -p "$folder_path"
    sudo cp -R "$tmp_folder_path"/* "$folder_path/"
    rm -rf "$tmp_folder_path"

    return 0
}

function create_android_vm_xml() {
    if [[ "$#" -eq "2" && -n ${1+x} && -n "$1" && -n ${2+x} && -n "$2" ]]; then
        if [[ "$1" != "android" ]]; then
            echo "Creating Android VM XML..."
            local newdomain=$1
            local platform=$2
            local xmlpath
            xmlpath=$(realpath "$scriptpath/../../platform/$platform/libvirt_xml")
            local -a xmlfiles=()
            mapfile -t xmlfiles < <(find "$xmlpath" -iname "android_*.xml")
            local max_vfs
            max_vfs=$(</sys/bus/pci/devices/0000:00:02.0/sriov_totalvfs)
            local -a used_vfs=()
            if [[ ! -d "$xmlpath" ]]; then
                echo "Cannot find platform $platform libvirt_xml path $xmlpath!"
                return 255
            fi
            local -a sriovxmlfiles=()
            mapfile -t sriovxmlfiles < <(find "$xmlpath" -type f -iname \*_sriov.xml -exec grep -le 'id=\"http:\/\/www.android.com\/android-[0-9]*\/\"' {} \;)
            for file in "${sriovxmlfiles[@]}"; do
                local vf
                vf=$(xmllint --xpath "string(//domain/devices/hostdev/source/address[@domain='0' and @bus='0' and @slot='2']/@function)" "$file")
                used_vfs+=("$vf")
            done
            for file in "${xmlfiles[@]}"; do
                local filename
                filename=$(basename "$file")
                local variant
                variant=$(echo "$filename" | awk -F[_.] '{ print $2 }')
                local newfilename="$newdomain""_""$variant.xml"
                echo "Creating $newfilename from $file"
                cp "$file" "$xmlpath/$newfilename"
                # update paths etc for new domain
                sed -i "s|$LIBVIRT_DEFAULT_IMAGES_PATH/android/|$LIBVIRT_DEFAULT_IMAGES_PATH/$newdomain/|" "$xmlpath"/"$newfilename"
                if [ "$variant" == "install" ]; then
                    sed -i -r "s|<name>(.*)</name>|<name>""$newdomain""_install""</name>|" "$xmlpath"/"$newfilename"
                else
                    sed -i -r "s|<name>(.*)</name>|<name>$newdomain</name>|" "$xmlpath"/"$newfilename"
                fi
                sed -i -r "s|android-serial0.log|$newdomain-serial0.log|" "$xmlpath"/"$newfilename"
                # generate a random mac address
                local sigbyte
                sigbyte=$(od -txC -An -N1 /dev/random | tr -d '[:space:]')
                sigbyte=$(printf "%02x\n" "$(( 0x$sigbyte & ~3 ))")
                local macbytes
                macbytes="$sigbyte$(od -txC -An -N5 /dev/random)"
                local macstr
                macstr=$(echo "$macbytes" | tr ' ' :)
                xmlstarlet ed -L --update "//domain/devices/interface[@type='network']/mac/@address" --value "$macstr" "$xmlpath/$newfilename"
                if [ "$variant" == "sriov" ]; then
                    # set to unused VF of same os
                    local -a new_vf
                    mapfile -t new_vf < <(comm -13 <(printf '%s\n' "${used_vfs[@]}" | LC_ALL=C sort) <(seq 1 "$max_vfs"))
                    xmlstarlet ed -L --update "//domain/devices/hostdev/source/address[@domain='0' and @bus='0' and @slot='2']/@function" --value "${new_vf[0]}" "$xmlpath"/"$newfilename"
                    used_vfs+=("${new_vf[0]}")
                fi
            done
        fi
    fi
}

function install_android_vm() {
    if [[ "$#" -eq "2" && -n ${1+x} && -n "$1" && -n ${2+x} && -n "$2" ]]; then
        echo "Starting Android VM installation..."
        local name=$1
        local platform=$2
        local xmlpath
        xmlpath=$(realpath "$scriptpath"/../../platform/"$platform"/libvirt_xml)
        local xmlname="$name""_install"
        local xmlfile
        xmlfile=$(realpath "$xmlpath/$xmlname.xml")
        if [[ ! -d "$xmlpath" || ! -f "$xmlfile" ]]; then
            echo "Cannot find $xmlname.xml in platform $platform libvirt_xml path $xmlpath!"
            return 255
        fi
        if sudo virsh list --all | grep -q "$name""_install"; then
            sudo virsh undefine --nvram "$name""_install"
        fi
        sudo virsh list --all | grep "$name""_install"
        sudo virsh define "$xmlfile" || return 255
        echo "Installing Android into VM storage"
        sudo virsh start "$xmlname" || return 255
        sudo virsh console "$xmlname" || return 255
        sudo virsh undefine --nvram "$xmlname" || return 255
    fi
}

function update_launch_multios() {
    if [[ "$#" -eq "2" && -n ${1+x} && -n "$1" && -n ${2+x} && -n "$2" ]]; then
        if [[ "$1" != "android" ]]; then
            local name=$1
            local platform=$2
            echo "Add domain $name for platform $platform launch_multios.sh"
            local file
            file=$(realpath "$scriptpath/../../platform/$platform/launch_multios.sh")
            if [ ! -f "$file" ]; then
                echo "Cannot find $file for platform $platform!"
                return 255
            fi
            if ! grep -Fq "[\"$name\"]=" "$file"; then
                sed -i -e "/\[\"android\"\]=/i \
                    \[\"$name\"\]=\"""$name""_sriov.xml\"" "$file"
            fi
        fi
    fi
}


function get_supported_platform_names() {
    local -n arr=$1
    local -a platpaths
    mapfile -t platpaths < <(find "$scriptpath/../../platform/" -maxdepth 1 -mindepth 1 -type d)
    for p in "${platpaths[@]}"; do
        arr+=( "$(basename "$p")" )
    done
}

function set_platform_name() {
    local -a platforms=()
    local platform

    platform=$1
    get_supported_platform_names platforms

    for p in "${platforms[@]}"; do
        if [[ "$p" == "$platform" ]]; then
            PLATFORM_NAME="$platform"
            return
        fi
    done

    echo "Error: $platform is not a supported platform"
    return 255
}

function invoke_platform_android_setup() {
    local platform=$1
    local osname
    osname=$(basename "$scriptpath")
    local platpath="$scriptpath/../../platform/$platform/guest_setup/$osname"
    if [ -d "$platpath" ] ; then
        platpath=$(realpath "$platpath")
        if [ -f "$platpath/android_setup.sh" ]; then
            rscriptpath=$(realpath "$platpath/android_setup.sh")
            echo "Invoking $platform script $rscriptpath"
            # shellcheck source=/dev/null
            source "$rscriptpath"
        fi
    fi
}

function show_help() {
    local platforms=()

    printf "%s [-h] [-f] [-n] [-p] [-r] [-t] [--disk-size] [--noinstall] [--forceclean] [--dupxml] [--qemufromsrc]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Installs Celadon system dependencies and create android vm images from CIV releasefiles archive to dest folder %s/<vm_domain_name>\n" "$LIBVIRT_DEFAULT_IMAGES_PATH"
    printf "Options:\n"
    printf "\t-h            Show this help message\n"
    printf "\t-r            Celadon releasefiles archive file. \"-r caas-releasefiles-userdebug.tar.gz\". If option is present, any existing dest folder will be deleted.\n"
    printf "\t-t            Dest folder to decompress releasefiles archive into. Default: \"-t ./caas-releasefiles\"\n"
    printf "\t-f            Celadon flashfiles zip archive file. \"Default is auto set to caas-flashfiles-xxxx.zip as found in dest folder specified by -t option\"\n"
    printf "\t-n            Android vm libvirt domain name. Default: \"-n android\"\n"
    printf "\t-p            specific platform to setup for, eg. \"-p client \"\n"
    printf "\t              Accepted values:\n"
    get_supported_platform_names platforms
    for p in "${platforms[@]}"; do
    printf "\t                %s\n" "$(basename "$p")"
    done
    printf "\t--disk-size   Disk storage size of Android vm in GiB, default is 40 GiB\n"
    printf "\t--noinstall   Only rebuild Android per vm required images and data output. Needs folder specified by -t option to be present and with valid contents.\n"
    printf "\t--forceclean  Delete android VM dest folder if exists. Default not enabled\n"
    printf "\t--dupxml      Duplicate Android guest XM xmls for this VM (when not using \"-n android\")\n"
    printf "\t--qemufromsrc Rebuild qemu from source and install (overwrites existing platform BSP installation. Do not use if unsure.)\n"
    printf "\t--suspend     Enable Android autosuspend \n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit 0
                ;;

            -n)
                LIBVIRT_DOMAIN_NAME="$2"
                shift
                ;;

            -r)
                setup_relfiles_path "$2" || return 255
                shift
                ;;

            -t)
                RELFILE_OUT=$(realpath "$2")
                shift
                ;;

            -f)
                setup_zip_flashfiles_path "$2"
                shift
                ;;

            -p)
                set_platform_name "$2" || return 255
                shift
                ;;

            --disk-size)
                SETUP_DISK_SIZE="$2"
                shift
                ;;

            --noinstall)
                NOINSTALL=1
                ;;

            --forceclean)
                FORCECLEAN=1
                ;;

            --dupxml)
                DUPXML=1
                ;;

            --qemufromsrc)
                ENABLE_QEMU_FROM_SRC=1
                ;;

            --suspend)
                ENABLE_SUSPEND="true"
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
    # do something
    echo ""
}

#-------------    main processes    -------------
trap 'cleanup' EXIT
trap 'error ${LINENO} "$BASH_COMMAND"' ERR

parse_arg "$@" || exit 255
if [[ -z "${LIBVIRT_DOMAIN_NAME+x}" || -z "$LIBVIRT_DOMAIN_NAME" ]]; then
	echo "Error: valid VM domain name needed"
    show_help
    exit 255
fi
if [[ -z "${PLATFORM_NAME+x}" || -z "$PLATFORM_NAME" ]]; then
	echo "Error: valid platform name required"
    show_help
    exit 255
fi
if [[ -d "$LIBVIRT_DEFAULT_IMAGES_PATH/$LIBVIRT_DOMAIN_NAME" && "$FORCECLEAN" != "1" ]]; then
    echo "VM domain($LIBVIRT_DOMAIN_NAME) images already exists! Use --forceclean to overwrite or create new domain name."
    show_help
    exit 255
fi
if ! [[ $SETUP_DISK_SIZE =~ ^[0-9]+$ ]]; then
    echo "Invalid input disk size"
    exit 255
fi

check_host_distribution || exit 255

uncompress_relfiles || exit 255
if [[ -z "${FLASHFILES_ZIP+x}" || -z "$FLASHFILES_ZIP" ]]; then
    setup_zip_flashfiles_path "$(find "$RELFILE_OUT" -iname caas-flashfiles\*.zip)" || exit 255
fi
print_info
if [[ "$NOINSTALL" -ne "1" ]]; then
    install_dep || exit 255
fi
setup_android_images || exit 255
# create new xml for new domains as necessary
if [[ "$DUPXML" -eq "1" ]]; then
    sudo apt install -y xmlstarlet
    create_android_vm_xml "$LIBVIRT_DOMAIN_NAME" "$PLATFORM_NAME" || exit 255
fi
# Platform specific android guest setup
# invoke platform/<plat>/guest_setup/android/setup_xxxx.sh scripts
invoke_platform_android_setup "$PLATFORM_NAME" || exit 255

# Run Android installation
install_android_vm "$LIBVIRT_DOMAIN_NAME" "$PLATFORM_NAME" || exit 255

# add new Android VM to launch_multios.sh
update_launch_multios "$LIBVIRT_DOMAIN_NAME" "$PLATFORM_NAME" || exit 255

echo "$(basename "${BASH_SOURCE[0]}") done"
exit 0

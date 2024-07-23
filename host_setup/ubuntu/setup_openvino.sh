#!/bin/bash

# Copyright (c) 2024 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error $(realpath ${BASH_SOURCE[0]}) line ${LINENO}: $BASH_COMMAND"' ERR

#---------      Global variable     -------------------
reboot_required=${reboot_required:=0}
script=$(realpath "${BASH_SOURCE[0]}")
LOGTAG=$(basename "$script")
LOG_FILE=${LOG_FILE:="/tmp/$LOGTAG.log"}
SETUP_DEBUG=${SETUP_DEBUG:=0}

declare -a TMP_FILES
TMP_FILES=()

#OPENVINO_VIRT_ENV_NAME='openvino_env'
declare -A OPENVINO_REL=(
  ['version']='2024.1.0'
  ['ubuntu_version_supported']='22.04'
  ['openvino_archive']='https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.1/linux/l_openvino_toolkit_ubuntu22_2024.1.0.15008.f4afc983258_x86_64.tgz'
)

INSTALL_NPU=0
declare -A LINUX_NPU_DRV_REL=(
  ['version']="v1.2.0"
  ['ubuntu_version_supported']='22.04'
  ['intel-driver-compiler-npu']='https://github.com/intel/linux-npu-driver/releases/download/v1.2.0/intel-driver-compiler-npu_1.2.0.20240404-8553879914_ubuntu22.04_amd64.deb'
  ['intel-fw-npu']='https://github.com/intel/linux-npu-driver/releases/download/v1.2.0/intel-fw-npu_1.2.0.20240404-8553879914_ubuntu22.04_amd64.deb'
  ['intel-level-zero-npu']='https://github.com/intel/linux-npu-driver/releases/download/v1.2.0/intel-level-zero-npu_1.2.0.20240404-8553879914_ubuntu22.04_amd64.deb'
  ['level-zero']='https://github.com/oneapi-src/level-zero/releases/download/v1.16.1/level-zero_1.16.1+u22.04_amd64.deb'
)

INSTALL_NEO=0
declare -A COMPUTE_RUNTIME_REL=(
  ['version']='24.13.29138.7'
  ['igc-version']='1.0.16510.2'
  ['gmmlib-version']='22.3.18'
  ['ubuntu_version_supported']='22.04'
  ['intel-igc-core']='https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.16510.2/intel-igc-core_1.0.16510.2_amd64.deb'
  ['intel-igc-opencl']='https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.16510.2/intel-igc-opencl_1.0.16510.2_amd64.deb'
  ['intel-level-zero-gpu']='https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/intel-level-zero-gpu_1.3.29138.7_amd64.deb'
  ['intel-opencl-icd']='https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/intel-opencl-icd_24.13.29138.7_amd64.deb'
  ['intel-gmmlib']='https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/libigdgmm12_22.3.18_amd64.deb'
  ['intel-gmmlib-dev']='https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/libigdgmm-dev_22.3.18_amd64.deb'
)

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
        dpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -d "$dpath" ]]; then
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
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f "$fpath" || ! -s "$fpath" ]]; then
            echo "Error: $fpath invalid/zero sized" | tee -a "$LOG_FILE"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

declare -F "log_func" >/dev/null || log_func() {
    if declare -F "$1" >/dev/null; then
        start=$(date +%s)
        echo -e "$(date)   start:   \t$1" >> "$LOG_FILE"
        "$@"
        ec=$?
        end=$(date +%s)
        echo -e "$(date)   end ($((end-start))s):\t$1" >> "$LOG_FILE"
        return $ec
    else
        echo "Error: $1 is not a function"
        exit 255
    fi
}

function check_os() {
    if [[ -z "${1+x}" || -z "$1" ]]; then
        echo "ERROR: invalid Ubuntu version input to check for" | tee -a "$LOG_FILE"
        return 255
    fi

    # Check OS
    local version
    version=$(cat /proc/version)
    if [[ ! "$version" =~ "Ubuntu" ]]; then
        echo "Error: Only Ubuntu is supported" | tee -a "$LOG_FILE"
        return 255
    fi

    # Check Ubuntu version
    req_version=$1
    cur_version=$(lsb_release -rs)
    if [[ "$cur_version" != "$req_version" ]]; then
        echo "Error: Ubuntu $cur_version is not supported" | tee -a "$LOG_FILE"
        echo "Error: Please use Ubuntu $req_version" | tee -a "$LOG_FILE"
        return 255
    fi
}

function install_dep() {
  which sha256sum > /dev/null || sudo apt install -y coreutils
}

function setup_openvino_npu() {
    local dest_tmp_path
    dest_tmp_path=$(realpath "/tmp/linux_npu_driver_install")

    log_func check_os "${LINUX_NPU_DRV_REL["ubuntu_version_supported"]}" || return 255

    if [[ -d "$dest_tmp_path" ]]; then
      rm -rf "$dest_tmp_path"
    fi
    mkdir -p "$dest_tmp_path"
    TMP_FILES+=("$dest_tmp_path")
    # Linux NPU driver release
    sudo dpkg --purge --force-remove-reinstreq intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu level-zero
    echo "INFO: Downloading Linux NPU Driver release ${LINUX_NPU_DRV_REL["version"]}" | tee -a "$LOG_FILE"
    wget -O "$dest_tmp_path/intel-driver-compiler-npu.deb" "${LINUX_NPU_DRV_REL["intel-driver-compiler-npu"]}" || return 255
    check_file_valid_nonzero "$dest_tmp_path/intel-driver-compiler-npu.deb"
    wget -O "$dest_tmp_path/intel-fw-npu.deb" "${LINUX_NPU_DRV_REL["intel-fw-npu"]}" || return 255
    check_file_valid_nonzero "$dest_tmp_path/intel-fw-npu.deb"
    wget -O "$dest_tmp_path/intel-level-zero-npu.deb" "${LINUX_NPU_DRV_REL["intel-level-zero-npu"]}" || return 255
    check_file_valid_nonzero "$dest_tmp_path/intel-level-zero-npu.deb"
    wget -O "$dest_tmp_path/level-zero.deb" "${LINUX_NPU_DRV_REL["level-zero"]}" || return 255
    check_file_valid_nonzero "$dest_tmp_path/level-zero.deb"

    echo "INFO: Installing Linux NPU Driver release ${LINUX_NPU_DRV_REL["version"]}" | tee -a "$LOG_FILE"
    sudo apt install -y libtbb12
    sudo dpkg -i "$dest_tmp_path"/*.deb

    # add user to the render group
    local username=""
    if [[ (-z "${SUDO_USER+x}" || -z "$SUDO_USER") && (-n "${USER+x}" && -n "$USER")  ]]; then
        echo "INFO: Add $USER to group render." | tee -a "$LOG_FILE"
        username="$USER"
    else
        if [[ -n "${SUDO_USER+x}" && -n "$SUDO_USER" ]]; then
            echo "INFO: Add $SUDO_USER to group render." | tee -a "$LOG_FILE"
            username="$SUDO_USER"
        fi
    fi
    if [[ -n "$username" ]]; then
        sudo usermod -a -G render "$username"
    fi

    echo 'SUBSYSTEM=="accel", KERNEL=="accel*", GROUP="render", MODE="0660"' | sudo tee /etc/udev/rules.d/10-intel-vpu.rules
    if [[ -c /dev/accel/accel0 ]]; then
        sudo chown root:render /dev/accel/accel0
        sudo chmod g+rw /dev/accel/accel0

        sudo udevadm control --reload-rules
        sudo udevadm trigger --subsystem-match=accel
    fi

    reboot_required=1

    #if sudo journalctl -k -o cat --no-pager | grep 'Initialized intel_vpu [0-9].[0-9].[0-9] [0-9]* for 0000:00:0b.0 on minor 0'; then
    #    bash -c 'python3 -c "from openvino import Core; print(Core().available_devices)"' | tee -a "$LOG_FILE"
    #fi
}

function download_url_checksum() {
    if [[ -z "${1+x}" || -z "$1" ]]; then
      echo "Error: no dest path provided" | tee -a "$LOG_FILE"
      return 255
    fi
    local dest_path=$1
    if [[ -z "${2+x}" || -z "$2" ]]; then
      echo "Error: no source url provided" | tee -a "$LOG_FILE"
      return 255
    fi
    local src_url=$2
    local src_sha256sum_url
    if [[ $# -eq 3 && -n "${3+x}" && -n "$3" ]]; then
        src_sha256sum_url=$3
    else
        src_sha256sum_url=""
    fi
    if [[ -d "$dest_path" ]]; then
        local fname
        fname=$(basename "$src_url")
        dest_path="$dest_path/$fname"
    fi

    local maxcount=10
    local count=0
    while [[ "$count" -lt "$maxcount" ]]; do
      count=$((count+1))
      echo "$count: Download $src_url"
      if ! curl -JL --connect-timeout 10 --output "$dest_path" "$src_url"; then
        # attempt again with proxy enabled except for localhost
        if ! curl -JL --noproxy "localhost,127.0.0.1" --connect-timeout 10 --output "$dest_path" "$src_url"; then
          # attempt again without proxy
          if ! curl -JL --noproxy '*' --connect-timeout 10 --output "$dest_path" "$src_url"; then
            echo "Unable download $src_url. Check internet connection."
            return 255
          fi
        fi
      fi
      if [[ -n "$src_sha256sum_url" ]]; then
        wget -O "$dest_path.sha256" "$src_sha256sum_url" || return 255
        if ! curl --connect-timeout 10 --output "$dest_path.sha256" "$src_sha256sum_url"; then
          # attempt again with proxy enabled except for localhost
          if ! curl --noproxy "localhost,127.0.0.1" --connect-timeout 10 --output "$dest_path.sha256" "$src_sha256sum_url"; then
            # attempt again without proxy
            if ! curl --noproxy '*' --connect-timeout 10 --output "$dest_path.sha256" "$src_sha256sum_url"; then
              echo "Unable download $src_sha256sum_url. Check internet connection."
              return 255
            fi
          fi
        fi
        local isochksum
        isochksum=$(sha256sum "$dest_path" | awk '{print $1}')
        if grep -q "$isochksum" < "$dest_path.sha256"; then
          # downloaded iso is okay.
          echo "Verified sha256 checksum is as expected: $isochksum"
          break
        fi
      else
        break
      fi
    done
    if [[ $count -ge $maxcount ]]; then
      echo "error: download $src_url exceeded max tries." | tee -a "$LOG_FILE"
      return 255
    fi
    return 0
}

function setup_openvino() {
    local dest_tmp_path
    dest_tmp_path=$(realpath "/tmp/linux_openvino_install")

    log_func check_os "${OPENVINO_REL["ubuntu_version_supported"]}" || return 255

    if [[ -d "$dest_tmp_path" ]]; then
        rm -rf "$dest_tmp_path"
    fi
    mkdir -p "$dest_tmp_path"
    TMP_FILES+=("$dest_tmp_path")

    echo "INFO: Installing Openvino ${OPENVINO_REL["version"]} from archive" | tee -a "$LOG_FILE"
    download_url_checksum "$dest_tmp_path/${OPENVINO_REL["version"]}.tgz" "${OPENVINO_REL["openvino_archive"]}" "${OPENVINO_REL["openvino_archive"]}.sha256" || return 255

    tar -xf "$dest_tmp_path/${OPENVINO_REL["version"]}.tgz" -C "$dest_tmp_path" || return 255
    if [[ ! -d /opt/intel ]]; then
        sudo mkdir /opt/intel
    fi
    check_dir_valid /opt/intel
    local extracted_folder
    extracted_folder=$(find "$dest_tmp_path" -name "l_openvino_toolkit_ubuntu*")
    extracted_folder=$(realpath "$extracted_folder")
    if [[ -d "/opt/intel/openvino_${OPENVINO_REL["version"]}" ]]; then
        sudo rm -rf "/opt/intel/openvino_${OPENVINO_REL["version"]}"
    fi
    sudo mv "$extracted_folder" "/opt/intel/openvino_${OPENVINO_REL["version"]}"
    cd "/opt/intel/openvino_${OPENVINO_REL["version"]}"
    sudo -E ./install_dependencies/install_openvino_dependencies.sh -y || return 255
    python3 -m pip install -r ./python/requirements.txt || return 255
    cd -

    local -a ver
    mapfile -td ' ' ver <<< "${OPENVINO_REL["version"]//./ }"
    cd /opt/intel
    if [[ -L "/opt/intel/openvino_${ver[0]}" ]]; then
        sudo unlink "/opt/intel/openvino_${ver[0]}"
    fi
    sudo ln -s "openvino_${OPENVINO_REL["version"]}" "openvino_${ver[0]}"
    cd -
    if ! grep -Fq  "source /opt/intel/openvino_${ver[0]}/setupvars.sh" /etc/bash.bashrc; then
        # Added to first line of bash.bashrc so that it will be called even for non interactive shell
        sudo sed -i "1s:^:source /opt/intel/openvino_${ver[0]}/setupvars.sh\n:" /etc/bash.bashrc
    fi
    # do not perform echo if in non interactive shell
    sudo sed -i "s/^echo \"\[setupvars.sh\] OpenVINO environment initialized\"/\[ ! -z \"\$PS1\" \] \&\& echo \"\[setupvars.sh\] OpenVINO environment initialized\"/" "/opt/intel/openvino_${ver[0]}/setupvars.sh"

}

function setup_neo() {
    local dest_tmp_path
    dest_tmp_path=$(realpath "/tmp/linux_compute_runtime_install-${COMPUTE_RUNTIME_REL["version"]}")

    log_func check_os "${COMPUTE_RUNTIME_REL["ubuntu_version_supported"]}" || return 255

    if [[ -d "$dest_tmp_path" ]]; then
        rm -rf "$dest_tmp_path"
    fi
    mkdir -p "$dest_tmp_path"
    TMP_FILES+=("$dest_tmp_path")

    local installed_igc_ver
    installed_igc_ver=$(apt list --installed | grep "intel-igc-core" | awk '{print $2}')
    if [[ -z "$installed_igc_ver" || (-n "$installed_igc_ver" && "$installed_igc_ver" < "${COMPUTE_RUNTIME_REL['igc-version']}") ]]; then
        if [[ -n "$installed_igc_ver" ]]; then
            echo "INFO: Intel intel-graphics-compiler ver: $installed_igc_ver. Installing: ${COMPUTE_RUNTIME_REL['igc-version']}" | tee -a "$LOG_FILE"
        fi
        download_url_checksum "$dest_tmp_path" "${COMPUTE_RUNTIME_REL["intel-igc-core"]}" || return 255
        download_url_checksum "$dest_tmp_path" "${COMPUTE_RUNTIME_REL["intel-igc-opencl"]}" || return 255
    fi
    download_url_checksum "$dest_tmp_path" "${COMPUTE_RUNTIME_REL["intel-level-zero-gpu"]}" || return 255
    download_url_checksum "$dest_tmp_path" "${COMPUTE_RUNTIME_REL["intel-opencl-icd"]}" || return 255
    local installed_gmmlib_ver
    installed_gmmlib_ver=$(apt list --installed | grep "libigdgmm12" | awk '{print $2}')
    if [[ -z "$installed_gmmlib_ver" || (-n "$installed_gmmlib_ver" && "$installed_gmmlib_ver" < "${COMPUTE_RUNTIME_REL['gmmlib-version']}") ]]; then
        if [[ -n "$installed_gmmlib_ver" ]]; then
            echo "INFO: Intel gmmlib ver: $installed_gmmlib_ver. Installing: ${COMPUTE_RUNTIME_REL['gmmlib-version']}" | tee -a "$LOG_FILE"
        fi
        download_url_checksum "$dest_tmp_path" "${COMPUTE_RUNTIME_REL["intel-gmmlib"]}" || return 255
        download_url_checksum "$dest_tmp_path" "${COMPUTE_RUNTIME_REL["intel-gmmlib-dev"]}" || return 255
    fi

    for fname in "$dest_tmp_path"/*.deb; do
        check_file_valid_nonzero "$fname"
    done
    echo "INFO: Installing Intel compute-runtime ${COMPUTE_RUNTIME_REL["version"]}" | tee -a "$LOG_FILE"
    sudo dpkg -i "$dest_tmp_path"/*.deb
}

function show_help() {
    printf "%s [-h] [--npu]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Options:\n"
    printf "\t-h\tshow this help message\n"
    printf "\t--npu\tInstall NPU device driver for OpenVINO\n"
    printf "\t--neo\tInstall Intel(R) Graphics Compute Runtime for oneAPI Level Zero and OpenCL(TM) Driver\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help | tee -a "$LOG_FILE"
                exit
                ;;

            --npu)
                INSTALL_NPU=1
                ;;

            --neo)
                INSTALL_NEO=1
                ;;

            -?*)
                echo "Error: Invalid option: $1" | tee -a "$LOG_FILE"
                show_help
                return 255
                ;;
            *)
                echo "Error: Unknown option: $1" | tee -a "$LOG_FILE"
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
        if [[ -n "${USER+x}" && -n "$USER" ]]; then
           if [[ "$fowner" == "$USER" ]]; then
                rm -rf "$f"
            else
                sudo rm -rf "$f"
            fi
        fi
      fi
    done
}

trap 'cleanup' EXIT
#-------------    main processes    -------------
parse_arg "$@" || exit 255

log_func install_dep || exit 255
log_func setup_openvino || exit 255
if [[ $INSTALL_NPU -eq 1 ]]; then
    log_func setup_openvino_npu || exit 255
fi
if [[ $INSTALL_NEO -eq 1 ]]; then
    if apt list --installed | grep "intel-opencl-icd"; then
        installed_neo_ver=$(apt list --installed | grep "intel-opencl-icd" | awk '{print $2}')
        if [[ -z "$installed_neo_ver" || (-n "$installed_neo_ver" && "$installed_neo_ver" < "${COMPUTE_RUNTIME_REL['version']}") ]]; then
            if [[ -n "$installed_neo_ver" ]]; then
                echo "INFO: Intel compute-runtime intel-opencl-icd ver: $installed_neo_ver. Installing: ${COMPUTE_RUNTIME_REL['version']}" | tee -a "$LOG_FILE"
            fi
            log_func setup_neo || exit 255
        else
            echo "INFO: Intel compute-runtime intel-opencl-icd version $installed_neo_ver already installed" | tee -a "$LOG_FILE"
        fi
    else
        echo "INFO: Installing Intel compute-runtime intel-opencl-icd version ${COMPUTE_RUNTIME_REL['version']}" | tee -a "$LOG_FILE"
        log_func setup_neo || exit 255
    fi
fi

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

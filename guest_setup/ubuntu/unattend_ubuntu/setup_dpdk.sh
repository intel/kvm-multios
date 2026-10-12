#!/bin/bash

# Copyright (c) 2026 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#-------------    functions    -------------
function package_is_unconfigured() {
    local pkg_name="$1"
    local pkg_status

    pkg_status=$(dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null || true)
    [[ "$pkg_status" == install* && "$pkg_status" != "install ok installed" ]]
}

# Ubuntu 26.04 guest flow runs setup_openvino.sh --neo before DPDK.
# If OpenVINO/NEO leaves dpkg partially configured, apt install of DPDK fails.
# Keep this as a no-op safeguard when package state is already healthy.
function repair_apt_state_for_ubuntu_2604() {
    local osver
    osver=$(lsb_release -rs 2>/dev/null || true)
    if [[ "$osver" != "26.04" ]]; then
        return 0
    fi

    local needs_repair=0
    local dpkg_audit
    dpkg_audit=$(dpkg --audit 2>/dev/null || true)
    if [[ -n "$dpkg_audit" ]]; then
        needs_repair=1
    fi

    local -a ov_pkg_candidates=(
        "intel-igc-opencl-2"
        "intel-igc-core-2"
        "intel-ocloc"
        "intel-opencl-icd"
        "libigdgmm12"
        "libze-intel-gpu1"
    )
    local pkg
    for pkg in "${ov_pkg_candidates[@]}"; do
        if package_is_unconfigured "$pkg"; then
            needs_repair=1
            break
        fi
    done

    if [[ "$needs_repair" -eq 0 ]]; then
        return 0
    fi

    echo "INFO: Ubuntu 26.04 broken package state detected before DPDK install. Attempting repair."
    sudo apt-get -y --fix-broken install || true

    # Remove only partially installed OpenVINO runtime packages that still block apt.
    local purged=0
    for pkg in "${ov_pkg_candidates[@]}"; do
        if package_is_unconfigured "$pkg"; then
            echo "INFO: Purging unresolved package: $pkg"
            sudo dpkg --purge --force-remove-reinstreq "$pkg" || true
            purged=1
        fi
    done

    if [[ "$purged" -eq 1 ]]; then
        sudo apt-get -y --fix-broken install || true
    fi
}

function install_dpdk() {
    local osver
    osver=$(lsb_release -rs 2>/dev/null || true)

    if [[ "$osver" == "26.04" ]]; then
        repair_apt_state_for_ubuntu_2604
    fi

    sudo apt-get update
    if sudo apt-get install -y dpdk dpdk-dev; then
        return 0
    fi

    if [[ "$osver" == "26.04" ]]; then
        echo "WARNING: Initial DPDK install failed on Ubuntu 26.04; retrying after apt-state repair."
        repair_apt_state_for_ubuntu_2604
        sudo apt-get update
        sudo apt-get install -y dpdk dpdk-dev
    fi
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

install_dpdk || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

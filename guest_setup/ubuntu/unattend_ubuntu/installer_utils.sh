#!/bin/bash

# Copyright (c) 2026 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

# Shared utility functions for extracting configuration from installer.sh files
# Used by both setup_bsp.sh and ubuntu_setup.sh

# Find installer.sh file if available
# Returns the path to installer.sh or empty string if not found
function find_installer_file() {
    # Look for installer.sh in /tmp (where it's downloaded during guest setup)
    # or in the same directory as this script (for standalone execution)
    if [[ -f "/tmp/installer.sh" ]]; then
        echo "/tmp/installer.sh"
        return 0
    fi

    local script_dir
    script_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
    if [[ -f "$script_dir/installer.sh" ]]; then
        echo "$script_dir/installer.sh"
        return 0
    fi

    return 1
}

# Extract PPA settings from installer file if available
# Modifies global variables: PPA_URLS, PPA_GPGS, PPA_WGET_NO_PROXY, PPA_APT_CONF, PPA_PIN, PPA_PIN_PRIORITY
# Requires: $LOGD for logging
# Parameters:
#   $1 - installer_path: Path to the installer.sh file
function extract_ppa_from_installer() {
    local installer_file="$1"

    if [[ -z "$installer_file" ]]; then
        return 1
    fi

    ${LOGD:-echo} "Processing installer file: $installer_file"

    # Get Ubuntu codename
    local ubuntu_codename
    ubuntu_codename=$(lsb_release -cs 2>/dev/null || echo "noble")

    # Detect installer type first
    # External installer uses ppa_url variable and download.01.org
    # Internal installer has full URLs directly in echo commands
    local installer_type="unknown"

    if grep -q 'ppa_url="https://download.01.org' "$installer_file" 2>/dev/null; then
        installer_type=external
        ${LOGD:-echo} "Detected external installer.sh format (download.01.org)"
    elif grep -E "echo.*deb.*(http|https)://.*$ubuntu_codename" "$installer_file" 2>/dev/null | \
         head -1 | \
         grep -qv download.01.org; then
        installer_type=internal
        ${LOGD:-echo} "Detected internal installer.sh format"
    else
        return 1
    fi

    # Extract PPA configuration based on installer type
    local ppa_repo_config=""

    if [[ "$installer_type" == "external" ]]; then
        # Extract ppa_url variable value
        local ppa_url
        ppa_url=$(grep -oP 'ppa_url="\Khttps://[^"]+' "$installer_file" 2>/dev/null | head -1)

        if [[ -z "$ppa_url" ]]; then
            return 1
        fi

        # Extract deb line components (everything after ${ppa_url})
        local deb_components
        deb_components=$(grep -E "echo.*deb.*\\\${ppa_url}" "$installer_file" 2>/dev/null | \
                        sed -n "s/.*deb[[:space:]]*\${ppa_url}[[:space:]]*\([^'\"]*\).*/\1/p" | \
                        sed "s/[[:space:]]*'[[:space:]]*\$//g" | \
                        sed "s|^/[[:space:]]*||" | \
                        sed 's/[[:space:]]*$//' | \
                        head -1)

        if [[ -z "$deb_components" ]]; then
            return 1
        fi

        ppa_repo_config="$ppa_url $deb_components"

    else
        # Internal installer: extract full URL from echo command
        local echo_command_line
        echo_command_line=$(grep -E "echo.*deb.*(http|https)://.*$ubuntu_codename" "$installer_file" 2>/dev/null | \
                           head -1)

        if [[ -z "$echo_command_line" ]]; then
            return 1
        fi

        # Extract everything after "deb " up to the closing quote or redirection
        ppa_repo_config=$(echo "$echo_command_line" | sed -n 's/.*deb[[:space:]]*\([^"]*\).*/\1/p')

        # Remove any file redirection (> /etc/apt/...) and clean up spacing
        ppa_repo_config=$(echo "$ppa_repo_config" | \
                         sed -e 's|[[:space:]]*>[[:space:]]*/etc/apt/.*||' \
                             -e 's|/[[:space:]]| |g' \
                             -e 's/[[:space:]]*$//')
    fi

    # Extract GPG key URLs from installer file
    # Look for wget commands that download .gpg files to /etc/apt/trusted.gpg.d/
    local gpg_urls=()
    local has_gpg_commands=0
    while IFS= read -r line; do
        has_gpg_commands=1
        local gpg_url
        gpg_url=$(echo "$line" | sed -n 's/.*wget[[:space:]]\+\([^[:space:]]*\.gpg\).*/\1/p')
        [[ -n "$gpg_url" ]] && gpg_urls+=("$gpg_url")
    done < <(grep -E "wget.*\.gpg.*-O /etc/apt/trusted.gpg.d/" "$installer_file" 2>/dev/null || true)

    # If installer has GPG commands but we didn't extract any URLs, parsing failed
    if [[ $has_gpg_commands -eq 1 && ${#gpg_urls[@]} -eq 0 ]]; then
        return 1
    fi

    # If no GPG URLs were extracted, use "auto" to let setup_overlay_ppa discover keys
    if [[ ${#gpg_urls[@]} -eq 0 ]]; then
        gpg_urls=("auto")
    fi

    # Determine proxy settings for wget based on repository type
    local wget_no_proxy=""
    if [[ "$installer_type" == "internal" ]]; then
        wget_no_proxy="--no-proxy"
    fi

    # Extract proxy settings for internal repositories
    local proxy_conf=()
    if [[ "$installer_type" == "internal" ]]; then
        ${LOGD:-echo} "Using internal PPA configuration"
        while IFS= read -r line; do
            local proxy_line
            proxy_line=$(echo "$line" | \
                sed -n 's/.*echo[[:space:]]*'\''\(Acquire::https::proxy::[^'\'']*\)'\''.*/\1/p' | \
                sed 's/\\"/"/g')
            [[ -n "$proxy_line" ]] && proxy_conf+=("$proxy_line")
        done < <(grep -E "echo.*Acquire::https::proxy::.*DIRECT" "$installer_file" 2>/dev/null || true)
    else
        ${LOGD:-echo} "Using external PPA configuration"
    fi

    # Extract PPA PIN from installer file
    local extracted_pin
    local pin_pattern='s/.*Pin:[[:space:]]*\(\(release[[:space:]]\+o=[^"\\]*\)\|\(origin[[:space:]]\+[^"\\]*\)\).*/\1/p'
    extracted_pin=$(grep -E 'echo.*Pin:' "$installer_file" 2>/dev/null | \
                   sed -n "$pin_pattern" | \
                   head -1 || true)

    # Extract PPA PIN Priority from installer file
    local extracted_priority
    extracted_priority=$(grep -E 'echo.*Pin-Priority:' "$installer_file" 2>/dev/null | \
                        sed -n 's/.*Pin-Priority:[[:space:]]*\([0-9]\+\).*/\1/p' | \
                        head -1 || true)

    # Verify all required settings were extracted successfully
    if [[ -z "$ppa_repo_config" || -z "$extracted_pin" || -z "$extracted_priority" ]]; then
        return 1
    fi

    # Update global variables with extracted settings
    PPA_URLS=("$ppa_repo_config")
    PPA_GPGS=("${gpg_urls[@]}")
    PPA_WGET_NO_PROXY=("$wget_no_proxy")
    PPA_APT_CONF=("${proxy_conf[@]}")
    PPA_PIN="$extracted_pin"
    PPA_PIN_PRIORITY="$extracted_priority"

    ${LOGD:-echo} "Successfully extracted and applied all PPA settings from installer file"
    ${LOGD:-echo} "PPA URL: ${PPA_URLS[0]}"
    ${LOGD:-echo} "PPA GPGS: ${PPA_GPGS[*]}"
    ${LOGD:-echo} "PPA WGET NO PROXY: ${PPA_WGET_NO_PROXY[*]}"
    ${LOGD:-echo} "PPA APT CONF: ${PPA_APT_CONF[*]}"
    ${LOGD:-echo} "PPA PIN: $PPA_PIN"
    ${LOGD:-echo} "PPA PIN Priority: $PPA_PIN_PRIORITY"

    return 0
}

# Extract package list from installer file
# Sets global variable: EXTRACTED_PACKAGES
# Requires: $LOGD for logging
function extract_packages_from_installer() {
    local installer_path="$1"

    # Look for package assignment in the format: package=("...")
    # Extract only the initial package=(...) assignment, ignore conditional additions
    local packages_line
    packages_line=$(grep -oP 'package=\("\K[^"]+' "$installer_path" 2>/dev/null | head -1)

    if [[ -z "$packages_line" ]]; then
        return 1
    fi

    # Store extracted packages in global variable
    EXTRACTED_PACKAGES="$packages_line"
    ${LOGD:-echo} "Extracted packages from installer: $EXTRACTED_PACKAGES"

    return 0
}

# Extract kernel version from installer file
# Sets global variable: EXTRACTED_KERNEL_VER
# Requires: $LOGD for logging
function extract_kernel_ver_from_installer() {
    local installer_path="$1"
    local prefer_rt=${2:-0}  # 0=prefer non-RT (default), 1=prefer RT

    # Look for kernel install commands in apt-get or kernelCmd assignments
    # Patterns: linux-headers-6.12-intel=version or linux-headers-6.12rt-intel=version
    # Explicitly match kernel type to --rt flag: RT kernel required if flag set, non-RT otherwise
    local kernel_line

    if [[ "$prefer_rt" == "1" ]]; then
        # Search for RT kernel only
        kernel_line=$(grep -E 'linux-headers-[0-9]+\.[0-9]+rt-intel=' "$installer_path" 2>/dev/null | head -1)

        if [[ -z "$kernel_line" ]]; then
            ${LOGD:-echo} "WARNING: RT kernel requested (--rt flag) but no RT kernel found in installer.sh"
            ${LOGD:-echo} "Expected pattern: linux-headers-X.Yrt-intel=version"
            return 1
        fi
    else
        # Search for non-RT kernel only
        kernel_line=$(grep -E 'linux-headers-[0-9]+\.[0-9]+-intel=' "$installer_path" 2>/dev/null | \
                     grep -v rt-intel | \
                     head -1)

        if [[ -z "$kernel_line" ]]; then
            ${LOGD:-echo} "WARNING: Non-RT kernel requested (default) but no non-RT kernel found in installer.sh"
            ${LOGD:-echo} "Expected pattern: linux-headers-X.Y-intel=version (without rt)"
            return 1
        fi
    fi

    # Extract kernel name and version (e.g., "6.12-intel=250924t142248z-r2")
    local kernel_with_ver
    kernel_with_ver=$(echo "$kernel_line" | grep -oP 'linux-headers-\K[0-9]+\.[0-9]+(rt)?-intel=[^\s"]+' | head -1)

    if [[ -z "$kernel_with_ver" ]]; then
        return 1
    fi

    # Store extracted kernel version in global variable
    EXTRACTED_KERNEL_VER="$kernel_with_ver"
    ${LOGD:-echo} "Extracted kernel version from installer: $EXTRACTED_KERNEL_VER"

    return 0
}

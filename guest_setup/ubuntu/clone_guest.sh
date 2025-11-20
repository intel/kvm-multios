#!/bin/bash

# Copyright (c) 2024-2025 Intel Corporation.
# All rights reserved.
#

set -Eeuo pipefail

#---------      Global variable     -------------------
LIBVIRT_DEFAULT_IMAGES_PATH=/var/lib/libvirt/images
NEW_DOMAIN_NAME=""
SOURCE_DOMAIN_NAME=""
SOURCE_XML=""
FORCECLEAN=0
FORCECLEAN_DOMAIN=0
PRESERVE_DATA=0
PRESERVE_PASSTHROUGH=0
IGPU_VF=0
IGPU_VF_FORCE=0
IGPU_VF_AUTO=1
IGPU_VF_SPECIFIED=0
IGPU_VF_FORCE_SPECIFIED=0
IGPU_VF_AUTO_SPECIFIED=0
PLATFORM_NAME=""
PLATFORM_ARG=""
DISPLAY_TYPE=""
SYS_STATE_REQUESTED=0
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
        if [[ $? -ne 0 || ! -f "$fpath" || ! -s "$fpath" ]]; then
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

    if [[ ! "$dist" =~ "Ubuntu" ]]; then
        echo "Error: only Ubuntu is supported!"
        return 255
    fi
}

function install_dep () {
    which xmlstarlet > /dev/null || sudo apt-get install -y xmlstarlet
    which xmllint > /dev/null || sudo apt-get install -y libxml2-utils
    which virt-clone > /dev/null || sudo apt-get install -y virtinst
}

function next_available_igpu_vf() {
    local max_vfs
    max_vfs=$(</sys/bus/pci/devices/0000:00:02.0/sriov_totalvfs)
    local -A defined_vf_map=()  # Map VF number to domain name (O(1) lookup)
    local -A static_vf_map=()   # Map VF number to filename (O(1) lookup)
    local IFS=$'\n'

    # Scan defined domains for VF usage
    local -a domains
    mapfile -t domains < <(virsh list --all --name | sed '/^[[:space:]]*$/d')
    for domain in "${domains[@]}"; do
        local domain_xml
        domain_xml=$(virsh dumpxml "$domain")
        # Get the domain sriov vf if defined
        local domain_vf_hex
        domain_vf_hex=$(xmllint --xpath \
            "string(//domain/devices/hostdev/source/address[@domain='0x0000' and @bus='0x00' and @slot='0x02']/@function)" \
            - <<<"$domain_xml")
        local domain_vf_num=$((domain_vf_hex))
        if [[ $domain_vf_num -gt 0 ]]; then
            defined_vf_map[$domain_vf_num]="$domain"
        fi
    done

    # Scan platform XML files for static VF assignments
    local -a platpaths
    mapfile -t platpaths < <(find "$scriptpath/../../platform/" -maxdepth 1 -mindepth 1 -type d)
    for platpath in "${platpaths[@]}"; do
        local xml_dir="$platpath/libvirt_xml"
        [[ ! -d "$xml_dir" ]] && continue

        local -a xml_files
        mapfile -t xml_files < <(find "$xml_dir" -maxdepth 1 -name "*.xml" -type f)
        for xml_file in "${xml_files[@]}"; do
            [[ ! -f "$xml_file" ]] && continue

            # Use single XPath that matches both hex and decimal formats
            local xml_vf_hex
            xml_vf_hex=$(xmllint --xpath \
                "string(//domain/devices/hostdev/source/address[(@domain='0x0000' or @domain='0') and \
                    (@bus='0x00' or @bus='0') and (@slot='0x02' or @slot='2')]/@function)" \
                "$xml_file" 2>/dev/null || echo "")

            [[ -z "$xml_vf_hex" || "$xml_vf_hex" == "0x0" || "$xml_vf_hex" == "0" ]] && continue

            local xml_vf_num=$((xml_vf_hex))
            if [[ $xml_vf_num -gt 0 && -z "${static_vf_map[$xml_vf_num]:-}" ]]; then
                static_vf_map[$xml_vf_num]="$(basename "$xml_file")"
            fi
        done
    done

    # Handle --igpu_vf_force: Use specified VF with warnings
    if [[ $IGPU_VF_FORCE -gt 0 ]]; then
        if [[ -n "${defined_vf_map[$IGPU_VF_FORCE]:-}" ]]; then
            echo "Warning: iGPU VF $IGPU_VF_FORCE already used by defined domain" \
                 "'${defined_vf_map[$IGPU_VF_FORCE]}', ignoring as force option is used" >&2
        fi
        if [[ -n "${static_vf_map[$IGPU_VF_FORCE]:-}" ]]; then
            echo "Warning: VF $IGPU_VF_FORCE is statically assigned in: ${static_vf_map[$IGPU_VF_FORCE]}" >&2
            echo "Warning: This may cause conflicts if the statically assigned domain is launched later." >&2
        fi
        echo "$IGPU_VF_FORCE"
        return 0
    fi

    # Handle --igpu_vf: Use specified VF only if available
    if [[ $IGPU_VF -gt 0 ]]; then
        if [[ -n "${defined_vf_map[$IGPU_VF]:-}" ]]; then
            echo "Error: iGPU VF $IGPU_VF already used by defined domain '${defined_vf_map[$IGPU_VF]}'" >&2
            echo "Hint: Use --igpu_vf_force $IGPU_VF to override" >&2
            return 1
        fi
        if [[ -n "${static_vf_map[$IGPU_VF]:-}" ]]; then
            echo "Error: iGPU VF $IGPU_VF is statically assigned in: ${static_vf_map[$IGPU_VF]}" >&2
            echo "Hint: Use --igpu_vf_force $IGPU_VF to override" >&2
            return 1
        fi
        echo "$IGPU_VF"
        return 0
    fi

    # Handle --igpu_vf_auto: Find first available VF
    # Step 1: Try to find VFs that are neither defined nor statically assigned
    local vf
    for (( vf=IGPU_VF_AUTO; vf<=max_vfs; vf++ )); do
        if [[ -z "${defined_vf_map[$vf]:-}" && -z "${static_vf_map[$vf]:-}" ]]; then
            echo "$vf"
            return 0
        fi
    done

    # Step 2: Fall back to statically assigned VFs (not used by defined domains)
    echo "Warning: No completely unused VFs available. Checking statically assigned VFs..." >&2
    for (( vf=IGPU_VF_AUTO; vf<=max_vfs; vf++ )); do
        if [[ -z "${defined_vf_map[$vf]:-}" ]]; then
            if [[ -n "${static_vf_map[$vf]:-}" ]]; then
                echo "Warning: Assigning VF $vf which conflicts with static assignment in: ${static_vf_map[$vf]}" >&2
                echo "Warning: This may cause conflicts if the statically assigned domain is launched later." >&2
            fi
            echo "$vf"
            return 0
        fi
    done

    # No VF available
    echo "Error: No available iGPU VF (all VFs are in use by defined domains)" >&2
    return 1
}

function is_valid_igpu_vf() {
    local max_vfs
    max_vfs=$(</sys/bus/pci/devices/0000:00:02.0/sriov_totalvfs)
    local vf=$1
    if [[ -z "$vf" ]]; then
        echo "Error: VF not defined"
        return 255
    fi
    if [[ $vf -gt 0 && $vf -le $max_vfs ]]; then
        return 0
    else
        echo "Error: VF $vf out of range, valid range from 1 to $max_vfs"
        return 255
    fi
}

# Function to remove USB and PCI passthrough devices from domain XML
# This allows devices to be explicitly attached via launch script passthrough options
# Preserves iGPU devices (bus=0x00/0, slot=0x02/2, functions 0x0-0x7/0-7)
function remove_passthrough_devices() {
    local xml_content="$1"

    # Remove all USB hostdev devices
    xml_content=$(xmlstarlet ed -d "//domain/devices/hostdev[@type='usb']" <<< "$xml_content")

    # Remove PCI hostdev devices except iGPU devices
    # Keep devices with domain='0x0000'/'0' bus='0x00'/'0' slot='0x02'/'2' functions 0x0-0x7/0-7
    # Remove all other PCI hostdev devices
    xml_content=$(xmlstarlet ed -d \
        "//domain/devices/hostdev[@type='pci' and \
            not(source/address[(@domain='0x0000' or @domain='0') and \
                              (@bus='0x00' or @bus='0') and \
                              (@slot='0x02' or @slot='2') and \
                              (@function='0x0' or @function='0' or \
                               @function='0x1' or @function='1' or \
                               @function='0x2' or @function='2' or \
                               @function='0x3' or @function='3' or \
                               @function='0x4' or @function='4' or \
                               @function='0x5' or @function='5' or \
                               @function='0x6' or @function='6' or \
                               @function='0x7' or @function='7')])]" \
        <<< "$xml_content")

    echo "$xml_content"
}

function clone_vm() {
    local clone_option=("--auto-clone")
    local clone_xml=""
    if [[ -f "$LIBVIRT_DEFAULT_IMAGES_PATH/${NEW_DOMAIN_NAME}.qcow2" ]]; then
        if [[ "$FORCECLEAN" == "1" ]]; then
            echo "$NEW_DOMAIN_NAME.qcow2 image already exists, remove before creating new image"
            # Delete the existing image
            sudo rm "$LIBVIRT_DEFAULT_IMAGES_PATH/$NEW_DOMAIN_NAME.qcow2"
        fi
        if [[ "$PRESERVE_DATA" == "1" ]]; then
            echo "Use existing $NEW_DOMAIN_NAME.qcow2 image for new VM creation"
            clone_option=("-f" "$LIBVIRT_DEFAULT_IMAGES_PATH/$NEW_DOMAIN_NAME.qcow2" "--preserve-data")
        fi
    fi
    # Check if iGPU SRIOV is present and update to the next available vf
    if [[ -n "${SOURCE_DOMAIN_NAME+x}" && -n "$SOURCE_DOMAIN_NAME" ]]; then
        clone_xml=$(virsh dumpxml "$SOURCE_DOMAIN_NAME")
    else
        local xmlfile
        xmlfile=$(realpath "$scriptpath/../../platform/$PLATFORM_NAME/libvirt_xml/$SOURCE_XML")
        clone_xml=$(xmlstarlet ed -d '//comment()' "$xmlfile")
    fi

    # Detect display type BEFORE device removal to preserve original intent
    # Use format-agnostic XPath that handles both hex and decimal formats
    local clone_vf_raw clone_vf_num
    clone_vf_raw=$(xmllint --xpath \
        "string(//domain/devices/hostdev/source/address[
            (@domain='0x0000' or @domain='0') and
            (@bus='0x00' or @bus='0') and
            (@slot='0x02' or @slot='2')
        ]/@function)" - <<<"$clone_xml")

    # Handle both string and numeric VF values uniformly
    if [[ "$clone_vf_raw" =~ ^(0x)?[0-9]+$ ]]; then
        clone_vf_num=$((clone_vf_raw))
    else
        clone_vf_num=""  # Empty or invalid value
    fi

    # Get supported display types and concatenate the different types with _
    # e.g if both vnc and spice are supported, return vnc_spice
    local clone_display
    clone_display=$(xmllint --xpath "//domain/devices/graphics/@type" - <<<"$clone_xml" 2>/dev/null | \
                    grep -o '"\([^"]*\)"' | \
                    sed 's|"||g' | \
                    xargs | \
                    sed 's/ /_/g')

    # Determine display type based on original XML content
    if [[ -n "$clone_vf_num" && $clone_vf_num -gt 0 ]]; then
        DISPLAY_TYPE="sriov"
        if [[ $clone_display == "spice" ]]; then
            DISPLAY_TYPE="spice-gst"
        fi
    elif [[ -n "$clone_vf_num" && $clone_vf_num -eq 0 ]]; then
        DISPLAY_TYPE="gvtd"
    else
        # No iGPU VF detected (empty or unset), determine from graphics configuration
        if [[ -z "$clone_display" ]]; then
            echo "Warning: No graphics configuration found in source, defaulting to headless"
            DISPLAY_TYPE="headless"
        else
            DISPLAY_TYPE="$clone_display"
        fi
    fi

    # Remove USB and PCI passthrough devices (except iGPU devices) to avoid conflicts
    # unless --preserve_passthrough is specified
    if [[ "$PRESERVE_PASSTHROUGH" != "1" ]]; then
        echo "Removing USB and PCI passthrough devices from cloned domain to prevent conflicts"
        clone_xml=$(remove_passthrough_devices "$clone_xml")
    else
        echo "Preserving USB and PCI passthrough devices in cloned domain as requested"
    fi

    # Handle iGPU VF assignment if SRIOV display type was detected
    if [[ "$DISPLAY_TYPE" == "sriov" || "$DISPLAY_TYPE" == "spice-gst" ]]; then
        local available_vf
        available_vf=$(next_available_igpu_vf)
        if [[ $? -ne 0 || -z "$available_vf" ]]; then
            echo "Error: New VM not created"
            return 255
        else
            echo "Use iGPU VF $available_vf in new VM creation"
        fi
        # Update existing iGPU VF to use available VF number using format-agnostic XPath
        clone_xml=$(xmlstarlet ed -L \
            --update "//domain/devices/hostdev/source/address[
                (@domain='0x0000' or @domain='0') and
                (@bus='0x00' or @bus='0') and
                (@slot='0x02' or @slot='2')
            ]/@function" \
            --value "$available_vf" <<<"$clone_xml")
    fi
    virt-clone -n "$NEW_DOMAIN_NAME" "${clone_option[@]}" --original-xml /dev/stdin <<<"$clone_xml"
}

# Function to shutdown and undefine a domain
function cleanup_domain() {
    local domain="$1"
    local state="$2"
    if [[ "$state" == "running" ]]; then
        echo "Shutting down domain $domain"
        virsh shutdown "$domain" >/dev/null 2>&1 || :
        # check if VM has shutdown at 5s interval, timeout 60s
        for (( x=0; x<12; x++ )); do
            echo "Wait for $domain to shutdown: $x"
            sleep 5
            state=$(virsh list --all | grep " $domain " | awk '{ print $3}')
            if [[ "$state" == "shut" ]]; then
                break
            fi
        done
    fi
    if [[ "$state" != "shut" ]]; then
        echo "$domain in $state, force destroy $domain"
        virsh destroy "$domain" >/dev/null 2>&1 || :
        sleep 5
    fi
    virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
}

function update_launch_multios() {
    local xml_file="${NEW_DOMAIN_NAME}_${DISPLAY_TYPE}.xml"
    local xml_file_path
    xml_file_path=$(realpath "$scriptpath/../../platform/$PLATFORM_NAME/libvirt_xml")
    echo "Save domain $NEW_DOMAIN_NAME xml to $xml_file_path/$xml_file"
    virsh dumpxml "$NEW_DOMAIN_NAME" > "$xml_file_path/$xml_file"
    echo "Add domain $NEW_DOMAIN_NAME for platform $PLATFORM_NAME in launch_multios.sh"
    local file
    file=$(realpath "$scriptpath/../../platform/$PLATFORM_NAME/launch_multios.sh")
    if [ ! -f "$file" ]; then
        echo "Cannot find $file for platform $PLATFORM_NAME!"
        return 255
    fi

    # Helper function to update or insert domain entry in a bash array block
    update_array_entry() {
        local array_decl="$1"
        local value="$2"
        local file="$3"
        local new_domain="$4"
        local indent="${5:-  }"  # Default indent is two spaces

        if grep -Fq "$array_decl" "$file"; then
            if ! sed -n "/$array_decl/,/^)/p" "$file" | grep -Fq "[\"$new_domain\"]="; then
                sed -i -e "/$array_decl/a\\${indent}[\"$new_domain\"]=$value" "$file"
            else
                sed -i -e "/$array_decl/,/^)/s/\\[\"$new_domain\"\\]=.*/${indent}[\"$new_domain\"]=$value/" "$file"
            fi
        fi
    }

    update_array_entry "declare -A VM_DOMAIN" "\"$xml_file\"" "$file" "$NEW_DOMAIN_NAME"
    update_array_entry "declare -A REDEFINE_DOMAIN" "1" "$file" "$NEW_DOMAIN_NAME"
    update_array_entry "declare -A EXCLUDED_DOMAIN_BY_USER" "0" "$file" "$NEW_DOMAIN_NAME" "    "
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
    local platforms=()
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

function show_help() {
    printf "\n"
    printf "%s [-h] [-s source_domain] [-x source_xml] [-n new_domain] [-p platform] \n" "$(basename "${BASH_SOURCE[0]}")"
    printf "[--igpu_vf_auto start_vf_num] [--igpu_vf vf_num] [--igpu_vf_force vf_num]\n"
    printf "[--forceclean] [--forceclean_domain] [--preserve_data] [--preserve_passthrough] [--sys_state]\n"
    printf "\n"
    printf "This script clones a new Ubuntu or Windows guest VM from an existing domain\n"
    printf "or XML file using virt-clone. It supports changing the iGPU SRIOV VF in the new\n"
    printf "guest VM if iGPU VF is passed through in the source. The input vf_num will be\n"
    printf "checked to ensure it is within the valid range from 1 to the maximum iGPU VF supported.\n"
    printf "By default, --igpu_vf_auto 1 is enabled and all existing domains and platform XML files\n"
    printf "are checked for iGPU VF usage. First, truly available VFs (not used by defined domains or\n"
    printf "statically assigned in XML files) are preferred. If no truly available VFs exist,\n"
    printf "statically assigned VFs will be used with conflict warnings. New domain created will be\n"
    printf "automatically added to the platform launch_multios.sh and the domain xml saved in the\n"
    printf "libvirt_xml folder.\n"
    printf "\n"
    printf "Options:\n"
    printf "\t-h                           Show this help message\n"
    printf "\t-s source_domain             Source domain name to clone from,\n"
    printf "\t                             mutually exclusive with -x option\n"
    printf "\t-x source_xml                Source XML to clone from,\n"
    printf "\t                             mutually exclusive with -s option\n"
    printf "\t-n new_domain                New domain name\n"
    printf "\t-p platform                  Specific platform to setup for, eg. \"-p client \"\n"
    printf "\t                             Accepted values:\n"
    get_supported_platform_names platforms
    for p in "${platforms[@]}"; do
    printf "\t                             %s\n" "$(basename "$p")"
    done
    printf "\t--igpu_vf_auto start_vf_num  Auto search for available VF, starting from\n"
    printf "\t                             start_vf_num to maximum available VF\n"
    printf "\t--igpu_vf vf_num             Use vf_num for iGPU SRIOV in the new domain\n"
    printf "\t                             only if vf_num has not been used in existing domains\n"
    printf "\t--igpu_vf_force vf_num       Use vf_num for iGPU SRIOV in the new domain,\n"
    printf "\t                             not considering if the vf_num has been used\n"
    printf "\t                             in existing domains\n"
    printf "\t--forceclean                 Delete both new domain and image data if they already\n"
    printf "\t                             exist. Default not enabled, mutually exclusive\n"
    printf "\t                             with --preserve_data\n"
    printf "\t--forceclean_domain          Delete only new domain if it already exists.\n"
    printf "\t                             Default not enabled\n"
    printf "\t--preserve_data              Preserve new domain image data if it already exists,\n"
    printf "\t                             create new one if it does not exist. Default not enabled\n"
    printf "\t--preserve_passthrough       Preserve USB and PCI passthrough device configurations\n"
    printf "\t                             from source domain/XML in the cloned domain. Default not enabled.\n"
    printf "\t                             By default, passthrough devices are removed to avoid conflicts\n"
    printf "\t--sys_state                  Show current system state (domains, XML files, VF usage)\n"
    printf "\t                             for the specified platform and exit without performing\n"
    printf "\t                             any cloning operations. Requires -p parameter.\n"
    printf "Usage examples:\n"
    printf "Clone from existing ubuntu domain, auto search available iGPU VF starting from 4\n"
    printf "./guest_setup/ubuntu/clone_guest.sh -s ubuntu -n ubuntu_2 -p client --igpu_vf_auto 4\n"
    printf "\n"
    printf "Clone from windows xml, using iGPU VF 4\n"
    printf "./guest_setup/ubuntu/clone_guest.sh -x windows_sriov_ovmf.xml -n windows_2 -p client --igpu_vf 4\n"
    printf "\n"
    printf "Display system state summary for client platform\n"
    printf "./guest_setup/ubuntu/clone_guest.sh --sys_state -p client\n"
    printf "\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit 0
                ;;
            --sys_state)
                SYS_STATE_REQUESTED=1
                ;;
            -s)
                if [[ $# -lt 2 || -z "${2// }" || "$2" == -* ]]; then
                    echo "Error: -s requires a non-empty source domain name"
                    show_help
                    return 255
                fi
                SOURCE_DOMAIN_NAME=$2
                shift
                ;;
            -x)
                if [[ $# -lt 2 || -z "${2// }" || "$2" == -* ]]; then
                    echo "Error: -x requires a non-empty source XML filename"
                    show_help
                    return 255
                fi
                SOURCE_XML=$2
                shift
                ;;
            -n)
                if [[ $# -lt 2 || -z "${2// }" || "$2" == -* ]]; then
                    echo "Error: -n requires a non-empty new domain name"
                    show_help
                    return 255
                fi
                NEW_DOMAIN_NAME=$2
                shift
                ;;
            -p)
                if [[ $# -lt 2 || -z "${2// }" || "$2" == -* ]]; then
                    echo "Error: -p requires a non-empty platform name"
                    show_help
                    return 255
                fi
                PLATFORM_ARG=$2
                shift
                ;;
            --forceclean)
                FORCECLEAN=1
                ;;
            --forceclean_domain)
                FORCECLEAN_DOMAIN=1
                ;;
            --preserve_data)
                PRESERVE_DATA=1
                ;;
            --preserve_passthrough)
                PRESERVE_PASSTHROUGH=1
                ;;
            --igpu_vf)
                if [[ $# -lt 2 || -z "${2// }" || "$2" == -* ]]; then
                    echo "Error: --igpu_vf requires a non-empty VF number"
                    show_help
                    return 255
                fi
                IGPU_VF=$2
                IGPU_VF_SPECIFIED=1
                shift
                ;;
            --igpu_vf_force)
                if [[ $# -lt 2 || -z "${2// }" || "$2" == -* ]]; then
                    echo "Error: --igpu_vf_force requires a non-empty VF number"
                    show_help
                    return 255
                fi
                IGPU_VF_FORCE=$2
                IGPU_VF_FORCE_SPECIFIED=1
                shift
                ;;
            --igpu_vf_auto)
                if [[ $# -lt 2 || -z "${2// }" || "$2" == -* ]]; then
                    echo "Error: --igpu_vf_auto requires a non-empty VF start number"
                    show_help
                    return 255
                fi
                IGPU_VF_AUTO=$2
                IGPU_VF_AUTO_SPECIFIED=1
                shift
                ;;
            -?*)
                echo "Error: Invalid option $1"
                show_help
                return 255
                ;;
            *)
                echo "Error: Unknown option: $1"
                show_help
                return 255
                ;;
        esac
        shift
    done
}

function validate_source_domain() {
    local domain_name="$1"

    # Early return if domain exists and is accessible
    if virsh dominfo "$domain_name" >/dev/null 2>&1; then
        # Check if domain is in shutdown state
        local domain_state
        domain_state=$(virsh list --all | grep " $domain_name " | awk '{print $3}' 2>/dev/null || echo "unknown")
        if [[ "$domain_state" != "shut" ]]; then
            echo "Error: Source domain '$domain_name' is not in shutdown state (current state: $domain_state)."
            echo "Please shut it down before cloning."
            return 255
        fi
        return 0
    fi

    # Domain validation failed - show error and available domains
    echo "Error: Source domain '$domain_name' does not exist or is not accessible"
    echo "Available domains:"
    local -a available_domains
    mapfile -t available_domains < <(virsh list --all --name 2>/dev/null | sed '/^[[:space:]]*$/d')

    if [[ ${#available_domains[@]} -eq 0 ]]; then
        echo "  (No domains found - check if libvirtd service is running)"
        echo "  Run: sudo systemctl status libvirtd"
        return 255
    fi

    for domain in "${available_domains[@]}"; do
        local domain_state
        domain_state=$(virsh list --all | grep " $domain " | awk '{print $3}' 2>/dev/null || echo "unknown")
        echo "  - $domain ($domain_state)"
    done
    return 255
}

function validate_source_xml() {
    local xml_file="$1"
    local xmlfile
    xmlfile=$(realpath "$scriptpath/../../platform/$PLATFORM_NAME/libvirt_xml/$xml_file")

    if [[ -f "$xmlfile" ]]; then
        check_file_valid_nonzero "$xmlfile"

        # If the XML has a <name> element, check if a domain with that name exists and is shut down
        local xml_domain_name
        xml_domain_name=$(xmllint --xpath 'string(//domain/name)' "$xmlfile" 2>/dev/null || true)
        if [[ -n "$xml_domain_name" ]] && virsh dominfo "$xml_domain_name" >/dev/null 2>&1; then
            local domain_state
            domain_state=$(virsh list --all | grep " $xml_domain_name " | awk '{print $3}' 2>/dev/null || echo "unknown")
            if [[ "$domain_state" != "shut" ]]; then
                echo "Error: Domain referenced in XML ('$xml_domain_name') is not in shutdown state (current state: $domain_state)."
                echo "Please shut it down before cloning."
                return 255
            fi
        fi

        # Check if referenced disk images exist
        local disk_sources
        disk_sources=$(xmllint --xpath "//domain/devices/disk[@device='disk']/source/@file" "$xmlfile" 2>/dev/null | \
                      grep -o '"\([^"\]*\)"' | sed 's|"||g' || true)

        if [[ -n "$disk_sources" ]]; then
            local missing_disks=()
            while IFS= read -r disk_path; do
                if [[ -n "$disk_path" && ! -f "$disk_path" ]]; then
                    missing_disks+=("$disk_path")
                fi
            done <<< "$disk_sources"

            if [[ ${#missing_disks[@]} -gt 0 ]]; then
                echo "Error: Referenced disk image(s) do not exist:"
                for disk in "${missing_disks[@]}"; do
                    echo "  - $disk"
                done
                echo "When cloning from XML, the referenced disk images must exist."
                echo "Either create the domain with the guest setup scripts or clone from an"
                echo "existing domain instead using -s option."
                return 255
            fi
        fi

        return 0
    fi

    # File not found - show error message and list available XML files
    local xml_dir_raw="$scriptpath/../../platform/$PLATFORM_NAME/libvirt_xml"
    local xml_dir
    xml_dir=$(realpath "$xml_dir_raw" 2>/dev/null || echo "$xml_dir_raw")

    if [[ "$xml_file" != *.xml ]]; then
        echo "Error: Source XML file must have .xml extension"
        echo "Expected location: $xml_dir"
    else
        echo "Error: Cannot find XML file at: $xmlfile"
        echo "Expected location: $xml_dir"
    fi

    echo "Available XML files in $xml_dir:"
    find "$xml_dir" -name "*.xml" -type f -exec basename {} \; 2>/dev/null | sort | sed 's/^/  - /' || echo "  (No XML files found)"
    return 255
}

# Function to check if new domain already exists
function validate_new_domain() {
    local domain="$NEW_DOMAIN_NAME"

    # Check for invalid combinations first
    if [[ "$FORCECLEAN" == "1" && "$FORCECLEAN_DOMAIN" == "1" ]]; then
        echo "Error: --forceclean cannot be used together with --forceclean_domain"
        return 255
    fi

    if [[ "$FORCECLEAN" == "1" && "$PRESERVE_DATA" == "1" ]]; then
        echo "Error: --forceclean cannot be used together with --preserve_data"
        return 255
    fi

    # Check for existing domain and image
    local status
    status=$(virsh list --all | grep " $domain " || true)
    local domain_exists=0
    if [[ -n "${status}" ]]; then
        domain_exists=1
    fi

    local image_exists=0
    if [[ -f "$LIBVIRT_DEFAULT_IMAGES_PATH/$NEW_DOMAIN_NAME.qcow2" ]]; then
        image_exists=1
    fi

    # Warn about orphaned resources
    if [[ $domain_exists -eq 1 && $image_exists -eq 0 ]]; then
        echo "Warning: Domain '$domain' exists but image '$NEW_DOMAIN_NAME.qcow2' is missing (orphaned domain)"
    fi

    if [[ $domain_exists -eq 0 && $image_exists -eq 1 ]]; then
        echo "Warning: Image '$NEW_DOMAIN_NAME.qcow2' exists but domain '$domain' is missing (orphaned image)"
    fi

    # Warn if --forceclean_domain will create orphaned image
    if [[ "$FORCECLEAN_DOMAIN" == "1" && $domain_exists -eq 1 && $image_exists -eq 1 ]]; then
        echo "Warning: Using --forceclean_domain will remove domain '$domain' but leave image '$NEW_DOMAIN_NAME.qcow2' (creating an orphaned image)"
    fi

    # Check required options when conflicts exist
    if [[ $domain_exists -eq 1 ]]; then
        if [[ "$FORCECLEAN" != "1" && "$FORCECLEAN_DOMAIN" != "1" ]]; then
            echo "Error: New domain $domain already exists! Use --forceclean or --forceclean_domain"
            return 255
        fi
    fi

    if [[ $image_exists -eq 1 ]]; then
        if [[ "$FORCECLEAN" != "1" && "$PRESERVE_DATA" != "1" ]]; then
            echo "Error: $NEW_DOMAIN_NAME.qcow2 image already exists! Use --forceclean or --preserve_data"
            return 255
        fi
    fi
}

# Function to handle domain cleanup when needed
function cleanup_existing_domain() {
    local domain="$NEW_DOMAIN_NAME"
    local status
    status=$(virsh list --all | grep " $domain " || true)

    if [[ -n "${status}" && ("$FORCECLEAN" == "1" || "$FORCECLEAN_DOMAIN" == "1") ]]; then
        echo "Domain $domain exists, remove before create"
        local state
        state=$(echo "$status" | awk '{ print $3}')
        cleanup_domain "$domain" "$state"
    fi
}

# Function to validate iGPU VF arguments
function validate_igpu_vf() {
    # Check for mutual exclusivity of VF options
    local vf_count=0
    [[ $IGPU_VF_SPECIFIED -eq 1 ]] && ((vf_count++))
    [[ $IGPU_VF_FORCE_SPECIFIED -eq 1 ]] && ((vf_count++))
    [[ $IGPU_VF_AUTO_SPECIFIED -eq 1 ]] && ((vf_count++))

    if [[ $vf_count -gt 1 ]]; then
        echo "Error: Only one VF option can be specified (--igpu_vf, --igpu_vf_force, or --igpu_vf_auto)"
        return 255
    fi

    # Early exit if no VF options specified
    if [[ $vf_count -eq 0 ]]; then
        return 0
    fi

    # Only set variables and validate when we know exactly one option is specified
    local vf_value vf_type
    if [[ $IGPU_VF_SPECIFIED -eq 1 ]]; then
        vf_value="$IGPU_VF"
        vf_type="--igpu_vf"
    elif [[ $IGPU_VF_FORCE_SPECIFIED -eq 1 ]]; then
        vf_value="$IGPU_VF_FORCE"
        vf_type="--igpu_vf_force"
    else  # $IGPU_VF_AUTO_SPECIFIED -eq 1
        vf_value="$IGPU_VF_AUTO"
        vf_type="--igpu_vf_auto"
    fi

    if [[ ! "$vf_value" =~ ^[0-9]+$ ]]; then
        echo "Error: $vf_type requires a numeric VF number"
        return 255
    fi

    if ! is_valid_igpu_vf "$vf_value"; then
        return 255
    fi
}

function validate_arguments() {
    # Phase 1: Check the validity of -p argument (required for all operations)
    if [[ -z "${PLATFORM_ARG:-}" ]]; then
        echo "Error: -p platform parameter is required"
        exit 255
    fi
    set_platform_name "$PLATFORM_ARG" || exit 255

    # If only --sys_state was requested, validation is complete
    if [[ "$SYS_STATE_REQUESTED" -eq 1 ]]; then
        return 0
    fi

    # Phase 2: Check the mode of cloning (mutually exclusive -s or -x)
    if [[ -n "${SOURCE_DOMAIN_NAME:-}" && -n "${SOURCE_XML:-}" ]]; then
        echo "Error: use either original domain (-s) or xml (-x) option but not both"
        exit 255
    fi
    if [[ -z "${SOURCE_DOMAIN_NAME:-}" && -z "${SOURCE_XML:-}" ]]; then
        echo "Error: either original domain (-s) or xml (-x) option is required"
        exit 255
    fi

    # Phase 3: Check the validity of the source arguments
    if [[ -n "${SOURCE_DOMAIN_NAME:-}" ]]; then
        validate_source_domain "$SOURCE_DOMAIN_NAME" || exit 255
    fi
    if [[ -n "${SOURCE_XML:-}" ]]; then
        validate_source_xml "$SOURCE_XML" || exit 255
    fi

    # Phase 4: Check the validity of the -n new domain argument and related options
    if [[ -z "${NEW_DOMAIN_NAME:-}" ]]; then
        echo "Error: valid VM domain name needed"
        exit 255
    fi
    validate_new_domain || exit 255

    # Phase 5: Check the validity of the vf-related arguments
    validate_igpu_vf || exit 255
}

# Function to display system state after cloning
function show_system_state() {
    echo ""
    echo "=== System State Summary ==="
    echo ""

    # Get all domains once and reuse throughout
    local -a all_domains
    mapfile -t all_domains < <(virsh list --all --name 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -V)

    # Early exit if no domains
    if [[ ${#all_domains[@]} -eq 0 ]]; then
        echo "Domains:"
        echo "  (No domains found)"
        echo ""
        echo "Note: No virtual machines are currently defined on this system"
        echo ""
        return
    fi

    # Get all domain states and XMLs in batch to minimize virsh calls
    local -A domain_states=() domain_xmls=()

    # Fetch states and XMLs for each domain
    for domain in "${all_domains[@]}"; do
        domain_states[$domain]=$(virsh domstate "$domain" 2>/dev/null || echo "unknown")
        domain_xmls[$domain]=$(virsh dumpxml "$domain" 2>/dev/null || echo "")
    done

    # Show domains
    echo "Domains:"
    for domain in "${all_domains[@]}"; do
        echo "  - $domain (${domain_states[$domain]})"
    done

    # XML files section
    echo ""
    # Use the platform specified via -p parameter (required and validated)
    local xml_dir="$scriptpath/../../platform/$PLATFORM_NAME/libvirt_xml"
    local xml_dir_abs
    xml_dir_abs=$(realpath "$xml_dir" 2>/dev/null || echo "$xml_dir")
    echo "XML files for defined domains:"
    echo "  Location:"
    echo "    $xml_dir_abs"

    if [[ -d "$xml_dir" ]]; then
        # Batch discover all XML files once
        local -A domain_xml_files=()
        local all_xml_files
        all_xml_files=$(find "$xml_dir" -maxdepth 1 -type f -name "*.xml" -printf '%f\n' 2>/dev/null | sort)

        # Group XML files by domain
        while IFS= read -r xml_file; do
            [[ -z "$xml_file" ]] && continue
            local domain_name="${xml_file%%_*}"
            # Check if this domain is in our list
            for domain in "${all_domains[@]}"; do
                if [[ "$domain_name" == "$domain" || "${xml_file%.xml}" == "$domain" ]]; then
                    # Append XML file to domain's list (newline-separated)
                    local current_files="${domain_xml_files[$domain]:-}"
                    domain_xml_files[$domain]="${current_files:+${current_files}$'\n'}$xml_file"
                    break
                fi
            done
        done <<< "$all_xml_files"

        # Display grouped XML files
        local found_xml=0
        for domain in "${all_domains[@]}"; do
            if [[ -n "${domain_xml_files[$domain]:-}" ]]; then
                echo ""
                echo "  $domain:"
                while IFS= read -r xml_file; do
                    echo "    - $xml_file"
                done <<< "${domain_xml_files[$domain]}"
                found_xml=1
            fi
        done
        [[ $found_xml -eq 0 ]] && echo "  (No XML files found matching defined domains in $xml_dir_abs)"
    else
        echo "  (XML directory not found: $xml_dir_abs)"
    fi

    # Disk images processing
    echo ""
    echo "Disk images in $LIBVIRT_DEFAULT_IMAGES_PATH:"
    if [[ ! -d "$LIBVIRT_DEFAULT_IMAGES_PATH" ]]; then
        echo "  (Libvirt images directory not found: $LIBVIRT_DEFAULT_IMAGES_PATH)"
    else
        local -a image_files
        mapfile -t image_files < <(
            if [[ -r "$LIBVIRT_DEFAULT_IMAGES_PATH" ]]; then
                find "$LIBVIRT_DEFAULT_IMAGES_PATH" -maxdepth 1 -type f \
                    \( -name "*.qcow2" -o -name "*.img" -o -name "*.raw" -o -name "*.vmdk" \) \
                    -printf '%f\n' 2>/dev/null | sort
            else
                sudo find "$LIBVIRT_DEFAULT_IMAGES_PATH" -maxdepth 1 -type f \
                    \( -name "*.qcow2" -o -name "*.img" -o -name "*.raw" -o -name "*.vmdk" \) \
                    -printf '%f\n' 2>/dev/null | sort
            fi
        )

        if [[ ${#image_files[@]} -eq 0 ]]; then
            echo "  (No disk images found in $LIBVIRT_DEFAULT_IMAGES_PATH)"
        else
            # Build image-domain mapping and cache disk paths using cached XMLs
            local -A image_domain_map=()
            local -A domain_disk_paths=()
            local -A image_shown=()  # Track already displayed images to avoid duplicates

            for domain in "${all_domains[@]}"; do
                [[ -z "${domain_xmls[$domain]}" ]] && continue
                local disk_paths
                disk_paths=$(xmllint --xpath "//domain/devices/disk[@device='disk']/source/@file" - \
                    <<<"${domain_xmls[$domain]}" 2>/dev/null | grep -o '"/[^"]*"' | tr -d '"' || echo "")

                # Cache disk paths for later use
                domain_disk_paths[$domain]="$disk_paths"

                while IFS= read -r disk_path; do
                    if [[ -n "$disk_path" ]]; then
                        local disk_basename
                        disk_basename=$(basename "$disk_path")
                        # Append domain to image mapping (comma-separated)
                        local current_domains="${image_domain_map[$disk_basename]:-}"
                        image_domain_map[$disk_basename]="${current_domains:+${current_domains}, }$domain"
                    fi
                done <<< "$disk_paths"
            done

            # Categorize images efficiently
            local -a associated_images=() orphaned_images=()
            for image_file in "${image_files[@]}"; do
                if [[ -n "${image_domain_map[$image_file]:-}" ]]; then
                    associated_images+=("$image_file")
                else
                    orphaned_images+=("$image_file")
                fi
            done

            # Display in domain order for associated images (optimized: O(n) instead of O(n²))
            echo ""
            echo "  Images associated with defined domains:"
            if [[ ${#associated_images[@]} -eq 0 ]]; then
                echo "    (No images associated with defined domains)"
            else
                for domain in "${all_domains[@]}"; do
                    local disk_paths="${domain_disk_paths[$domain]:-}"
                    [[ -z "$disk_paths" ]] && continue

                    while IFS= read -r disk_path; do
                        [[ -z "$disk_path" ]] && continue
                        local disk_basename
                        disk_basename=$(basename "$disk_path")
                        # Only show if it exists in image_domain_map and hasn't been shown yet
                        local has_mapping="${image_domain_map[$disk_basename]:-}"
                        local already_shown="${image_shown[$disk_basename]:-}"
                        if [[ -n "$has_mapping" && -z "$already_shown" ]]; then
                            echo "    - $disk_basename -> ${image_domain_map[$disk_basename]}"
                            image_shown[$disk_basename]=1
                        fi
                    done <<< "$disk_paths"
                done
            fi

            # Check for domains with missing images using cached disk paths
            echo ""
            echo "  Domains with missing images:"
            local found_missing=0
            for domain in "${all_domains[@]}"; do
                local disk_paths="${domain_disk_paths[$domain]:-}"
                [[ -z "$disk_paths" ]] && continue

                while IFS= read -r disk_path; do
                    [[ -z "$disk_path" ]] && continue
                    [[ -f "$disk_path" ]] && continue

                    local disk_basename
                    disk_basename=$(basename "$disk_path")
                    echo "    - $domain: missing $disk_basename"
                    found_missing=1
                done <<< "$disk_paths"
            done
            [[ $found_missing -eq 0 ]] && echo "    (All defined domains have their disk images)"

            echo ""
            echo "  Orphaned images (not associated with any defined domains):"
            if [[ ${#orphaned_images[@]} -eq 0 ]]; then
                echo "    (No orphaned images found)"
            else
                printf '    - %s\n' "${orphaned_images[@]}"
            fi
        fi
    fi

    # iGPU VF usage - reuse cached domain_xmls instead of reading files again
    echo ""
    echo "iGPU VF usage for defined domains:"
    if [[ ! -f "/sys/bus/pci/devices/0000:00:02.0/sriov_totalvfs" ]]; then
        echo "  (iGPU SRIOV not available or not configured)"
    else
        local max_vfs
        max_vfs=$(</sys/bus/pci/devices/0000:00:02.0/sriov_totalvfs)
        echo "  Total VFs available: $max_vfs"

        local -A vf_domain_map=()
        local -A vf_domain_xml_map=()

        # Process cached domain XMLs directly instead of reading from files
        for domain in "${all_domains[@]}"; do
            [[ -z "${domain_xmls[$domain]}" ]] && continue
            [[ -z "${domain_xml_files[$domain]:-}" ]] && continue

            # Process each XML file for this domain
            while IFS= read -r xml_basename; do
                [[ -z "$xml_basename" ]] && continue

                # Use cached XML from domain_xmls if this is the active domain XML
                # Otherwise read from file (for alternate configurations)
                local xml_content="${domain_xmls[$domain]}"

                # If there are multiple XML files for this domain, we need to read from disk
                # for the non-active configurations
                local xml_count
                xml_count=$(echo "${domain_xml_files[$domain]}" | wc -l)
                if [[ $xml_count -gt 1 ]]; then
                    # Read from file for alternate configs
                    local xml_file="$xml_dir/$xml_basename"
                    if [[ -f "$xml_file" ]]; then
                        xml_content=$(cat "$xml_file" 2>/dev/null || echo "")
                    fi
                fi

                [[ -z "$xml_content" ]] && continue

                # Extract VF number from XML
                # Try both hex format (0x0000) and decimal format (0) for domain/bus/slot
                local domain_vf_hex
                domain_vf_hex=$(xmllint --xpath \
                    "string(//domain/devices/hostdev/source/address[\
                        (@domain='0x0000' or @domain='0') and \
                        (@bus='0x00' or @bus='0') and \
                        (@slot='0x02' or @slot='2')]/@function)" - \
                    <<<"$xml_content" 2>/dev/null || echo "")

                # Only process if we found a valid VF assignment (non-empty)
                if [[ -n "$domain_vf_hex" ]]; then
                    local domain_vf_num=$((domain_vf_hex))
                    if [[ $domain_vf_num -gt 0 ]]; then
                        # Track which domains use this VF (avoid duplicates)
                        local current_domains="${vf_domain_map[$domain_vf_num]:-}"
                        if [[ ! " $current_domains " =~ \ $domain\  ]]; then
                            vf_domain_map[$domain_vf_num]="${current_domains:+$current_domains }$domain"
                        fi
                        # Track XML files per domain for this VF
                        local key="${domain_vf_num}_${domain}"
                        local current_xmls="${vf_domain_xml_map[$key]:+${vf_domain_xml_map[$key]}, }"
                        vf_domain_xml_map[$key]="${current_xmls}$xml_basename"
                    fi
                fi
            done <<< "${domain_xml_files[$domain]}"
        done

        if [[ ${#vf_domain_map[@]} -eq 0 ]]; then
            echo "  (No VFs in use by defined domains)"
        else
            for vf_num in $(printf '%s\n' "${!vf_domain_map[@]}" | sort -n); do
                # Check for conflicts: count unique domains using this VF (optimized)
                local domain_list="${vf_domain_map[$vf_num]}"
                local unique_count
                unique_count=$(echo "$domain_list" | tr ' ' '\n' | sort -u | wc -l)

                if [[ $unique_count -eq 1 ]]; then
                    # Single domain - show on one line
                    local domain="$domain_list"
                    local key="${vf_num}_${domain}"
                    echo "    - VF $vf_num: $domain (${vf_domain_xml_map[$key]:-unknown})"
                else
                    # Multiple domains - show first domain on main line, rest indented
                    local -a unique_domains
                    mapfile -t unique_domains < <(echo "$domain_list" | tr ' ' '\n' | sort -u)

                    local first_domain="${unique_domains[0]}"
                    local key="${vf_num}_${first_domain}"
                    echo "    - VF $vf_num: $first_domain (${vf_domain_xml_map[$key]:-unknown})"

                    # Show remaining domains indented to align with first domain name
                    for ((i=1; i<${#unique_domains[@]}; i++)); do
                        local domain="${unique_domains[i]}"
                        key="${vf_num}_${domain}"
                        echo "            $domain (${vf_domain_xml_map[$key]:-unknown})"
                    done

                    # Show warning for conflicts
                    echo "           *WARNING: Multiple domains share this VF"
                fi
            done
        fi
    fi

    echo ""
}

# Uncomment function if needed
#function cleanup () {
#}

#-------------    main processes    -------------
# Uncomment cleanup trap if needed
#trap 'cleanup' EXIT
#trap 'error ${LINENO} "$BASH_COMMAND"' ERR

parse_arg "$@" || exit 255
validate_arguments || exit 255

# If --sys_state was requested, show state and exit
if [[ "$SYS_STATE_REQUESTED" -eq 1 ]]; then
    show_system_state
    exit 0
fi

cleanup_existing_domain || exit 255

check_host_distribution || exit 255
install_dep || exit 255
clone_vm || exit 255
update_launch_multios || exit 255

show_system_state

exit 0

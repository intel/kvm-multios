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
IGPU_VF=0
IGPU_VF_FORCE=0
IGPU_VF_AUTO=1
PLATFORM_NAME=""
DISPLAY_TYPE=""
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
    local -a used_vfs=()
    local -a new_vf=()
    local IFS=$'\n'
    local -a domains
    mapfile -t domains < <(virsh list --all --name | sed '/^[[:space:]]*$/d')
    for domain in "${domains[@]}"; do
        local domain_xml
        domain_xml=$(virsh dumpxml "$domain")
        # Get the domain sriov vf if defined
        local domain_vf_hex
        domain_vf_hex=$(xmllint --xpath "string(//domain/devices/hostdev/source/address[@domain='0x0000' and @bus='0x00' and @slot='0x02']/@function)" - <<<"$domain_xml" )
        local domain_vf_num=$((domain_vf_hex))
        if [[ $domain_vf_num -gt 0 ]]; then
            used_vfs+=("$domain_vf_num")
        fi
    done
    if [[ $IGPU_VF_FORCE -gt 0 ]]; then
        mapfile -t new_vf < <(comm -13 <(printf '%s\n' "${used_vfs[@]}" | LC_ALL=C sort) <(seq "$IGPU_VF_FORCE" "$IGPU_VF_FORCE"))
        if [[ -z ${new_vf+x} || -z "$new_vf" ]]; then
          echo "iGPU VF $IGPU_VF_FORCE already used in other domain, ignoring as force option is used"
        fi
        new_vf=$IGPU_VF_FORCE
    elif  [[ $IGPU_VF -gt 0 ]]; then
        mapfile -t new_vf < <(comm -13 <(printf '%s\n' "${used_vfs[@]}" | LC_ALL=C sort) <(seq "$IGPU_VF" "$IGPU_VF"))
        if [[ -z ${new_vf+x} || -z "$new_vf" ]]; then
          echo "Error: iGPU VF $IGPU_VF already used in other domain"
        fi
    else
        mapfile -t new_vf < <(comm -13 <(printf '%s\n' "${used_vfs[@]}" | LC_ALL=C sort) <(seq "$IGPU_VF_AUTO" "$max_vfs"))
        if [[ -z ${new_vf+x} || -z "$new_vf" ]]; then
          echo "Error: No available iGPU VF"
        fi
    fi
    if [[ -z "${new_vf+x}" || -z "$new_vf" ]]; then
      # No vf is available
      return 0
    fi
    return "$new_vf"
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

function clone_vm() {
    local clone_option="--auto-clone"
    local clone_xml=""
    if [[ -f "$LIBVIRT_DEFAULT_IMAGES_PATH/${NEW_DOMAIN_NAME}.qcow2" ]]; then
        if [[ "$FORCECLEAN" == "1" ]]; then
            echo "$NEW_DOMAIN_NAME.qcow2 image already exists, remove before creating new image"
            # Delete the existing image
            sudo rm "$LIBVIRT_DEFAULT_IMAGES_PATH/$NEW_DOMAIN_NAME.qcow2"
        fi
        if [[ "$PRESERVE_DATA" == "1" ]]; then
            echo "Use existing $NEW_DOMAIN_NAME.qcow2 image for new VM creation"
            clone_option="-f $LIBVIRT_DEFAULT_IMAGES_PATH/$NEW_DOMAIN_NAME.qcow2 --preserve-data"
        fi
    fi
    # Check if iGPU SRIOV is present and update to the next available vf
    if [[ -n "${SOURCE_DOMAIN_NAME+x}" && -n "$SOURCE_DOMAIN_NAME" ]]; then
        clone_xml=$(virsh dumpxml "$SOURCE_DOMAIN_NAME")
        local clone_vf_hex
        clone_vf_hex=$(xmllint --xpath "string(//domain/devices/hostdev/source/address[@domain='0x0000' and @bus='0x00' and @slot='0x02']/@function)" - <<<"$clone_xml" )
        local clone_vf_num=$((clone_vf_hex))
        # Get supported display types and concatenate the different types with _
        # e.g if both vnc and spice are supported, return vnc_spice
        local clone_display
        clone_display=$(xmllint --xpath "//domain/devices/graphics/@type" - <<<"$clone_xml" 2>/dev/null | grep -o '"\([^"]*\)"' | sed 's|"||g'|xargs | sed 's/ /_/g')
        if [[ $clone_vf_num -gt 0 ]]; then
            DISPLAY_TYPE="sriov"
            if [[ $clone_display == "spice" ]]; then
                DISPLAY_TYPE="spice-gst"
            fi
            next_available_igpu_vf
            local available_vf=$?
            if [[ $available_vf -eq 0 ]]; then
                echo "Error: New VM not created"
                return 255
            else
                echo "Use iGPU VF $available_vf in new VM creation"
            fi
            clone_xml=$(xmlstarlet ed -L --update "//domain/devices/hostdev/source/address[@domain='0x0000' and @bus='0x00' and @slot='0x02']/@function" --value $available_vf <<<"$clone_xml")
        elif [[ "$clone_vf_hex" == "0x0" ]]; then
            DISPLAY_TYPE="gvtd"
        else
            if [[ $clone_display == "" ]]; then
                clone_display="headless"
            fi
            DISPLAY_TYPE="$clone_display"
        fi
    else
        local xmlfile
        xmlfile=$(realpath "$scriptpath/../../platform/$PLATFORM_NAME/libvirt_xml/$SOURCE_XML")
        check_file_valid_nonzero "$xmlfile"
        if [[ ! -f $xmlfile ]]; then
            echo "Cannot find $xmlfile!"
            return 255
        fi
        clone_xml=$(xmlstarlet ed -d '//comment()' "$xmlfile")
        local clone_vf_num
        clone_vf_num=$(xmllint --xpath "string(//domain/devices/hostdev/source/address[@domain='0' and @bus='0' and @slot='2']/@function)" - <<<"$clone_xml" )
        # Get supported display types and concatenate the different types with _
        # e.g if both vnc and spice are supported, return vnc_spice
        local clone_display
        clone_display=$(xmllint --xpath "//domain/devices/graphics/@type" - <<<"$clone_xml" 2>/dev/null | grep -o '"\([^"]*\)"' | sed 's|"||g'|xargs | sed 's/ /_/g')
        if [[ $clone_vf_num -gt 0 ]]; then
            DISPLAY_TYPE="sriov"
            if [[ $clone_display == "spice" ]]; then
                DISPLAY_TYPE="spice-gst"
            fi
            next_available_igpu_vf
            local available_vf=$?
            if [[ $available_vf -eq 0 ]]; then
                echo "Error: New VM not created"
                return 255
            else
                echo "Use iGPU VF $available_vf in new VM creation"
            fi
            clone_xml=$(xmlstarlet ed -L --update "//domain/devices/hostdev/source/address[@domain='0' and @bus='0' and @slot='2']/@function" --value $available_vf <<<"$clone_xml")
        elif [[ "$clone_vf_num" == "0" ]]; then
            DISPLAY_TYPE="gvtd"
        else
            if [[ $clone_display == "" ]]; then
                clone_display="headless"
            fi
            DISPLAY_TYPE="$clone_display"
        fi
    fi
    virt-clone -n "$NEW_DOMAIN_NAME" "$clone_option" --original-xml /dev/stdin <<<"$clone_xml"
}

# Function to check if new domain is already exist
function check_domain() {
    local domain="$NEW_DOMAIN_NAME"
    local status
    status=$(virsh list --all | grep "$domain ")
    if [[ -z "${status+x}" || -z "$status" ]]; then
        return 0
    fi
    # New domain already exist
    if [[ "$FORCECLEAN" == "1" || "$FORCECLEAN_DOMAIN" == "1" ]]; then
        echo "Domain $domain exist, remove before create"
        local state
        state=$(echo "$status" | awk '{ print $3}')
        cleanup_domain "$domain" "$state"
    else
        echo "Error: New domain $domain already exist"
        return 255
    fi
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
    if ! grep -Fq "[\"$NEW_DOMAIN_NAME\"]=" "$file"; then
        sed -i -e "/\[\"ubuntu\"\]=/i \[\"$NEW_DOMAIN_NAME\"\]=\"$xml_file\"" "$file"
    else
        sed -i "s/\[\"$NEW_DOMAIN_NAME\"\]=.*/\[\"$NEW_DOMAIN_NAME\"\]=\"$xml_file\"/" "$file"
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
    printf "%s [-h] [-s source_domain] [-x source_xml] [-n new_domain] [-p platform] \n" "$(basename "${BASH_SOURCE[0]}")"
    printf "[--igpu_vf_auto start_vf_num] [--igpu_vf vf_num] [--igpu_vf_force vf_num] [--forceclean] [--forceclean_domain] [--preserve_data]\n"
    printf "This script clone a new Ubuntu or Windows guest VM from an existing domain or XML file using virt-clone.\n"
    printf "It support changing of the iGPU SRIOV VF in the new guest VM if iGPU VF is passthrough in the source.\n"
    printf "The input vf_num will be checked if within valid range from 1 to maximum iGPU VF supported.\n"
    printf "By default, --igpu_vf_auto 1 is enabled and all existing domains is checked for iGPU VF usage \n"
    printf "against the range from 1 to maximum iGPU VF to determine the next available VF for the new VM.\n"
    printf "New domain created will be automatically added to the platform launch_multios.sh and the domain xml \n"
    printf "saved in the libvirt_xml folder.\n"
    printf "Options:\n"
    printf "\t-h                           Show this help message\n"
    printf "\t-s source_domain             Source domain name to clone from, mutually exclusive with -x option\n"
    printf "\t-x source_xml                Source XML to clone from, mutually exclusive with -o option\n"
    printf "\t-n new_domain                New domain name\n"
    printf "\t-p platform                  Specific platform to setup for, eg. \"-p client \"\n"
    printf "\t                             Accepted values:\n"
    get_supported_platform_names platforms
    for p in "${platforms[@]}"; do
    printf "\t                             %s\n" "$(basename "$p")"
    done
    printf "\t--igpu_vf_auto start_vf_num  Auto search for available vf, starting from start_vf_num to maximum available vf\n"   
    printf "\t--igpu_vf vf_num             Use vf_num for igpu sriov in the new domain only if vf_num has not been used in existing domains\n"
    printf "\t--igpu_vf_force vf_num       Use vf_num for igpu sriov in the new domain, not considering if the vf_num has been used in existing domains\n"   
    printf "\t--forceclean                 Delete both new domain and image data if already exists. Default not enabled, mutually exclusive with --preserve_data\n"
    printf "\t--forceclean_domain          Delete only new domain if already exists. Default not enabled\n"
    printf "\t--preserve_data              Preserve new domain image data if already exists, create new one if not exist. Default not enabled\n"
    printf "Usage examples:\n"
    printf "Clone from existing ubuntu domain, auto search available iGPU VF starting from 4\n"
    printf "./guest_setup/ubuntu/clone_guest.sh -s ubuntu -n ubuntu_2 -p client --igpu_vf_auto 4\n"
    printf "Clone from windows xml, using iGPU VF 4\n"
    printf "./guest_setup/ubuntu/clone_guest.sh -x windows_sriov_ovmf.xml -n windows_2 -p client --igpu_vf 4\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit 0
                ;;
            -s)
                SOURCE_DOMAIN_NAME=$2
                shift
                ;;
            -x)
                SOURCE_XML=$2
                shift
                ;;
            -n)
                NEW_DOMAIN_NAME=$2
                shift
                ;;
            -p)
                set_platform_name "$2" || return 255
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
            --igpu_vf)
                if ! is_valid_igpu_vf "$2"; then
                    show_help
                    return 255
                fi
                IGPU_VF=$2
                shift
                ;;
            --igpu_vf_force)
                if ! is_valid_igpu_vf "$2"; then
                    show_help
                    return 255
                fi
                IGPU_VF_FORCE=$2
                shift
                ;;
            --igpu_vf_auto)
                if ! is_valid_igpu_vf "$2"; then
                    show_help
                    return 255
                fi
                IGPU_VF_AUTO=$2
                shift
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

# Uncomment function if needed
#function cleanup () {
#}

#-------------    main processes    -------------
# Uncomment cleanup trap if needed
#trap 'cleanup' EXIT
trap 'error ${LINENO} "$BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

if [[ -z "${NEW_DOMAIN_NAME+x}" || -z "$NEW_DOMAIN_NAME" ]]; then
    echo "Error: valid VM domain name needed"
    show_help
    exit 255
fi
if [[ -z "${SOURCE_DOMAIN_NAME+x}" || -z "$SOURCE_DOMAIN_NAME" ]]; then
    if [[ -z "${SOURCE_XML+x}" || -z "$SOURCE_XML" ]]; then
        echo "Error: either original domain or xml is required"
        show_help
        exit 255
    fi
fi
if [[ -n "${SOURCE_DOMAIN_NAME+x}" && -n "$SOURCE_DOMAIN_NAME" ]]; then
    if [[ -n "${SOURCE_XML+x}" && -n "$SOURCE_XML" ]]; then
        echo "Error: use either original domain or xml but not both"
        show_help
        exit 255
    fi
fi
if [[ -z "${PLATFORM_NAME+x}" || -z "$PLATFORM_NAME" ]]; then
	echo "Error: valid platform name required"
    show_help
    exit 255
fi
if [[ "$FORCECLEAN" == "1" && "$PRESERVE_DATA" == "1" ]]; then
    echo "Error: Use --forceclean to overwrite or --preserve_data to use the existing image, cannot use both."
    show_help
    exit 255
fi
if [[ -f "$LIBVIRT_DEFAULT_IMAGES_PATH/$NEW_DOMAIN_NAME.qcow2" ]]; then
    if [[ "$FORCECLEAN" != "1" && "$PRESERVE_DATA" != "1" ]]; then
        echo "Error: $NEW_DOMAIN_NAME.qcow2 image already exists! Use --forceclean to overwrite or --preserve_data to use the existing image."
        show_help
        exit 255
    fi
fi
check_domain || exit 255
check_host_distribution || exit 255
install_dep || exit 255
clone_vm || exit 255
update_launch_multios || exit 255

echo "$(basename "${BASH_SOURCE[0]}") done"
exit 0

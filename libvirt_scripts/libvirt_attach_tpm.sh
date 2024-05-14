#!/bin/bash

# Copyright (c) 2023-2024 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------  Global variables  -------------------

# Default parameters
LIBVIRT_QEMU_PATH="/etc/libvirt/qemu/"

domain_name=""
tpm_type=""
tpm_model="crb"
tpm_device="/dev/tpm0"
tpm_version="2.0"

#---------      Functions    -------------------
#
# Function to show help information
function show_help() {
    printf "%s -h -d <domain_name> -type <passthrough/emulated> [-model <tis/crb>] [-version <2.0>] [-device </dev/tpm0>]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Options:\n"
    printf "\t-h            show this help message\n"
    printf "\t-d            domain name, eg. ubuntu or windows \n"
    printf "\t-type         TPM backend type, eg. passthrough or emulated \n"
    printf "\t-model        TPM model, eg. tis or crb\n"
    printf "\t-version      TPM version, eg. 2.0\n"
    printf "\t-device       TPM device name, eg. /dev/tpm0\n"
    printf "Warning:\n"
    printf "Passthrough TPM device to any guest vm will force stop the service(s) using TPM on the host!\n"
}

# Function to parse input arguments
function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h)
                show_help
                exit 0
                ;;
            -d)
                if [[ -z "${2+x}" || -z "$2" ]]; then
                    echo "Error: '-d' option requires a parameter."
                    show_help
                    exit 255
                fi
                domain_name="$2"
                shift 2
                ;;
            -type)
                if [[ -z "${2+x}" ||  -z "$2" ]]; then
                    echo "Error: '-type' option requires a parameter."
                    show_help
                    exit 255
                fi
                tpm_type="$2"
                shift 2
                ;;
            -model)
                if [[ -z "${2+x}" ||  -z "$2" ]]; then
                    echo "Error: '-model' option requires a parameter."
                    show_help
                    exit 255
                fi
                tpm_model="$2"
                shift 2
                ;;
            -version)
                if [[ -z "${2+x}" ||  -z "$2" ]]; then
                    echo "Error: '-version' option requires a parameter."
                    show_help
                    exit 255
                fi
                tpm_version="$2"
                shift 2
                ;;
            -device)
                if [[ -z "${2+x}" ||  -z "$2" ]]; then
                    echo "Error: '-device' option requires a parameter."
                    show_help
                    exit 255
                fi
                tpm_device="$2"
                shift 2
                ;;
            *)
                echo "Error: Invalid argument."
                show_help
                exit 255
                ;;
        esac
    done

    # Check for required options
    if [[ -z "${domain_name:-}" ]]; then
        echo "Error: Missing required option '-d <domain_name>'."
        show_help
        exit 255
    fi

    # Check for required options
    if [[ -z "${tpm_type:-}" ]]; then
        echo "Error: Missing required option '-type <passthrough/emulated>'."
        show_help
        exit 255
    fi
}

# Function to validate type
function validate_type() {
    if [[ "$tpm_type" != "passthrough" && "$tpm_type" != "emulated" ]]; then
        echo "Error: Type should be 'passthrough' or 'emulated'."
        show_help
        exit 255
    fi
}

# Function to validate model
function validate_model() {
    if [[ "$tpm_model" != "tis" && "$tpm_model" != "crb" ]]; then
        echo "Error: Model should be 'tis' or 'crb'."
        show_help
        exit 255
    fi
}

# Function to validate version
function validate_version() {
    if [[ "$tpm_version" != "2.0" ]]; then
        echo "Error: Currently only supports TPM version '2.0'."
        show_help
        exit 255
    fi
}

# Function to validate device path (used only in passthrough mode)
function validate_device_path() {
    if [[ "$tpm_type" == "passthrough" ]] && [[ ! -e "$tpm_device" ]]; then
        echo "Error: Device path '$tpm_device' does not exist."
        show_help
        exit 255
    fi
}

# Function to append TPM XML content
function append_tpm_config() {
    local domain="$1"
    local xml_file="$LIBVIRT_QEMU_PATH$domain.xml"

    if [ ! -f "$xml_file" ]; then
        echo "Error: XML file '$xml_file' not found."
        exit 1
    fi

    # Define the TPM XML content based on mode
    local tpm_xml=""
    if [[ "$tpm_type" == "passthrough" ]]; then
        tpm_xml="<tpm model=\"tpm-$tpm_model\">
          <backend type=\"$tpm_type\">
            <device path=\"$tpm_device\"/>
          </backend>
        </tpm>"
    elif [[ "$tpm_type" == "emulated" ]]; then
        tpm_xml="<tpm model=\"tpm-$tpm_model\">
          <backend type=\"emulator\"/>
        </tpm>"
    else
        # by right should not reach here!
        echo "Error: Type should be 'passthrough' or 'emulated'."
        show_help
        exit 255
    fi

    # Check if TPM device already exists and remove it
    sudo sed -i '/<tpm/,/<\/tpm>/d' "$xml_file"

    # Insert the TPM XML content within <devices> section
    #TODO: do not touch domain file in libvirt directory
    #shellcheck disable=SC1078
    sudo bash -c "awk -v tpm_xml='$tpm_xml' '
      /<devices>/ {
        devices=1
      }
      /<\/devices>/ {
        if (devices) {
          print tpm_xml
          devices=0
        }
      }
      { print }
    ' \"$xml_file\" > temp.xml && mv temp.xml \"$xml_file\""

    # Redefine domain for the updated xml
    sudo virsh define "$xml_file"
}

function check_tpm_services() {
    # Check if any service is using /dev/tpm0
    if sudo lsof "$tpm_device" &> /dev/null; then
        echo "Services are using $tpm_device on the host"

        # Identify services using TPM device and stop them
        tpm_services=$(sudo lsof -t "$tpm_device" | xargs -I {} ps -p {} -o comm=)
        while IFS= read -r service; do
            echo "Stopping $service ..."
            sudo systemctl stop "$service"
        done <<< "$tpm_services"
    else
        echo "No service is using $tpm_device on the host"
    fi
}

# Main function to execute the script
function main() {
    parse_arg "$@" || return 255
    validate_type || return 255
    validate_model || return 255
    validate_version || return 255
    validate_device_path || return 255
    append_tpm_config "$domain_name" || return 255
    check_tpm_services || return 255
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

main "$@" || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

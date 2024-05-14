#!/bin/bash

# Copyright (c) 2023-2024 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
# Define supported VM domains and configuration files
declare -A VM_DOMAIN=(
  ["ubuntu"]="ubuntu_vnc_spice.xml"
  ["windows"]="windows_vnc_spice.xml"
  ["redhat"]="redhat_vnc_spice.xml"
  ["centos"]="centos_vnc_spice.xml"
)

# Array to store the list of passthrough devices
declare -A device_passthrough

# Define variables

# Set default vm image directory and vm config xml file directory
#IMAGE_DIR="/home/user/vm_images/"

# Set passthrough script name
PASSTHROUGH_SCRIPT="./libvirt_scripts/virsh_attach_device.sh"

# Set default domain force launch option
FORCE_LAUNCH="false"

# Set default vm config xml file directory
XML_DIR="./platform/server/libvirt_xml"

# Error log file
ERROR_LOG_FILE="/tmp/launch_multios_errors.log"

#---------      Functions    -------------------
declare -F "check_non_symlink" >/dev/null || function check_non_symlink() {
    if [[ $# -eq 1 ]]; then
        if [[ -L "$1" ]]; then
            echo "Error: $1 is a symlink." | tee -a "$ERROR_LOG_FILE"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}" | tee -a "$ERROR_LOG_FILE"
        exit 255
    fi
}

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f "$fpath" || ! -s "$fpath" ]]; then
            echo "Error: $fpath invalid/zero sized" | tee -a "$ERROR_LOG_FILE"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}" | tee -a "$ERROR_LOG_FILE"
        exit 255
    fi
}

# Function to log errors
function log_error() {
  echo "$(date): line: ${BASH_LINENO[0]}: $1" >> "$ERROR_LOG_FILE"
  echo "Error: $1"
  echo ""
}


function show_help() {
  printf "Usage:\n"
  printf "%s [-h|--help] [-f] [-a] [-d <domain1> <domain2> ...] [-p <domain> --usb|--pci <device> (<number>) | -p <domain> --xml <xml file>]\n" "$(basename "${BASH_SOURCE[0]}")"
  printf "Launch one or more guest VM domain(s) with libvirt\n\n"
  printf "Options:\n"
  printf "  -h,--help                     Show the help message and exit\n"
  printf "  -f                            Force shutdown, destory and start VM domain(s) without checking\n"
  printf "                                if it's already running.\n"
  printf "  -a                            Launch all defined VM domains\n"
  printf "  -d <domain(s)>                Name of the VM domain(s) to launch\n"
  printf "  -p <domain>                   Name of the VM domain for device passthrough\n"
  printf "      --usb | --pci             Options of interface (eg. --usb or --pci)\n"
  printf "      <device>                  Name of the device (eg. mouse, keyboard, bluetooth, etc\n"
  printf "      (<number>)                Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'\n"
  printf "                                by default is the first device found\n"
  printf "  -p <domain> --xml <xml file>  Passthrough devices defined in an XML file\n\n"
  printf "Supported domains:\n"
  for domain in "${!VM_DOMAIN[@]}"; do
    printf "  -  %s\n" "$domain"
  done
}

# Function to handle command line arguments
function parse_arg() {
  # Print help if no input argument found
  if [[ $# -eq 0 ]]; then
    log_error "No input argument found"
    show_help
    exit 255
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -f)
        FORCE_LAUNCH="true"
        shift
        ;;
      -a)
        domains=("${!VM_DOMAIN[@]}")
        shift
        ;;
      -d)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option"
          show_help
          exit 255
        fi
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-[^-] ]]; do
          # Check if domain is supported
          if [[ ! "${!VM_DOMAIN[*]}" =~ $1 ]]; then
            log_error "Domain $1 is not supported."
            show_help
            exit 255
          fi
          domains+=("$1")
          shift
          done
          ;;
      -p)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option."
          show_help
          exit 255
        fi
        domain=$2
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[*]}" =~ $domain ]]; then
          log_error "Domain $domain is not supported."
          show_help
          exit 255
        fi
        shift 2
        devices=()
        # Check passthrough options
        while [[ $# -gt 0 && ("$1" == "--xml" || "$1" == "--usb" || "$1" == "--pci") ]]; do
          if [[ "$1" == "--xml" ]]; then
            if [[ -z "$2" || "$2" == -* ]]; then
              log_error "Missing XML file name after --xml"
              show_help
              exit 255
            fi
            devices+=("$1" "$2")
            shift 2
          elif [[ "$1" == "--usb" || "$1" == "--pci" ]]; then
            if [[ -z "$2" || "$2" == -* ]]; then
              log_error "Missing device name after $1"
              show_help
              exit 255
            fi
            if [[ -z "$3" || "$3" == -* ]]; then
              devices+=("$1" "$2")
              shift 2
            else
              devices+=("$1" "$2" "$3")
              shift 3
            fi
          else
            log_error "unknown device type"
            show_help
            exit 255
          fi
        done
        if [[ ${#devices[@]} -eq 0 ]]; then
          log_error "Missing device parameters after -p $domain"
          show_help
          exit 255
        fi
        device_passthrough["$domain"]="${devices[*]}"
        ;;

      -?*)
          echo "Error: Invalid option: $1"
          show_help
          return 255
          ;;
      *)
          echo "Error: Unknown option: $1"
          return 255
          ;;
    esac
  done
}

# Function to check if domain is already exist or running
function check_domain() {
  for domain in "$@"; do
    status=$(virsh domstate "$domain" 2>&1 ||:)

    if [[ "$status" =~ "running" || "$status" =~ "paused" ]]; then
      if [[ ! "$FORCE_LAUNCH" == "true" ]]; then
        read -r -p "Domain $domain is already $status. Do you want to continue (y/n)? " choice
        case "$choice" in
          y|Y)
            # Continue to cleanup vm domain
            cleanup_domain "$domain"
            ;;
          n|N)
            echo "Aborting launch of domain"
            exit 255
            ;;
          *)
            log_error "Invalid choice. Aborting launch of domain"
            show_help
	    exit 255
            ;;
        esac
      else
        cleanup_domain "$domain"
      fi
    elif [[ "$status" =~ "shut off" ]]; then
      echo "Domain $domain is shut off. Undefining domain $domain"
      virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    #domstate may return "error: failed to get domain" for undefine domain
    elif [[ "$status" =~ "not found" || "$status" =~ "error" ]]; then
      echo "Domain $domain not found. Proceeding with launch"
    else
      echo "Domain $domain is $status. Destroy and undefine domain"
      virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
      virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    fi
  done
}

# Function to shutdown and undefine a domain
function cleanup_domain() {
  local domain="$1"
  echo "Shutting down and undefining domain $domain"
  virsh shutdown "$domain" >/dev/null 2>&1 || :
  # check if VM has shutdown at 5s interval, timeout 60s
  for (( x=0; x<12; x++ )); do
      echo "Wait for $domain to shutdown: $x"
      sleep 5
      state=$(virsh list --all | grep " $domain " | awk '{ print $3}')
      if [[ "$state" == "shut" ]];then
          break
      fi
  done
  state=$(virsh list --all | grep " $domain " | awk '{ print $3}')
  if [[ "$state" != "shut" ]];then
      echo "$domain in $state, force destroy $domain"
  virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
  fi
  virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
}

# Function to launch domain(s)
function launch_domains() {
  for domain in "$@"; do
    # Check if domain is supported
    if [[ ! "${VM_DOMAIN[*]}" =~ $domain ]]; then
      # By right should not come here, just double check
      log_error "Domain $domain is not supported."
      show_help
      exit 255
    fi
  done

  for domain in "$@"; do
    # Check if domain is already running or defined
    check_domain "$domain"
  done

  for domain in "$@"; do
    # Define domain
    echo "Define domain $domain"
    check_file_valid_nonzero "$XML_DIR/${VM_DOMAIN[$domain]}"
    virsh define "$XML_DIR/${VM_DOMAIN[$domain]}"

    # Passthrough devices
    echo "Passthrough device to domain $domain if any"
    passthrough_devices $domain

    # Start domain
    echo "Starting domain $domain..."
    virsh start $domain
    sleep 2
  done
}

# Function to passthrough devices
function passthrough_devices() {
  local domain=$1

  # Check if domain has device passthrough
  if [[ "${device_passthrough[$domain]+_}" ]]; then
    local raw_devices="${device_passthrough[$domain]}"
    local devices=()
    IFS=' ' read -r -a devices <<< "$raw_devices"

    # Check the list of devices
    local i=0
    while [[ $i -lt "${#devices[@]}" ]]; do
      local option=${devices[$i]}
      case $option in
        --xml)
          # XML file passthrough
          echo "Use XML file passthrough for domain: $domain"
          local xml_file=${devices[$i + 1]}
          check_file_valid_nonzero "$xml_file"
          if [[ ! -f "$xml_file" ]]; then
            log_error "XML file not found for domain $domain: $xml_file"
            show_help
            exit 255
          fi
          echo "Performing XML file passthrough for domain $domain"
          virsh attach-device "$domain" --config --file "$xml_file"
          ((i+=2))
          ;;

        --usb | --pci)
          # Individual device passthrough
          local interface=$option
          local device_name=""
          local device_number="1"

          # Process device name and number
          ((i+=1))
          while [[ $i -lt ${#devices[@]} && ${devices[$i]} != -* ]]; do
            current_device=${devices[$i]}
            if [[ -n "$current_device" ]]; then
              # Check if the current device is a digit
              if [[ "$current_device" =~ ^[0-9]+$ ]]; then
                device_number=$current_device
              else
                # Add the current device to the device name
                if [[ -z "$device_name" ]]; then
                  device_name=$current_device
                else
                  device_name+=" $current_device"
                fi
              fi
            fi
            ((i+=1))
          done

          # Perform device passthrough
          echo "Performing device passthrough for domain $domain with $interface device $device_name $device_number"
          "$PASSTHROUGH_SCRIPT" -p "$domain" "$interface" "$device_name" "$device_number"
          ;;

        *)
          log_error "Invalid passthrough device option: $option"
          show_help
          exit 255
          ;;
      esac

    done
  else
    # No device passthrough
    echo "No device passthrough for domain $domain"
  fi
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR
parse_arg "$@" || exit 255

# Launch domain(s)
launch_domains "${domains[@]}" || exit 255
exit 0

#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

# Define supported VM domains and configuration files
declare -A VM_DOMAIN=(
  ["ubuntu"]="ubuntu_vnc.xml"
  ["windows"]="windows_vnc.xml"
  ["redhat"]="redhat_vnc.xml"
  ["centos"]="centos_vnc.xml"
)

# Array to store the list of passthrough devices
declare -A device_passthrough

# Define variables

# Set default vm image directory and vm config xml file directory
IMAGE_DIR="/home/user/vm_images/"

# Set passthrough script name
PASSTHROUGH_SCRIPT="./libvirt_scripts/virsh_attach_device.sh"

# Set default domain force launch option
FORCE_LAUNCH="false"

# Set default vm config xml file directory
XML_DIR="./platform/server/libvirt_xml"

# Error log file
ERROR_LOG_FILE="launch_multios_errors.log"

# Function to log errors
function log_error() {
  echo "$(date): line: ${BASH_LINENO[0]}: $1" >> $ERROR_LOG_FILE
  echo "Error: $1"
  echo ""
}

# Function to print help info
function print_help() {
  echo ""
  echo "Usage:"
  echo "sudo $0 [-h|--help] [-f] [-a] [-d <domain1> <domain2> ...] [-p <domain> --usb|--pci <device> (<number>) | -p <domain> --xml <xml file>]"
  echo ""
  echo "Launch one or more guest VM domain(s) with libvirt"
  echo "Options:"
  echo "  -h,--help                     Show the help message and exit"
  echo "  -f                            Force shutdown, destory and start VM domain(s) without checking"
  echo "                                if it's already running"
  echo "  -a                            Launch all defined VM domains"
  echo "  -d <domain(s)>                Name of the VM domain(s) to launch"
  echo "  -p <domain>                   Name of the VM domain for device passthrough"
  echo "     --usb | --pci              Options of interface (eg. --usb or --pci)"
  echo "     <device>                   Name of the device (eg. mouse, keyboard, bluetooth, etc"
  echo "     (<number>)                 Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'"
  echo "                                by default is the first device found"
  echo "  -p <domain> --xml <xml file>  Passthrough devices defined in an XML file"
  echo ""
  echo "Supported domains:"
  for domain in "${!VM_DOMAIN[@]}"; do
    echo "  - $domain"
  done
  echo ""
}

# Function to handle command line arguments
function handle_arguments() {
  # Print help if no input argument found
  if [[ $# -eq 0 ]]; then
    log_error "No input argument found"
    print_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_help
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
          print_help
          exit 1
        fi
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-[^-] ]]; do
          # Check if domain is supported
          if [[ ! "${!VM_DOMAIN[@]}" =~ "$1" ]]; then
            log_error "Domain $1 is not supported."
            print_help
            exit 1
          fi
          domains+=("$1")
          shift
          done
          ;;
      -p)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option."
          print_help
          exit 1
        fi
        domain=$2
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[@]}" =~ "$domain" ]]; then
          log_error "Domain $domain is not supported."
          print_help
          exit 1
        fi
        shift 2
        devices=()
        # Check passthrough options
        while [[ $# -gt 0 && ($1 != -* || $1 == "--xml" || $1 == "--usb" || $1 == "--pci") ]]; do
          if [[ $1 == "--xml" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing XML file name after --xml"
              print_help
              exit 1
            fi
            devices+=("$1" "$2")
            shift 2
          elif [[ $1 == "--usb" || $1 == "--pci" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing device name after $1"
              print_help
              exit 1
            fi
            devices+=("$1" "$2")
            shift 2
          else
            devices+=("$1")
            shift
          fi
        done
        if [[ ${#devices[@]} -eq 0 ]]; then
          log_error "Missing device parameters after -p $domain"
          print_help
          exit 1
        fi
        device_passthrough[$domain]="${devices[*]}"
        ;;

      *)
        log_error "Invalid argument '${1}'"
        print_help
        exit 1
        ;;
    esac
  done
}

# Function to check if domain is already exist or running
function check_domain() {
  for domain in "$@"; do
    status=$(sudo virsh domstate "$domain" 2>&1 ||:)

    if [[ "$status" =~ "running" || "$status" =~ "paused" ]]; then
      if [[ ! "$FORCE_LAUNCH" == "true" ]]; then
        read -p "Domain $domain is already $status. Do you want to continue (y/n)? " choice
        case "$choice" in
          y|Y)
            # Continue to cleanup vm domain
            cleanup_domain "$domain"
            ;;
          n|N)
            echo "Aborting launch of domain"
            exit 1
            ;;
          *)
            log_error "Invalid choice. Aborting launch of domain"
            print_help
	    exit 1
            ;;
        esac
      else
        cleanup_domain "$domain"
      fi
    elif [[ "$status" =~ "shut off" ]]; then
      echo "Domain $domain is shut off. Undefining domain $domain"
      sudo virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    #domstate may return "error: failed to get domain" for undefine domain
    elif [[ "$status" =~ "not found" || "$status" =~ "error" ]]; then
      echo "Domain $domain not found. Proceeding with launch"
    else
      echo "Domain $domain is $status. Destroy and undefine domain"
      sudo virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
      sudo virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    fi
  done
}

# Function to shutdown and undefine a domain
function cleanup_domain() {
  local domain="$1"
  echo "Shutting down and undefining domain $domain"
  sudo virsh shutdown "$domain" >/dev/null 2>&1 || :
  # check if VM has shutdown at 5s interval, timeout 60s
  for (( x=0; x<12; x++ )); do
      echo "Wait for $domain to shutdown: $x"
      sleep 5
      state=$(sudo virsh list --all | grep " $domain " | awk '{ print $3}')
      if [[ "$state" == "shut" ]];then
          break
      fi
  done
  state=$(sudo virsh list --all | grep " $domain " | awk '{ print $3}')
  if [[ "$state" != "shut" ]];then
      echo "$domain in $state, force destroy $domain"
  sudo virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
  fi
  sudo virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
}

# Function to launch domain(s)
function launch_domains() {
  for domain in "$@"; do
    # Check if domain is supported
    if [[ ! "${VM_DOMAIN[@]}" =~ "$domain" ]]; then
      # By right should not come here, just double check
      log_error "Domain $domain is not supported."
      print_help
      exit 1
    fi
  done

  for domain in "$@"; do
    # Check if domain is already running or defined
    check_domain "$domain"
  done

  for domain in "$@"; do
    # Define domain
    echo "Define domain $domain"
    sudo virsh define $XML_DIR/${VM_DOMAIN[$domain]}

    # Passthrough devices
    echo "Passthrough device to domain $domain if any"
    passthrough_devices $domain

    # Start domain
    echo "Starting domain $domain..."
    sudo virsh start $domain
    sleep 2
  done
}

# Function to passthrough devices
function passthrough_devices() {
  local domain=$1

  # Check if domain has device passthrough
  if [[ ${device_passthrough[$domain]+_} ]]; then
    local raw_devices="${device_passthrough[$domain]}"
    local devices=()
    IFS=' ' read -r -a devices <<< "$raw_devices"

    # Check the list of devices
    local i=0
    while [[ $i -lt ${#devices[@]} ]]; do
      local option=${devices[$i]}
      case $option in
        --xml)
          # XML file passthrough
          echo "Use XML file passthrough for domain: $domain"
          local xml_file=${devices[$i + 1]}
          if [[ ! -f $xml_file ]]; then
            log_error "XML file not found for domain $domain: $xml_file"
            print_help
            exit 1
          fi
          echo "Performing XML file passthrough for domain $domain"
          sudo virsh attach-device $domain --config --file $xml_file
          ((i+=2))
          ;;

        --usb | --pci)
          # Individual device passthrough
          local interface=${option#--}
          local device_name=""
          local device_number=""

          # Process device name and number
          ((i+=1))
          while [[ $i -lt ${#devices[@]} && ${devices[$i]} != -* ]]; do
            current_device=${devices[$i]}
            if [[ -n "$current_device" ]]; then
              # Check if the current device is a digit
              if [[ $current_device =~ ^[0-9]+$ ]]; then
                device_number=$current_device
              else
                # Add the current device to the device name
                if [[ -z $device_name ]]; then
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
          $PASSTHROUGH_SCRIPT $domain $interface "$device_name" $device_number
          ;;

        *)
          log_error "Invalid passthrough device option: $option"
          print_help
          exit 1
          ;;
      esac

    done
  else
    # No device passthrough
    echo "No device passthrough for domain $domain"
  fi
}

# main function
function main() {
  # Handle input arguments
  handle_arguments "$@"

  # Launch domain(s)
  launch_domains "${domains[@]}"
}

# Call main function
main "$@"

exit 0

#!/bin/bash

# Copyright (c) 2023-2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail


#---------      Global variable     -------------------
# Define supported VM domains and configuration files
declare -A VM_DOMAIN=(
  ["ubuntu"]="ubuntu_vnc_spice.xml"
  ["windows"]="windows_vnc_spice_ovmf.xml"
  ["ubuntu_rt"]="ubuntu_rt_headless.xml"
  ["android"]="android_virtio-gpu.xml"
  ["windows11"]="windows11_vnc_spice_ovmf.xml"
)

# Array to store the list of passthrough devices
declare -A device_passthrough

# Array to store multi-display configuration for specific VM
declare -A multi_display

# Array to store network name per domain
declare -a DOMAIN_NET_PAIRS=()

# Define variables

# Set default vm image directory and vm config xml file directory
#IMAGE_DIR="/var/lib/libvirt/images/"

# Set passthrough script name
PASSTHROUGH_SCRIPT="./libvirt_scripts/virsh_attach_device.sh"

# Set tpm attach script name
TPM_ATTACH_SCRIPT="./libvirt_scripts/libvirt_attach_tpm.sh"

# Set multi display script name
MULTI_DISPLAY_SCRIPT="./libvirt_scripts/libvirt_multi_display.sh"

# Set libvirt xml script name
SETUP_LIBVIRT_XML_SCRIPT="./host_setup/ubuntu/setup_libvirt_xml.sh"

# Set libvirt network script name
LIBVIRT_NETWORK_SCRIPT="./libvirt_scripts/libvirt_network.sh"

# Set default domain force launch option
FORCE_LAUNCH="false"

# Set default vm config xml file directory
XML_DIR="./platform/client/libvirt_xml"

# Set default BIOS used for windows VM
BIOS_WIN="ovmf"

# Disable SRIOV by default
SRIOV_ENABLE="false"

# Number of VF configure for SRIOV
#SRIOV_VF_NUM=3

# Error log file
ERROR_LOG_FILE="/tmp/launch_multios_errors.log"

# This variable is used to check if the domain is already defined
declare -A REDEFINE_DOMAIN=(
  ["ubuntu"]=1
  ["windows"]=1
  ["ubuntu_rt"]=1
  ["android"]=1
  ["windows11"]=1
)

# This variable is used to check if snapshots should be deleted
DELETE_SNAPSHOTS=0

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

# Function to show help info
function show_help() {
  printf "%s [-h|--help] [-f] [-a] [-d <domain1> <domain2> ...] [-g <headless|vnc|spice|spice-gst|sriov|gvtd> <domain>] [-n <sriov|network_name> <domain(s)>] [-p <domain> [[--usb|--pci <device>] (<number>) | [--usbtree <bus-port_L1.port_L2...port_Lx>]] | -p <domain> --tpm <type> (<model>) | -p <domain> --xml <xml file>]\n" "$(basename "${BASH_SOURCE[0]}")"
  printf "Launch one or more guest VM domain(s) with libvirt\n\n"
  printf "Options:\n"
  printf "  -h,--help                                         Show the help message and exit\n"
  printf "  -f                                                Force shutdown, destroy and start VM domain(s) without checking\n"
  printf "                                                    if it's already running\n"
  printf "                                                    Snapshots will be deleted if any\n"
  printf "  -a                                                Launch all defined VM domains\n"
  printf "  -d <domain(s)>                                    Name of the VM domain(s) to launch\n"
  printf "  -g <headless|vnc|spice|spice-gst|sriov|gvtd>      Type of display model use by the VM domain\n"
  printf "      <domain(s)>                                   \n"
  printf "  -n <sriov|network_name> <domain(s)>               Attach the specified network to one or more domains.\n"
  printf "                                                    Choose 'sriov' to auto-select an available SR-IOV pool.\n"
  printf "                                                    or <network_name> which is any network from 'virsh net-list --name'.\n"
  printf "                                                    Multiple domains can be specified after a network name.\n"
  printf "                                                    This option can be used multiple times for different combinations.\n"
  printf "                                                    Example: -n default ubuntu windows11 -n sriov ubuntu -n isolated-guest-net windows11\n"
  printf "  -p <domain>                                       Name of the VM domain for device passthrough\n"
  printf "      --usb | --pci                                 Options of interface (eg. --usb or --pci)\n"
  printf "      <device>                                      Name of the device (eg. mouse, keyboard, bluetooth, etc\n"
  printf "      (<number>)                                    Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'\n"
  printf "                                                    by default is the first device found\n"
  printf "      --usbtree                                     Options of interface (eg. --usbtree)\n"
  printf "      <bus-port_L1.port_L2...port_Lx>               USB bus and port number retrived from lsusb -t\n"
  printf "      --tpm                                         Options of tpm device\n"
  printf "      <type>                                        Type of tpm backend (eg. passthrough)\n"
  printf "      (<model>)                                     Optional, specify the model of tpm (eg. crb or tis)\n"
  printf "                                                    by default is crb model\n"
  printf "  -p <domain> --xml <xml file>                      Passthrough devices defined in an XML file\n"
  printf "  -m <domain>                                       Name of the VM domain for multi display configuration\n"
  printf "Options for multi display:\n"
  printf "  --output n                                        Number of output displays, n, range from 1 to 4\n"
  printf "  --connectors HDMI-n/DP-n,...                      physical display connector per display output\n"
  printf "  --full-screen                                     Set display to full-screen\n"
  printf "  --show-fps                                        Show fps info on guest vm primary display\n"
  printf "  --extend-abs-mode                                 Enable extend absolute mode across all monitors\n"
  printf "  --disable-host-input                              Disable host's HID devices to control the monitors\n\n"
  printf "Supported domains:\n"
  for domain in "${!VM_DOMAIN[@]}"; do
    printf "  -  %s\n" "$domain"
  done
}

# Function to parse input arguments
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
      -g)
        # Check if next argument is a valid display model
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Display model missing after $1 option"
          show_help
          exit 255
        fi
        shift
        if [[ "$1" == "gvtd" || "$1" == "sriov" || "$1" == "vnc" || "$1" == "spice" || "$1" == "spice-gst" || "$1" == "headless" ]]; then
          display="$1"
          if [[ "$1" == "sriov" || "$1" == "spice-gst" ]]; then
            SRIOV_ENABLE="true"
          fi
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
            # No VNC/SPICE/headless display support for Android
            if [[ "$1" == "android" ]]; then
              if [[ "${display}" == "vnc" || "${display}" == "spice" || "${display}" == "spice-gst" || "${display}" == "headless" ]]; then
                log_error "VNC/SPICE/SPICE-GST/headless display for Android is not supported."
                show_help
                exit 255
              fi
            fi
            if [[ ! "${VM_DOMAIN[$1]}" =~ ${display} ]]; then
              if [[ "$1" == "windows" || "$1" == "windows11" ]]; then
                VM_DOMAIN[$1]="${1}_${display}_${BIOS_WIN}.xml"
              else
                VM_DOMAIN[$1]="${1}_${display}.xml"
              fi
            fi
            shift
          done
        else
          log_error "Display model $1 not supported"
          show_help
          exit 255
        fi
        ;;
      -p)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option"
          show_help
          exit 255
        fi
        domain=$2
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[*]}" =~ $domain ]]; then
          log_error "Domain $domain is not supported"
          show_help
          exit 255
        fi
        shift 2
        devices=()
        # Check passthrough options
        while [[ $# -gt 0 && ($1 == "--xml" || $1 == "--usb" || $1 == "--usbtree" || $1 == "--pci" || $1 == "--tpm") ]]; do
          if [[ $1 == "--xml" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing XML file name after --xml"
              show_help
              exit 255
            fi
            devices+=("$1" "$2")
            shift 2
          elif [[ "$1" == "--usb" || $1 == "--usbtree" || "$1" == "--pci" ]]; then
            if [[ -z "$2" || "$2" == -* ]]; then
              log_error "Missing device name or bus:port after $1"
              show_help
              exit 255
            fi
            if [[ $# -lt 3 || -z "$3" || "$3" == -* ]]; then
              devices+=("$1" "$2")
              shift 2
            else
              devices+=("$1" "$2" "$3")
              shift 3
            fi
          elif [[ "$1" == "--tpm" ]]; then
            if [[ -z "$2" || "$2" == -* ]]; then
              log_error "Missing tpm passthrough parameters after $1"
              show_help
              exit 255
            fi
            if [[ $# -lt 3 || -z "$3" || "$3" == -* ]]; then
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
        device_passthrough[$domain]="${devices[*]}"
        ;;
      -m)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option"
          show_help
          exit 255
        fi
        domain=$2
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[*]}" =~ $domain ]]; then
          log_error "Domain $domain is not supported"
          show_help
          exit 255
        fi
        shift 2
        display_args=()
        # Check multi display options
        while [[ $# -gt 0 && ("$1" != -* || "$1" == "--output" || "$1" == "--connectors" || "$1" == "--full-screen" || "$1" == "--show-fps" || "$1" == "--extend-abs-mode" || "$1" == "--disable-host-input") ]]; do
          if [[ "$1" == "--output" || "$1" == "--connectors" ]]; then
            if [[ -z "$2" || "$2" == -* ]]; then
              log_error "Missing parameter after $1"
              show_help
              exit 255
            fi
            display_args+=("$1" "$2")
            shift 2
          else
            display_args+=("$1")
            shift
          fi
        done
        if [[ ${#display_args[@]} -eq 0 ]]; then
          log_error "Missing multi display parameters after -m $domain"
          show_help
          exit 255
        fi
        multi_display["$domain"]="${display_args[*]}"
        ;;

      -n)
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Missing network after -n"
          show_help
          exit 255
        fi
        net_name="$2"
        shift 2

        # Accept any network name from virsh net-list, or "sriov" keyword
        valid_net="false"
        if [[ "$net_name" == "sriov" ]]; then
          valid_net="true"
        else
          # Check if network exists in virsh net-list
          if virsh net-list --all --name | grep -Fxq "$net_name"; then
            valid_net="true"
          fi
        fi
        if [[ "$valid_net" != "true" ]]; then
          log_error "Invalid network for -n: $net_name (not found in virsh net-list)"
          show_help
          exit 255
        fi

        # Process domains for this network
        domains_found=0
        while [[ $# -gt 0 ]]; do
          # Check if this looks like an option (starts with -)
          if [[ "$1" =~ ^- ]]; then
            break
          fi
          domain="$1"
          if [[ ! "${!VM_DOMAIN[*]}" =~ $domain ]]; then
            log_error "Domain $domain is not supported."
            show_help
            exit 255
          fi
          # Store network-domain pair
          DOMAIN_NET_PAIRS+=("$net_name" "$domain")
          domains_found=1
          shift
        done

        if [[ $domains_found -eq 0 ]]; then
          log_error "Missing domain(s) after -n $net_name"
          show_help
          exit 255
        fi
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

function check_virtualization() {
    local error=0

    # Check VT-x
    local vtx
    vtx=$(lscpu | grep Virtualization | awk '{print $2}' || :;)
    if [[ "$vtx" != "VT-x" ]]; then
        echo "Error: VT-x is not enabled."
        error=1
    fi

    # Check VMX
    local kvm
    kvm=$(kvm-ok 2>&1 | grep "KVM acceleration can be used" || :;)
    if [[ -z "$kvm" ]]; then
        echo "Error: VMX is not enabled."
        error=1
    fi

    # Check VT-d
    local vtd
    vtd=$(journalctl -k -b | grep -e DMAR -e IOMMU | \
          grep -e "Virtualization Technology for Directed I/O" || :;)
    if [[ -z "$vtd" ]]; then
        echo "Error: VT-d is not enabled"
        error=1
    fi

    if [[ "$error" -eq 1 ]]; then
        echo "Please check the BIOS settings"
        exit 255
    fi
}

# Function to handle cleanup of domains
function cleanup_domain() {
  local domain="$1"
  local status
  status=$(virsh domstate "$domain" 2>&1 ||:)

  if [[ "$FORCE_LAUNCH" == "true" || "$DELETE_SNAPSHOTS" -eq 1 ]]; then
    delete_all_snapshots "$domain"
  fi

  # If force launch is set, destroy and undefine the domain without
  # user confirmation
  if [[ "$FORCE_LAUNCH" == "true" ]]; then
    if [[ "$status" == "running" || "$status" == "paused" ]]; then
      destroy_domain "$domain"
    fi
    undefine_domain "$domain"
    return 0
  fi

  # Shutdown domain if it is running or paused
  if [[ "$status" == "running" || "$status" == "paused" ]]; then
    destroy_domain "$domain"
  fi

  # If domain is running, paused or shut off, undefine it
  if [[ "${REDEFINE_DOMAIN[$domain]}" -eq 1 ]]; then
    case "$status" in
      "running"|"paused"|"shut"|"shut off")
          undefine_domain "$domain"
        ;;
    esac
  fi
  return 0
}

# Function to check if domain is already exist or running
function check_domain() {
  status=$(virsh domstate "$domain" 2>&1 ||:)
  DELETE_SNAPSHOTS=0

  # Handle not found or error status first
  if [[ "$status" == "not found" ]] || echo "$status" | grep -iq error; then
    echo "Domain $domain not found. Proceeding with launch."
    return 0
  fi

  # If FORCE_LAUNCH is set, return without any furter checks and prompts
  # Snapshots will be deleted and domain will be redefined
  if [[ "$FORCE_LAUNCH" == "true" ]]; then
    return 0
  fi

  # Check if domain XML needs to be redefined
  check_domain_xml_unchanged

  # If domain is already defined and running or paused, prompt user for confirmation
  if ! prompt_user_for_domain_conflicts "$domain" "$status"; then
    return 1
  fi
  return 0
}

function check_domain_xml_unchanged() {
  if virsh list --all | grep -q " $domain " \
  && [[ -f "$XML_DIR/.${domain}.bak" ]] \
  && diff "$XML_DIR/${VM_DOMAIN[$domain]}" "$XML_DIR/.${domain}.bak" >/dev/null; then
      REDEFINE_DOMAIN["$domain"]=0
  else
      REDEFINE_DOMAIN["$domain"]=1
  fi
}

# To be called only if FORCE_LAUNCH is not set
function prompt_user_for_domain_conflicts() {
  local domain="$1"
  local status="$2"
  # Since FORCE_LAUNCH is not set, prompt user before proceeding, if domain is already running or paused
  if [[ "$status" == "running" || "$status" == "paused" ]]; then
    read -r -p "Domain $domain is already $status. Shutdown and relaunch (y/n)? " choice
    case "$choice" in
      y|Y)
        echo "Continuing with launch of domain $domain"
        ;;
      n|N)
        echo "Aborting launch of domain $domain"
        return 1
        ;;
      *)
        log_error "Invalid choice. Aborting launch of domain $domain"
        show_help
        exit 255
        ;;
    esac
  fi

  # If user proceeds with launch, check and prompt user for deleting snapshots before redefining domain.
  # Snapshots need not be deleted if relaunching domain with same XML file
  # Only check for snapshots if domain actually exists to avoid 'failed to get domain' errors
  if virsh list --all | grep -q " $domain " && \
     virsh snapshot-list "$domain" 2>/dev/null | tail -n +3 | grep -q -v "^$"; then
    echo "Domain $domain has snapshots."
    if [[ "${REDEFINE_DOMAIN[$domain]}" -eq 1 ]]; then
      read -r -p "Domain cannot be redefined with existing snapshots. Do you want to delete all snapshots for $domain? (y/n) " snap_choice
      if [[ "$snap_choice" =~ ^[Yy]$ ]]; then
        DELETE_SNAPSHOTS=1
      else
        DELETE_SNAPSHOTS=0
        echo "Aborting domain definition for $domain due to existing snapshots."
        return 1
      fi
    fi
  fi
}

function delete_all_snapshots() {
  local domain="$1"
  # Only attempt to delete snapshots if domain exists
  if virsh list --all | grep -q " $domain "; then
    for snap in $(virsh snapshot-list "$domain" --name 2>/dev/null); do
      virsh snapshot-delete "$domain" --snapshotname "$snap"
    done
  fi
}

# Function to shutdown and undefine a domain
function destroy_domain() {
  local domain="$1"
  echo "Shutting down domain $domain"
  virsh shutdown "$domain" >/dev/null 2>&1 || :
  # check if VM has shutdown at 15s interval, timeout 60s
  for (( x=0; x<4; x++ )); do
      echo "Wait for $domain to shutdown: $x"
      sleep 15
      state=$(virsh list --all | grep " $domain " | awk '{ print $3}')
      if [[ "$state" == "shut" || "$state" == "shut off" ]];then
          break
      fi
  done
  state=$(virsh list --all | grep " $domain " | awk '{ print $3}')
  if [[ "$state" != "shut" && "$state" != "shut off" ]];then
      echo "$domain in $state, force destroy $domain"
      virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
  fi
}

function undefine_domain() {
  local domain="$1"
  virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
  # Delete backup XML file if it exists
  if [[ -f "$XML_DIR/.${domain}.bak" ]]; then
    rm -f "$XML_DIR/.${domain}.bak"
  fi
}

# Function to launch domain(s)
function launch_domains() {
  # Array to store the domains to launch
  local -A EXCLUDED_DOMAIN_BY_USER=(
    ["ubuntu"]=0
    ["windows"]=0
    ["ubuntu_rt"]=0
    ["android"]=0
    ["windows11"]=0
  )

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
    # If multiple domains are to be launched with single command, mark the ones where
    # relaunch is not needed. Eg, if user inputs no to the prompt for Windows but
    # proceeds with Ubuntu
    if ! check_domain "$domain"; then
      EXCLUDED_DOMAIN_BY_USER["$domain"]=1
    fi
  done

  for domain in "$@"; do
    # If domain is excluded by user, skip it and continue with next domain
    if [[ -n "${EXCLUDED_DOMAIN_BY_USER[$domain]+_}" && "${EXCLUDED_DOMAIN_BY_USER[$domain]}" -eq 1 ]]; then
      continue
    fi
    cleanup_domain "$domain"
    check_file_valid_nonzero "$XML_DIR/${VM_DOMAIN[$domain]}"
    if [[ "${REDEFINE_DOMAIN[$domain]}" -eq 0 ]]; then
      echo "Domain $domain is already defined. Skipping new definition."
    else
      virsh define "$XML_DIR/${VM_DOMAIN[$domain]}" || return 255
      cp "$XML_DIR/${VM_DOMAIN[$domain]}" "$XML_DIR/.${domain}.bak"
    fi

    # Configure multi-display for domain if present
    if [[ "${multi_display[$domain]+_}" ]]; then
      echo "Configure multi display for $domain"
      # word splitting intended and required in this case
      # shellcheck disable=2086
      "$MULTI_DISPLAY_SCRIPT" "$domain" ${multi_display["$domain"]} || return 255
    fi

    # Passthrough devices
    echo "Passthrough device to domain $domain if any"
    passthrough_devices "$domain" || return 255

    # Configure networks for this specific domain
    local -a domain_network_args=()
    if [[ ${#DOMAIN_NET_PAIRS[@]} -gt 0 ]]; then
      for ((i=0; i<${#DOMAIN_NET_PAIRS[@]}; i+=2)); do
        if [[ "${DOMAIN_NET_PAIRS[i+1]}" == "$domain" ]]; then
          domain_network_args+=("${DOMAIN_NET_PAIRS[i]}" "$domain")
        fi
      done
    fi

    if [[ ${#domain_network_args[@]} -gt 0 ]]; then
      echo "Configuring networks for domain $domain..."
      "$LIBVIRT_NETWORK_SCRIPT" "${domain_network_args[@]}" || return 255
    fi

    # Start domain
    echo "Starting domain $domain..."
    virsh start "$domain" || return 255
    sleep 2
  done
}

# Function to passthrough devices
function passthrough_devices() {
  local domain=$1

  # Check if domain has device passthrough
  if [[ "${device_passthrough[$domain]+_}" ]]; then
    local raw_devices="${device_passthrough[$domain]}"
    local -a devices=()
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

        --usbtree)
          # Individual device passthrough
          local interface=$option
          local device_name=""

          # Process device name
          ((i+=1))
          while [[ $i -lt ${#devices[@]} && ${devices[$i]} != -* ]]; do
            current_device=${devices[$i]}
            if [[ -n "$current_device" ]]; then
              device_name=$current_device
            fi
            ((i+=1))
          done

          # Perform device passthrough
          echo "Performing device passthrough for domain $domain with $interface device $device_name"
          "$PASSTHROUGH_SCRIPT" -p "$domain" "$interface" "$device_name"
          ;;

        --tpm)
          # TPM device passthrough
          local tpm_backend_type="passthrough"
          local tpm_model="crb"
          local domain_xml_info
          domain_xml_info=$(virsh dumpxml "$domain" 2>/dev/null)

          if [ -z "$domain_xml_info" ]; then
            echo "Error: Domain $domain does not exist or cannot be accessed."
            exit 1
          fi

          # Process TPM device parameters
          ((i+=1))
          tpm_backend_type=${devices[$i]}
          if [[ "$tpm_backend_type" != "passthrough" ]] || grep -q 'android' <<< "$domain_xml_info"; then
            log_error "tpm backend type $tpm_backend_type is not supported for domain $domain"
            show_help
            exit 255
          fi
          ((i+=1))

          # Process remaining parameters
          if [[ $i -lt ${#devices[@]} && ${devices[$i]} != -* ]]; then
            tpm_model=${devices[$i]}
            if [[ "$tpm_model" != "tis" && $tpm_model != "crb" ]]; then
              log_error "tpm passthrough model $tpm_model is invalid for domain $domain"
              show_help
              exit 255
            fi
          ((i+=1))
          fi

          # Perform TPM device passthrough
          echo "Performing TPM device passthrough for domain $domain with type: $tpm_backend_type model: $tpm_model"
          "$TPM_ATTACH_SCRIPT" -d "$domain" -type "$tpm_backend_type" -model "$tpm_model"
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
check_virtualization || exit 255

if [[ "$SRIOV_ENABLE" == "true" ]]; then
  display_num=$(who | { grep -o ' :.' || :; } | xargs)
  if [[ -z $display_num ]]; then
    echo "Error: Please log in to the host's graphical login screen on the physical display."
    exit 255
  fi
  export DISPLAY=$display_num
  xhost +
fi

"$SETUP_LIBVIRT_XML_SCRIPT"

# Launch domain(s)
launch_domains "${domains[@]}" || exit 255
exit 0

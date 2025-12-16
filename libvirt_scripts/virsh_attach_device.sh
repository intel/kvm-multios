#!/bin/bash

# Copyright (c) 2023-2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
VM=""
INTERFACE=""
DEVICE_NAME=""
DEVICE_NUMBER=0
NR_DEVICE=""
USB_VENDOR_ID=""
USB_PRODUCT_ID=""
USB_BUS_ID=""
USB_PORT_ID=""
USB_DEVICE_ID=""

PCI_DOMAIN=""
PCI_BUS=""
PCI_SLOT=""
PCI_FUNC=""

RAM_PCI_DEV="RAM memory"

# Reattach mode variables
REATTACH_MODE=false
REATTACH_DOMAIN=""
USB_DEVICES_FOLDER="./platform/client/usb_devices"

FORCE_CLEANUP=false

#---------      Functions    -------------------
function show_help() {
  printf "%s [-h|--help] [-f [<domain>]] [--reattach_usb [<domain>]] [-p <domain> [--usb|--pci <device>] (<number>) |[--usbtree <bus-port_L1.port_L2...port_Lx>]]\n\n" "$(basename "${BASH_SOURCE[0]}")"
  printf "Options:\n"
  printf "  -h,--help          Show the help message and exit\n"
  printf "  -p <domain>        Name of the VM domain for device passthrough\n"
  printf "    --usb | --pci    Options of interface (eg. --usb or --pci)\n"
  printf "    <device>         Name of the device (eg. mouse, keyboard, bluetooth, etc)\n"
  printf "    (<number>)       Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'\n"
  printf "                     by default is the first device found\n"
  printf "    --usbtree        Options of interface (eg. --usbtree)\n"
  printf "    <bus-port_L1.port_L2...port_Lx> \n"
  printf "                     USB bus and port numbers retrieved from lsusb -t \n"
  printf "  --reattach_usb [<domain>]      Reattach USB devices from saved XML files\n"
  printf "                     If domain is specified, reattach devices only for that domain\n"
  printf "                     If domain is not specified, reattach all saved devices for all domains\n"
  printf "                     Note: Only works for USB devices passed through via --usbtree (bus-port addressing)\n"
  printf "                     Does not work for devices passed through via vendor/product ID (--usb)\n"
  printf "  -f [<domain>]      Force cleanup - remove all saved USB device XML files\n"
  printf "                     If domain is specified, cleanup only for that domain\n"
  printf "                     If domain is not specified, cleanup all saved devices for all domains\n"
  printf "\n"
  printf "e.g\n"
  printf "    ./virsh_attach_device.sh --reattach_usb\n"
  printf "    ./virsh_attach_device.sh --reattach_usb ubuntu\n"
  printf "    ./virsh_attach_device.sh -f\n"
  printf "    ./virsh_attach_device.sh -f ubuntu\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --usb mouse\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --usb keyboard\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --usb bluetooth\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --usbtree <bus-port_L1.port_L2...port_Lx>\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --pci wi-fi\n"
  printf "    ./virsh_attach_device.sh -p ubuntu_rt1 --pci i225 1\n"
  printf "    ./virsh_attach_device.sh -p ubuntu_rt2 --pci i225 2\n"
}

function attach_usb() {
  cat<<EOF | tee usb.xml
<hostdev mode="subsystem" type="usb" managed="yes">
  <source>
    <vendor id="0x$USB_VENDOR_ID"/>
    <product id="0x$USB_PRODUCT_ID"/>
  </source>
</hostdev>
EOF

  sudo virsh attach-device "$VM" usb.xml --current 2>/dev/null || return 1
  rm usb.xml
  return 0
}

function attach_usb_busport() {
  cat<<EOF | tee usb_bus.xml
<hostdev mode="subsystem" type="usb" managed="yes">
  <source>
    <address type="usb" bus="$USB_BUS_ID" port="$USB_PORT_ID" device="$USB_DEVICE_ID" />
  </source>
</hostdev>
EOF

  sudo virsh attach-device "$VM" usb_bus.xml --current 2>/dev/null || return 1
  mkdir -p "$USB_DEVICES_FOLDER/$VM"
  mv usb_bus.xml "$USB_DEVICES_FOLDER/$VM/usb_${USB_BUS_ID}_${USB_PORT_ID}.xml"
  return 0
}

function attach_pci() {
  #check devices belong to same iommu group
  pci_iommu=$(sudo virsh nodedev-dumpxml pci_"${PCI_DOMAIN}"_"${PCI_BUS}"_"${PCI_SLOT}"_"${PCI_FUNC}" | grep address)
  mapfile pci_array <<< "$pci_iommu"

  for pci in "${pci_array[@]}";do
    # Only check for RAM memory on Linux kernel 6.12
    if [[ $(uname -r) =~ ^6\.12 ]]; then
      local pci_bus
      # shellcheck disable=SC2001
      pci_bus=$(echo "$pci" | sed "s/.*domain='0x\([^']\+\)'.*bus='0x\([^']\+\)'.*slot='0x\([^']\+\)'.*function='0x\([^']\+\)'.*/\1:\2:\3.\4/")
      if [[ $(lspci -s "$pci_bus") =~ $RAM_PCI_DEV ]]; then
        echo "Find ram memory: $pci_bus. Skip this device"
        continue;
      fi
    fi

    cat<<EOF | tee pci.xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
  $pci
  </source>
</hostdev>
EOF
    sudo virsh attach-device "$VM" pci.xml --current
 done
}

# Validate domain function
function validate_domain() {
  local domain="$1"
  local check_running="${2:-false}"

  # Check if domain is defined
  if ! sudo virsh list --all | grep -qw "$domain"; then
    echo "Error: Domain '$domain' is not defined"
    exit 255
  fi

  # Check if domain is running (if requested)
  if [[ "$check_running" == "true" ]]; then
    if ! virsh list --state-running | grep -qw "$domain"; then
      echo "Error: Domain '$domain' is not running. Please start the domain before reattaching devices."
      exit 255
    fi
  fi
}

# Get domain directories with nullglob
function get_domain_directories() {
  shopt -s nullglob
  local dirs=("${USB_DEVICES_FOLDER}"/*)
  shopt -u nullglob
  printf '%s\n' "${dirs[@]}"
}

# Check if domain directories exist and exit if empty
function check_domain_directories_exist() {
  local action="$1"
  local dirs
  mapfile -t dirs < <(get_domain_directories)
  
  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No domain directories found in ${USB_DEVICES_FOLDER}"
    echo "No devices to ${action}."
    exit 0
  fi
}

# Detach all saved devices for a domain
function detach_domain_devices() {
  local domain="$1"
  local domain_xml_dir="${USB_DEVICES_FOLDER}/${domain}"

  # Check if VM is running
  if ! virsh list --state-running | grep -qw "$domain"; then
    echo "VM '$domain' is not running. Skipping device detachment."
    return 0
  fi

  echo "Note: Only USB devices passed through via --usbtree (bus-port addressing) will be detached."

  if [[ ! -d "${domain_xml_dir}" ]]; then
    echo "No saved devices found for domain: $domain"
    return 0
  fi

  # Detach all saved devices for this domain
  shopt -s nullglob
  for xml_file in "${domain_xml_dir}"/*.xml; do
    # Check if this XML uses bus/port addressing (address type="usb")
    if ! grep -q '<address type="usb"' "$xml_file"; then
      echo "Skipping $(basename "$xml_file"): Not a bus-port addressed USB device"
    elif ! sudo virsh detach-device "$domain" "$xml_file" --current 2>/dev/null; then
      echo "Failed to detach device from $(basename "$xml_file") (device may not be attached)"
    fi
  done
  shopt -u nullglob
}

# Force cleanup function
function force_cleanup_domain() {
  local domain="$1"

  # Check if domain is defined in virsh
  validate_domain "$domain"

  # Check if domain folder exists
  if [[ ! -d "${USB_DEVICES_FOLDER}/${domain}" ]]; then
    echo "No saved USB devices found for domain: $domain"
    exit 0
  fi

  # Detach devices before cleanup
  detach_domain_devices "$domain"

  # Remove saved XML files for the domain
  rm -rf "${USB_DEVICES_FOLDER}/${domain:?}"
  echo "Cleanup completed for domain: $domain"
}

# Reattach functions
function reattach_devices_from_xml() {
  local target_domain="$1"

  # If specific domain requested, only process that domain
  if [[ -n "$target_domain" ]]; then
    validate_domain "$target_domain" "true"

    if [[ ! -d "${USB_DEVICES_FOLDER}/${target_domain}" ]]; then
      echo "${USB_DEVICES_FOLDER}/${target_domain} does not exist. No devices to reattach for domain '$target_domain'."
      exit 0
    fi
    reattach_domain_devices "$target_domain" || true
  else
    # Process all domains
    check_domain_directories_exist "reattach"
    
    mapfile -t domain_dirs < <(get_domain_directories)
    for domain_dir in "${domain_dirs[@]}"; do
      if [[ -d "$domain_dir" ]]; then
        local domain_name
        domain_name=$(basename "$domain_dir")
        reattach_domain_devices "$domain_name" || true
      fi
    done
  fi
}

function reattach_domain_devices() {
  local domain="$1"
  local domain_xml_dir="${USB_DEVICES_FOLDER}/${domain}"

  # Check if VM is running
  if ! virsh list --state-running | grep -qw "$domain"; then
    echo "Warning: VM '$domain' is not running. Skipping all devices for this domain."
    return 1
  fi

  # Check if there are any XML files
  shopt -s nullglob
  local xml_files=("${domain_xml_dir}"/*.xml)
  shopt -u nullglob
  
  if [[ ${#xml_files[@]} -eq 0 ]]; then
    echo "No saved USB device XML files found for domain '$domain'"
    return 1
  fi

  # Process all XML files in the domain directory
  for xml_file in "${xml_files[@]}"; do
    # Check if this XML uses bus/port addressing (address type="usb")
    if ! grep -q '<address type="usb"' "$xml_file"; then
      echo "Skipping $(basename "$xml_file"): Not a bus-port addressed USB device"
      continue
    fi

    # Extract bus and port from XML content
    local bus_id port_id
    bus_id=$(grep -oP 'bus="\K[^"]+' "$xml_file")
    port_id=$(grep -oP 'port="\K[^"]+' "$xml_file")

    if [[ -z "$bus_id" || -z "$port_id" ]]; then
      echo "Warning: Failed to extract bus/port from $(basename "$xml_file")"
      continue
    fi

    local bus_port="${bus_id}-${port_id}"

    # Check if the USB device still exists at this bus-port
    if [[ ! -d "/sys/bus/usb/devices/$bus_port" || ! -f "/sys/bus/usb/devices/$bus_port/devnum" ]]; then
      echo "Warning: USB device at bus-port $bus_port not found ($(basename "$xml_file"))"
      echo "Device may have been unplugged or moved to a different port"
      continue
    fi

    # Read the current device number
    local current_device_id
    current_device_id=$(cat "/sys/bus/usb/devices/$bus_port/devnum")

    # Update the XML file with the new device ID
    sed -i "s/device=\"[0-9]*\"/device=\"$current_device_id\"/" "$xml_file"

    # Attach the device with updated XML
    if ! sudo virsh attach-device "$domain" "$xml_file" --current 2>/dev/null; then
      echo "Error: Failed to attach device from $(basename "$xml_file")"
      continue
    fi

    echo "Successfully attached device at bus-port $bus_port ($(basename "$xml_file"))"
  done
}

function parse_arg() {
  if [[ $# -eq 0 ]]; then
    echo "Error: NO input argument found"
    show_help
    exit 255
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;

      --reattach_usb)
        REATTACH_MODE=true
        shift
        # Check if next argument is a domain name (not another option)
        if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
          REATTACH_DOMAIN="$1"
          shift
        fi
        ;;

      -p)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          echo "Error: Domain name missing after $1 option"
          show_help
          exit 255
        fi
        VM=$2
        # Check if domain is supported
        validate_domain "$VM"
        shift 2
        if [[ "$1" == "--usb" || "$1" == "--pci" ]]; then
          if [[ -z "$2" || "$2" == -* ]]; then
              echo "Error: Missing device name after $1"
              show_help
              exit 255
          fi
          INTERFACE=$1
          DEVICE_NAME=$2
          shift 2
          if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
              DEVICE_NUMBER=$1
              shift
          else
              DEVICE_NUMBER=1
          fi
          NR_DEVICE="NR==$DEVICE_NUMBER"
        elif [[ "$1" == "--usbtree" ]]; then
          if [[ -z "$2" || "$2" == -* ]]; then
              echo "Error: Missing bus-port_L1.port_L2...port_Lx number after $1"
              show_help
              exit 255
          fi
          INTERFACE=$1
          DEVICE_NAME=$2
          shift 2
        else
          echo "Error: unknown device type"
          show_help
          exit 255
        fi
        ;;
      -f)
        FORCE_CLEANUP=true
        shift
        # Check if next argument is a domain name (not another option)
        if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
          VM="$1"
          shift
        fi
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
  done
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

# Handle reattach mode
if [[ "$REATTACH_MODE" == true ]]; then
  echo "Note: Only USB devices passed through via --usbtree (bus-port addressing) will be reattached."
  echo "Devices passed through via --usb (vendor/product ID) are not supported for reattachment."
  reattach_devices_from_xml "$REATTACH_DOMAIN"
  exit 0
fi

if [[ "$FORCE_CLEANUP" == true ]]; then
  # Check if USB_DEVICES_FOLDER exists first
  if [[ ! -d "$USB_DEVICES_FOLDER" ]]; then
    echo "No saved USB devices found."
    exit 0
  fi

  # If specific domain provided, cleanup only that domain
  if [[ -n "$VM" ]]; then
    force_cleanup_domain "$VM"
  else
    # Cleanup all domains
    check_domain_directories_exist "clean up"

    # Process all domain directories
    mapfile -t domain_dirs < <(get_domain_directories)
    for domain_dir in "${domain_dirs[@]}"; do
      if [[ -d "$domain_dir" ]]; then
        domain_name=$(basename "$domain_dir")
        detach_domain_devices "$domain_name"
        rm -rf "${domain_dir:?}"
      fi
    done
    echo "All domain cleanup completed."
  fi
  exit 0
fi

if [[ "--pci" == "$INTERFACE" ]]; then
  DEVICE_FOUND=$(lspci -Dnn | grep -i "$DEVICE_NAME" | cut -d' ' -f1 | awk "$NR_DEVICE")
  if [[ -z "$DEVICE_FOUND" ]]; then
    echo "No device $DEVICE_NAME found"
    exit 255
  fi
  PCI_DOMAIN=$(echo "$DEVICE_FOUND" | cut -d':' -f1)
  PCI_BUS=$(echo "$DEVICE_FOUND" | cut -d':' -f2)
  PCI_SLOT=$(echo "$DEVICE_FOUND" | cut -d':' -f3 | cut -d '.' -f1)
  PCI_FUNC=$(echo "$DEVICE_FOUND" | cut -d':' -f3 | cut -d '.' -f2)
  attach_pci
elif [[ "--usb" == "$INTERFACE" ]]; then
  DEVICE_FOUND=$(lsusb | grep -i "$DEVICE_NAME" | awk "$NR_DEVICE" | grep -o "ID ....:....")
  if [[ -z "$DEVICE_FOUND" ]]; then
    echo "No device $DEVICE_NAME found"
    exit 255
  fi
  USB_VENDOR_ID=$(echo "$DEVICE_FOUND" | cut -d' ' -f2 | cut -d':' -f1)
  USB_PRODUCT_ID=$(echo "$DEVICE_FOUND" | cut -d' ' -f2 | cut -d':' -f2)
  attach_usb
elif [[ "--usbtree" == "$INTERFACE" ]]; then
  if [[ "$DEVICE_NAME" =~ ^[0-9.-]+$ ]]; then
    echo "Bus Port numbers: $DEVICE_NAME"
  else
    echo "Error:Input $DEVICE_NAME contains non-numeric characters"
    exit 255
  fi

  USB_BUS_ID=$(echo "$DEVICE_NAME" | cut -d' ' -f2 | cut -d'-' -f1)
  USB_PORT_ID=$(echo "$DEVICE_NAME" | cut -d' ' -f2 | cut -d'-' -f2)

  if [[ -d "/sys/bus/usb/devices/$DEVICE_NAME" ]]; then
    USB_DEVICE_ID=$(cat "/sys/bus/usb/devices/$DEVICE_NAME/devnum")
  else
    echo "Provided USB bus=$USB_BUS_ID and port=$USB_PORT_ID not found"
    echo "For example, to passthrough the keyboard in the example below"
    echo "lsusb: Bus 003 Device 021: ID 413c:2003 Dell Computer Corp. Keyboard SK-8115"
    echo "Bus 003.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/16p, 480M"
    echo "|__ Port 002: Dev 020, If 0, Class=Hub, Driver=hub/4p, 480M"
    echo "    |__ Port 001: Dev 021, If 0, Class=Human Interface Device, Driver=usbhid, 1.5M"
    echo "Dev 021: bus 3 -> port 2 -> port 1"
    echo "USE ==>  --usbtree 3-2.1"
    exit 255
  fi

  attach_usb_busport
else
  echo "Interface $INTERFACE not supported"
  exit 255
fi
exit 0
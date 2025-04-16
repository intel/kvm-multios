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

#---------      Functions    -------------------
function show_help() {
  printf "%s [-h|--help] [-p <domain> [--usb|--pci <device>] (<number>) |[--usbtree <bus-port_L1.port_L2...port_Lx>]]\n\n" "$(basename "${BASH_SOURCE[0]}")"
  printf "Options:\n"
  printf "  -h,--help          Show the help message and exit\n"
  printf "  -p <domain>        Name of the VM domain for device passthrough\n"
  printf "    --usb | --pci    Options of interface (eg. --usb or --pci)\n"
  printf "    <device>         Name of the device (eg. mouse, keyboard, bluetooth, etc)\n"
  printf "    (<number>)       Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'\n"
  printf "                     by default is the first device found\n"
  printf "    --usbtree        Options of interface (eg. --usbtree)\n"
  printf "    <bus-port_L1.port_L2...port_Lx> \n"
  printf "                     USB bus and port numbers retrived from lsusb -t \n"
  printf "\n"
  printf "e.g\n"
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

  sudo virsh attach-device "$VM" usb.xml --current
}

function attach_usb_busport() {
  cat<<EOF | tee usb_bus.xml
<hostdev mode="subsystem" type="usb" managed="yes">
  <source>
    <address type="usb" bus="$USB_BUS_ID" port="$USB_PORT_ID" device="$USB_DEVICE_ID" />
  </source>
</hostdev>
EOF

  sudo virsh attach-device "$VM" usb_bus.xml --current
}

function attach_pci() {
  #check devices belong to same iommu group
  pci_iommu=$(sudo virsh nodedev-dumpxml pci_"${PCI_DOMAIN}"_"${PCI_BUS}"_"${PCI_SLOT}"_"${PCI_FUNC}" | grep address)
  mapfile pci_array <<< "$pci_iommu"

  for pci in "${pci_array[@]}";do
    local pci_bus
    # shellcheck disable=SC2001
    pci_bus=$(echo "$pci" | sed "s/.*domain='0x\([^']\+\)'.*bus='0x\([^']\+\)'.*slot='0x\([^']\+\)'.*function='0x\([^']\+\)'.*/\1:\2:\3.\4/")
    if [[ $(lspci -s "$pci_bus") =~ $RAM_PCI_DEV ]]; then
      echo "Find ram memory: $pci_bus. Skip this device"
      continue;
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

function parse_arg() {
  if [[ $# -eq 0 ]]; then
    log_error "NO input argument found"
    show_help
    exit 255
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;

      -p)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option"
          show_help
          exit 255
        fi
        VM=$2
        # Check if domain is supported
        if ! sudo virsh list --all | grep -q "$VM"; then
          log_error "$VM is not defined"
          show_help
          exit 255
        fi
        shift 2
        if [[ "$1" == "--usb" || "$1" == "--pci" ]]; then
          if [[ -z "$2" || "$2" == -* ]]; then
              log_error "Missing device name after $1"
              show_help
              exit 255
          fi
          INTERFACE=$1
          DEVICE_NAME=$2
          if [[ -z "$3" || "$3" == -* ]]; then
              DEVICE_NUMBER=1
          else
              DEVICE_NUMBER=$3
          fi
          NR_DEVICE="NR==$DEVICE_NUMBER"
	        shift 3
        elif [[ "$1" == "--usbtree" ]]; then
          if [[ -z "$2" || "$2" == -* ]]; then
              log_error "Missing bus-port_L1.port_L2...port_Lx number after $1"
              show_help
              exit 255
          fi
          INTERFACE=$1
          DEVICE_NAME=$2
          shift 2
        else
          log_error "unknown device type"
          show_help
          exit 255
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
  echo "Not supported interface $INTERFACE"
fi
exit 0


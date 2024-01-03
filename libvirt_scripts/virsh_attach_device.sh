#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeo pipefail

#---------      Global variable     -------------------
VM=""
INTERFACE=""
DEVICE_NAME=""
DEVICE_NUMBER=0
NR_DEVICE=""
USB_VENDOR_ID=""
USB_PRODUCT_ID=""

PCI_BUS=""
PCI_SLOT=""
PCI_FUNC=""

#---------      Functions    -------------------
function show_help() {
  printf "$(basename "${BASH_SOURCE[0]}") [-h|--help] [-p <domain> --usb|--pci <device> (<number>)]\n\n"
  printf "Options:\n"
  printf "  -h,--help          Show the help message and exit\n"
  printf "  -p <domain>        Name of the VM domain for device passthrough\n"
  printf "    --usb | --pci    Options of interface (eg. --usb or --pci)\n"
  printf "    <device>         Name of the device (eg. mouse, keyboard, bluetooth, etc)\n"
  printf "    (<number>)       Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'\n"
  printf "                     by default is the first device found\n"
  printf "\n"
  printf "e.g\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --usb mouse\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --usb keyboard\n"
  printf "    ./virsh_attach_device.sh -p ubuntu --usb bluetooth\n"
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

  sudo virsh attach-device $VM usb.xml --current
}

function attach_pci() {

  #check devices belong to same iommu group
  pci_iommu=$(sudo virsh nodedev-dumpxml pci_0000_${PCI_BUS}_${PCI_SLOT}_${PCI_FUNC} | grep address)
  readarray pci_array <<< $pci_iommu

  for pci in "${pci_array[@]}";do
    cat<<EOF | tee pci.xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
  $pci
  </source>
</hostdev>
EOF
    sudo virsh attach-device $VM pci.xml --current
 done
}

function parse_arg() {
  if [[ $# -eq 0 ]]; then
    log_error "NO input argument found"
    show_help
    exit -1
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
          exit -1
        fi
        VM=$2
        # Check if domain is supported
        if [[ -z $(sudo virsh list --all | grep $VM) ]]; then
          log_error "$VM is not defined"
          show_help
          exit -1
        fi
        shift 2
        if [[ $1 == "--usb" || $1 == "--pci" ]]; then
          if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing device name after $1"
              show_help
              exit -1
          fi
          INTERFACE=$1
          DEVICE_NAME=$2
          if [[ -z $3 || $3 == -* ]]; then
              DEVICE_NUMBER=1
          else
              DEVICE_NUMBER=$3
          fi
          NR_DEVICE="NR==$DEVICE_NUMBER"
	        shift 3
        else
          log_error "unknown device type"
          show_help
          exit -1
        fi
        ;;
      -?*)
        echo "Error: Invalid option $1"
        show_help
        return -1
        ;;
      *)
        echo "Error: Unknown option: $1"
        return -1
        ;;
    esac
  done
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit -1

if [[ "--pci" == "$INTERFACE" ]]; then
  DEVICE_FOUND=$(lspci -nn | grep -i "$DEVICE_NAME" | cut -d' ' -f1 | awk $NR_DEVICE)
  if [[ -z "$DEVICE_FOUND" ]]; then
    echo "No device $DEVICE_NAME found"
    exit -1
  fi
  PCI_BUS=$(echo $DEVICE_FOUND | cut -d':' -f1)
  PCI_SLOT=$(echo $DEVICE_FOUND | cut -d':' -f2 | cut -d '.' -f1)
  PCI_FUNC=$(echo $DEVICE_FOUND | cut -d':' -f2 | cut -d '.' -f2)
  attach_pci
elif [[ "--usb" == "$INTERFACE" ]]; then
  DEVICE_FOUND=$(lsusb | grep -i $DEVICE_NAME | awk $NR_DEVICE | grep -o "ID ....:....")
  if [[ -z "$DEVICE_FOUND" ]]; then
    echo "No device $DEVICE_NAME found"
    exit -1
  fi
  USB_VENDOR_ID=$(echo $DEVICE_FOUND | cut -d' ' -f2 | cut -d':' -f1)
  USB_PRODUCT_ID=$(echo $DEVICE_FOUND | cut -d' ' -f2 | cut -d':' -f2)
  attach_usb
else
  echo "Not supported interface $INTERFACE"
fi
exit 0


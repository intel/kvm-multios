#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeo pipefail
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

VM=$1
INTERFACE=$2
DEVICE_NAME=$3
if [[ -z "$4" ]]; then
  DEVICE_NUMBER=1
else
  DEVICE_NUMBER=$4
fi
USB_VENDOR_ID=""
USB_PRODUCT_ID=""

PCI_BUS=""
PCI_SLOT=""
PCI_FUNC=""

if [[ -z "$VM" || -z "$INTERFACE" || -z "$DEVICE_NAME" ]]; then
  echo "input $VM $INTERFACE $DEVICE_NAME 0"
  echo "Usage: ./virsh_attach_device.sh [vm_name] [pci/usb] [device_name] [device_number, optional, default first device found]"
  echo "e.g"
  echo "    ./virsh_attach_device.sh Ubuntu usb mouse"
  echo "    ./virsh_attach_device.sh Ubuntu usb keyboard"
  echo "    ./virsh_attach_device.sh Ubuntu usb bluetooth"
  echo "    ./virsh_attach_device.sh Ubuntu pci wi-fi"
  echo "    ./virsh_attach_device.sh Ubuntu_RT1 pci i225 1"
  echo "    ./virsh_attach_device.sh Ubuntu_RT2 pci i225 2"
  exit 0
fi

NR_DEVICE="NR==$DEVICE_NUMBER"

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

if [[ -z $(sudo virsh list --all | grep $VM) ]]; then
  echo "$VM not defined"
  exit 0
fi

if [[ "pci" == "$INTERFACE" ]]; then
  DEVICE_FOUND=$(lspci -nn | grep -i "$DEVICE_NAME" | cut -d' ' -f1 | awk $NR_DEVICE)
  if [[ -z "$DEVICE_FOUND" ]]; then
    echo "No device $DEVICE_NAME found"
    exit 0
  fi
  PCI_BUS=$(echo $DEVICE_FOUND | cut -d':' -f1)
  PCI_SLOT=$(echo $DEVICE_FOUND | cut -d':' -f2 | cut -d '.' -f1)
  PCI_FUNC=$(echo $DEVICE_FOUND | cut -d':' -f2 | cut -d '.' -f2)
  attach_pci
elif [[ "usb" == "$INTERFACE" ]]; then
  DEVICE_FOUND=$(lsusb | grep -i $DEVICE_NAME | awk $NR_DEVICE | grep -o "ID ....:....")
  if [[ -z "$DEVICE_FOUND" ]]; then
    echo "No device $DEVICE_NAME found"
    exit 0
  fi
  USB_VENDOR_ID=$(echo $DEVICE_FOUND | cut -d' ' -f2 | cut -d':' -f1)
  USB_PRODUCT_ID=$(echo $DEVICE_FOUND | cut -d' ' -f2 | cut -d':' -f2)
  attach_usb
else
  echo "Not supported interface $INTERFACE"
fi


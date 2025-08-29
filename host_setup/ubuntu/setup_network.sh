#!/bin/bash

# Copyright (c) 2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#------------ global variables -------------
script=$(realpath "${BASH_SOURCE[0]}")
LOGTAG=$(basename "$script")
LOG_FILE=${LOG_FILE:="/tmp/$LOGTAG.log"}
NUM_VFS=8

declare -a sriov_nics

#-------------    functions    -------------
function log() {
    echo "$@" | tee -a "$LOG_FILE"
}

function create_default_network() {
    # Clean up any existing default network XML file first
    in_use=$(
        for dom in $(sudo virsh list --name); do
            sudo virsh domiflist "$dom"
        done | awk '$3 == "default" {print $1}' | wc -l
    )
    if [[ "$in_use" -gt 0 ]]; then
        log "Error: Cannot destroy 'default' network. It is in use by $in_use running VM(s)."
        exit 255
    fi
    if sudo virsh net-list --name | grep -q 'default'; then
        sudo virsh net-destroy default
    fi
    if sudo virsh net-list --name --all | grep -q 'default'; then
        sudo virsh net-undefine default
    fi

    # Define and start default guest network
    tee default_network.xml &>/dev/null <<EOF
<network>
  <name>default</name>
  <bridge name='virbr0'/>
  <forward/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
      <host mac='52:54:00:ab:cd:11' name='ubuntu' ip='192.168.122.11'/>
      <host mac='52:54:00:ab:cd:22' name='windows' ip='192.168.122.22'/>
      <host mac='52:54:00:ab:cd:33' name='android' ip='192.168.122.33'/>
      <host mac='52:54:00:ab:cd:44' name='ubuntu_rt' ip='192.168.122.44'/>
      <host mac='52:54:00:ab:cd:55' name='windows11' ip='192.168.122.55'/>
    </dhcp>
  </ip>
</network>
EOF

    sudo virsh net-define default_network.xml
    sudo virsh net-autostart default
    sudo virsh net-start default
    rm default_network.xml
}

function create_isolated_network() {
    # Clean up any existing isolated network XML file first
    in_use=$(
        for dom in $(sudo virsh list --name); do
            sudo virsh domiflist "$dom"
        done | awk '$3 == "isolated-guest-net" {print $1}' | wc -l
    )
    if [[ "$in_use" -gt 0 ]]; then
        log "Error: Cannot destroy 'isolated-guest-net' network. It is in use by $in_use running VM(s)."
        exit 255
    fi
    if sudo virsh net-list --name | grep -q 'isolated-guest-net'; then
        sudo virsh net-destroy isolated-guest-net
    fi
    if sudo virsh net-list --name --all | grep -q 'isolated-guest-net'; then
        sudo virsh net-undefine isolated-guest-net
    fi

    # Define and start isolated guest network
    tee isolated-guest-net.xml &>/dev/null <<EOF
<network>
  <name>isolated-guest-net</name>
  <forward mode='none'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <ip address='192.168.200.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.200.2' end='192.168.200.254'/>
      <host mac='52:54:00:ab:cd:11' name='ubuntu' ip='192.168.200.11'/>
      <host mac='52:54:00:ab:cd:22' name='windows' ip='192.168.200.22'/>
      <host mac='52:54:00:ab:cd:33' name='android' ip='192.168.200.33'/>
      <host mac='52:54:00:ab:cd:44' name='ubuntu_rt' ip='192.168.200.44'/>
      <host mac='52:54:00:ab:cd:55' name='windows11' ip='192.168.200.55'/>
    </dhcp>
  </ip>
</network>
EOF

    sudo virsh net-define isolated-guest-net.xml
    sudo virsh net-autostart isolated-guest-net
    sudo virsh net-start isolated-guest-net
    rm isolated-guest-net.xml
}

function search_network_sriov() {
    # Check for SR-IOV capable NICs
    sriov_nics=()
    for netdev in /sys/class/net/*; do
        dev=$(basename "$netdev")
        sriov_totalvfs="/sys/class/net/$dev/device/sriov_totalvfs"
        if [[ -f "$sriov_totalvfs" ]]; then
            log "Found SR-IOV NIC: $dev"
            sriov_nics+=("$dev")
        fi
    done

    if [[ "${#sriov_nics[@]}" -eq 0 ]]; then
        log "No SR-IOV capable NICs found."
    fi
}

function setup_network_sriov() {
    # Skip if no SR-IOV NICs found
    if [[ "${#sriov_nics[@]}" -eq 0 ]]; then
        log "No SR-IOV NICs to configure, skipping SR-IOV setup."
        return
    fi

    # Clean up any existing SR-IOV pools and VFs before proceeding
    for device_name in "${sriov_nics[@]}"; do
        destroy_sriov_pool "sriov-pool-${device_name}"
        disable_sriov_vfs "$device_name"
    done

    # Enable SR-IOV VFs and create pools for each NIC
    for device_name in "${sriov_nics[@]}"; do
        enable_sriov_vfs "$device_name" || continue
        create_sriov_pool "$device_name"
    done
}

function check_vfs_attached() {
    local device_name="$1"
    for vf in /sys/class/net/"$device_name"/device/virtfn*; do
        if [[ -e "$vf" ]]; then
            # If the net directory does not exist, VF may be attached to a guest
            if [[ ! -d "$vf/net" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

function enable_sriov_vfs() {
    local device_name="$1"
    local sriov_totalvfs="/sys/class/net/$device_name/device/sriov_totalvfs"
    local sriov_numvfs="/sys/class/net/$device_name/device/sriov_numvfs"

    # Check if the device supports SR-IOV
    if [[ ! -f "$sriov_totalvfs" || ! -f "$sriov_numvfs" ]]; then
        log "Error: Device $device_name does not support SR-IOV."
        return
    fi

    # Check the requested number of VFs is supported
    local totalvfs
    totalvfs=$(cat "$sriov_totalvfs")
    if [[ "$totalvfs" -lt "$NUM_VFS" ]]; then
        log "Error: Unable to set $NUM_VFS VFs on $device_name"
        log "Device $device_name supports only $totalvfs VFs, skipping."
        return
    fi

    # Enable SR-IOV VFs
    if [[ $(cat "$sriov_numvfs") -ne 0 ]]; then
        if check_vfs_attached "$device_name"; then
            log "Cannot disable VFs on $device_name: one or more VFs are attached to a guest."
            exit 255
        fi
        echo 0 | sudo tee "$sriov_numvfs" >/dev/null
    fi
    echo "$NUM_VFS" | sudo tee "$sriov_numvfs" >/dev/null
    log "Enabled $NUM_VFS VFs on $device_name"

    # Dynamically obtain the driver name
    local driver_path
    driver_path=$(readlink -f "/sys/class/net/$device_name/device/driver")
    local driver_name
    driver_name=$(basename "$driver_path")

    # Clean up any existing udev rules file first
    local udev_rule_file="/etc/udev/rules.d/${device_name}.rules"
    if [[ -f "$udev_rule_file" ]]; then
        sudo rm -f "$udev_rule_file"
    fi

    # Create udev rule to set the number of VFs using the detected driver
    sudo tee "$udev_rule_file" >/dev/null <<EOF
ACTION=="add", SUBSYSTEM=="net", ENV{ID_NET_DRIVER}=="$driver_name", ATTR{device/sriov_numvfs}="$NUM_VFS"
EOF
}

function disable_sriov_vfs() {
    local device_name="$1"
    local sriov_numvfs="/sys/class/net/$device_name/device/sriov_numvfs"
    if [[ ! -f "$sriov_numvfs" ]]; then
        log "Error: Device $device_name does not have sriov_numvfs, skipping disable."
        return
    fi

    if [[ $(cat "$sriov_numvfs") -ne 0 ]]; then
        if check_vfs_attached "$device_name"; then
            log "Error: Cannot disable VFs on $device_name: one or more VFs are attached to a guest."
            exit 255
        fi
        echo 0 | sudo tee "$sriov_numvfs" >/dev/null
        log "Disabled all VFs on $device_name"
    fi

    # Remove any udev rule for this device
    local udev_rule_file="/etc/udev/rules.d/${device_name}.rules"
    if [[ -f "$udev_rule_file" ]]; then
        sudo rm -f "$udev_rule_file"
    fi
}

function create_sriov_pool() {
    local device_name="$1"
    local pool_name="sriov-pool-${device_name}"

    # Clean up any existing pool first
    destroy_sriov_pool "$pool_name"

    # Clean up any existing XML file first
    pool_xml="/tmp/${pool_name}.xml"
    if [[ -f "$pool_xml" ]]; then
        rm -f "$pool_xml"
    fi

    # Create the XML for the libvirt network pool
    cat > "$pool_xml" <<EOF
<network>
  <name>${pool_name}</name>
  <forward mode='hostdev' managed='yes'>
    <driver name='vfio'/>
    <pf dev='${device_name}'/>
  </forward>
</network>
EOF
    # Define and start the pool
    sudo virsh net-define "$pool_xml" || log "Pool $pool_name already defined"
    sudo virsh net-autostart "$pool_name"
    sudo virsh net-start "$pool_name"
    log "Created libvirt pool $pool_name"
}

function destroy_sriov_pool() {
    local pool_name="$1"

    # Destroy any active network
    if sudo virsh net-list --name | grep -q "^${pool_name}$"; then
        # Extract used connections from <network connections='N'>
        local used_connections
        used_connections=$(virsh net-dumpxml "$pool_name" 2>/dev/null | \
            grep -o "<network connections='[0-9]\+'" | grep -o "[0-9]\+" || true)
        if [[ -n "$used_connections" && "$used_connections" -gt 0 ]]; then
            log "Error: Cannot destroy pool $pool_name: it is in use by $used_connections connections."
            exit 255
        fi
        sudo virsh net-destroy "$pool_name"
    fi

    # Undefine any inactive network
    if sudo virsh net-list --name --all | grep -q "^${pool_name}$"; then
        sudo virsh net-undefine "$pool_name"
    fi
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sriov-vfs)
                NUM_VFS="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [--sriov-vfs N]"
                echo "  --sriov-vfs N   Number of VFs to create per device (default: $NUM_VFS)"
                exit 0
                ;;
            *)
                echo "Error: Unknown argument: $1"
                exit 255
                ;;
        esac
    done
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255
create_default_network || exit 255
create_isolated_network || exit 255
search_network_sriov
setup_network_sriov || exit 255

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

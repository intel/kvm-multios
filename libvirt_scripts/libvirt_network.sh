#!/bin/bash

# Copyright (c) 2025 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#------------ global variables -------------
domain=""
net_name=""
available_sriov_net_name=""

#-------------    functions    -------------
function check_network() {
    if [[ "$net_name" == "sriov" ]]; then
        sriov_networks=""
        available_sriov_net_name=""
        for net in $(virsh net-list --all --name); do
            # Search for <driver name='vfio'/>
            if check_sriov_pool_network "$net"; then
                sriov_networks+="$net "
                if check_available_sriov_connection "$net"; then
                    available_sriov_net_name="$net"
                    break
                fi
            fi
        done
        sriov_networks=$(echo "$sriov_networks" | xargs)
        if [[ -z "$sriov_networks" ]]; then
            echo "Error: No SR-IOV networks found." >&2
            echo "Please install SR-IOV capable NIC hardware and run setup_network.sh to setup." >&2
            exit 255
        fi
        if [[ -z "$available_sriov_net_name" ]]; then
            echo "Error: No SR-IOV networks with available connections found." >&2
            exit 255
        fi
    else
        # Check if the network exists
        if ! virsh net-list --all --name | grep -Fxq "$net_name"; then
            echo "Error: network '$net_name' does not exist (not found in virsh net-list)" >&2
            exit 255
        fi
        # Check if the network is an SR-IOV pool
        if check_sriov_pool_network "$net_name"; then
            # It's an SR-IOV pool, check for available connection
            if ! check_available_sriov_connection "$net_name"; then
                echo "Error: SR-IOV network '$net_name' has no available connections." >&2
                exit 255
            fi
        fi
    fi
}

function check_sriov_pool_network() {
    local net="$1"
    # Check if network has forward mode='hostdev' managed='yes' and driver name='vfio'
    local xpath="//network/forward[@mode='hostdev' and @managed='yes']/driver[@name='vfio']"
    if virsh net-dumpxml "$net" 2>/dev/null | \
        xmllint --xpath "$xpath" - &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function check_available_sriov_connection() {
    local net="$1"
    # Extract used connections from <network connections='N'>
    local used_connections
    used_connections=$(virsh net-dumpxml "$net" 2>/dev/null | \
        grep -o "<network connections='[0-9]\+'" | grep -o "[0-9]\+" || true)
    if [[ -z "$used_connections" ]]; then
        used_connections=0
    fi
    # Count number of <address .../> lines for available connections
    local total_connections
    total_connections=$(virsh net-dumpxml "$net" 2>/dev/null | grep -c "<address ")
    local available_connections=$((total_connections - used_connections))
    # echo "SR-IOV network $net:"
    # echo "  - Total connections: $total_connections"
    # echo "  - Used connections: $used_connections"
    # echo "  - Available connections: $available_connections"
    if [[ $available_connections -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

function setup_network() {
    # Detach all existing network interfaces from the specified VM domain.
    iface_list=$(virsh domiflist "$domain" | awk 'NR>2 {print $5}')
    for iface in $iface_list; do
        if [[ -n "$iface" && "$iface" != "-" ]]; then
            echo "Detaching interface $iface from domain: $domain"
            virsh detach-interface "$domain" --type network --mac "$iface" --config || true
        fi
    done

    # Attach the requested network to the domain.
    if [[ "$net_name" == "sriov" ]]; then
        echo "Configuring SR-IOV network '$available_sriov_net_name' for domain: $domain"
        virsh attach-interface --domain "$domain" --type network --source "$available_sriov_net_name" --config
    else
        echo "Configuring network '$net_name' for domain: $domain"
        virsh attach-interface --domain "$domain" --type network --source "$net_name" --config
    fi
}

function show_help() {
    echo "Usage: $0 <net_name> <domain>"
    echo ""
    echo "Attach a libvirt network to a VM domain, replacing any existing network interfaces."
    echo ""
    echo "Arguments:"
    echo "  <net_name>   Name of the libvirt network to attach (from 'virsh net-list --all --name'),"
    echo "               or 'sriov' to auto-select an available SR-IOV pool."
    echo "  <domain>     Name of the VM domain."
    echo ""
    echo "Examples:"
    echo "  $0 default ubuntu"
    echo "  $0 sriov windows11"
    echo ""
    echo "This script will detach all existing network interfaces from the domain and attach the specified network."
    echo "If 'sriov' is specified, the script will select the first SR-IOV pool with available connections."
}

function parse_arg() {
    if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
        show_help
        exit 0
    fi
    if [[ $# -ne 2 ]]; then
        show_help
        echo "Error: Invalid arguments." >&2
        exit 255
    fi
    net_name="$1"
    domain="$2"

    # Basic sanity checks
    if [[ -z "$domain" ]]; then
        show_help
        echo "Error: domain argument is empty" >&2
        exit 255
    fi
    if [[ -z "$net_name" ]]; then
        show_help
        echo "Error: net_name argument is empty" >&2
        exit 255
    fi
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255
echo ""
echo "Preparing to configure network '$net_name' for domain: $domain"
echo ""
check_network
setup_network

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

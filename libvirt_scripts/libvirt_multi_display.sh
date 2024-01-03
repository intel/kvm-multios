#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------  Global variables  -------------------
GUEST_DOMAIN=""
GUEST_DISP_TYPE="-display gtk,gl=on"
GUEST_DISPLAY_MAX=4
GUEST_DISPLAY_MIN=1
GUEST_MAX_OUTPUTS=1
GUEST_CONNECTORS=""

#---------      Functions    -------------------
function edit_xml() {

    # Convert domain existing qemu commandline to arg and env strings
    # Example:
    #  <qemu:commandline>
    #    <qemu:arg value='-set'/>
    #    <qemu:arg value='device.video0.blob=true'/>
    #    <qemu:arg value='-display'/>
    #    <qemu:arg value='gtk,gl=on'/>
    #  </qemu:commandline>
    # will be convert to: "-set device.video0.blob=true -display gtk,gl=on"
    qemu_arg=$(sudo virsh dumpxml $GUEST_DOMAIN | grep "qemu:arg" | grep -P "'\K[^'/>]+" | tr '\n' ' ')
    qemu_arg=$(echo "$qemu_arg" | sed -e 's/<//g' -e 's/qemu:arg value=//g' -e "s/'//g" -e 's/\/>//g')

    if [[ "$qemu_arg" =~ "-display gtk,gl=on" ]]; then
      qemu_arg=$(sed "s/-display gtk,gl=on\S*/$GUEST_DISP_TYPE/" <<< $qemu_arg)
    else
      qemu_arg+=" $GUEST_DISP_TYPE"
    fi
    
    sudo virt-xml $GUEST_DOMAIN -q --edit --video model.heads=$GUEST_MAX_OUTPUTS
    sudo virt-xml $GUEST_DOMAIN -q --edit --qemu-commandline clearxml=yes
    sudo virt-xml $GUEST_DOMAIN -q --edit --qemu-commandline args="$qemu_arg"
    sudo virt-xml $GUEST_DOMAIN -q --edit --qemu-commandline env="DISPLAY=:0"
}

function show_help() {
    local platforms

    printf "$(basename "${BASH_SOURCE[0]}") domain_name [-h] [--output n] [--connectors list] [--full-screen] [--show-fps] [--extend-abs-mode] [--disable-host-input] \n"
    printf "Options:\n"
    printf "\t-h\tshow this help message\n"
    printf "\t--output n]\tNumber of output displays, n, range from 1 to 4\n"
    printf "\t--connectors HDMI-n/DP-n,...\tphysical display connector per display output.\n"
    printf "\t--full-screen\tSet display to full-screen\n"
    printf "\t--show-fps\tShow fps info on guest vm primary display\n"
    printf "\t--extend-abs-mode\tEnable extend absolute mode across all monitors\n"
    printf "\t--disable-host-input\tDisable host's HID devices to control the monitors\n"
}

function parse_connectors() {
    OIFS=$IFS IFS=',' connector_arr=($GUEST_CONNECTORS) IFS=$OIFS
    display_num=0
    for connector in "${connector_arr[@]}"; do
        GUEST_DISP_TYPE+=",connectors.${display_num}=${connector}"  
        ((display_num+=1))
        # Check if display number within limit
        if [[ $display_num -gt $GUEST_MAX_OUTPUTS ]]; then
            echo "$GUEST_CONNECTORS exceed maximum display output of $GUEST_MAX_OUTPUTS!"
            return -1
        fi
    done
}

function parse_arg() {
    # First argument is fixed, the name of the domain
    # Verify domain name
    if [[ $# -eq 0 || "$1" == "-h" ]]; then
      show_help
      return -1
    else
      if [[ -z $(sudo virsh list --all | grep $1) ]]; then
        echo "Domain $1 is not defined"
        return -1
      fi
    fi
    GUEST_DOMAIN=$1
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit 0
                ;;

            --output)
                # Save max-ouputs
                GUEST_MAX_OUTPUTS=$2
                if [ $GUEST_MAX_OUTPUTS -lt $GUEST_DISPLAY_MIN ] || [ $GUEST_MAX_OUTPUTS -gt $GUEST_DISPLAY_MAX ]; then
                    echo "$1 exceed limit, must be between $GUEST_DISPLAY_MIN to $GUEST_DISPLAY_MAX!"
                    exit -1
                fi
                shift
                ;;

            --connectors)
                GUEST_CONNECTORS=$2
                shift
                ;;

            --full-screen)
                # Set full-screen=on
                GUEST_DISP_TYPE+=",full-screen=on"
                ;;

            --show-fps)
                # Set show-fps=on
                GUEST_DISP_TYPE+=",show-fps=on"
                ;;

            --extend-abs-mode)
                # Set extend-abs-mode=on
                GUEST_DISP_TYPE+=",extend-abs-mode=on"
                shift
                ;;

            --disable-host-input)
                # Set input=off to disallow host HID control guest
                GUEST_DISP_TYPE+=",input=off"
                shift
                ;;

            -?*)
                echo "Error: Invalid option: $1"
                show_help
                return -1
                ;;
            *)
                echo "Error: Unknown option: $1"
                return -1
                ;;
        esac
        shift
    done

    parse_connectors
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit -1
edit_xml || exit -1
echo "Done: \"$(realpath ${BASH_SOURCE[0]}) $@\""

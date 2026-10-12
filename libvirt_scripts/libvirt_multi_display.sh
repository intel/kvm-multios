#!/bin/bash

# Copyright (c) 2023-2026 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------  Global variables  -------------------
GUEST_DOMAIN=""
GUEST_DISP_TYPE="-display gtk,gl=on,hw-cursor=on"
GUEST_DISPLAY_MAX=4
GUEST_DISPLAY_MIN=1
GUEST_MAX_OUTPUTS=1
GUEST_CONNECTORS=""
declare -a NORMALIZED_CONNECTORS=()

# QEMU 10.2 dropped the gtk hw-cursor/render_sync options.
if [[ "$(qemu-system-x86_64 --version 2>/dev/null || true)" == *"version 10.2."* ]]; then
    GUEST_DISP_TYPE="-display gtk,gl=on,keep-aspect-ratio=off"
fi

#---------      Functions    -------------------
function print_display_login_error() {
    local -a session_types=()
    mapfile -t session_types < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' | xargs -r -n1 loginctl show-session -p Type 2>/dev/null || true)

    if [[ "${session_types[*]-}" =~ Type=wayland ]]; then
        echo "Error: Host graphical session is Wayland, but an Xorg session is required."
        echo "       Set 'WaylandEnable=false' in the [daemon] section of /etc/gdm3/custom.conf,"
        echo "       then run 'sudo systemctl restart gdm' or reboot the host."
    else
        echo "Error: Please log in to the host's graphical login screen on the physical display."
    fi
}

function host_uses_wayland() {
    [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && return 0

    local session_id
    local session_type
    while read -r session_id; do
        [[ -n "$session_id" ]] || continue
        session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null || true)
        [[ "$session_type" == "wayland" ]] && return 0
    done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' || true)

    return 1
}

function edit_xml() {
    local display
    display="${DISPLAY:-}"
    if [[ -z "$display" ]]; then
      display=$(who | { grep -o ' :.' || :; } | xargs)
    fi
    if [[ -z $display ]]; then
      print_display_login_error
      return 255
    fi

    sudo virt-xml "$GUEST_DOMAIN" -q --edit --video model.heads="$GUEST_MAX_OUTPUTS"
    sudo virt-xml "$GUEST_DOMAIN" -q --edit --qemu-commandline args="$GUEST_DISP_TYPE"
    sudo virt-xml "$GUEST_DOMAIN" -q --edit --qemu-commandline env="DISPLAY=$display"
}

function show_help() {
    printf "%s domain_name [-h] [--output n] [--connectors list] [--full-screen] [--show-fps] [--extend-abs-mode] [--disable-host-input] \n" "$(basename "${BASH_SOURCE[0]}")"
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
	[[ -z "$GUEST_CONNECTORS" ]] && return 0
    local -a connector_arr
    local connector
    local normalized_connector
    mapfile -t -d ',' connector_arr <<< "$GUEST_CONNECTORS"
    if host_uses_wayland; then
        return 0
    fi
    display_num=0
    for connector in "${connector_arr[@]}"; do
	    [[ -z "$connector" ]] && continue
        connector="${connector//$'\n'/}"
        normalized_connector="$connector"
        if [[ "$normalized_connector" =~ ^(HDMI|DP)-A-([0-9]+)$ ]]; then
            normalized_connector="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
        fi
        NORMALIZED_CONNECTORS+=("$normalized_connector")
        GUEST_DISP_TYPE+=",connectors.${display_num}=${normalized_connector}"
        ((display_num+=1))
        # Check if display number within limit
        if [[ $display_num -gt $GUEST_MAX_OUTPUTS ]]; then
            echo "$GUEST_CONNECTORS exceed maximum display output of $GUEST_MAX_OUTPUTS!"
            return 255
        fi
    done
    return 0
}

function check_connectors() {
    [[ ${#NORMALIZED_CONNECTORS[@]} -gt 0 ]] || return 0
    command -v xrandr >/dev/null 2>&1 || return 0

    local -a connected_connectors=()
    local connector
    local connected
    local connected_connector
    local xrandr_output
    xrandr_output=$(xrandr --query 2>/dev/null || true)
    while read -r connector connected _; do
        if [[ "$connector" =~ ^(HDMI|DP)-[0-9]+$ && "$connected" == "connected" ]]; then
            connected_connectors+=("$connector")
        fi
    done <<< "$xrandr_output"
    [[ ${#connected_connectors[@]} -gt 0 ]] || return 0

    for connector in "${NORMALIZED_CONNECTORS[@]}"; do
        connected=0
        for connected_connector in "${connected_connectors[@]}"; do
            if [[ "$connector" == "$connected_connector" ]]; then
                connected=1
                break
            fi
        done
        if [[ $connected -eq 0 ]]; then
            echo "Error: Connector '$connector' is not connected on DISPLAY=${DISPLAY:-unknown}."
            echo "       Connected connectors: ${connected_connectors[*]}"
            echo "       Use one of the connected connectors and retry."
            return 255
        fi
    done
}

function parse_arg() {
    # First argument is fixed, the name of the domain
    # Verify domain name
    if [[ $# -eq 0 || "$1" == "-h" ]]; then
      show_help
      return 255
    else
      if ! sudo virsh list --all | grep -q "$1"; then
        echo "Domain $1 is not defined"
        return 255
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
                if [ "$GUEST_MAX_OUTPUTS" -lt "$GUEST_DISPLAY_MIN" ] || [ "$GUEST_MAX_OUTPUTS" -gt "$GUEST_DISPLAY_MAX" ]; then
                    echo "$1 exceed limit, must be between $GUEST_DISPLAY_MIN to $GUEST_DISPLAY_MAX!"
                    exit 255
                fi
                shift
                ;;

            --connectors)
                GUEST_CONNECTORS="$2"
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
                return 255
                ;;
            *)
                echo "Error: Unknown option: $1"
                return 255
                ;;
        esac
        shift
    done

    parse_connectors || return 255
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255
check_connectors || exit 255
edit_xml || exit 255
echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

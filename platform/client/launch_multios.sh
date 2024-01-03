#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail


#---------      Global variable     -------------------
# Define supported VM domains and configuration files
declare -A VM_DOMAIN=(
  ["ubuntu"]="ubuntu_vnc.xml"
  ["windows"]="windows_vnc_ovmf.xml"
  ["ubuntu_rt"]="ubuntu_rt_vnc.xml"
  ["android"]="android_virtio-gpu.xml"
)

# Array to store the list of passthrough devices
declare -A device_passthrough

# Array to store multi-display configuration for specific VM
declare -A multi_display

# Define variables

# Set default vm image directory and vm config xml file directory
IMAGE_DIR="/var/lib/libvirt/images/"

# Set passthrough script name
PASSTHROUGH_SCRIPT="./libvirt_scripts/virsh_attach_device.sh"

# Set multi display script name
MULTI_DISPLAY_SCRIPT="./libvirt_scripts/libvirt_multi_display.sh"

# Set default domain force launch option
FORCE_LAUNCH="false"

# Set default vm config xml file directory
XML_DIR="./platform/client/libvirt_xml"

# Set default BIOS used for windows VM
BIOS_WIN="ovmf"

# Disable SRIOV by default
SRIOV_ENABLE="false"

# Number of VF configure for SRIOV
SRIOV_VF_NUM=3

# Error log file
ERROR_LOG_FILE="/tmp/launch_multios_errors.log"

#---------      Functions    -------------------
declare -F "check_non_symlink" >/dev/null || function check_non_symlink() {
    if [[ $# -eq 1 ]]; then
        if [[ -L "$1" ]]; then
            echo "Error: $1 is a symlink." | tee -a $ERROR_LOG_FILE
            exit -1
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}" | tee -a $ERROR_LOG_FILE
        exit -1
    fi
}

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f $fpath || ! -s $fpath ]]; then
            echo "Error: $fpath invalid/zero sized" | tee -a $ERROR_LOG_FILE
            exit -1
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}" | tee -a $ERROR_LOG_FILE
        exit -1
    fi
}

# Function to log errors
function log_error() {
  echo "$(date): line: ${BASH_LINENO[0]}: $1" >> $ERROR_LOG_FILE
  echo "Error: $1"
  echo ""
}

function show_help() {
  printf "$(basename "${BASH_SOURCE[0]}") [-h|--help] [-f] [-a] [-d <domain1> <domain2> ...] [-g <vnc|sriov|gvtd> <domain>] [-p <domain> --usb|--pci <device> (<number>) | -p <domain> --xml <xml file>]\n"
  printf "Launch one or more guest VM domain(s) with libvirt\n\n"
  printf "Options:\n"
  printf "  -h,--help                         Show the help message and exit\n"
  printf "  -f                                Force shutdown, destory and start VM domain(s) without checking\n"
  printf "                                    if it's already running\n"
  printf "  -a                                Launch all defined VM domains\n"
  printf "  -d <domain(s)>                    Name of the VM domain(s) to launch\n"
  printf "  -g <vnc|sriov|gvtd> <domain(s)>   Type of display model use by the VM domain\n"
  printf "  -p <domain>                       Name of the VM domain for device passthrough\n"
  printf "      --usb | --pci                 Options of interface (eg. --usb or --pci)\n"
  printf "      <device>                      Name of the device (eg. mouse, keyboard, bluetooth, etc\n"
  printf "      (<number>)                    Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'\n"
  printf "                                    by default is the first device found\n"
  printf "  -p <domain> --xml <xml file>      Passthrough devices defined in an XML file\n"
  printf "  -m <domain>                       Name of the VM domain for multi display configuration\n"
  printf "Options for multi display:\n"
  printf "  --output n                        Number of output displays, n, range from 1 to 4\n"
  printf "  --connectors HDMI-n/DP-n,...      physical display connector per display output\n"
  printf "  --full-screen                     Set display to full-screen\n"
  printf "  --show-fps                        Show fps info on guest vm primary display\n"
  printf "  --extend-abs-mode                 Enable extend absolute mode across all monitors\n"
  printf "  --disable-host-input              Disable host's HID devices to control the monitors\n\n"
  printf "Supported domains:\n"
  for domain in "${!VM_DOMAIN[@]}"; do
    printf "  -  $domain\n"
  done
}


# Function to load SRIOV VF
function load_sriov() {
  export DISPLAY=:0
  xhost +

  NUMVFS=$1

  vendor=$(cat /sys/bus/pci/devices/0000:00:02.0/vendor)
  device=$(cat /sys/bus/pci/devices/0000:00:02.0/device)
  sudo modprobe i2c-algo-bit
  sudo modprobe video
  echo '0' | sudo tee -a /sys/bus/pci/devices/0000\:00\:02.0/sriov_drivers_autoprobe
  echo $NUMVFS | sudo tee -a /sys/class/drm/card0/device/sriov_numvfs
  echo '1' | sudo tee -a /sys/bus/pci/devices/0000\:00\:02.0/sriov_drivers_autoprobe
  sudo modprobe vfio-pci
  echo "$vendor $device" | sudo tee -a /sys/bus/pci/drivers/vfio-pci/new_id || :

  vfschedexecq=25
  vfschedtimeout=500000

  iov_path="/sys/class/drm/card0/iov"
  if [[ -d "/sys/class/drm/card0/prelim_iov" ]]; then
    iov_path="/sys/class/drm/card0/prelim_iov"
  fi
  local gt_name='gt0'
  for (( i = 1; i <= $NUMVFS; i++ ))
  do
    if [[ -d "${iov_path}/vf$i/gt" ]]; then
      gt_name="gt"
    fi

    echo $vfschedexecq | sudo tee -a ${iov_path}/vf$i/$gt_name/exec_quantum_ms
    echo $vfschedtimeout | sudo tee -a ${iov_path}/vf$i/$gt_name/preempt_timeout_us
    if [[ -d "/sys/class/drm/card0/gt/gt1" ]]; then
      echo $vfschedexecq | sudo tee -a ${iov_path}/vf$i/gt1/exec_quantum_ms
      echo $vfschedtimeout | sudo tee -a ${iov_path}/vf$i/gt1/preempt_timeout_us
    fi
  done
}

# Function to allocate/deallocate huge pages to meet the memory required by the guests
function resize_huge_pages() {
    required_hugepage_kb=$1
    required_hugepage_nr=$(($required_hugepage_kb/2048))
    free_hugepages=$(</sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages)
    if [[ $required_hugepage_nr -gt $free_hugepages ]]; then
        current_hugepages=$(</sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
        new_hugepages=$((required_hugepage_nr - free_hugepages + current_hugepages))
        echo "Setting hugepages $new_hugepages"
        echo $new_hugepages | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages > /dev/null
        # Check and wait for hugepages to be allocated
        local read_hugepages=0
        local count=0
        while [[ $((read_hugepages)) -ne $new_hugepages ]]
        do
            if [[ $((count++)) -ge 20 ]]; then
                echo "Error: insufficient memory to allocate hugepages"
                exit -1
            fi
            sleep 0.5
            read_hugepages=$(</sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
        done
    elif [[ $required_hugepage_nr -lt $free_hugepages ]]; then
      # reduce the number of hugepages if not required
      current_hugepages=$(</sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
      new_hugepages=$((current_hugepages - free_hugepages + required_hugepage_nr))
        echo "Setting hugepages $new_hugepages"
        echo $new_hugepages | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages > /dev/null
    fi
}

function parse_arg() {
  # Print help if no input argument found
  if [[ $# -eq 0 ]]; then
    log_error "No input argument found"
    show_help
    exit -1
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
          exit -1
        fi
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-[^-] ]]; do
          # Check if domain is supported
          if [[ ! "${!VM_DOMAIN[@]}" =~ "$1" ]]; then
            log_error "Domain $1 is not supported."
            show_help
            exit -1
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
          exit -1
        fi
        shift
        if [[ "$1" == "gvtd" || "$1" == "sriov" || "$1" == "vnc" ]]; then
          display="$1"
          if [[ "$1" == "sriov" ]]; then
            SRIOV_ENABLE="true"
          else
            SRIOV_ENABLE="false"
          fi
          # Check if next argument is a valid domain
          if [[ -z "${2+x}" || -z "$2" ]]; then
            log_error "Domain name missing after $1 option"
            show_help
            exit -1
          fi
          shift
          while [[ $# -gt 0 && ! "$1" =~ ^-[^-] ]]; do
            # Check if domain is supported
            if [[ ! "${!VM_DOMAIN[@]}" =~ "$1" ]]; then
              log_error "Domain $1 is not supported."
              show_help
              exit -1
            fi
            # No VNC support for Android
            if [[ "$1" == "android" && "${display}" == "vnc" ]]; then
              log_error "VNC for Android is not supported."
              show_help
              exit -1
            fi
            if [[ "$1" == "windows" ]]; then
              VM_DOMAIN[$1]="${1}_${display}_${BIOS_WIN}.xml"
            else
              VM_DOMAIN[$1]="${1}_${display}.xml"
            fi
            shift
          done
        else
          log_error "Display model $1 not supported"
          show_help
          exit -1
        fi
        ;;
      -p)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option"
          show_help
          exit -1
        fi
        domain=$2
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[@]}" =~ "$domain" ]]; then
          log_error "Domain $domain is not supported"
          show_help
          exit -1
        fi
        shift 2
        devices=()
        # Check passthrough options
        while [[ $# -gt 0 && ($1 == "--xml" || $1 == "--usb" || $1 == "--pci") ]]; do
          if [[ $1 == "--xml" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing XML file name after --xml"
              show_help
              exit -1
            fi
            devices+=("$1" "$2")
            shift 2
          elif [[ $1 == "--usb" || $1 == "--pci" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing device name after $1"
              show_help
              exit -1
            fi
            if [[ $# -lt 3 || -z $3 || $3 == -* ]]; then
              devices+=("$1" "$2")
              shift 2
            else
              devices+=("$1" "$2" "$3")
              shift 3
            fi
          else
            log_error "unknown device type"
            show_help
            exit -1
          fi
        done
        if [[ ${#devices[@]} -eq 0 ]]; then
          log_error "Missing device parameters after -p $domain"
          show_help
          exit -1
        fi
        device_passthrough[$domain]="${devices[*]}"
        ;;
      -m)
        # Check if next argument is a valid domain
        if [[ -z "${2+x}" || -z "$2" ]]; then
          log_error "Domain name missing after $1 option"
          show_help
          exit -1
        fi
        domain=$2
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[@]}" =~ "$domain" ]]; then
          log_error "Domain $domain is not supported"
          show_help
          exit -1
        fi
        shift 2
        display_args=()
        # Check multi display options
        while [[ $# -gt 0 && ($1 != -* || $1 == "--output" || $1 == "--connectors" || $1 == "--full-screen" || $1 == "--show-fps" || $1 == "--extend-abs-mode" || $1 == "--disable-host-input") ]]; do
          if [[ $1 == "--output" || $1 == "--connectors" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing parameter after $1"
              show_help
              exit -1
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
          exit -1
        fi
        multi_display[$domain]="${display_args[*]}"
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
  done
}


# Function to check if domain is already exist or running
function check_domain() {
  for domain in "$@"; do
    status=$(virsh domstate "$domain" 2>&1 ||:)

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
            exit -1
            ;;
          *)
            log_error "Invalid choice. Aborting launch of domain"
            print_help
            exit -1
            ;;
        esac
      else
        cleanup_domain "$domain"
      fi
    elif [[ "$status" =~ "shut off" ]]; then
      echo "Domain $domain is shut off. Undefining domain $domain"
      virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    #domstate may return "error: failed to get domain" for undefine domain
    elif [[ "$status" =~ "not found" || "$status" =~ "error" ]]; then
      echo "Domain $domain not found. Proceeding with launch"
    else
      echo "Domain $domain is $status. Destroy and undefine domain"
      virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
      virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    fi
  done
}

# Function to shutdown and undefine a domain
function cleanup_domain() {
  local domain="$1"
  echo "Shutting down and undefining domain $domain"
  virsh shutdown "$domain" >/dev/null 2>&1 || :
  # check if VM has shutdown at 5s interval, timeout 60s
  for (( x=0; x<12; x++ )); do
      echo "Wait for $domain to shutdown: $x"
      sleep 5
      state=$(virsh list --all | grep " $domain " | awk '{ print $3}')
      if [[ "$state" == "shut" ]];then
          break
      fi
  done
  state=$(virsh list --all | grep " $domain " | awk '{ print $3}')
  if [[ "$state" != "shut" ]];then
      echo "$domain in $state, force destroy $domain"
      virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
  fi
  virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
}

# Function to launch domain(s)
function launch_domains() {
  for domain in "$@"; do
    # Check if domain is supported
    if [[ ! "${VM_DOMAIN[@]}" =~ "$domain" ]]; then
      # By right should not come here, just double check
      log_error "Domain $domain is not supported."
      print_help
      exit -1
    fi
  done

  for domain in "$@"; do
    check_domain "$domain"
  done

  # reserve hugepages required for all domains
  total_required_hugepage_kb=0
  for domain in "$@"; do
    check_file_valid_nonzero "$XML_DIR/${VM_DOMAIN[$domain]}"
    hugepages_required=$(cat $XML_DIR/${VM_DOMAIN[$domain]} | grep \<memoryBacking\>) || :
    if [[ ! -z "$hugepages_required" ]]; then
      hugepage_memory_string=$(cat $XML_DIR/${VM_DOMAIN[$domain]} | grep -e "\<memory\>" -e "\<memory unit=.*\>")
      hugepage_memory_kb=${hugepage_memory_string//[!0-9]/}
      total_required_hugepage_kb=$((total_required_hugepage_kb + hugepage_memory_kb))
    fi
  done
  resize_huge_pages $total_required_hugepage_kb

  for domain in "$@"; do
    # Define domain
    check_file_valid_nonzero "$XML_DIR/${VM_DOMAIN[$domain]}"
    echo "Define domain $domain"
    virsh define $XML_DIR/${VM_DOMAIN[$domain]}

    # Configure multi-display for domain if present
    if [[ ${multi_display[$domain]+_} ]]; then
      echo "Configure multi display for $domain"
      $MULTI_DISPLAY_SCRIPT $domain ${multi_display[$domain]}
    fi

    # Passthrough devices
    echo "Passthrough device to domain $domain if any"
    passthrough_devices $domain

    # Start domain
    echo "Starting domain $domain..."
    virsh start $domain
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
          check_file_valid_nonzero $xml_file
          if [[ ! -f $xml_file ]]; then
            log_error "XML file not found for domain $domain: $xml_file"
            show_help
            exit -1
          fi
          echo "Performing XML file passthrough for domain $domain"
          virsh attach-device $domain --config --file $xml_file
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
          $PASSTHROUGH_SCRIPT -p $domain $interface "$device_name" $device_number
          ;;

        *)
          log_error "Invalid passthrough device option: $option"
          show_help
          exit -1
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

parse_arg "$@" || exit -1
# Configure SRIOV if needed
if [[ "$SRIOV_ENABLE" == "true" ]]; then
  load_sriov $SRIOV_VF_NUM
fi
# Launch domain(s)
launch_domains "${domains[@]}" || exit -1
exit 0

#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

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
ERROR_LOG_FILE="launch_multios_errors.log"

# Function to log errors
function log_error() {
  echo "$(date): line: ${BASH_LINENO[0]}: $1" >> $ERROR_LOG_FILE
  echo "Error: $1"
  echo ""
}

# Function to print help info
function print_help() {
  echo ""
  echo "Usage:"
  echo "$0 [-h|--help] [-f] [-a] [-d <domain1> <domain2> ...] [-g <vnc|sriov|gvtd> <domain>] [-p <domain> --usb|--pci <device> (<number>) | -p <domain> --xml <xml file>]"
  echo ""
  echo "Launch one or more guest VM domain(s) with libvirt"
  echo "Options:"
  echo "  -h,--help                       Show the help message and exit"
  echo "  -f                              Force shutdown, destory and start VM domain(s) without checking"
  echo "                                  if it's already running"
  echo "  -a                              Launch all defined VM domains"
  echo "  -d <domain(s)>                  Name of the VM domain(s) to launch"
  echo "  -g <vnc|sriov|gvtd> <domain(s)> Type of display model use by the VM domain"
  echo "  -p <domain>                     Name of the VM domain for device passthrough"
  echo "     --usb | --pci                Options of interface (eg. --usb or --pci)"
  echo "     <device>                     Name of the device (eg. mouse, keyboard, bluetooth, etc"
  echo "     (<number>)                   Optional, specify the 'N'th device found in the device list of 'lsusb' or 'lspci'"
  echo "                                  by default is the first device found"
  echo "  -p <domain> --xml <xml file>    Passthrough devices defined in an XML file"
  echo "  -m <domain>                     Name of the VM domain for multi display configuration"
  echo "                                  Options for multi display"
  echo "    --output n                    Number of output displays, n, range from 1 to 4"
  echo "    --connectors HDMI-n/DP-n,...  physical display connector per display output"
  echo "    --full-screen                 Set display to full-screen"
  echo "    --show-fps                    Show fps info on guest vm primary display"
  echo "    --extend-abs-mode             Enable extend absolute mode across all monitors"
  echo "    --disable-host-input          Disable host's HID devices to control the monitors"
  echo ""
  echo "Supported domains:"
  for domain in "${!VM_DOMAIN[@]}"; do
    echo "  - $domain"
  done
  echo ""
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

function remove_huge_page_settings() {
    guest_domain=$1
    sudo virt-xml $guest_domain -q --edit --memorybacking clearxml=yes
    if [[ $(sudo virsh dumpxml $guest_domain | grep "qemu:arg") ]]; then
      qemu_arg=$(sudo virsh dumpxml $guest_domain | grep "qemu:arg" | grep -oP "(?<=value=').*(?=')" | tr '\n' ' ')
      #qemu_arg=$(sudo virsh dumpxml $guest_domain | grep "qemu:arg" | grep -oP "'\K[^'/>]+" | tr '\n' ' ')
      if [[ "$qemu_arg" =~ "-set device.video0.blob=true" ]]; then
        qemu_arg=$(sed "s/\-set device.video0.blob=true//g" <<< $qemu_arg)
      fi
      sudo virt-xml $guest_domain -q --edit --qemu-commandline clearxml=yes
      sudo virt-xml $guest_domain -q --edit --qemu-commandline args="$qemu_arg"
      sudo virt-xml $guest_domain -q --edit --qemu-commandline env="DISPLAY=:0"
    fi
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
                exit 1
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

# Function to handle command line arguments
function handle_arguments() {
  # Print help if no input argument found
  if [[ $# -eq 0 ]]; then
    log_error "No input argument found"
    print_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_help
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
        if [[ -z "$2" ]]; then
          log_error "Domain name missing after $1 option"
          print_help
          exit 1
        fi
        shift
        while [[ $# -gt 0 && ! "$1" =~ ^-[^-] ]]; do
          # Check if domain is supported
          if [[ ! "${!VM_DOMAIN[@]}" =~ "$1" ]]; then
            log_error "Domain $1 is not supported."
            print_help
            exit 1
          fi
          domains+=("$1")
          shift
        done
        ;;
      -g)
        # Check if next argument is a valid display model
        if [[ -z "$2" ]]; then
          log_error "Display model missing after $1 option"
          print_help
          exit 1
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
            print_help
            exit 1
          fi
          shift
          while [[ $# -gt 0 && ! "$1" =~ ^-[^-] ]]; do
            # Check if domain is supported
            if [[ ! "${!VM_DOMAIN[@]}" =~ "$1" ]]; then
              log_error "Domain $1 is not supported."
              print_help
              exit 1
            fi
            # No VNC support for Android
            if [[ "$1" == "android" && "${display}" == "vnc" ]]; then
              log_error "VNC for Android is not supported."
              print_help
              exit 1
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
          print_help
          exit 1
        fi
        ;;
      -p)
        # Check if next argument is a valid domain
        domain=$2
        if [[ -z $domain ]]; then
          log_error "Domain name missing after $1 option"
          print_help
          exit 1
        fi
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[@]}" =~ "$domain" ]]; then
          log_error "Domain $domain is not supported"
          print_help
          exit 1
        fi
        shift 2
        devices=()
        # Check passthrough options
        while [[ $# -gt 0 && ($1 != -* || $1 == "--xml" || $1 == "--usb" || $1 == "--pci") ]]; do
          if [[ $1 == "--xml" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing XML file name after --xml"
              print_help
              exit 1
            fi
            devices+=("$1" "$2")
            shift 2
          elif [[ $1 == "--usb" || $1 == "--pci" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing device name after $1"
              print_help
              exit 1
            fi
            devices+=("$1" "$2")
            shift 2
          else
            devices+=("$1")
            shift
          fi
        done
        if [[ ${#devices[@]} -eq 0 ]]; then
          log_error "Missing device parameters after -p $domain"
          print_help
          exit 1
        fi
        device_passthrough[$domain]="${devices[*]}"
        ;;
      -m)
        # Check if next argument is a valid domain
        domain=$2
        if [[ -z $domain ]]; then
          log_error "Domain name missing after $1 option"
          print_help
          exit 1
        fi
        # Check if domain is supported
        if [[ ! "${!VM_DOMAIN[@]}" =~ "$domain" ]]; then
          log_error "Domain $domain is not supported"
          print_help
          exit 1
        fi
        shift 2
        display_args=()
        # Check multi display options
        while [[ $# -gt 0 && ($1 != -* || $1 == "--output" || $1 == "--connectors" || $1 == "--full-screen" || $1 == "--show-fps" || $1 == "--extend-abs-mode" || $1 == "--disable-host-input") ]]; do
          if [[ $1 == "--output" || $1 == "--connectors" ]]; then
            if [[ -z $2 || $2 == -* ]]; then
              log_error "Missing parameter after $1"
              print_help
              exit 1
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
          print_help
          exit 1
        fi
        multi_display[$domain]="${display_args[*]}"
        ;;      
      *)
        log_error "Invalid argument '${1}'"
        print_help
        exit 1
        ;;
    esac
  done
}

# Function to check if domain is already exist or running
function check_domain() {
  for domain in "$@"; do
    status=$(sudo virsh domstate "$domain" 2>&1 ||:)

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
            exit 1
            ;;
          *)
            log_error "Invalid choice. Aborting launch of domain"
            print_help
            exit 1
            ;;
        esac
      else
        cleanup_domain "$domain"
      fi
    elif [[ "$status" =~ "shut off" ]]; then
      echo "Domain $domain is shut off. Undefining domain $domain"
      sudo virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    #domstate may return "error: failed to get domain" for undefine domain
    elif [[ "$status" =~ "not found" || "$status" =~ "error" ]]; then
      echo "Domain $domain not found. Proceeding with launch"
    else
      echo "Domain $domain is $status. Destroy and undefine domain"
      sudo virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
      sudo virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
    fi
  done
}

# Function to shutdown and undefine a domain
function cleanup_domain() {
  local domain="$1"
  echo "Shutting down and undefining domain $domain"
  sudo virsh shutdown "$domain" >/dev/null 2>&1 || :
  # check if VM has shutdown at 5s interval, timeout 60s
  for (( x=0; x<12; x++ )); do
      echo "Wait for $domain to shutdown: $x"
      sleep 5
      state=$(sudo virsh list --all | grep " $domain " | awk '{ print $3}')
      if [[ "$state" == "shut" ]];then
          break
      fi
  done
  state=$(sudo virsh list --all | grep " $domain " | awk '{ print $3}')
  if [[ "$state" != "shut" ]];then
      echo "$domain in $state, force destroy $domain"
      sudo virsh destroy "$domain" >/dev/null 2>&1 || :
      sleep 5
  fi
  sudo virsh undefine "$domain" --nvram >/dev/null 2>&1 || :
}

# Function to launch domain(s)
function launch_domains() {
  for domain in "$@"; do
    # Check if domain is supported
    if [[ ! "${VM_DOMAIN[@]}" =~ "$domain" ]]; then
      # By right should not come here, just double check
      log_error "Domain $domain is not supported."
      print_help
      exit 1
    fi
  done

  for domain in "$@"; do
    check_domain "$domain"
  done
#From V6.4 kernel there is no hugepage required
  local major_version=$(uname -r | awk -F'.' '{ print $1 }')
  local minor_version=$(uname -r | awk -F'.' '{ split($2, a, /[^0-9]/); print a[1] }')
  # reserve hugepages required for all domains
if [[ "$major_version" -lt 6 ]] || [[ ("$major_version" -eq 6 && "$minor_version" -lt 4) ]]; then
  total_required_hugepage_kb=0
  for domain in "$@"; do
    hugepages_required=$(cat $XML_DIR/${VM_DOMAIN[$domain]} | grep \<memoryBacking\>) || :
    if [[ ! -z "$hugepages_required" ]]; then
      hugepage_memory_string=$(cat $XML_DIR/${VM_DOMAIN[$domain]} | grep -e "\<memory\>" -e "\<memory unit=.*\>")
      hugepage_memory_kb=${hugepage_memory_string//[!0-9]/}
      total_required_hugepage_kb=$((total_required_hugepage_kb + hugepage_memory_kb))
    fi
  done
  resize_huge_pages $total_required_hugepage_kb
fi

  for domain in "$@"; do
    # Define domain
    echo "Define domain $domain"
    sudo virsh define $XML_DIR/${VM_DOMAIN[$domain]}

    if [[ "$major_version" -gt 6 ]] || [[ ("$major_version" -eq 6 && "$minor_version" -ge 4) ]]; then
      remove_huge_page_settings $domain
    fi

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
    sudo virsh start $domain
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
          if [[ ! -f $xml_file ]]; then
            log_error "XML file not found for domain $domain: $xml_file"
            print_help
            exit 1
          fi
          echo "Performing XML file passthrough for domain $domain"
          sudo virsh attach-device $domain --config --file $xml_file
          ((i+=2))
          ;;

        --usb | --pci)
          # Individual device passthrough
          local interface=${option#--}
          local device_name=""
          local device_number=""

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
          $PASSTHROUGH_SCRIPT $domain $interface "$device_name" $device_number
          ;;

        *)
          log_error "Invalid passthrough device option: $option"
          print_help
          exit 1
          ;;
      esac

    done
  else
    # No device passthrough
    echo "No device passthrough for domain $domain"
  fi
}

# main function
function main() {
  # Handle input arguments
  handle_arguments "$@"

  # Configure SRIOV if needed
  if [[ "$SRIOV_ENABLE" == "true" ]]; then
    load_sriov $SRIOV_VF_NUM
  fi
  
  # Launch domain(s)
  launch_domains "${domains[@]}"
}

# Call main function
main "$@"

exit 0

#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

LIBVIRT_DEFAULT_IMAGES_PATH=/var/lib/libvirt/images
OVMF_DEFAULT_PATH=/usr/share/OVMF
WIN_DOMAIN_NAME=windows
WIN_IMAGE_NAME=$WIN_DOMAIN_NAME.qcow2
WIN_INSTALLER_ISO=windowsNoPrompt.iso
WIN_VIRTIO_ISO=virtio-win.iso
WIN_UNATTEND_ISO=$WIN_DOMAIN_NAME-unattend-win10.iso
WIN_UNATTEND_FOLDER=unattend_win10

# files required to be in $WIN_UNATTEND_FOLDER folder for installation
REQUIRED_FILES=( "$WIN_INSTALLER_ISO" "windows-updates.msu" "ZCBuild_MSFT_Signed.zip" "Driver-Release-64-bit.zip" )

FORCECLEAN=0
VIEWER=0
PLATFORM_NAME=""

VIEWER_DAEMON_PID=
FILE_SERVER_DAEMON_PID=
FILE_SERVER_IP="192.168.122.1"
FILE_SERVER_PORT=8002

script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

function run_file_server() {
    local folder=$1
    local ip=$2
    local port=$3
    local -n pid=$4
   
    cd $folder
    python3 -m http.server -b $ip $port &
    pid=$!
    cd -
}

function kill_by_pid() {
    if [[ $# -eq 1 && ! -z "${1+x}" ]]; then
        local pid=$1
        if [[ -n "$(ps -p $pid -o pid=)" ]]; then
            sudo kill -9 $pid
        fi 
    fi
}

function install_dep() {
  sudo apt install -y virtinst
}

function clean_windows_images() {
  echo "Remove existing windows image"
  sudo virsh destroy $WIN_DOMAIN_NAME &>/dev/null || :
  sleep 5
  sudo virsh undefine $WIN_DOMAIN_NAME --nvram &>/dev/null || :
  sudo rm -f ${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME}

  echo "Remove and rebuild unattend_win10.iso"
  sudo rm -f /tmp/${WIN_UNATTEND_ISO}
}

function install_windows() {
  local dest_tmp_path=$(realpath "/tmp/${WIN_DOMAIN_NAME}_install_tmp_files")
  local fileserverdir="$scriptpath/$WIN_UNATTEND_FOLDER"

  for file in ${REQUIRED_FILES[@]}; do
	local rfile=$(realpath $fileserverdir/$file)
	if [ ! -f $rfile ]; then
		echo "Error: Missing $file in $fileserverdir required for installation!"
		return -1
	fi
  done

  install_dep || return -1
  if [[ -d "$dest_tmp_path" ]]; then
    rm -rf "$dest_tmp_path"
  fi
  mkdir -p "$dest_tmp_path"

  cp "$scriptpath/$WIN_UNATTEND_FOLDER/autounattend.xml" $dest_tmp_path/
  local file_server_url="http://$FILE_SERVER_IP:$FILE_SERVER_PORT"

  tee $fileserverdir/zc_install.ps1 &>/dev/null <<EOF
\$tempdir="C:\Temp"
Start-Transcript -Path "\$tempdir\RunDVInstallerLogs.txt" -Force -Append
\$Host.UI.RawUI.WindowTitle = 'Check for installing Zero-copy drivers as required.'
if ( (Get-ScheduledTask -TaskName "DVEnabler" -TaskPath "\Microsoft\Windows\DVEnabler\") -or (Get-CimInstance -ClassName Win32_VideoController | where-Object { \$_.Name -like "DVServerUMD*" }) ) {
    Write-Output "Zero-copy driver already installed"
    Disable-ScheduledTask -TaskName 'RunZCDrvInstall' -TaskPath '\Microsoft\Windows\RunZCDrvInstall\'
    Unregister-ScheduledTask -TaskName 'RunZCDrvInstall' -TaskPath '\Microsoft\Windows\RunZCDrvInstall\' -Confirm:\$false
    Stop-Computer -Force
} else {
    if (Get-CimInstance -ClassName Win32_VideoController | Where-Object { \$_.PNPDeviceID -like 'PCI\VEN_8086*' }) {
        if (-not(Test-Path -Path \$tempdir\GraphicsDriver)) {
            Expand-Archive -Path '\$tempdir\Driver-Release-64-bit.zip' -DestinationPath '\$tempdir\GraphicsDriver' -Force
        }

        \$Host.UI.RawUI.WindowTitle = "Running Intel Graphics driver install"
        Write-Output "Found Intel GPU. Running Intel Graphics driver install"
        \$p=Start-Process -FilePath "\$tempdir\GraphicsDriver\install\installer.exe" -ArgumentList "-o", "-s" -WorkingDirectory "\$tempdir\GraphicsDriver\install" -Wait -Verb RunAs -PassThru
        if ((\$p.ExitCode -ne 0) -and (\$p.ExitCode -ne 14)) {
            Write-Output "Graphics Driver install returned \$(\$p.ExitCode). Check <WINDIR>\Temp\IntelGFX.log"
            Exit \$LASTEXITCODE
        }

        \$Host.UI.RawUI.WindowTitle = "Running Intel Zero-copy driver install"
        Set-Location -Path "\$tempdir\ZCBuild_Install\ZCBuild_MSFT_Signed"
        Write-Output "Found Intel GPU. Running Intel Zero-copy driver install"
        \$EAPBackup = \$ErrorActionPreference
        \$ErrorActionPreference = 'Stop'
        # Script restarts computer upon success
        Try {
            & ".\DVInstaller.ps1"
        }
        Catch {
            Write-Output "Zero-copy install script threw error. Check \$tempdir\RunDVInstallerLogs.txt"
        }
        \$ErrorActionPreference = \$EAPBackup
        # check for installed driver and reboot in case zero-copy install script did not reboot
        if (Get-ScheduledTask -TaskName "DVEnabler" -TaskPath "\Microsoft\Windows\DVEnabler\") {
            Restart-Computer -Force
        }
        Exit \$LASTEXITCODE
    }
}
EOF

  sed -i "s|%FILE_SERVER_URL%|$file_server_url|g" $dest_tmp_path/autounattend.xml
  run_file_server "$fileserverdir" $FILE_SERVER_IP $FILE_SERVER_PORT FILE_SERVER_DAEMON_PID || return -1

  if [[ ! -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_VIRTIO_ISO}" ]]; then
    echo "Download virtio-win iso"
    sudo wget -O ${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_VIRTIO_ISO} https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.229-1/virtio-win-0.1.229.iso
  fi

  sudo mkisofs -o /tmp/${WIN_UNATTEND_ISO} -J -r $dest_tmp_path
  echo "$(date): Start windows guest creation and auto-installation"
  if [[ "$VIEWER" -eq "1" ]]; then
    virt-viewer -w -r --domain-name ${WIN_DOMAIN_NAME} &
    VIEWER_DAEMON_PID=$!
  fi
  sudo virt-install \
  --name=${WIN_DOMAIN_NAME} \
  --ram=4096 \
  --vcpus=4 \
  --cpu host \
  --machine q35 \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5902 \
  --cdrom $scriptpath/$WIN_UNATTEND_FOLDER/${WIN_INSTALLER_ISO} \
  --disk ${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_VIRTIO_ISO},device=cdrom \
  --disk /tmp/${WIN_UNATTEND_ISO},device=cdrom \
  --disk path=${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME},format=qcow2,size=60,bus=virtio,cache=none \
  --os-variant win10 \
  --boot loader=$OVMF_DEFAULT_PATH/OVMF_CODE_4M.ms.fd,loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template=$OVMF_DEFAULT_PATH/OVMF_VARS_4M.ms.fd \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --pm suspend_to_mem.enabled=off,suspend_to_disk.enabled=on \
  --features smm.state=on \
  --noautoconsole \
  --wait=-1

  echo "$(date): Waiting for restarted Windows guest to complete installation and shutdown"
  local state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
  local loop=1
  while [[ ! -z ${state+x} && $state == "running" ]]; do
    echo "$(date): $loop: waiting for running VM..."
    local count=0
    local maxcount=120
    while [[ count -lt $maxcount ]]; do
      state=$(virsh list --all | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
      if [[ ! -z ${state+x} && $state == "running" ]]; then
        sleep 60
      else
        break
      fi
      count=$((count+1))
    done
    if [[ $count -ge $maxcount ]]; then
      echo "$(date): Error: timed out waiting for Windows required installation to finish after $maxcount min."
      return -1
    fi
    loop=$((loop+1))
  done

  # Start Windows VM with SRIOV to allow SRIOV Zero-Copy + graphics driver install
  echo "$(date): Proceeding with Zero-copy driver installation..."
  local platpath="$scriptpath/../../platform/$PLATFORM_NAME"
  if [ -d $platpath ]; then
    platpath=$(realpath "$platpath")
    echo "$(date): Restarting windows VM with SRIOV for Zero-Copy driver installation on local display."
    #sudo pkill virt-viewer
    kill_by_pid $VIEWER_DAEMON_PID
    $platpath/launch_multios.sh -f -d windows -g sriov windows

    if [ $? -eq 0 ]; then
      local count=0
      local maxcount=30
      while [[ count -lt $maxcount ]]; do
        echo "$(date): $loop: waiting for installation to complete and shutdown VM..."
        local state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
        if [[ ! -z ${state+x} && $state == "running" ]]; then
          #timeout 600 watch -g -n 2 'sudo virsh domstate windows'
          sleep 60
        else
          break
        fi
        count=$((count+1))
        if [[ $count -gt $maxcount ]]; then
          echo "$(date): Error: timed out waiting for SRIOV Zero-copy driver install to complete"
          return -1
        fi
      done
    else
      echo "$(date): Start Windows domain with SRIOV failed"
      return -1
    fi
  fi
}

function get_supported_platform_names() {
    local -n arr=$1
    local platpaths=( $(find "$scriptpath/../../platform/" -maxdepth 1 -mindepth 1 -type d) )
    for p in "${platpaths[@]}"; do
        arr+=( $(basename $p) )
    done
}

function set_platform_name() {
    local platforms=()
    local platform

    platform=$1
    get_supported_platform_names platforms

    for p in "${platforms[@]}"; do
        if [[ "$p" == "$platform" ]]; then
            PLATFORM_NAME="$platform"
            return
        fi
    done

    echo "Error: $platform is not a supported platform"
    return -1
}

function show_help() {
    local platforms=()

    printf "$(basename "${BASH_SOURCE[0]}") [-h] [-p] [--force] [--viewer]\n"
    printf "Create Windows vm required images and data to dest folder $LIBVIRT_DEFAULT_IMAGES_PATH/${WIN_DOMAIN_NAME}.qcow2\n"
    printf "Place required Windows installation files as listed below in guest_setup/ubuntu/$WIN_UNATTEND_FOLDER folder prior to running.\n"
	printf "(windowNoPrompt.iso, windows-updates.msu, ZCBuild_MSFT_Signed.zip, Driver-Release-64-bit.zip)\n"
    printf "Options:\n"
    printf "\t-h        show this help message\n"
    printf "\t-p        specific platform to setup for, eg. \"-p client \"\n"
    printf "\t          Accepted values:\n"
    get_supported_platform_names platforms
    for p in "${platforms[@]}"; do
    printf "\t            $(basename $p)\n"
    done
    printf "\t--force   force clean if windows vm qcow is already present\n"
    printf "\t--viewer  show installation display\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit
                ;;

            -p)
                set_platform_name $2 || return -1
                shift
                ;;

            --force)
                FORCECLEAN=1
                ;;

            --viewer)
                VIEWER=1
                ;;

            -?*)
                echo "Error: Invalid option $1"
                show_help
                return -1
                ;;
            *)
                echo "unknown option: $1"
                return -1
                ;;
        esac
        shift
    done
}

function cleanup () {
    local dest_tmp_path=$(realpath "/tmp/${WIN_DOMAIN_NAME}_install_tmp_files")
    if [ -d "$dest_tmp_path" ]; then
        rm -rf $dest_tmp_path
    fi
    kill_by_pid $FILE_SERVER_DAEMON_PID
    local state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
    if [[ ! -z ${state+x} && "$state" == "running" ]]; then
        echo "Shutting down running domain $WIN_DOMAIN_NAME"
        sudo virsh shutdown $WIN_DOMAIN_NAME
        echo "Waiting for domain $WIN_DOMAIN_NAME to shut down..."
        sleep 30
        sudo virsh destroy $WIN_DOMAIN_NAME
        sudo virsh undefine --nvram $WIN_DOMAIN_NAME
    fi
    sudo virsh undefine --nvram $WIN_DOMAIN_NAME
    kill_by_pid $VIEWER_DAEMON_PID
}

#-------------    main processes    -------------
trap 'cleanup' EXIT
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit -1

if [[ $FORCECLEAN == "1" ]]; then
    clean_windows_images || exit -1
fi

if [[ -z ${PLATFORM_NAME+x} || -z "$PLATFORM_NAME" ]]; then
	echo "Error: valid platform name required"
    show_help
    exit
fi

if [[ -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME}" ]]; then
    echo "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME} present"
    echo "Use --force option to force clean and re-install windows"
    exit
fi

install_windows || exit -1

echo "$(basename "${BASH_SOURCE[0]}") done"

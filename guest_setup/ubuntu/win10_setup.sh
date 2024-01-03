#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail

#---------      Global variable     -------------------
LIBVIRT_DEFAULT_IMAGES_PATH=/var/lib/libvirt/images
OVMF_DEFAULT_PATH=/usr/share/OVMF
WIN_DOMAIN_NAME=windows
WIN_IMAGE_NAME=$WIN_DOMAIN_NAME.qcow2
WIN_INSTALLER_ISO=windowsNoPrompt.iso
WIN_VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso"
WIN_VIRTIO_ISO=virtio-win.iso
WIN_UNATTEND_ISO=$WIN_DOMAIN_NAME-unattend-win10.iso
WIN_UNATTEND_FOLDER=unattend_win10
WIN_DISK_SIZE=60 # size in GiB

# files required to be in $WIN_UNATTEND_FOLDER folder for installation
REQUIRED_FILES=( "$WIN_INSTALLER_ISO" "windows-updates.msu" )
declare -a TMP_FILES
TMP_FILES=()

FORCECLEAN=0
VIEWER=0
PLATFORM_NAME=""
SETUP_NO_SRIOV=0
SETUP_NON_WHQL_GFX_DRV=0
SETUP_DEBUG=0

VIEWER_DAEMON_PID=
FILE_SERVER_DAEMON_PID=
FILE_SERVER_IP="192.168.122.1"
FILE_SERVER_PORT=8002

script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")

#---------      Functions    -------------------
declare -F "check_non_symlink" >/dev/null || function check_non_symlink() {
    if [[ $# -eq 1 ]]; then
        if [[ -L "$1" ]]; then
            echo "Error: $1 is a symlink."
            exit -1
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit -1
    fi
}

declare -F "check_dir_valid" >/dev/null || function check_dir_valid() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        dpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -d $dpath ]]; then
            echo "Error: $dpath invalid directory"
            exit -1
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit -1
    fi
}

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f $fpath || ! -s $fpath ]]; then
            echo "Error: $fpath invalid/zero sized"
            exit -1
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit -1
    fi
}

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
            kill -9 $pid
        fi 
    fi
}

function install_dep() {
  sudo apt install -y virtinst
  sudo apt install -y p7zip-full zip atool
}

function clean_windows_images() {
  echo "Remove existing windows image"
  if [[ ! -z $(virsh list --name | grep -w $WIN_DOMAIN_NAME) ]]; then
    echo "Shutting down running windows VM"
    virsh destroy $WIN_DOMAIN_NAME &>/dev/null || :
    sleep 30
  fi
  if [[ ! -z $(virsh list --name --all | grep -w $WIN_DOMAIN_NAME) ]]; then
    virsh undefine --nvram $WIN_DOMAIN_NAME
  fi
  sudo rm -f ${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME}

  echo "Remove and rebuild unattend_win10.iso"
  sudo rm -f /tmp/${WIN_UNATTEND_ISO}
  sudo rm -f /tmp/${WIN_VIRTIO_ISO}
}

function check_prerequisites() {
  local fileserverdir="$scriptpath/$WIN_UNATTEND_FOLDER"

  for file in ${REQUIRED_FILES[@]}; do
    if [[ "$file" == "Driver-Release-64-bit.[zip|7z]" ]]; then
       local nfile=$(find $fileserverdir -regex "$fileserverdir/Driver-Release-64-bit\.\(zip\|7z\)" | wc -l )
       if [[ $nfile -ne 1 ]]; then
         echo "Error: Only one of $file in $fileserverdir allowed for installation!"
         return -1
       fi
    else
      check_file_valid_nonzero "$fileserverdir/$file"
      local rfile=$(realpath $fileserverdir/$file)
      if [ ! -f $rfile ]; then
        echo "Error: Missing $file in $fileserverdir required for installation!"
        return -1
      fi
    fi
  done
}

function convert_drv_pkg_7z_to_zip() {
  local fileserverdir="$scriptpath/$WIN_UNATTEND_FOLDER"
  check_dir_valid "$scriptpath/$WIN_UNATTEND_FOLDER"
  local fname="Driver-Release-64-bit"
  local nfile=$(find $fileserverdir -regex "$fileserverdir/Driver-Release-64-bit\.\(zip\|7z\)" | wc -l )
  declare -a afiles
  local afiles=$(find $fileserverdir -regex "$fileserverdir/Driver-Release-64-bit\.\(zip\|7z\)")

  if [[ $nfile -ne 1 ]]; then
    echo "Only one if 7z/zip drv pkg archives allowed. ${afiles[@]} "
    return -1
  fi

  for afile in "${afiles[@]}"; do
    check_file_valid_nonzero $afile
    local rfile=$(realpath $afile)
    local ftype=$(file -b $rfile | awk -F',' '{print $1}')

    if [[ "$ftype" == "7-zip archive data" ]]; then
      echo "Converting 7-zip driver pkg to required zip archive format"
	  local zfile=$(realpath $fileserverdir/$fname.zip)
      arepack -f -F zip $rfile $zfile || return -1
      TMP_FILES+=("$zfile")

      return 0
    elif [[ "$ftype" == "Zip archive data" ]]; then
      echo "$fname.zip already present. No conversion needed"
      return 0
    else
      echo "Only one of Driver-Release-64-bit.7z or Driver-Release-64-bit.zip should be present! Remove accordingly."
      return -1
    fi
    break
  done

  return -1
}

function install_windows() {
  local dest_tmp_path=$(realpath "/tmp/${WIN_DOMAIN_NAME}_install_tmp_files")
  local fileserverdir="$scriptpath/$WIN_UNATTEND_FOLDER"
  local file_server_url="http://$FILE_SERVER_IP:$FILE_SERVER_PORT"

  if [[ $SETUP_NO_SRIOV -eq 0 ]]; then
    REQUIRED_FILES+=("ZCBuild_MSFT_Signed.zip")
    REQUIRED_FILES+=("Driver-Release-64-bit.[zip|7z]")
    if [[ $(xrandr -d :0 | grep -c "\bconnected\b") -lt 1 ]]; then
        echo "Error: Need at least 1 display connected for SR-IOV install."
        return -1
    fi
  fi
  check_prerequisites || return -1

  install_dep || return -1
  if [[ -d "$dest_tmp_path" ]]; then
    rm -rf "$dest_tmp_path"
  fi
  mkdir -p "$dest_tmp_path"
  TMP_FILES+=("$dest_tmp_path")

  check_dir_valid $fileserverdir
  if [[ $SETUP_NO_SRIOV -eq 1 ]]; then
    echo "Exit 0" > $fileserverdir/gfx_zc_setup.ps1
  else
    tee $fileserverdir/gfx_zc_setup.ps1 &>/dev/null <<EOF
\$tempdir='C:\Temp'
Start-Transcript -Path "\$tempdir\RunDVSetupLogs.txt" -Force -Append
\$Host.UI.RawUI.WindowTitle = 'Setup for GFX and Zero-copy installation.'
\$s='Downloading GFX driver'
Write-Output \$s
\$p=curl.exe -fSLo "\$tempdir\Driver-Release-64-bit.zip" "$file_server_url/Driver-Release-64-bit.zip"
if (\$LastExitCode -ne 0) {
  Write-Error "Error: \$s failed with exit code \$LastExitCode."
  Exit \$LastExitCode
}
\$s='Downloading Zero-copy driver'
Write-Output \$s
\$p=curl.exe -fSLo "\$tempdir\ZCBuild_MSFT_Signed.zip" "$file_server_url/ZCBuild_MSFT_Signed.zip"
if (\$LastExitCode -ne 0) {
  Write-Error "Error: \$s failed with exit code \$LastExitCode."
  Exit \$LastExitCode
}
\$s='Create driver install directory folder'
Write-Output \$s
\$p=New-Item -Force -Path "\$tempdir" -Name 'ZCBuild_Install' -ItemType 'directory'
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
\$s='Unzip Zero-Copy driver'
Write-Output \$s
\$p=Expand-Archive -Path "\$tempdir\ZCBuild_MSFT_Signed.zip" -DestinationPath "\$tempdir\ZCBuild_Install" -Force
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
\$s='Rename Zero-Copy driver folder'
Write-Output \$s
\$zcname=Get-ChildItem -Path "\$tempdir\ZCBuild_Install"|Where-Object {\$_.PSIsContainer -eq \$True -and \$_.Name -match 'ZCBuild_[0-9]+_MSFT_Signed'}
if (\$? -ne \$True) {
  Throw "Error: No Zero-copy driver folder found at \$tempdir\ZCBuild_Install."
}
\$p=Rename-Item -Path "\$tempdir\ZCBuild_Install\\\$zcname" -NewName 'ZCBuild_MSFT_Signed' -Force
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
\$s='Unzip Graphics driver'
Write-Output \$s
\$p=Expand-Archive -Path "\$tempdir\Driver-Release-64-bit.zip" -DestinationPath "\$tempdir\GraphicsDriver" -Force
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
\$s='Download GFX and Zero-copy driver install script'
Write-Output \$s
\$p=curl.exe -fSLo "\$tempdir\zc_install.ps1" "$file_server_url/zc_install.ps1"
if (\$LastExitCode -ne 0) {
  Write-Error "Error: \$s failed with exit code \$LastExitCode."
  Exit \$LastExitCode
}
\$s='Schedule task for GFX and Zero-copy driver install'
Write-Output \$s
\$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy ByPass -File ""\$tempdir\zc_install.ps1"""
\$taskTrigger = New-ScheduledTaskTrigger -AtStartup
\$taskName = "\Microsoft\Windows\RunZCDrvInstall\RunZCDrvInstall"
\$taskDescription = "RunZCDrvInstall"
\$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
\$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
\$taskTrigger.delay = 'PT30S'
Register-ScheduledTask -TaskName \$taskName -Action \$taskAction -Trigger \$taskTrigger -Description \$taskDescription -Principal \$taskPrincipal -Settings \$taskSettings
if (\$LastExitCode -ne 0) {
  Write-Error "Error: \$s failed with exit code \$LastExitCode."
  Exit \$LastExitCode
}
Exit \$LastExitCode
EOF

    convert_drv_pkg_7z_to_zip || return -1

    if [[ $SETUP_NON_WHQL_GFX_DRV -eq 1 ]]; then
      tee $fileserverdir/zc_install.ps1 &>/dev/null <<EOF
\$tempdir='C:\Temp'
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

        \$Host.UI.RawUI.WindowTitle = "Found Intel GPU. Running Intel Graphics driver install"
        Write-Output 'Installing Intel test sign certificate.'
        \$signature=Get-AuthenticodeSignature "\$tempdir\GraphicsDriver\extinf.cat"
        if (\$? -ne \$True) {
            Throw "Get Intel GPU driver signature failed"
        }
        \$store=Get-Item -Path Cert:\LocalMachine\TrustedPublisher
        if (\$? -ne \$True) {
            Throw "Get LocalMachine\TrustedPublisher cert path failed"
        }
        \$store.Open("ReadWrite")
        if (\$? -ne \$True) {
            Throw "Open LocalMachine\TrustedPublisher cert path for readwrite failed"
        }
        \$store.Add(\$signature.SignerCertificate)
        if (\$? -ne \$True) {
            Throw "Add Intel GPU driver signing cert failed"
        }
        \$store.Close()
        if (\$? -ne \$True) {
            Throw "Close cert store failed"
        }

        Write-Output 'Install Intel Graphics driver using pnputil'
        \$p=Start-Process pnputil.exe -ArgumentList '/add-driver',"\$tempdir\GraphicsDriver\iigd_dch.inf",'/install' -WorkingDirectory "\$tempdir\GraphicsDriver" -Wait -Verb RunAs -PassThru
        if (\$p.ExitCode -ne 0) {
            Write-Error "pnputil install Graphics Driver iigd_dch.inf failure return \$p.ExitCode"
            Exit \$p.ExitCode
        }

        Write-Output "Enable test signing"
        \$p=Start-Process bcdedit -ArgumentList "/set testsigning on" -Wait -Verb RunAs -PassThru
        if (\$p.ExitCode -ne 0) {
            Write-Error "Enable test signing failure return \$p.ExitCode"
            Exit \$p.ExitCode
        }

        Write-Output "Disable driver updates for GPU"
        \$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall'
        # Create the key if it does not exist
        If (-NOT (Test-Path \$RegistryPath)) {
            New-Item -Path \$RegistryPath -Force | Out-Null
            if (\$? -ne \$True) {
                Throw "Create \$RegistryPath failed"
            }
        }
        # Set variables to indicate value and key to set
        \$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
        \$Name = 'DenyDeviceIDs'
        \$Value = '1'
        # Create the key if it does not exist
        If (-NOT (Test-Path \$RegistryPath)) {
            New-Item -Path \$RegistryPath -Force | Out-Null
            if (\$? -ne \$True) {
                Throw "Create \$RegistryPath failed"
            }
        }
        New-ItemProperty -Path \$RegistryPath -Name \$Name -Value \$Value -PropertyType DWORD -Force 
        if (\$? -ne \$True) {
            Throw "Write \$RegistryPath\\\\\$Name key failed"
        }
        \$Name = 'DenyDeviceIDsRetroactive'
        \$Value = '1'
        # Create the key if it does not exist
        If (-NOT (Test-Path \$RegistryPath)) {
          New-Item -Path \$RegistryPath -Force | Out-Null
        }
        New-ItemProperty -Path \$RegistryPath -Name \$Name -Value \$Value -PropertyType DWORD -Force 
        if (\$? -ne \$True) {
            Throw "Write \$RegistryPath\\\\\$Name key failed"
        }
        \$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'
        If (-NOT (Test-Path \$RegistryPath)) {
            New-Item -Path \$RegistryPath -Force | Out-Null
            if (\$? -ne \$True) {
                Throw "Create \$RegistryPath failed"
            }
        }
        \$devidfull = (Get-PnpDevice -PresentOnly | Where { \$_.Class -like 'Display' -and \$_.InstanceId -like 'PCI\VEN_8086*' }).DeviceID
        \$strmatch = 'PCI\\\\VEN_8086&DEV_[A-Za-z0-9]{4}&SUBSYS_[A-Za-z0-9]{8}'
        \$deviddeny = ''
        If (\$devidfull -match \$strmatch -eq \$False) {
            Throw "Did not find Intel Video controller deviceID \$devidfull matching \$strmatch"
        }
        \$deviddeny = \$matches[0]
        for(\$x=1; \$x -lt 10; \$x=\$x+1) {
            \$Name = \$x
            \$value1 = (Get-ItemProperty \$RegistryPath -ErrorAction SilentlyContinue).\$Name
            If ((\$value1 -eq \$null) -or (\$value1.Length -eq 0)) {
                New-ItemProperty -Path \$RegistryPath -Name \$Name -Value \$deviddeny -PropertyType String -Force
                if (\$? -ne \$True) {
                    Throw "Write \$RegistryPath\\\\\$Name key failed"
                }
                break
            } else {
                If ((\$value1.Length -ne 0) -and (\$value1 -like \$deviddeny)) {
                    # already exists
                    break
                }
                continue
            }
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
            Write-Output "Force compuer restart after Zero-copy driver install"
            Restart-Computer -Force
        }
        Exit \$LastExitCode
    }
}
EOF
    else
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
            Write-Error "Graphics Driver install returned \$(\$p.ExitCode). Check <WINDIR>\Temp\IntelGFX.log"
            Exit \$LastExitCode
        }

        Write-Output "Disable driver updates for GPU"
        \$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall'
        # Create the key if it does not exist
        If (-NOT (Test-Path \$RegistryPath)) {
            New-Item -Path \$RegistryPath -Force | Out-Null
            if (\$? -ne \$True) {
                Throw "Create \$RegistryPath failed"
            }
        }
        # Set variables to indicate value and key to set
        \$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
        \$Name = 'DenyDeviceIDs'
        \$Value = '1'
        # Create the key if it does not exist
        If (-NOT (Test-Path \$RegistryPath)) {
            New-Item -Path \$RegistryPath -Force | Out-Null
            if (\$? -ne \$True) {
                Throw "Create \$RegistryPath failed"
            }
        }
        New-ItemProperty -Path \$RegistryPath -Name \$Name -Value \$Value -PropertyType DWORD -Force 
        if (\$? -ne \$True) {
            Throw "Write \$RegistryPath\\\\\$Name key failed"
        }
        \$Name = 'DenyDeviceIDsRetroactive'
        \$Value = '1'
        # Create the key if it does not exist
        If (-NOT (Test-Path \$RegistryPath)) {
          New-Item -Path \$RegistryPath -Force | Out-Null
        }
        New-ItemProperty -Path \$RegistryPath -Name \$Name -Value \$Value -PropertyType DWORD -Force 
        if (\$? -ne \$True) {
            Throw "Write \$RegistryPath\\\\\$Name key failed"
        }
        \$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'
        If (-NOT (Test-Path \$RegistryPath)) {
            New-Item -Path \$RegistryPath -Force | Out-Null
            if (\$? -ne \$True) {
                Throw "Create \$RegistryPath failed"
            }
        }
        \$devidfull = (Get-PnpDevice -PresentOnly | Where { \$_.Class -like 'Display' -and \$_.InstanceId -like 'PCI\VEN_8086*' }).DeviceID
        \$strmatch = 'PCI\\\\VEN_8086&DEV_[A-Za-z0-9]{4}&SUBSYS_[A-Za-z0-9]{8}'
        \$deviddeny = ''
        If (\$devidfull -match \$strmatch -eq \$False) {
            Throw "Did not find Intel Video controller deviceID \$devidfull matching \$strmatch"
        }
        \$deviddeny = \$matches[0]
        for(\$x=1; \$x -lt 10; \$x=\$x+1) {
            \$Name = \$x
            \$value1 = (Get-ItemProperty \$RegistryPath -ErrorAction SilentlyContinue).\$Name
            If ((\$value1 -eq \$null) -or (\$value1.Length -eq 0)) {
                New-ItemProperty -Path \$RegistryPath -Name \$Name -Value \$deviddeny -PropertyType String -Force
                if (\$? -ne \$True) {
                    Throw "Write \$RegistryPath\\\\\$Name key failed"
                }
                break
            } else {
                If ((\$value1.Length -ne 0) -and (\$value1 -like \$deviddeny)) {
                    # already exists
                    break
                }
                continue
            }
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
            Write-Output "Force compuer restart after Zero-copy driver install"
            Restart-Computer -Force
        }
        Exit \$LastExitCode
    }
}
EOF
    fi
    TMP_FILES+=("$(realpath $fileserverdir/zc_install.ps1)")
  fi
  TMP_FILES+=("$(realpath $fileserverdir/gfx_zc_setup.ps1)")

  check_file_valid_nonzero "$scriptpath/$WIN_UNATTEND_FOLDER/autounattend.xml"
  cp "$scriptpath/$WIN_UNATTEND_FOLDER/autounattend.xml" $dest_tmp_path/
  sed -i "s|%FILE_SERVER_URL%|$file_server_url|g" $dest_tmp_path/autounattend.xml

  if [[ ! -f "/tmp/${WIN_VIRTIO_ISO}" ]]; then
    echo "Download virtio-win iso"
    local is_200_okay=$(wget --server-response --content-on-error=off -O /tmp/${WIN_VIRTIO_ISO} ${WIN_VIRTIO_URL} 2>&1 | grep -c '200 OK')
    TMP_FILES+=("/tmp/${WIN_VIRTIO_ISO}")
    if [[ $is_200_okay -ne 1 || ! -f /tmp/${WIN_VIRTIO_ISO} ]]; then
        echo "Error: wget ${WIN_VIRTIO_URL} failure!"
        return -1
    fi
  else
    check_file_valid_nonzero "/tmp/${WIN_VIRTIO_ISO}"
  fi

  mkisofs -o /tmp/${WIN_UNATTEND_ISO} -J -r $dest_tmp_path || return -1
  TMP_FILES+=("/tmp/${WIN_UNATTEND_ISO}")

  echo "$(date): Start windows guest creation and auto-installation"
  run_file_server "$fileserverdir" $FILE_SERVER_IP $FILE_SERVER_PORT FILE_SERVER_DAEMON_PID || return -1
  if [[ "$VIEWER" -eq "1" ]]; then
    virt-viewer -w -r --domain-name ${WIN_DOMAIN_NAME} &
    VIEWER_DAEMON_PID=$!
  fi
  virt-install \
  --name=${WIN_DOMAIN_NAME} \
  --ram=4096 \
  --vcpus=4 \
  --cpu host \
  --machine q35 \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5902 \
  --cdrom $scriptpath/$WIN_UNATTEND_FOLDER/${WIN_INSTALLER_ISO} \
  --disk /tmp/${WIN_VIRTIO_ISO},device=cdrom \
  --disk /tmp/${WIN_UNATTEND_ISO},device=cdrom \
  --disk path=${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME},format=qcow2,size=${WIN_DISK_SIZE},bus=virtio,cache=none \
  --os-variant win10 \
  --boot loader=$OVMF_DEFAULT_PATH/OVMF_CODE_4M.ms.fd,loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template=$OVMF_DEFAULT_PATH/OVMF_VARS_4M.ms.fd \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --pm suspend_to_mem.enabled=off,suspend_to_disk.enabled=on \
  --features smm.state=on \
  --noautoconsole \
  --wait=-1 || return -1

  echo "$(date): Waiting for restarted Windows guest to complete installation and shutdown"
  local state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
  local loop=1
  while [[ ! -z ${state+x} && $state == "running" ]]; do
    local count=0
    local maxcount=120
    while [[ count -lt $maxcount ]]; do
      state=$(virsh list --all | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
      if [[ ! -z ${state+x} && $state == "running" ]]; then
        echo "$(date): $count: waiting for running VM..."
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

  if [[ $SETUP_NO_SRIOV -eq 0 ]]; then
    # Start Windows VM with SRIOV to allow SRIOV Zero-Copy + graphics driver install
    echo "$(date): Proceeding with Zero-copy driver installation..."
    local platpath="$scriptpath/../../platform/$PLATFORM_NAME"
    if [ -d $platpath ]; then
      platpath=$(realpath "$platpath")
      echo "$(date): Restarting windows VM with SRIOV for Zero-Copy driver installation on local display."
      #sudo pkill virt-viewer
      kill_by_pid $VIEWER_DAEMON_PID
      $platpath/launch_multios.sh -f -d windows -g sriov windows || return -1

      if [ $? -eq 0 ]; then
        local count=0
        local maxcount=90
        while [[ count -lt $maxcount ]]; do
          echo "$(date): $count: waiting for installation to complete and shutdown VM..."
          local state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
          if [[ ! -z ${state+x} && $state == "running" ]]; then
            #timeout 600 watch -g -n 2 'virsh domstate windows'
            sleep 60
          else
            break
          fi
          count=$((count+1))
          if [[ $count -ge $maxcount ]]; then
            echo "$(date): Error: timed out waiting for SRIOV Zero-copy driver install to complete"
            return -1
          fi
        done
      else
        echo "$(date): Start Windows domain with SRIOV failed"
        return -1
      fi
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
	declare -a required_files_help
	local required_files_help=( "${REQUIRED_FILES[@]}" )

    required_files_help+=("ZCBuild_MSFT_Signed.zip")
    required_files_help+=("Driver-Release-64-bit.[zip|7z]") 
    printf "$(basename "${BASH_SOURCE[0]}") [-h] [-p] [--no-sriov] [--non-whql-gfx] [--force] [--viewer] [--debug]\n"
    printf "Create Windows vm required images and data to dest folder $LIBVIRT_DEFAULT_IMAGES_PATH/${WIN_DOMAIN_NAME}.qcow2\n"
    printf "Place required Windows installation files as listed below in guest_setup/ubuntu/$WIN_UNATTEND_FOLDER folder prior to running.\n"
    printf "("
    for i in "${!required_files_help[@]}"; do
	  printf "${required_files_help[$i]}"
      if [[ $(($i + 1)) -lt ${#required_files_help[@]} ]]; then
        printf ", "
      fi
    done
    printf ")\n"
    printf "Options:\n"
    printf "\t-h                show this help message\n"
    printf "\t-p                specific platform to setup for, eg. \"-p client \"\n"
    printf "\t                  Accepted values:\n"
    get_supported_platform_names platforms
    for p in "${platforms[@]}"; do
    printf "\t                    $(basename $p)\n"
    done
    printf "\t--no-sriov        Non-SR-IOV windows install. No GFX/SRIOV support to be installed\n"
    printf "\t--non-whql-gfx    GFX driver to be installed is non-WHQL signed but test signed\n"
    printf "\t--force           force clean if windows vm qcow is already present\n"
    printf "\t--viewer          show installation display\n"
    printf "\t--debug           Do not remove temporary files. For debugging only.\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit 0
                ;;

            -p)
                set_platform_name $2 || return -1
                shift
                ;;

            --no-sriov)
                SETUP_NO_SRIOV=1
                ;;

            --non-whql-gfx)
                SETUP_NON_WHQL_GFX_DRV=1
                ;;

            --force)
                FORCECLEAN=1
                ;;

            --viewer)
                VIEWER=1
                ;;

            --debug)
                SETUP_DEBUG=1
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
        shift
    done
}

function cleanup () {
    for f in "${TMP_FILES[@]}"; do
      if [[ $SETUP_DEBUG -ne 1 ]]; then
        local fowner=$(ls -l $f | awk '{print $3}')
        if [[ "$fowner" == "$USER" ]]; then
            rm -rf $f
        else
            sudo rm -rf $f
        fi
      fi
    done
    kill_by_pid $FILE_SERVER_DAEMON_PID
    local state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
    if [[ ! -z ${state+x} && "$state" == "running" ]]; then
        echo "Shutting down running domain $WIN_DOMAIN_NAME"
        virsh shutdown $WIN_DOMAIN_NAME
        echo "Waiting for domain $WIN_DOMAIN_NAME to shut down..."
        sleep 30
        state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
        if [[ ! -z ${state+x} && "$state" == "running" ]]; then
            virsh destroy $WIN_DOMAIN_NAME
        fi
        virsh undefine --nvram $WIN_DOMAIN_NAME
    fi
    if [[ ! -z $(virsh list --name --all | grep -w $WIN_DOMAIN_NAME) ]]; then
        virsh undefine --nvram $WIN_DOMAIN_NAME
    fi
    kill_by_pid $VIEWER_DAEMON_PID
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit -1

if [[ $FORCECLEAN == "1" ]]; then
    clean_windows_images || exit -1
fi

if [[ -z ${PLATFORM_NAME+x} || -z "$PLATFORM_NAME" ]]; then
	echo "Error: valid platform name required"
    show_help
    exit -1
fi

if [[ -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME}" ]]; then
    echo "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME} present"
    echo "Use --force option to force clean and re-install windows"
    exit -1
fi

trap 'cleanup' EXIT

install_windows || exit -1

echo "$(basename "${BASH_SOURCE[0]}") done"

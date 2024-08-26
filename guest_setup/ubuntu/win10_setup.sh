#!/bin/bash

# Copyright (c) 2023-2024 Intel Corporation.
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
# "Windows for OpenSSH" v9.5.0.0p1-Beta release
WIN_OPENSSH_MSI_URL='https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64-v9.5.0.0.msi'
WIN_OPENSSH_MSI='OpenSSH-Win64.msi'

# files required to be in $WIN_UNATTEND_FOLDER folder for installation
REQUIRED_FILES=( "$WIN_INSTALLER_ISO" "windows-updates.msu" )
declare -a TMP_FILES
TMP_FILES=()

FORCECLEAN=0
VIEWER=0
PLATFORM_NAME=""
SETUP_DISK_SIZE=60 # size in GiB
SETUP_NO_SRIOV=0
SETUP_NON_WHQL_GFX_DRV=0
SETUP_DEBUG=0
SETUP_DISABLE_SECURE_BOOT=0
SETUP_ZC_GUI_INSTALLER=0
SETUP_ZC_FILENAME=''
ADD_INSTALL_DL_FAIL_EXIT=0

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
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

declare -F "check_dir_valid" >/dev/null || function check_dir_valid() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        dpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -d "$dpath" ]]; then
            echo "Error: $dpath invalid directory"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        fpath=$(realpath "$1")
        if [[ $? -ne 0 || ! -f "$fpath" || ! -s "$fpath" ]]; then
            echo "Error: $fpath invalid/zero sized"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}

function run_file_server() {
    local folder=$1
    local ip=$2
    local port=$3
    local -n pid=$4

    cd "$folder"
    python3 -m http.server -b "$ip" "$port" &
    pid=$!
    cd -
}

function kill_by_pid() {
    if [[ $# -eq 1 && -n "${1}" && -n "${1+x}" ]]; then
        local pid=$1
        if [[ -n "$(ps -p "$pid" -o pid=)" ]]; then
            kill -9 "$pid"
        fi
    fi
}

function install_dep() {
  which virt-install > /dev/null || sudo apt install -y virtinst
  which arepack > /dev/null || sudo apt install -y p7zip-full zip atool
  which mkisofs > /dev/null || sudo apt install -y mkisofs
  which virt-viewer > /dev/null || sudo apt install -y virt-viewer
  which unzip > /dev/null || sudo apt install -y unzip
  which xmllint > /dev/null || sudo apt install -y libxml2-utils
  which yamllint > /dev/null || sudo apt install -y yamllint
  which cabextract > /dev/null || sudo apt install -y cabextract
  which xmlstarlet > /dev/null || sudo apt install -y xmlstarlet
  which yq > /dev/null || sudo snap install yq
}

function clean_windows_images() {
  echo "Remove existing windows image"
  if virsh list --name | grep -q -w "$WIN_DOMAIN_NAME"; then
    echo "Shutting down running windows VM"
    virsh destroy "$WIN_DOMAIN_NAME" &>/dev/null || :
    sleep 30
  fi
  if virsh list --name --all | grep -q -w "$WIN_DOMAIN_NAME"; then
    virsh undefine --nvram "$WIN_DOMAIN_NAME"
  fi
  sudo rm -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME}"

  echo "Remove and rebuild unattend_win10.iso"
  rm -f "/tmp/${WIN_UNATTEND_ISO}"
  sudo rm -f "/tmp/${WIN_VIRTIO_ISO}"
  rm -f "/tmp/${WIN_OPENSSH_MSI_URL}"
}

function check_prerequisites() {
  local fileserverdir="$scriptpath/$WIN_UNATTEND_FOLDER"

  for file in "${REQUIRED_FILES[@]}"; do
    if [[ "$file" == "Driver-Release-64-bit.[zip|7z]" ]]; then
      local nfile
      nfile=$(find "$fileserverdir" -regex "$fileserverdir/Driver-Release-64-bit\.\(zip\|7z\)" | wc -l )
      if [[ $nfile -ne 1 ]]; then
        echo "Error: Only one of $file in $fileserverdir allowed for installation!"
        return 255
      fi
    elif [[ "$file" == "ZCBuild_MSFT_Signed.zip|ZCBuild_MSFT_Signed_Installer.zip" ]]; then
      local nfile
      nfile=$(find "$fileserverdir" -regex "$fileserverdir/ZCBuild_MSFT_Signed.zip" | wc -l )
      local nfile1
      nfile1=$(find "$fileserverdir" -regex "$fileserverdir/ZCBuild_MSFT_Signed_Installer.zip" | wc -l )
      if [[ $nfile -eq 0 && $nfile1 -eq 1 ]]; then
        SETUP_ZC_GUI_INSTALLER=1
        SETUP_ZC_FILENAME="ZCBuild_MSFT_Signed_Installer.zip"
      elif [[ $nfile -eq 1 && $nfile1 -eq 0 ]]; then
        SETUP_ZC_GUI_INSTALLER=0
        SETUP_ZC_FILENAME="ZCBuild_MSFT_Signed.zip"
      else
        echo "Error: Only one of $file in $fileserverdir allowed for installation!"
        return 255
      fi
    else
      check_file_valid_nonzero "$fileserverdir/$file"
      local rfile
      rfile=$(realpath "$fileserverdir/$file")
      if [ ! -f "$rfile" ]; then
        echo "Error: Missing $file in $fileserverdir required for installation!"
        return 255
      fi
    fi
  done
}

function convert_drv_pkg_7z_to_zip() {
  local fileserverdir="$scriptpath/$WIN_UNATTEND_FOLDER"
  check_dir_valid "$scriptpath/$WIN_UNATTEND_FOLDER"
  local fname="Driver-Release-64-bit"
  local nfile
  nfile=$(find "$fileserverdir" -regex "$fileserverdir/Driver-Release-64-bit\.\(zip\|7z\)" | wc -l )
  local -a afiles
  afiles=$(find "$fileserverdir" -regex "$fileserverdir/Driver-Release-64-bit\.\(zip\|7z\)")

  if [[ $nfile -ne 1 ]]; then
    echo "Only one if 7z/zip drv pkg archives allowed. ${afiles[*]} "
    return 255
  fi

  for afile in "${afiles[@]}"; do
    check_file_valid_nonzero "$afile"
    local rfile
    rfile=$(realpath "$afile")
    local ftype
    ftype=$(file -b "$rfile" | awk -F',' '{print $1}')

    if [[ "$ftype" == "7-zip archive data" ]]; then
      echo "Converting 7-zip driver pkg to required zip archive format"
      local zfile
	  zfile=$(realpath "$fileserverdir/$fname.zip")
      arepack -f -F zip "$rfile" "$zfile" || return 255
      TMP_FILES+=("$zfile")

      return 0
    elif [[ "$ftype" == "Zip archive data" ]]; then
      echo "$fname.zip already present. No conversion needed"
      return 0
    else
      echo "Only one of Driver-Release-64-bit.7z or Driver-Release-64-bit.zip should be present! Remove accordingly."
      return 255
    fi
    break
  done

  return 255
}

function setup_additional_installs() {
  declare -a installations
  local cfgfile
  local fileserverdir
  local file_server_url
  local xmlfile

  if [[ -z "${1+x}" || -z "$1" ]]; then
    echo "Invalid param. Installation yaml config file param expected."
    return 255
  fi
  check_file_valid_nonzero "$1"
  cfgfile=$(realpath "$1")
  if [[ -z "${2+x}" || -z "$2" ]]; then
    echo "Invalid param. file server directory path param expected."
    return 255
  fi
  check_dir_valid "$2"
  fileserverdir=$(realpath "$2")
  if [[ -z "${3+x}" || -z "$3" ]]; then
    echo "Invalid param. file server url param expected."
    return 255
  fi
  file_server_url="$3"
  if [[ -z "${4+x}" || -z "$4" ]]; then
    echo "Invalid param. Autoattend xml file param expected."
    return 255
  fi
  check_file_valid_nonzero "$4"
  xmlfile=$(realpath "$4")
  if ! xmllint --noout "$xmlfile"; then
    echo "Error: XML file $xmlfile has formatting error!"
    return 255
  fi

  mapfile installations < <(yq e -o=j -I=0 '.installations[]' "$cfgfile")
  if [[ ${#installations[@]} -ne 0 ]]; then
    # sanity check configuation file
    local -a names
    local -a descs
    local -a fnames
    local -a urls
    local -a itypes
    local -a ifiles
    local -a ioptions
    local -a etestsigns
    mapfile names < <(yq e -o=j -I=0 '.installations[].name' "$cfgfile")
    mapfile descs < <(yq e -o=j -I=0 '.installations[].description' "$cfgfile")
    mapfile fnames < <(yq e -o=j -I=0 '.installations[].filename' "$cfgfile")
    mapfile urls < <(yq e -o=j -I=0 '.installations[].download_url' "$cfgfile")
    mapfile itypes < <(yq e -o=j -I=0 '.installations[].install_type' "$cfgfile")
    mapfile ifiles < <(yq e -o=j -I=0 '.installations[].install_file' "$cfgfile")
    mapfile ioptions < <(yq e -o=j -I=0 '.installations[].install_silent_option' "$cfgfile")
    mapfile etestsigns < <(yq e -o=j -I=0 '.installations[].enable_test_sign' "$cfgfile")
    if [[ ${#names[@]} -ne ${#installations[@]} || ${#descs[@]} -ne ${#installations[@]} ||
      ${#fnames[@]} -ne ${#installations[@]} || ${#urls[@]} -ne ${#installations[@]} ||
      ${#itypes[@]} -ne ${#installations[@]} || ${#ifiles[@]} -ne ${#installations[@]} ||
      ${#ioptions[@]} -ne ${#installations[@]} || ${#etestsigns[@]} -ne ${#installations[@]} ]]; then
      echo "Missing fields for installations object found in $cfgfile."
      return 255
    fi
  else
    echo "No additional installations found in $cfgfile."
    return 0
  fi

  local step_id=20      # should be after end of basic install step_ids
  for installation in "${installations[@]}"; do
    #echo $installation
    local name
    name=$(echo "$installation" | yq e '.name' -)
    local cnt
    cnt=$(wc -w <<< "$name")
    if [[ $cnt -gt 1 ]]; then
      local newname
      newname="${name%% *}"
      echo "WARNING: $name is multi-word string. Using first word $newname only"
      name=$newname
    fi
    if echo "${names_arr[@]}" | grep -q -w -F "$name"; then
      echo "ERROR: duplicate section name $name found in additional installs."
      return 255
    else
      names_arr+=("$name")
    fi
  done
  for installation in "${installations[@]}"; do
    local name
    name=$(echo "$installation" | yq e '.name' -)
    local cnt
    cnt=$(wc -w <<< "$name")
    if [[ $cnt -gt 1 ]]; then
      name="${name%% *}"
    fi
    local desc
    desc=$(echo "$installation" | yq e '.description' -)
    local dl_url
    dl_url=$(echo "$installation" | yq e '.download_url' -)

    echo "Setting up $name install for guest"
    local fname
    fname=$(echo "$installation" | yq e '.filename' -)
    check_non_symlink "$fileserverdir/$fname"
    local fpath
    fpath=$(realpath "$fileserverdir/$fname")
    if [[ $? -ne 0 || ! -f "$fpath" || ! -s "$fpath" ]]; then
      echo "$fpath not present/zero sized. Attempt to download from $dl_url"
      if ! curl --connect-timeout 10 --output "$fileserverdir/$fname" "$dl_url"; then
        # attempt again with proxy enabled except for localhost
        echo "INFO: Download connection timed out. Attempting download with proxy for all (except localhost)."
        if ! curl --noproxy "localhost,127.0.0.1" --connect-timeout 10 --output "$fileserverdir/$fname" "$dl_url"; then
          # attempt again without proxy
          echo "INFO: Download connection timed out. Attempting download without proxy for all."
          if ! curl --noproxy '*' --connect-timeout 10 --output "$fileserverdir/$fname" "$dl_url"; then
            echo "WARNING: Unable to download $dl_url for $name installation."
            echo "WARNING: Check internet connection or $name additional installation configuration validity."
            if [[ $ADD_INSTALL_DL_FAIL_EXIT -eq 1 ]]; then
              return 255
            fi
            continue
          fi
        fi
      fi
      TMP_FILES+=("$fileserverdir/$fname")
    fi

    # Check installation file
    local iftype
    iftype=$(echo "$installation" | yq e '.install_type' -)
    local ifname
    ifname=$(echo "$installation" | yq e '.install_file' -)
    local itestsign
    itestsign=$(echo "$installation" | yq e '.enable_test_sign' -)
    case "$itestsign" in
      "yes" | "no")
        ;;

      -?*)
        ;&
      *)
        echo "enable_test_sign set to \"$itestsign\". Supported values: yes | no."
        return 255
        ;;
    esac

    case "$iftype" in
      "inf")
        ifname_lin=$(echo "$ifname" | sed -r -e 's|\\|/|g')
        if [[ "$(basename "$ifname_lin")" == "*.inf" ]]; then
          if [[ "$itestsign" == "yes" ]]; then
            echo "Only install_file=specified path_to\xxxx.inf install_file supported for test signing enabled."
            return 255
          fi
          iftype="[.]inf"
        fi
        ;;
      "msi" | "exe" | "cab")
        if [[ "$itestsign" == "yes" ]]; then
          echo "Only install_type=inf supported for test signing enabled."
          return 255
        fi
        ;;

      -?*)
        ;&
      *)
        echo "install_type=\"$iftype\". Supported values: inf|exe|msi|cab."
        return 255
        ;;
    esac

    local ftype
    ftype=$(file -r "$fpath")
    if echo "$ftype" | grep -q "Zip archive data"; then
      ftype="zip"
      ifname_lin=$(echo "$ifname" | sed -r -e 's|\\|/|g')
      ifname_win_esc=$(echo "$ifname" | sed -r -e 's|\\|\\\\|g')
      echo "$ifname_lin"
      if [[ "$iftype" == "[.]inf" ]]; then
        if ! unzip -l "$fpath" | grep -i -e "$iftype"; then
          echo "No $ifname found inside $fpath zip archive."
          return 255
        fi
      else
        if ! (unzip -l "$fpath" | grep -e "$ifname_win_esc" || unzip -l "$fpath" | grep -e "$ifname_lin"); then
          echo "No $ifname found inside $fpath zip archive."
          return 255
        fi
      fi
    elif echo "$ftype" | grep -q "PE32+ executable (GUI) x86-64"; then
      ftype="exe"
      if [[ "$iftype" != "exe" ]]; then
        echo "Only install_type=exe supported for executable file."
        return 255
      fi
    elif echo "$ftype" | grep -q "Microsoft Cabinet archive data"; then
      ftype="cab"
      ifname_lin=$(echo "$ifname" | sed -r -e 's|\\|/|g')
      ifname_win_esc=$(echo "$ifname" | sed -r -e 's|\\|\\\\|g')
      echo "$ifname_lin"
      if [[ "$iftype" == "msi" || "$iftype" == "exe" ]]; then
        echo "install_type=msi|exe not supported for Cabinet archive file."
        return 255
      fi
      if [[ "$iftype" == "[.]inf" || "$iftype" == "inf" ]]; then
        if [[ "$iftype" == "[.]inf" ]]; then
          if ! cabextract -l "$fpath" | grep -q -i -e "$iftype"; then
            echo "No $ifname found inside $fpath cabinet archive."
            return 255
          fi
        else
          if ! (cabextract -l "$fpath" | grep -e "$ifname_win_esc" || cabextract -l "$fpath" | grep -e "$ifname_lin"); then
            echo "No $ifname found inside $fpath cabinet archive."
            return 255
          fi
        fi
      fi
    else
      file -r "$fpath"
      echo "Unsupported filename=\"$fname\" not of supported file type: zip|cab|exe."
      if [[ $ADD_INSTALL_DL_FAIL_EXIT -eq 1 ]]; then
        return 255
      else
        continue
      fi
    fi

    if [[ -f "$fileserverdir/$name-install.ps1" ]]; then
      echo "Name entry in $cfgfile must be unique!"
      return 255
    fi
    tee "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$tempdir='C:\Temp'
Start-Transcript -Path "\$tempdir\\$name-installation.txt" -Force -Append
\$Host.UI.RawUI.WindowTitle = 'Setup for $name installation.'
\$s="Downloading $name installation file"
Write-Output "\$s"
\$p=curl.exe -fSLo "\$tempdir\\$fname" "$file_server_url/$fname"
if (\$LastExitCode -ne 0) {
    Write-Error "Error: \$s failed with exit code \$LastExitCode."
    Exit \$LASTEXITCODE
}
EOF

    local ifpath="\$tempdir"
    if [[ "$ftype" == "zip" ]]; then
      ifpath="\$tempdir\\$name-installation"
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$s="Expand $name zip archive file $fname"
Write-Output "\$s"
\$p=Expand-Archive -Path "\$tempdir\\$fname" -DestinationPath "$ifpath" -Force
if (\$? -ne \$True) {
    Throw "Error: \$s failed."
}
EOF
    fi
    if [[ "$ftype" == "cab" && "$iftype" != "cab" ]]; then
      ifpath="\$tempdir\\$name-installation"
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$s="Extract $name cabinet archive file $fname"
Write-Output "\$s"
 \$p=Start-Process cmd.exe -ArgumentList 'expand',"\`"\$tempdir\\$fname\`"",'-F:*',"\`"\$tempdir\\$name-installation\`"" -WorkingDirectory "\$tempdir\\$name-installation" -Wait -Verb RunAs -PassThru
if (\$p.ExitCode -ne 0) {
    Write-Error "Expand $name cabinet archive file $fname failure return \$(\$p.ExitCode)"
    Exit \$LASTEXITCODE
}
EOF
    fi

    local icatfname="${ifname:0:-3}cat"
    case "$itestsign" in
      "yes")
      SETUP_DISABLE_SECURE_BOOT=1
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
Write-Output 'Installing driver test sign certificate.'
\$signature=Get-AuthenticodeSignature "\$tempdir\\$name-installation\\$icatfname"
if (\$? -ne \$True) {
    Throw "Get $ifname driver signature failed"
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
    Throw "Add $ifname driver signing cert failed"
}
\$store.Close()
if (\$? -ne \$True) {
    Throw "Close cert store failed"
}
Write-Output "Enable test signing"
\$p=Start-Process bcdedit -ArgumentList "/set testsigning on" -Wait -Verb RunAs -PassThru
if (\$p.ExitCode -ne 0) {
    Write-Error "Enable test signing failure return \$(\$p.ExitCode)"
    Exit \$LASTEXITCODE
}
EOF
      ;;

      "no")
      ;;

      -?*)
        ;&
      *)
        echo 'Only "yes" | "no" accepted for enable_test_sign field.'
        return 255
        ;;
    esac

    if [[ "$iftype" == "inf" ]]; then
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$s="Installing $name $ifname"
Write-Output "\$s"
\$p=Start-Process pnputil.exe -ArgumentList '/add-driver',"\`"$ifpath\\$ifname\`"",'/install' -WorkingDirectory "$ifpath" -Wait -Verb RunAs -PassThru
if (\$p.ExitCode -ne 0) {
    Write-Error "pnputil install $name file $ifname failure return \$(\$p.ExitCode)"
    Exit \$LASTEXITCODE
}
EOF
    elif [[ "$iftype" == "[.]inf" ]]; then
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$s="Installing $name $ifname"
Write-Output "\$s"
\$p=Start-Process pnputil.exe -ArgumentList '/add-driver',"\`"$ifpath\\$ifname\`"",'/install','/subdirs' -WorkingDirectory "$ifpath" -Wait -Verb RunAs -PassThru
if (\$p.ExitCode -ne 0) {
    Write-Error "pnputil install $name file $ifname failure return \$(\$p.ExitCode)"
    Exit \$LASTEXITCODE
}
EOF
    elif [[ "$iftype" == "msi" ]]; then
      local ioption
      ioption=$(echo "$installation" | yq e '.silent_install_option' -)
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$s="Installing $name MSI $ifname"
Write-Output "\$s"
\$p=Start-Process msiexec.exe -ArgumentList '/i',"\`"$ifpath\\$ifname\`"","$ioption" -WorkingDirectory "$ifpath" -Wait -Verb RunAs -PassThru
if (\$p.ExitCode -ne 0) {
    Write-Error "msiexec install $name file $ifname failure return \$(\$p.ExitCode)"
    Exit \$LASTEXITCODE
}
EOF
    elif [[ "$iftype" == "exe" ]]; then
      local ioption
      ioption=$(echo "$installation" | yq e '.silent_install_option' -)
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$s="Installing $name exe $ifname"
Write-Output "\$s"
\$p=Start-Process "$ifpath\\$ifname" -ArgumentList "$ioption" -WorkingDirectory "$ifpath" -Wait -Verb RunAs -PassThru
if (\$p.ExitCode -ne 0) {
    Write-Error "Install $name exe file $ifname failure return \$(\$p.ExitCode)"
    Exit $LASTEXITCODE
}
EOF
    elif [[ "$iftype" == "cab" ]]; then
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
\$s="Installing $name cab $ifname"
Write-Output "\$s"
Add-WindowsPackage -Online -PackagePath:"$ifpath\\$ifname" -LogLevel 4 -ScratchDirectory "$ifpath"
if (\$? -ne \$True) {
    Throw "Error: \$s failed."
}
EOF
    fi
      tee -a "$fileserverdir/$name-install.ps1" &>/dev/null <<EOF
Exit \$LASTEXITCODE
EOF
    TMP_FILES+=("$fileserverdir/$name-install.ps1")

    # shellcheck disable=SC2016
    xmlstarlet ed -L \
      -s '/_:unattend/_:settings[@pass="auditUser"]/_:component/_:RunSynchronous' -t 'elem' -n 'RunSynchronousCommand' \
      --var cmd1 '$prev' \
      -s '/_:unattend/_:settings[@pass="auditUser"]/_:component/_:RunSynchronous' -t 'elem' -n 'RunSynchronousCommand' \
      --var cmd2 '$prev' \
      -i '$cmd1' -t 'attr' -n 'wcm:action' -v 'add' \
      -s '$cmd1' -t 'elem' -n 'Path' -v "%SystemRoot%\\system32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command curl.exe -fSLo 'C:\Temp\\$name-install.ps1' \"$file_server_url/$name-install.ps1\"" \
      -s '$cmd1' -t 'elem' -n 'Description' -v "Download $desc install script" \
      -s '$cmd1' -t 'elem' -n 'WillReboot' -v 'OnRequest' \
      -s '$cmd1' -t 'elem' -n 'Order' -v "$((step_id++))" \
      -i '$cmd2' -t 'attr' -n 'wcm:action' -v 'add' \
      -s '$cmd2' -t 'elem' -n 'Path' -v "%SystemRoot%\\system32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Temp\\$name-install.ps1\"" \
      -s '$cmd2' -t 'elem' -n 'Description' -v "Run $desc install script" \
      -s '$cmd2' -t 'elem' -n 'WillReboot' -v 'OnRequest' \
      -s '$cmd2' -t 'elem' -n 'Order' -v "$((step_id++))" \
    "$xmlfile"
  done

  if ! xmllint --noout "$xmlfile"; then
    echo "Error: XML file $xmlfile has formatting error after addition installs!"
    return 255
  fi
}

function install_windows() {
  local dest_tmp_path
  dest_tmp_path=$(realpath "/tmp/${WIN_DOMAIN_NAME}_install_tmp_files")
  local fileserverdir="$scriptpath/$WIN_UNATTEND_FOLDER"
  local file_server_url="http://$FILE_SERVER_IP:$FILE_SERVER_PORT"

  # install dependencies
  install_dep || return 255

  # check config files
  check_file_valid_nonzero "$scriptpath/$WIN_UNATTEND_FOLDER/autounattend.xml"
  if ! xmllint --noout "$scriptpath/$WIN_UNATTEND_FOLDER/autounattend.xml"; then
    echo "Error: XML file $scriptpath/$WIN_UNATTEND_FOLDER/autounattend.xml has formatting error!"
    return 255
  fi
  check_file_valid_nonzero "$scriptpath/$WIN_UNATTEND_FOLDER/unattend.xml"
  if ! xmllint --noout "$scriptpath/$WIN_UNATTEND_FOLDER/unattend.xml"; then
    echo "Error: XML file $scriptpath/$WIN_UNATTEND_FOLDER/unattend.xml has formatting error!"
    return 255
  fi
  if [[ -f "$scriptpath/$WIN_UNATTEND_FOLDER/additional_installs.yaml" ]]; then
    check_file_valid_nonzero "$scriptpath/$WIN_UNATTEND_FOLDER/additional_installs.yaml"
    if ! yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}}}" "$scriptpath/$WIN_UNATTEND_FOLDER/additional_installs.yaml"; then
      echo "Error: Yaml file $scriptpath/$WIN_UNATTEND_FOLDER/additional_installs.yaml has formatting error!"
      return 255
    fi
  fi

  if [[ $SETUP_NO_SRIOV -eq 0 ]]; then
    REQUIRED_FILES+=("ZCBuild_MSFT_Signed.zip|ZCBuild_MSFT_Signed_Installer.zip")
    REQUIRED_FILES+=("Driver-Release-64-bit.[zip|7z]")
    if [[ $(xrandr -d :0 | grep -c "\bconnected\b") -lt 1 ]]; then
        echo "Error: Need at least 1 display connected for SR-IOV install."
        return 255
    fi
  fi
  check_prerequisites || return 255

  if [[ -d "$dest_tmp_path" ]]; then
    rm -rf "$dest_tmp_path"
  fi
  mkdir -p "$dest_tmp_path"
  TMP_FILES+=("$dest_tmp_path")

  check_dir_valid "$fileserverdir"
  if [[ $SETUP_NO_SRIOV -eq 1 ]]; then
    echo "Exit 0" > "$fileserverdir/gfx_zc_setup.ps1"
  else
    tee "$fileserverdir/gfx_zc_setup.ps1" &>/dev/null <<EOF
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
\$s='Downloading Zero-copy installation archive'
Write-Output \$s
\$p=curl.exe -fSLo "\$tempdir\\$SETUP_ZC_FILENAME" "$file_server_url/$SETUP_ZC_FILENAME"
if (\$LastExitCode -ne 0) {
  Write-Error "Error: \$s failed with exit code \$LastExitCode."
  Exit \$LastExitCode
}
\$s='Unzip Graphics driver'
Write-Output \$s
\$p=Expand-Archive -Path "\$tempdir\Driver-Release-64-bit.zip" -DestinationPath "\$tempdir\GraphicsDriver" -Force
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
\$s='Create Zero-copy installation directory folder'
Write-Output \$s
\$p=New-Item -Force -Path "\$tempdir" -Name 'ZC_Install' -ItemType 'directory'
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
\$s='Unzip Zero-Copy installation archive'
Write-Output \$s
\$p=Expand-Archive -Path "\$tempdir\\$SETUP_ZC_FILENAME" -DestinationPath "\$tempdir\ZC_Install" -Force
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
EOF
    if [[ $SETUP_ZC_GUI_INSTALLER -eq 0 ]]; then
      tee -a "$fileserverdir/gfx_zc_setup.ps1" &>/dev/null <<EOF
\$s='Rename Zero-Copy driver folder'
Write-Output \$s
\$zcname=Get-ChildItem -Path "\$tempdir\ZC_Install"|Where-Object {\$_.PSIsContainer -eq \$True -and \$_.Name -match 'ZCBuild_[0-9]+_MSFT_Signed'}
if (\$? -ne \$True) {
  Throw "Error: No Zero-copy driver folder found at \$tempdir\ZC_Install."
}
\$p=Rename-Item -Path "\$tempdir\ZC_Install\\\$zcname" -NewName 'ZCBuild_MSFT_Signed' -Force
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
EOF
    else
      tee -a "$fileserverdir/gfx_zc_setup.ps1" &>/dev/null <<EOF
\$s='Rename Zero-Copy installer folder'
Write-Output \$s
\$zcname=Get-ChildItem -Path "\$tempdir\ZC_Install"|Where-Object {\$_.PSIsContainer -eq \$True -and \$_.Name -match 'ZCBuild_[0-9]+_MSFT_Signed_Installer'}
if (\$? -ne \$True) {
  Throw "Error: No Zero-copy driver folder found at \$tempdir\ZC_Install."
}
\$p=Rename-Item -Path "\$tempdir\ZC_Install\\\$zcname" -NewName 'ZCBuild_MSFT_Signed_Installer' -Force
if (\$? -ne \$True) {
  Throw "Error: \$s failed."
}
EOF
    fi
    tee -a "$fileserverdir/gfx_zc_setup.ps1" &>/dev/null <<EOF
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

    convert_drv_pkg_7z_to_zip || return 255

    if [[ $SETUP_NON_WHQL_GFX_DRV -eq 1 ]]; then
      tee "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
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
            Write-Error "pnputil install Graphics Driver iigd_dch.inf failure return \$(\$p.ExitCode)"
            Exit \$p.ExitCode
        }

        Write-Output "Enable test signing"
        \$p=Start-Process bcdedit -ArgumentList "/set testsigning on" -Wait -Verb RunAs -PassThru
        if (\$p.ExitCode -ne 0) {
            Write-Error "Enable test signing failure return \$(\$p.ExitCode)"
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
EOF

      if [[ $SETUP_ZC_GUI_INSTALLER -eq 0 ]]; then
        tee -a "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
        \$Host.UI.RawUI.WindowTitle = "Running Intel Zero-copy driver install"
        Set-Location -Path "\$tempdir\ZC_Install\ZCBuild_MSFT_Signed"
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
EOF
      else
        tee -a "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
        \$Host.UI.RawUI.WindowTitle = "Running Intel Zero-copy GUI installer"
        Set-Location -Path "\$tempdir\ZC_Install\ZCBuild_MSFT_Signed_Installer\ZC_Installer"
        Write-Output "Found Intel GPU. Running Intel Zero-copy GUI installer"
        \$EAPBackup = \$ErrorActionPreference
        \$ErrorActionPreference = 'Stop'
        \$p=Start-Process ZeroCopyInstaller.exe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES' -WorkingDirectory "\$tempdir\ZC_Install\ZCBuild_MSFT_Signed_Installer\ZC_Installer" -Wait -Verb RunAs -PassThru
        if (\$p.ExitCode -ne 0) {
          Write-Output "Zero-copy installer threw error. Check \$tempdir\RunDVInstallerLogs.txt"
          Exit \$p.ExitCode
        }
        \$ErrorActionPreference = \$EAPBackup
        # check for installed driver and reboot in case zero-copy install did not reboot
        if (Get-ScheduledTask -TaskName "DVEnabler" -TaskPath "\Microsoft\Windows\DVEnabler\") {
            Write-Output "Force computer restart after Zero-copy driver install"
            Restart-Computer -Force
        }
        Exit \$LastExitCode
EOF
      fi
      tee -a "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
    }
}
EOF
    else
      tee "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
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
EOF
      if [[ $SETUP_ZC_GUI_INSTALLER -eq 0 ]]; then
        tee -a "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
        \$Host.UI.RawUI.WindowTitle = "Running Intel Zero-copy driver install"
        Set-Location -Path "\$tempdir\ZC_Install\ZCBuild_MSFT_Signed"
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
EOF
      else
        tee -a "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
        \$Host.UI.RawUI.WindowTitle = "Running Intel Zero-copy GUI installer"
        Set-Location -Path "\$tempdir\ZC_Install\ZCBuild_MSFT_Signed_Installer\ZC_Installer"
        Write-Output "Found Intel GPU. Running Intel Zero-copy GUI installer"
        \$EAPBackup = \$ErrorActionPreference
        \$ErrorActionPreference = 'Stop'
        \$p=Start-Process ZeroCopyInstaller.exe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES' -WorkingDirectory "\$tempdir\ZC_Install\ZCBuild_MSFT_Signed_Installer\ZC_Installer" -Wait -Verb RunAs -PassThru
        if (\$p.ExitCode -ne 0) {
          Write-Output "Zero-copy installer threw error. Check \$tempdir\RunDVInstallerLogs.txt"
          Exit \$p.ExitCode
        }
        \$ErrorActionPreference = \$EAPBackup
        # check for installed driver and reboot in case zero-copy install did not reboot
        if (Get-ScheduledTask -TaskName "DVEnabler" -TaskPath "\Microsoft\Windows\DVEnabler\") {
            Write-Output "Force computer restart after Zero-copy driver install"
            Restart-Computer -Force
        }
        Exit \$LastExitCode
EOF
      fi
      tee -a "$fileserverdir/zc_install.ps1" &>/dev/null <<EOF
    }
}
EOF
    fi
    TMP_FILES+=("$(realpath "$fileserverdir/zc_install.ps1")")
  fi
  TMP_FILES+=("$(realpath "$fileserverdir/gfx_zc_setup.ps1")")

  cp "$scriptpath/$WIN_UNATTEND_FOLDER/autounattend.xml" "$dest_tmp_path/"
  sed -i "s|%FILE_SERVER_URL%|$file_server_url|g" "$dest_tmp_path/autounattend.xml"

  # setup additional Windows guest installations
  if [[ -f "$scriptpath/$WIN_UNATTEND_FOLDER/additional_installs.yaml" ]]; then
    setup_additional_installs "$scriptpath/$WIN_UNATTEND_FOLDER/additional_installs.yaml" \
      "$fileserverdir" "$file_server_url" "$dest_tmp_path/autounattend.xml" || return 255
  fi

  if [[ -f "$scriptpath/$WIN_UNATTEND_FOLDER/${WIN_VIRTIO_ISO}" ]]; then
    check_file_valid_nonzero "$scriptpath/$WIN_UNATTEND_FOLDER/${WIN_VIRTIO_ISO}"
    cp "$scriptpath/$WIN_UNATTEND_FOLDER/${WIN_VIRTIO_ISO}" "/tmp/${WIN_VIRTIO_ISO}"
  fi
  if [[ ! -f "/tmp/${WIN_VIRTIO_ISO}" ]]; then
    echo "Download virtio-win iso"
    local is_200_okay
    is_200_okay=$(wget --server-response --content-on-error=off -O /tmp/${WIN_VIRTIO_ISO} ${WIN_VIRTIO_URL} 2>&1 | grep -c '200 OK')
    TMP_FILES+=("/tmp/${WIN_VIRTIO_ISO}")
    if [[ "$is_200_okay" -ne 1 || ! -f /tmp/${WIN_VIRTIO_ISO} ]]; then
        echo "Error: wget ${WIN_VIRTIO_URL} failure!"
        return 255
    fi
  else
    check_file_valid_nonzero "/tmp/${WIN_VIRTIO_ISO}"
  fi

  if [[ ! -f "$fileserverdir/${WIN_OPENSSH_MSI}" ]]; then
    echo "Download Powershell OpenSSH msi release."
    local is_200_okay
    is_200_okay=$(wget --server-response --content-on-error=off -O "$fileserverdir/${WIN_OPENSSH_MSI}" "${WIN_OPENSSH_MSI_URL}" 2>&1 | grep -c '200 OK')
    TMP_FILES+=("$fileserverdir/${WIN_OPENSSH_MSI}")
    if [[ "$is_200_okay" -ne 1 || ! -f "$fileserverdir/${WIN_OPENSSH_MSI}" ]]; then
        echo "Error: download ${WIN_OPENSSH_MSI} failure!"
        if [[ ADD_INSTALL_DL_FAIL_EXIT -eq 1 ]]; then
          return 255
        fi
    fi
  else
    if [[ ADD_INSTALL_DL_FAIL_EXIT -eq 1 ]]; then
      check_file_valid_nonzero "$fileserverdir/${WIN_OPENSSH_MSI}"
    else
      check_non_symlink "$fileserverdir/${WIN_OPENSSH_MSI}"
    fi
  fi

  if [[ -f "$fileserverdir/${WIN_OPENSSH_MSI}" ]]; then
    local win_openssh_ftype
    win_openssh_ftype=$(file -r "$fileserverdir/${WIN_OPENSSH_MSI}")
    if echo "$win_openssh_ftype" | grep -q "MSI Installer"; then
      local win_openssh_fname
      win_openssh_fname="${WIN_OPENSSH_MSI%.*}"
      tee "$fileserverdir/${win_openssh_fname}_setup.ps1" &>/dev/null <<EOF
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path",[System.EnvironmentVariableTarget]::Machine) + ';' + \${Env:ProgramFiles} + '\OpenSSH', [System.EnvironmentVariableTarget]::Machine)
EOF
      TMP_FILES+=("$(realpath "$fileserverdir/${win_openssh_fname}_setup.ps1")")
    else
      echo "WARNING: \"$fileserverdir/${WIN_OPENSSH_MSI}\" not of expected MSI installer file type"
      if [[ ADD_INSTALL_DL_FAIL_EXIT -eq 1 ]]; then
        return 255
      fi
    fi
  fi

  mkisofs -o "/tmp/${WIN_UNATTEND_ISO}" -J -r "$dest_tmp_path" || return 255
  TMP_FILES+=("/tmp/${WIN_UNATTEND_ISO}")

  echo "$(date): Start windows guest creation and auto-installation"
  run_file_server "$fileserverdir" "$FILE_SERVER_IP" "$FILE_SERVER_PORT" FILE_SERVER_DAEMON_PID || return 255
  if [[ "$VIEWER" -eq "1" ]]; then
    virt-viewer -w -r --domain-name "${WIN_DOMAIN_NAME}" &
    VIEWER_DAEMON_PID=$!
  fi
  local ovmf_option="$OVMF_DEFAULT_PATH/OVMF_VARS_4M.ms.fd"
  if [[ $SETUP_DISABLE_SECURE_BOOT -eq 1 ]]; then
    ovmf_option="$OVMF_DEFAULT_PATH/OVMF_VARS_4M.fd"
  fi
  virt-install \
  --name="${WIN_DOMAIN_NAME}" \
  --ram=4096 \
  --vcpus=4 \
  --cpu host \
  --machine q35 \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5902 \
  --cdrom "$scriptpath/$WIN_UNATTEND_FOLDER/${WIN_INSTALLER_ISO}" \
  --disk "/tmp/${WIN_VIRTIO_ISO}",device=cdrom \
  --disk "/tmp/${WIN_UNATTEND_ISO}",device=cdrom \
  --disk path="${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME}",format=qcow2,size=${SETUP_DISK_SIZE},bus=virtio,cache=none \
  --os-variant win10 \
  --boot loader="$OVMF_DEFAULT_PATH/OVMF_CODE_4M.ms.fd",loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template=$ovmf_option \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --pm suspend_to_mem.enabled=off,suspend_to_disk.enabled=on \
  --features smm.state=on \
  --noautoconsole \
  --wait=-1 || return 255

  echo "$(date): Waiting for restarted Windows guest to complete installation and shutdown"
  local state
  state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
  local loop=1
  while [[ -n "${state+x}" && $state == "running" ]]; do
    local count=0
    local maxcount=120
    while [[ count -lt $maxcount ]]; do
      state=$(virsh list --all | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
      if [[ -n "${state+x}" && $state == "running" ]]; then
        echo "$(date): $count: waiting for running VM..."
        sleep 60
      else
        break
      fi
      count=$((count+1))
    done
    if [[ $count -ge $maxcount ]]; then
      echo "$(date): Error: timed out waiting for Windows required installation to finish after $maxcount min."
      return 255
    fi
    loop=$((loop+1))
  done

  if [[ $SETUP_NO_SRIOV -eq 0 ]]; then
    # Start Windows VM with SRIOV to allow SRIOV Zero-Copy + graphics driver install
    echo "$(date): Proceeding with Zero-copy driver installation..."
    local platpath="$scriptpath/../../platform/$PLATFORM_NAME"
    if [ -d "$platpath" ]; then
      platpath=$(realpath "$platpath")
      echo "$(date): Restarting windows VM with SRIOV for Zero-Copy driver installation on local display."
      #sudo pkill virt-viewer
      kill_by_pid $VIEWER_DAEMON_PID

      if "$platpath/launch_multios.sh" -f -d windows -g sriov windows || return 255; then
        local count=0
        local maxcount=90
        while [[ count -lt $maxcount ]]; do
          echo "$(date): $count: waiting for installation to complete and shutdown VM..."
          local state
          state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
          if [[ -n "${state+x}" && $state == "running" ]]; then
            #timeout 600 watch -g -n 2 'virsh domstate windows'
            sleep 60
          else
            break
          fi
          count=$((count+1))
          if [[ $count -ge $maxcount ]]; then
            echo "$(date): Error: timed out waiting for SRIOV Zero-copy driver install to complete"
            return 255
          fi
        done
      else
        echo "$(date): Start Windows domain with SRIOV failed"
        return 255
      fi
    fi
  fi
}

function get_supported_platform_names() {
    local -n arr=$1
    local -a platpaths
    mapfile -t platpaths < <(find "$scriptpath/../../platform/" -maxdepth 1 -mindepth 1 -type d)
    for p in "${platpaths[@]}"; do
        arr+=( "$(basename "$p")" )
    done
}

function set_platform_name() {
    local -a platforms=()
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
    return 255
}

function show_help() {
    local -a platforms=()
	declare -a required_files_help
	local required_files_help=( "${REQUIRED_FILES[@]}" )

    required_files_help+=("ZCBuild_MSFT_Signed.zip|ZCBuild_MSFT_Signed_Installer.zip")
    required_files_help+=("Driver-Release-64-bit.[zip|7z]") 
    printf "%s [-h] [-p] [--disk-size] [--no-sriov] [--non-whql-gfx] [--force] [--viewer] [--debug] [--dl-fail-exit]\n" "$(basename "${BASH_SOURCE[0]}")"
    printf "Create Windows vm required images and data to dest folder %s.qcow2\n" "$LIBVIRT_DEFAULT_IMAGES_PATH/${WIN_DOMAIN_NAME}"
    printf "Place required Windows installation files as listed below in guest_setup/ubuntu/%s folder prior to running.\n" "$WIN_UNATTEND_FOLDER"
    printf "("
    for i in "${!required_files_help[@]}"; do
	  printf "%s" "${required_files_help[$i]}"
      if [[ $((i + 1)) -lt ${#required_files_help[@]} ]]; then
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
    printf "\t                    %s\n" "$(basename "$p")"
    done
    printf "\t--disk-size       disk storage size of windows vm in GiB, default is 60 GiB\n"
    printf "\t--no-sriov        Non-SR-IOV windows install. No GFX/SRIOV support to be installed\n"
    printf "\t--non-whql-gfx    GFX driver to be installed is non-WHQL signed but test signed\n"
    printf "\t--force           force clean if windows vm qcow is already present\n"
    printf "\t--viewer          show installation display\n"
    printf "\t--debug           Do not remove temporary files. For debugging only.\n"
    printf "\t--dl-fail-exit    Do not continue on any additional installation file download failure.\n"
}

function parse_arg() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit 0
                ;;

            -p)
                set_platform_name "$2" || return 255
                shift
                ;;

            --disk-size)
                SETUP_DISK_SIZE="$2"
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

            --dl-fail-exit)
                ADD_INSTALL_DL_FAIL_EXIT=1
                ;;

            -?*)
                echo "Error: Invalid option $1"
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
}

function cleanup () {
    local state
    state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
    if [[ -n ${state+x} && "$state" == "running" ]]; then
        echo "Shutting down running domain $WIN_DOMAIN_NAME"
        virsh shutdown "$WIN_DOMAIN_NAME"
        echo "Waiting for domain $WIN_DOMAIN_NAME to shut down..."
        sleep 30
        state=$(virsh list | awk -v a="$WIN_DOMAIN_NAME" '{ if ( NR > 2 && $2 == a ) { print $3 } }')
        if [[ -n ${state+x} && "$state" == "running" ]]; then
            virsh destroy "$WIN_DOMAIN_NAME"
        fi
        virsh undefine --nvram "$WIN_DOMAIN_NAME"
    fi
    if virsh list --name --all | grep -q -w $WIN_DOMAIN_NAME; then
        virsh undefine --nvram "$WIN_DOMAIN_NAME"
    fi
    local poolname
    poolname=$(basename '/tmp')
    if virsh pool-list | grep -q "$poolname"; then
        virsh pool-destroy "$poolname"
        if virsh pool-list --all | grep -q "$poolname"; then
            virsh pool-undefine "$poolname"
        fi
    fi
    poolname=$(basename "$WIN_UNATTEND_FOLDER")
    if virsh pool-list | grep -q "$poolname"; then
        virsh pool-destroy "$poolname"
        if virsh pool-list --all | grep -q "$poolname"; then
            virsh pool-undefine "$poolname"
        fi
    fi
    for f in "${TMP_FILES[@]}"; do
      if [[ $SETUP_DEBUG -ne 1 ]]; then
        local fowner
        fowner=$(stat -c "%U" "$f")
        if [[ "$fowner" == "$USER" ]]; then
            rm -rf "$f"
        else
            sudo rm -rf "$f"
        fi
      fi
    done
    kill_by_pid "$FILE_SERVER_DAEMON_PID"
    kill_by_pid "$VIEWER_DAEMON_PID"
}

#-------------    main processes    -------------
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

parse_arg "$@" || exit 255

if [[ $FORCECLEAN == "1" ]]; then
    clean_windows_images || exit 255
fi

if [[ -z "${PLATFORM_NAME+x}" || -z "$PLATFORM_NAME" ]]; then
	echo "Error: valid platform name required"
    show_help
    exit 255
fi

if ! [[ $SETUP_DISK_SIZE =~ ^[0-9]+$ ]]; then
    echo "Invalid input disk size"
    exit 255
fi

if [[ -f "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME}" ]]; then
    echo "${LIBVIRT_DEFAULT_IMAGES_PATH}/${WIN_IMAGE_NAME} present"
    echo "Use --force option to force clean and re-install windows"
    exit 255
fi

trap 'cleanup' EXIT

install_windows || exit 255

echo "$(basename "${BASH_SOURCE[0]}") done"

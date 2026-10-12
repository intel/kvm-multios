#!/bin/bash

# Copyright (c) 2023-2026 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error $(realpath ${BASH_SOURCE[0]}) line ${LINENO}: $BASH_COMMAND"' ERR

#---------      Global variable     -------------------

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

#-------------    main processes    -------------
# Update /etc/libvirt/qemu.conf

# Newer libvirt splits libvirtd into modular daemons; qemu.conf belongs to
# whichever one is actually running.
function restart_libvirt_daemon() {
  local unit

  for unit in virtqemud libvirtd; do
    if systemctl is-active --quiet "$unit.service"; then
      sudo systemctl restart "$unit.service"
      return 0
    fi
  done

  for unit in virtqemud libvirtd; do
    if systemctl cat "$unit.service" &>/dev/null; then
      sudo systemctl restart "$unit.service"
      return 0
    fi
  done

  echo "Error: no libvirt daemon (virtqemud or libvirtd) found to restart."
  return 255
}

UPDATE_FILE="/etc/libvirt/qemu.conf"
check_file_valid_nonzero "$UPDATE_FILE"

# Ubuntu 26.04 no longer ships every setting as a commented template, so append
# the option when neither an active nor a commented entry can be rewritten.
function set_qemu_conf_option() {
  local key=$1
  local line=$2

  if sudo grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$UPDATE_FILE"; then
    sudo sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${line}|" "$UPDATE_FILE"
  else
    echo "$line" | sudo tee -a "$UPDATE_FILE" > /dev/null
  fi
}

set_qemu_conf_option "security_default_confined" "security_default_confined = 0"
set_qemu_conf_option "user" 'user = "root"'
set_qemu_conf_option "group" 'group = "root"'

if ! sudo grep -qE "^[[:space:]]*cgroup_device_acl[[:space:]]*=" "$UPDATE_FILE"; then
  sudo tee -a "$UPDATE_FILE" > /dev/null <<'EOF'
cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm", "/dev/udmabuf", "/dev/dri/card0", "/dev/dri/renderD128"]
EOF
fi

# Apply qemu.conf now; the restart further below is skipped if any step in
# between fails, which silently leaves guests running as the wrong user.
restart_libvirt_daemon || exit 255

# Update /etc/sysctl.conf
# Ensure br_netfilter is loaded so the sysctl exists.
# Ubuntu 26 can leave /etc/sysctl.conf missing or empty, so create a minimal
# placeholder before relying on the file for net.bridge settings.
sudo modprobe br_netfilter

UPDATE_FILE="/etc/sysctl.conf"
if [[ ! -f "$UPDATE_FILE" || ! -s "$UPDATE_FILE" ]]; then
  echo "# Managed by virtualization.multios.kvm.platform" | sudo tee "$UPDATE_FILE" > /dev/null
fi
UPDATE_LINE="net.bridge.bridge-nf-call-iptables=0"
if [[ "$UPDATE_LINE" != $(grep -F "$UPDATE_LINE" "$UPDATE_FILE") ]]; then
  echo $UPDATE_LINE | sudo tee -a "$UPDATE_FILE"
  sudo sysctl "$UPDATE_LINE"
fi

UPDATE_LINE="net.ipv4.conf.all.route_localnet=1"
if [[ "$UPDATE_LINE" != $(grep -F "$UPDATE_LINE" "$UPDATE_FILE") ]]; then
  echo "$UPDATE_LINE" | sudo tee -a "$UPDATE_FILE"
  sudo sysctl "$UPDATE_LINE"
fi

# a hook-helper for libvirt which allows easier per-VM hooks.
# usually /etc/libvirt/libvirt/hooks/qemu.d/vm_name/hook_name/state_name/
# See: https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/
# Retry GitHub raw content without the proxy if the proxy returns an error.
qemu_hook_fallback=0
wget --no-check-certificate --timeout=10 --tries=1 'https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/4f6d505f7ef032b552c9a544f95e8586d954fe26/libvirt_hooks/qemu' -O qemu \
  || { qemu_hook_fallback=1; cat > qemu <<'EOF'
#!/bin/bash
GUEST_NAME="$1"
HOOK_NAME="$2"
STATE_NAME="$3"
MISC="${@:4}"
EOF
  }

# Configure iGPU SRIOV VF in qemu hook
tee -a qemu &>/dev/null <<EOF

VM_XML=\$(cat -)

function setup_sriov_guc() {
  local drm_drv="\$1"
  local base_path="\$2"
  local numvfs="\$3"

  # Set PF resource values
  gtt_spare_pf=\$((500 * 1024 * 1024)) # MB
  contex_spare_pf=9216
  doorbell_spare_pf=32

  # Apply PF resource configuration
  if [[ "\$drm_drv" == "xe" ]]; then
    echo \$gtt_spare_pf | tee \$base_path/gt0/pf/ggtt_spare
    echo \$contex_spare_pf | tee \$base_path/gt0/pf/contexts_spare
    echo \$doorbell_spare_pf | tee \$base_path/gt0/pf/doorbells_spare
  fi

  # Set VF resource values
  gtt_spare_vf_manual=\$((3 * 1024 * 1024 * 1024)) # 3GB
  context_spare_vf_manual=51200
  if [[ "\$drm_drv" == "xe" ]]; then
    doorbell_spare_vf_manual=224  # xe specific value
  fi

  # Calculate values per VF
  gtt_spare_vf=\$((gtt_spare_vf_manual / numvfs))
  context_spare_vf=\$((context_spare_vf_manual / numvfs))
  doorbell_spare_vf=\$((doorbell_spare_vf_manual / numvfs))

  # Apply VF resource configuration
  for (( i = 1; i <= numvfs; i++ )); do
    if [[ "\$drm_drv" == "xe" ]]; then
      # Configure gt0 for xe
      echo \$gtt_spare_vf | tee \$base_path/gt0/vf\$i/ggtt_quota
      echo \$context_spare_vf | tee \$base_path/gt0/vf\$i/contexts_quota
      echo \$doorbell_spare_vf | tee \$base_path/gt0/vf\$i/doorbells_quota

      # Configure gt1 if it exists (xe doesn't set GTT for gt1)
      if [[ -d "\$base_path/gt1/vf\$i" ]]; then
        echo \$context_spare_vf | tee \$base_path/gt1/vf\$i/contexts_quota
        echo \$doorbell_spare_vf | tee \$base_path/gt1/vf\$i/doorbells_quota
      fi
    fi
  done
}

function setup_sriov_provisioning() {
  local drm_drv="\$1"
  local base_path="\$2"
  local numvfs="\$3"
  local vendor="\$4"
  local device="\$5"

  modprobe i2c-algo-bit
  modprobe video

  # Set auto_provisioning for i915 driver only
  if [[ "\$drm_drv" == "i915" ]]; then
    if [[ -f "\$base_path/pf/auto_provisioning" ]]; then
      echo '1' | tee -a \$base_path/pf/auto_provisioning
    fi
  fi

  echo '0' | tee '/sys/bus/pci/devices/0000:00:02.0/sriov_drivers_autoprobe'
  echo "\$numvfs" | tee -a /sys/class/drm/card0/device/sriov_numvfs
  echo '1' | tee '/sys/bus/pci/devices/0000:00:02.0/sriov_drivers_autoprobe'
  modprobe vfio-pci || :
    if modprobe -n i915-vfio-pci &>/dev/null && \
        lscpu | awk -F: '/Vendor ID:/ {if (\$2 ~ /GenuineIntel/) exit 0; else exit 1;}' && \
        lscpu | awk -F: '/Model:/ {if (\$2 ~ /197|198/) exit 0; else exit 1;}'; then
    modprobe i915-vfio-pci || :
    echo "\$vendor \$device" | tee /sys/bus/pci/drivers/i915-vfio-pci/new_id
  else
    echo "\$vendor \$device" | tee /sys/bus/pci/drivers/vfio-pci/new_id
  fi
}

function setup_sriov_scheduling() {
  local drm_drv="\$1"
  local base_path="\$2"
  local numvfs="\$3"

  pfexecquanta=25
  pfpreemtimeout=0

  vfschedexecq=25
  vfschedtimeout=500000

  if [[ "\$drm_drv" == "xe" ]]; then
    echo "\$pfexecquanta" | tee \$base_path/gt0/pf/exec_quantum_ms
    echo "\$pfpreemtimeout" | tee \$base_path/gt0/pf/preempt_timeout_us
    if [[ -d "\$base_path/gt1" ]]; then
      echo "\$pfexecquanta" | tee \$base_path/gt1/pf/exec_quantum_ms
      echo "\$pfpreemtimeout" | tee \$base_path/gt1/pf/preempt_timeout_us
    fi

    for (( i = 1; i <= numvfs; i++ )); do
      echo "\$vfschedexecq" | tee \$base_path/gt0/vf\$i/exec_quantum_ms
      echo "\$vfschedtimeout" | tee \$base_path/gt0/vf\$i/preempt_timeout_us
      if [[ -d "\$base_path/gt1" ]]; then
        echo "\$vfschedexecq" | tee \$base_path/gt1/vf\$i/exec_quantum_ms
        echo "\$vfschedtimeout" | tee \$base_path/gt1/vf\$i/preempt_timeout_us
      fi
    done
  else
    for (( i = 1; i <= numvfs; i++ )); do
      if [[ -d "\$base_path/vf\$i/gt0" ]]; then
        echo "\$vfschedexecq" | tee "\$base_path/vf\$i/gt0/exec_quantum_ms"
        echo "\$vfschedtimeout" | tee "\$base_path/vf\$i/gt0/preempt_timeout_us"
      fi
      if [[ -d "\$base_path/vf\$i/gt1" ]]; then
        echo "\$vfschedexecq" | tee "\$base_path/vf\$i/gt1/exec_quantum_ms"
        echo "\$vfschedtimeout" | tee "\$base_path/vf\$i/gt1/preempt_timeout_us"
      fi
    done
  fi
}

# Setup iGPU SRIOV VF
if [[ "\${2}" == "prepare" ]]; then
  sriov_vf_hex=\$(xmllint --xpath "string(//domain/devices/hostdev/source/address[@domain='0x0000' and @bus='0x00' and @slot='0x02']/@function)" - <<<"\$VM_XML" )
  sriov_vf_num=\$((sriov_vf_hex))
  if [[ \$sriov_vf_num -gt 0 ]]; then
    sriov_vfs=\$(cat /sys/class/drm/card0/device/sriov_numvfs)
    if [[ \$sriov_vfs -eq 0 ]]; then
      totalvfs=\$(cat /sys/class/drm/card0/device/sriov_totalvfs)
      vendor=\$(cat /sys/bus/pci/devices/0000:00:02.0/vendor)
      device=\$(cat /sys/bus/pci/devices/0000:00:02.0/device)

      # Detect driver type and set consolidated paths
      drm_drv=\$(lspci -D -k  -s 00:02.0 | grep "Kernel driver in use" | awk -F ':' '{print \$2}' | xargs)
      if [[ "\$drm_drv" == "xe" ]]; then
        # Verify xe debug path exists
        if [[ ! -d "/sys/kernel/debug/dri/0000:00:02.0" ]]; then
          echo "Error: xe driver detected but debug path not available" >&2
          exit 1
        fi
        base_path="/sys/kernel/debug/dri/0000:00:02.0"
      elif [[ "\$drm_drv" == "i915" ]]; then
        # For i915 driver, check for prelim_iov or iov paths
        if [[ -d "/sys/devices/pci0000:00/0000:00:02.0/drm/card0/prelim_iov" ]]; then
          base_path="/sys/devices/pci0000:00/0000:00:02.0/drm/card0/prelim_iov"
        elif [[ -d "/sys/class/drm/card0/iov" ]]; then
          base_path="/sys/class/drm/card0/iov"
        else
          echo "Error: Neither prelim_iov nor iov path available for i915 driver" >&2
          exit 1
        fi
      else
        echo "Error: Unsupported graphics driver: \$drm_drv" >&2
        exit 1
      fi

      # setup sriov guc
      setup_sriov_guc "\$drm_drv" "\$base_path" "\$totalvfs"

      # setup sriov provisioning
      setup_sriov_provisioning "\$drm_drv" "\$base_path" "\$totalvfs" "\$vendor" "\$device"

      # setup sriov scheduling
      setup_sriov_scheduling "\$drm_drv" "\$base_path" "\$totalvfs"
    fi
  fi
fi
EOF

# Allocate hugepage on demand in qemu hook
tee -a qemu &>/dev/null <<EOF

# Allocate hugepage on demand
if [[ "\${2}" == "prepare" ]]; then
  memory_size=\$(xmllint --xpath "string(//domain/memory)" - <<<"\$VM_XML")
  hugepage_size=\$(xmllint --xpath "string(//domain/memoryBacking/hugepages/page/@size)" - <<<"\$VM_XML")
  if [[ "\$hugepage_size" == "2048" ]]; then
    required_hugepage_nr=\$((memory_size/2048))
    free_hugepages=\$(</sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages)
    if [[ \$required_hugepage_nr -gt \$free_hugepages ]]; then
        current_hugepages=\$(</sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
        new_hugepages=\$((required_hugepage_nr - free_hugepages + current_hugepages))
        echo \$new_hugepages | tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages > /dev/null
        # Check and wait for hugepages to be allocated
        read_hugepages=0
        count=0
        compact_memory="false"
        while [[ \$read_hugepages -ne \$new_hugepages ]]
        do
          if [[ \$((count++)) -ge 20 ]]; then
            echo "Insufficient memory to allocate hugepages, current=\$read_hugepages required=\$new_hugepages" | systemd-cat -t libvirtd -p warning
            compact_memory="true"
            break
          fi
          sleep 0.5
          read_hugepages=\$(</sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
        done
        if [[ "\$compact_memory" == "true" ]]; then
          echo "Compact memory before re-try hugepages allocation" | systemd-cat -t libvirtd -p warning
          echo 1 > /proc/sys/vm/compact_memory
          sleep 5
          echo \$new_hugepages | tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages > /dev/null
          # Check and wait for hugepages to be allocated
          read_hugepages=0
          count=0
          while [[ \$read_hugepages -ne \$new_hugepages ]]; do
            if [[ \$((count++)) -ge 20 ]]; then
                echo "Insufficient memory to allocate \$required_hugepage_nr hugepages" >&2
                exit 1
            fi
            sleep 0.5
            read_hugepages=\$(</sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
          done
        fi
     fi
  fi
fi

# Release hugepage on demand
if [[ "\${2}" == "release" ]]; then
  memory_size=\$(xmllint --xpath "string(//domain/memory)" - <<<"\$VM_XML")
  hugepage_size=\$(xmllint --xpath "string(//domain/memoryBacking/hugepages/page/@size)" - <<<"\$VM_XML")
  if [[ "\$hugepage_size" == "2048" ]]; then
    release_hugepage_nr=\$((memory_size/2048))
    current_hugepages=\$(</sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
    if [[ \$release_hugepage_nr -gt \$current_hugepages ]]; then
      new_hugepages=0
    else
      new_hugepages=\$((current_hugepages - release_hugepage_nr))
    fi
    echo \$new_hugepages | tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages > /dev/null
  fi
fi
EOF

# Configure port forwarding from host to VMs in qemu hook
tee -a qemu &>/dev/null <<EOF

# Configure port forwarding from host to VMs
if [[ "\${1}" == "ubuntu" ]]; then
 
  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.11
  GUEST_PORT=22
  HOST_PORT=1111
 
  if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j MASQUERADE
  fi
  if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j MASQUERADE
  fi

elif [[ "\${1}" == "ubuntu_rt" ]]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.44
  GUEST_PORT=22
  HOST_PORT=4444

  if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j MASQUERADE
  fi
  if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport "\$HOST_PORT" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j MASQUERADE
  fi

elif [[ "\${1}" == "windows11" ]]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.55
  declare -A HOST_PORTS
  HOST_PORTS=([22]=5555 [3389]=3389)

  for GUEST_PORT in "\${!HOST_PORTS[@]}"; do
    if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
      /sbin/iptables -D FORWARD -o virbr0 -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j ACCEPT
      /sbin/iptables -t nat -D PREROUTING -p tcp --dport "\${HOST_PORTS[\$GUEST_PORT]}" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
      /sbin/iptables -t nat -D OUTPUT -p tcp --dport "\${HOST_PORTS[\$GUEST_PORT]}" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
      /sbin/iptables -t nat -D POSTROUTING -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j MASQUERADE
    fi
    if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
      /sbin/iptables -I FORWARD -o virbr0 -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j ACCEPT
      /sbin/iptables -t nat -I PREROUTING -p tcp --dport "\${HOST_PORTS[\$GUEST_PORT]}" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
      /sbin/iptables -t nat -I OUTPUT -p tcp --dport "\${HOST_PORTS[\$GUEST_PORT]}" -j DNAT --to "\$GUEST_IP:\$GUEST_PORT"
      /sbin/iptables -t nat -I POSTROUTING -p tcp -d "\$GUEST_IP" --dport "\$GUEST_PORT" -j MASQUERADE
    fi
  done

fi
EOF

if [[ "$qemu_hook_fallback" -eq 1 ]]; then
cat >> qemu <<'EOF'
HOOKPATH="$(dirname "$0")/qemu.d/$GUEST_NAME/$HOOK_NAME/$STATE_NAME"
if [[ -x "$HOOKPATH" ]]; then
  "$HOOKPATH" "$@"
elif [[ -d "$HOOKPATH" ]]; then
  find -L "$HOOKPATH" -maxdepth 1 -type f -executable -exec '{}' "$@" \;
fi
EOF
fi

sudo mv qemu /etc/libvirt/hooks/qemu
sudo chmod +x /etc/libvirt/hooks/qemu
sudo mkdir -p /etc/libvirt/hooks/qemu.d
check_dir_valid "/etc/libvirt/hooks/qemu.d"

restart_libvirt_daemon || exit 255

# install dependencies
sudo apt-get update
ubuntu_version=$(lsb_release -rs 2>/dev/null || true)
case "$ubuntu_version" in
  24.04) qemu_version="9.1.0" ;;
  26.04) qemu_version="10.2.0" ;;
  *) qemu_version="" ;;
esac

if [[ -n "$qemu_version" ]]; then
  qemu_series="${qemu_version%.*}"
  qemu_package_version=$(apt-cache madison qemu-system-x86 | \
    awk -v version="$qemu_series" '$3 ~ version && !found { print $3; found=1 }')

  if [[ -z "$qemu_package_version" && "$ubuntu_version" == "26.04" ]]; then
    sudo tee /etc/apt/sources.list.d/ubuntu-resolute.sources >/dev/null <<EOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: resolute resolute-updates
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    sudo apt-get update
    qemu_package_version=$(apt-cache madison qemu-system-x86 | \
      awk -v version="$qemu_series" '$3 ~ version && !found { print $3; found=1 }')
  fi

  if [[ -z "$qemu_package_version" ]]; then
    echo "ERROR: QEMU $qemu_version is not available for Ubuntu $ubuntu_version"
    exit 255
  fi
  sudo apt-get install -y virt-manager \
    "qemu-system-x86=$qemu_package_version" \
    "qemu-utils=$qemu_package_version"
else
  sudo apt-get install -y virt-manager qemu-system-x86 qemu-utils
fi

# Add user running host setup to group libvirt
username=""
if [[ -z "${SUDO_USER+x}" || -z "$SUDO_USER" ]]; then
    echo "Add $USER to group libvirt."
	username="$USER"
else
    echo "Add $SUDO_USER to group libvirt."
	username="$SUDO_USER"
fi
if [[ -n "$username" ]]; then
	sudo usermod -a -G libvirt "$username"
fi

# Allow ipv4 forwarding for host/vm ssh
check_file_valid_nonzero "/etc/sysctl.conf"
sudo sed -i "s/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g" /etc/sysctl.conf
sudo sysctl -p

# Temporary workaround: not require password sudo for launch_multios.sh until sriov dep are
# taken care not in launch_multios.sh
script=$(realpath "${BASH_SOURCE[0]}")
scriptpath=$(dirname "$script")
declare -a platpaths
mapfile -t platpaths < <(find "$scriptpath/../../platform/" -maxdepth 1 -mindepth 1 -type d) 
for p in "${platpaths[@]}"; do
    platscript=$(find "$p" -maxdepth 1 -mindepth 1 -type f -name "launch_multios.sh")
    check_file_valid_nonzero "$platscript"
    platscript=$(realpath "$platscript")
	if ! grep -Fqs "$platscript" /etc/sudoers.d/multios-sudo; then
		sudo tee -a /etc/sudoers.d/multios-sudo &>/dev/null <<EOF
%libvirt ALL=(ALL) NOPASSWD:SETENV:$platscript
EOF
	fi
done
sudo chmod 440 /etc/sudoers.d/multios-sudo

echo "Setting up libvirt xml"
# shellcheck source-path=SCRIPTDIR
source "$scriptpath/setup_libvirt_xml.sh"

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

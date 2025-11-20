#!/bin/bash

# Copyright (c) 2023-2025 Intel Corporation.
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
        if ! dpath=$(sudo realpath "$1") || sudo [ ! -d "$dpath" ]; then
            echo "Error: $dpath invalid directory"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}
export -f check_dir_valid

declare -F "check_file_valid_nonzero" >/dev/null || function check_file_valid_nonzero() {
    if [[ $# -eq 1 ]]; then
        check_non_symlink "$1"
        if ! fpath=$(sudo realpath "$1") || sudo [ ! -f "$fpath" ] || sudo [ ! -s "$fpath" ]; then
            echo "Error: $fpath invalid/zero sized"
            exit 255
        fi
    else
        echo "Error: Invalid param to ${FUNCNAME[0]}"
        exit 255
    fi
}
export -f check_file_valid_nonzero

#-------------    main processes    -------------
#Update /etc/libvirt/qemu.conf

UPDATE_FILE="/etc/libvirt/qemu.conf"
check_file_valid_nonzero "$UPDATE_FILE"
#libvirt works without below change,
#UPDATE_LINE="security_default_confined = 0"
#if [[ "$UPDATE_LINE" != $(sudo cat "$UPDATE_FILE" | grep -F "$UPDATE_LINE") ]]; then
#  sudo sed -i "s/^#security_default_confined.*/$UPDATE_LINE/g" "$UPDATE_FILE"
#fi

UPDATE_LINE='user = "root"'
if [[ "$UPDATE_LINE" != $(sudo cat "$UPDATE_FILE" | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s/^#user.*/$UPDATE_LINE/g" "$UPDATE_FILE"
fi

#libvirt works without below change,
#UPDATE_LINE='group = "root"'
#if [[ "$UPDATE_LINE" != $(sudo cat "$UPDATE_FILE" | grep -F "$UPDATE_LINE") ]]; then
#  sudo sed -i "s/^#group.*/$UPDATE_LINE/g" "$UPDATE_FILE"
#fi

UPDATE_LINE='cgroup_device_acl = ['
if [[ "$UPDATE_LINE" != $(sudo cat "$UPDATE_FILE" | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s/^#cgroup_device_acl.*/$UPDATE_LINE/g" "$UPDATE_FILE"
fi

UPDATE_LINE='    "/dev/null", "/dev/full", "/dev/zero",'
if [[ "$UPDATE_LINE" != $(sudo cat "$UPDATE_FILE" | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s+#    \"/dev/null\".*+$UPDATE_LINE+g" "$UPDATE_FILE"
fi

UPDATE_LINE='    "/dev/random", "/dev/urandom",'
if [[ "$UPDATE_LINE" != $(sudo cat "$UPDATE_FILE" | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s+#    \"/dev/random\".*+$UPDATE_LINE+g" "$UPDATE_FILE"
fi

UPDATE_LINE='    "/dev/ptmx", "/dev/kvm", "/dev/udmabuf", "/dev/dri/card0"]'
if [[ "$UPDATE_LINE" != $(sudo cat "$UPDATE_FILE" | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s+#    \"/dev/ptmx\".*+$UPDATE_LINE+g" "$UPDATE_FILE"
fi

# Update /etc/sysctl.d/90-enable-route-localnet.conf

UPDATE_FILE="/etc/sysctl.d/90-enable-route-localnet.conf"
UPDATE_LINE="net.ipv4.conf.all.route_localnet=1"
if [[ "$UPDATE_LINE" != $(grep -F "$UPDATE_LINE" "$UPDATE_FILE") ]]; then
  echo "$UPDATE_LINE" | sudo tee -a "$UPDATE_FILE"
  sudo sysctl "$UPDATE_LINE"
fi

# Update default network dhcp host

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
      <host mac='52:54:00:ab:cd:55' name='windows11' ip='192.168.122.55'/>
      <host mac='52:54:00:ab:cd:66' name='redhat' ip='192.168.122.66'/>
      <host mac='52:54:00:ab:cd:77' name='centos' ip='192.168.122.77'/>
    </dhcp>
  </ip>
</network>
EOF

echo end of file

if sudo virsh net-list --name | grep -q 'default'; then
    sudo virsh net-destroy default
fi
if sudo virsh net-list --name --all | grep -q 'default'; then
    sudo virsh net-undefine default
fi
sudo virsh net-define default_network.xml
sudo virsh net-autostart default
sudo virsh net-start default
rm default_network.xml

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

if sudo virsh net-list --name | grep -q 'isolated-guest-net'; then
    sudo virsh net-destroy isolated-guest-net
fi
if sudo virsh net-list --name --all | grep -q 'isolated-guest-net'; then
    sudo virsh net-undefine isolated-guest-net
fi
sudo virsh net-define isolated-guest-net.xml
sudo virsh net-autostart isolated-guest-net
sudo virsh net-start isolated-guest-net
rm isolated-guest-net.xml

# a hook-helper for libvirt which allows easier per-VM hooks.
# usually /etc/libvirt/libvirt/hooks/qemu.d/vm_name/hook_name/state_name/
# See: https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/
wget 'https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/4f6d505f7ef032b552c9a544f95e8586d954fe26/libvirt_hooks/qemu' -O qemu

# Configure port forwarding from host to VMs
tee -a qemu &>/dev/null <<EOF
if [[ "\${1}" == "ubuntu" ]]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.11
  GUEST_PORT=22
  HOST_PORT=1111

  if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi
  if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi

elif [[ "\${1}" == "windows" ]]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.22
  declare -A HOST_PORTS
  HOST_PORTS=([22]=2222 [3389]=3389)

  for GUEST_PORT in "\${!HOST_PORTS[@]}"; do
    if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
      /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
      /sbin/iptables -t nat -D PREROUTING -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -D OUTPUT -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
    fi
    if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
      /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
      /sbin/iptables -t nat -I PREROUTING -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -I OUTPUT -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
    fi
  done

elif [[ "\${1}" == "windows11" ]]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.55
  declare -A HOST_PORTS
  HOST_PORTS=([22]=5555 [3389]=3389)

  for GUEST_PORT in "\${!HOST_PORTS[@]}"; do
    if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
      /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
      /sbin/iptables -t nat -D PREROUTING -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -D OUTPUT -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
    fi
    if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
      /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
      /sbin/iptables -t nat -I PREROUTING -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -I OUTPUT -p tcp --dport \${HOST_PORTS[\$GUEST_PORT]} -j DNAT --to \$GUEST_IP:\$GUEST_PORT
      /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
    fi
  done

elif [[ "\${1}" == "redhat" ]]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.66
  GUEST_PORT=22
  HOST_PORT=6666

  if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi
  if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi

elif [[ "\${1}" == "centos" ]]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.77
  GUEST_PORT=22
  HOST_PORT=7777

  if [[ "\${2}" == "stopped" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi
  if [[ "\${2}" == "start" ]] || [[ "\${2}" == "reconnect" ]]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi

fi
EOF

sudo mkdir -p /etc/libvirt/hooks
check_dir_valid "/etc/libvirt/hooks"
sudo mv qemu /etc/libvirt/hooks/qemu
sudo chmod +x /etc/libvirt/hooks/qemu
sudo mkdir -p /etc/libvirt/hooks/qemu.d
check_dir_valid "/etc/libvirt/hooks/qemu.d"

sudo systemctl restart libvirtd

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
UPDATE_FILE="/etc/sysctl.d/90-enable-IP-forwarding.conf"
UPDATE_LINE="net.ipv4.ip_forward=1"
if [[ "$UPDATE_LINE" != $(grep -F "$UPDATE_LINE" "$UPDATE_FILE") ]]; then
  echo "$UPDATE_LINE" | sudo tee -a "$UPDATE_FILE"
  sudo sysctl "$UPDATE_LINE"
fi

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

echo "Done: \"$(realpath "${BASH_SOURCE[0]}") $*\""

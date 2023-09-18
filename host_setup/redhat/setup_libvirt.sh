#!/bin/bash

# Copyright (c) 2023 Intel Corporation.
# All rights reserved.

set -Eeuo pipefail
trap 'echo "Error line ${LINENO}: $BASH_COMMAND"' ERR

# Update /etc/default/grub

UPDATE_FILE="/etc/default/grub"
UPDATE_LINE="intel_iommu=on"
if [[ "$UPDATE_LINE" != $(sudo cat $UPDATE_FILE | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"$UPDATE_LINE /g" $UPDATE_FILE
  sudo grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
fi

# Update /etc/libvirt/qemu.conf

UPDATE_FILE="/etc/libvirt/qemu.conf"
UPDATE_LINE="security_default_confined = 0"
if [[ "$UPDATE_LINE" != $(sudo cat $UPDATE_FILE | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s/^#security_default_confined.*/$UPDATE_LINE/g" $UPDATE_FILE
fi

UPDATE_LINE='user = "root"'
if [[ "$UPDATE_LINE" != $(sudo cat $UPDATE_FILE | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s/^#user.*/$UPDATE_LINE/g" $UPDATE_FILE
fi

UPDATE_LINE='group = "root"'
if [[ "$UPDATE_LINE" != $(sudo cat $UPDATE_FILE | grep -F "$UPDATE_LINE") ]]; then
  sudo sed -i "s/^#group.*/$UPDATE_LINE/g" $UPDATE_FILE
fi

# Update /etc/sysctl.conf

sudo modprobe br_netfilter
UPDATE_FILE="/etc/sysctl.conf"
UPDATE_LINE="net.bridge.bridge-nf-call-iptables=0"
if [[ "$UPDATE_LINE" != $(cat $UPDATE_FILE | grep -F "$UPDATE_LINE") ]]; then
  echo $UPDATE_LINE | sudo tee -a $UPDATE_FILE
  sudo sysctl $UPDATE_LINE
fi

UPDATE_LINE="net.ipv4.conf.all.route_localnet=1"
if [[ "$UPDATE_LINE" != $(cat $UPDATE_FILE | grep -F "$UPDATE_LINE") ]]; then
  echo $UPDATE_LINE | sudo tee -a $UPDATE_FILE
  sudo sysctl $UPDATE_LINE
fi

# Update default network dhcp host

tee default_network.xml >& /dev/null <<EOF
<network>
  <name>default</name>
  <bridge name='virbr0'/>
  <forward/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
      <host mac='52:54:00:ab:cd:11' name='ubuntu' ip='192.168.122.11'/>
      <host mac='52:54:00:ab:cd:22' name='windows' ip='192.168.122.22'/>
      <host mac='52:54:00:ab:cd:33' name='redhat' ip='192.168.122.33'/>
      <host mac='52:54:00:ab:cd:33' name='centos' ip='192.168.122.44'/>
    </dhcp>
  </ip>
</network>
EOF

echo end of file

if [ ! -z $(sudo virsh net-list --name | grep default) ]; then
    sudo virsh net-destroy default
fi
if [ ! -z $(sudo virsh net-list --name --all | grep default) ]; then
    sudo virsh net-undefine default
fi
sudo virsh net-define default_network.xml
sudo virsh net-autostart default
sudo virsh net-start default


# Create qemu hook for port forwarding from host to VMs

tee qemu &>/dev/null <<EOF
#!/bin/bash

if [ "\${1}" = "ubuntu" ]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.11
  GUEST_PORT=22
  HOST_PORT=1111

  if [ "\${2}" = "stopped" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi
  if [ "\${2}" = "start" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi

elif [ "\${1}" = "windows" ]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.22
  GUEST_PORT=22
  HOST_PORT=2222

  if [ "\${2}" = "stopped" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi
  if [ "\${2}" = "start" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi

elif [ "\${1}" = "redhat" ]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.33
  GUEST_PORT=22
  HOST_PORT=3333

  if [ "\${2}" = "stopped" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi
  if [ "\${2}" = "start" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi

elif [ "\${1}" = "centos" ]; then

  # Update the following variables to fit your setup
  GUEST_IP=192.168.122.44
  GUEST_PORT=22
  HOST_PORT=4444

  if [ "\${2}" = "stopped" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -D FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -D PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -D POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi
  if [ "\${2}" = "start" ] || [ "\${2}" = "reconnect" ]; then
    /sbin/iptables -I FORWARD -o virbr0 -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j ACCEPT
    /sbin/iptables -t nat -I PREROUTING -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I OUTPUT -p tcp --dport \$HOST_PORT -j DNAT --to \$GUEST_IP:\$GUEST_PORT
    /sbin/iptables -t nat -I POSTROUTING -p tcp -d \$GUEST_IP --dport \$GUEST_PORT -j MASQUERADE
  fi

fi
EOF

sudo mkdir -p /etc/libvirt/hooks
sudo mv qemu /etc/libvirt/hooks/qemu
sudo chmod +x /etc/libvirt/hooks/qemu

sudo systemctl restart libvirtd

# Setup new directory for larger storage pool

# Create the directory if it doesn't exist
if [ ! -d "/home/user/vm_images" ]; then
    mkdir -p /home/user/vm_images
fi

# Create a new storage pool with the desired settings
mypool_defined=$(sudo virsh pool-list | grep mypool)
if [[ -z "$mypool_defined" ]]; then
  # Stop the default storage pool
  sudo virsh pool-destroy default || :
  # Remove the default storage pool configuration
  sudo virsh pool-undefine default || :
  sudo virsh pool-define-as mypool dir - - - - "/home/user/vm_images"
  sudo virsh pool-autostart mypool
  sudo virsh pool-build mypool
  sudo virsh pool-start mypool
else
  echo "mypool already created"
fi

echo "Setup Done! Please reboot the system!"


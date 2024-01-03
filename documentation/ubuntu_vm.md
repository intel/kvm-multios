# Table of Contents
1. [Automated Ubuntu/Ubuntu RT VM Installation](#automated-ubuntuubuntu-rt-vm-installation)
    1. [Prerequisites](#prerequisites)
    1. [Running Ubuntu 22.04 LTS Automated Install](#running-ubuntu-2204-lts-automated-install)
1. [Manual Ubuntu/Ubuntu RT VM guest configuration (only required if image not created using automated installation)](#manual-ubuntuubuntu-rt-vm-guest-configuration-only-required-if-image-not-created-using-automated-installation)
1. [Launching Ubuntu/Ubuntu RT VM](#launching-ubuntuubuntu-rt-vm)

# Automated Ubuntu/Ubuntu RT VM Installation
The automated Ubuntu/Ubuntu RT VM installation will perform the following:
- install Intel IOT Ubuntu from release ISO installer
- install Intel BSP overlay release for hardware platform into VM
- configure VM for KVM MultiOS Portfolio release supported features.

## Prerequisites
Obtain below required files are ready prior to running automated install:
- Ubuntu linux-headers and linux-image debian files for guest platform as per platform Ubuntu BSP release (if guide indicates using .deb files for kernel overlay installation) 
- Host platform BSP overlay release PPA download location, pgp keys, and PPA setup details as per host hardware platform Ubuntu BSP kernel overlay guide.

Host platform DUT setup:
- Host platform is setup as per platform release BSP guide and booted accordingly.
- Host platform has network connection and Internet access and proxy variables (http_proxy, https_proxy, no_proxy) are set appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. Running "sudo apt update" worked successfully.
- Host platform date/time is set up properly to current date/time.
- Host platform is already setup for using KVM MultiOS Portfolio release as per instructions [here](README.md#host-setup).

## Running Ubuntu 22.04 LTS Automated Install
1. Check platform BSP user guide if Intel kernel overlay is available via Intel PPA release. This information could be obtained from DUT platform BSP guide or inferred from a host platform which has been setup as per platform BSP user guide.

If linux kernel overlay was installed locally, "local" would be shown in "apt list --installed" output.

Example of host with kernel installed locally via .deb files as per BSP guide:
        $ uname -r
        x.y.z-aaaa-bbbbbb-cccccc

        $ apt list --installed | grep linux-headers-$(uname-a)
        linux-headers-x.y.z-aaaa-bbbbb-ccccc/now x.y-aaa-bbb amd64 [installed,local]

        $ apt list --installed | grep linux-image-$(uname-a)
        linux-image-x.y.z-aaaa-bbbbb-ccccc/now x.y-aaa-bbb amd64 [installed,local]

For Intel kernel overlay installed from Intel PPA release, kernel package name and version could be as per example below
where
x.y.z is the platform required kernel package and
aabbccdd is the exact kernel package version required. Also, "local" would not be found in "apt list --installed" output.

Example of host with kernel installed from Intel PPA release as per BSP guide:
        $ uname -r
        x.y.z-intel

        $ apt list --installed | grep linux-headers-$(uname-a)
        linux-headers-x.y.z-intel/<ppa_source_name> aabbccdd amd64 [installed]

        $ apt list --installed | grep linux-image-$(uname-a)
        linux-image-x.y.z-intel/<ppa_source_name> aabbccdd amd64 [installed]

For host DUT where platform BSP guide requires installation of Intel kernel overlay from .deb file, copy the same Ubuntu kernel headers and kernel image deb files to guest_setup/<host_os>/unattend_ubuntu folder prior to run Ubuntu guest VM auto installation.
Refer to the Ubuntu BSP release guide for the host hardware platform for steps on obtaining required kernel debian files.

        # To install Ubuntu VM
        cp linux-headers-x.y.z-mainline-tracking-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-headers.deb
        cp linux-image-x.y.z-mainline-tracking-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-image.deb

        # To install Ubuntu RT VM
        cp linux-headers-x.y.z-mainline-tracking-rt-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-headers-rt.deb
        cp linux-image-x.y.z-mainline-tracking-rt-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-image-rt.deb

2. Ensure host DUT is set up for Internet access in your environment. Setup any proxy as necessary and ensure DUT time is setup properly for current date/time.

3. Ensure Ubuntu BSP installation PPA variables to be used in guest VM setup is set desired as per host platform Ubuntu BSP release guide.
   Edit the file ./guest_setup/<host_os>/unattend_ubuntu/setup_bsp.sh accordingly for the variables shown below according to platform hardware Ubuntu BSP release guide.

        $ vi ./guest_setup/<host_os>/unattend_ubuntu/setup_bsp.sh

        # PPA url for Intel overlay installation
        # Add each required entry on new line
        PPA_URLS=(
            "https://download.01.org/intel-linux-overlay/ubuntu jammy main non-free multimedia"
        )
        # corresponding GPG key to use for each PPA_URL entry above in same sequence.
        # If GPG key is not set correctly,
        # Set to either one of below options:
        #   To auto use GPG key found in PPA entry (check PPA repository has required key available), set to: "auto"
        #   To force download GPG key at stated url, set to: "url of gpg key file"
        #   To force trusted access without GPG key (for unsigned PPA only), set to: "force"
        PPA_GPGS=(
            "auto"
        )
        # Set corresponding to use proxy as set in host env variable or not for each PPA_URL entry above in same sequence.
        # Set to either one of below options:
        #   To use auto proxy, set to: ""
        #   To not use proxy, set to: "--no-proxy"
        PPA_WGET_NO_PROXY=(
            ""
        )
        # Set additional apt proxy configuration required to access PPA_URL entries set.
        # Set to either one of below options:
        #   For no proxy required for PPA access, set to: ""
        #   For proxy required (eg. using myproxyserver.com at mynetworkdomain.com), set to:
        #     'Acquire::https::proxy::myproxyserver.com "DIRECT";' 'Acquire::https::proxy::*.mynetworkdomain.com "DIRECT";'
        #     where
        #     Change myproxyserver.com to your proxy server
        #     Change mynetworkdomain.com to your network domain
        PPA_APT_CONF=(
            ""
        )
        # PPA APT repository pin and priority required for Intel Overlay PPA
        # Reference: https://wiki.debian.org/AptConfiguration#Always_prefer_packages_from_a_repository
        PPA_PIN="release o=intel-iot-linux-overlay"
        PPA_PIN_PRIORITY=2000

4. If running behind proxy, ensure host platform machine running as VM host has proxy environment variables such as http_proxy/https_proxy/ftp_proxy/socks_server/no_proxy set appropriately in /etc/environment and reflected in bash shell before proceeding with next step.

5. Run below command to start Ubuntu/Ubuntu RT VM automated install from a terminal in host. Installed VM will be shutdown once installation is completed.

**Note: VM will restart multiple times and finally shutdown automatically after completion. Installation may take some time, please be patient.
DO NOT interfere or use VM before setup script exits successfully.**

        # To install Ubuntu VM
        ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer

        # To install Ubuntu RT VM (RT VM functionality is only applicable if running on RT host)
        ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --rt

        # To install Ubuntu VM kernel by local deb file instead of install kernel from Intel PPA (kernel image deb files available at guest_setup/<host_os>/unattend_ubuntu folder)
        # Required for non-RT VM: linux-headers.deb,linux-image.deb in guest_setup/<host_os>/unattend_ubuntu folder
        # Required for RT VM (--rt option): linux-headers-rt.deb,linux-image-rt.deb in guest_setup/<host_os>/unattend_ubuntu folder
        ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --force-kern-from-deb

        # To install Ubuntu non-RT VM on Ubuntu RT host with kernel installed from Intel PPA (assuming available)
        ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --force-kern-apt-ver <non-rt kernel version>=<specific package version>
        # Assumming RT host installed PPA kernel version 6.5rt-intel=231018t123235z-r1 with corresponding non-RT PPA kernel version 6.5-intel=231018t123235z-r1, then command to use would be:
        ./guest_setup/ubuntu/ubuntu_setup.sh --force --viewer --force-kern-apt-ver 6.5-intel=231018t123235z-r1

**Note: Unless --force-xxx options are used, the setup process would auto detect based on host installation the following for guest setup:<\br>
    - guest VM kernel is to be installed from PPA or from local debs<\br>
    - guest VM kernel specific version to be installed if from PPA<\br>
    - guest VM Intel overlay linux-firmware package version to be installed from PPA.<\br>
    Only use --force-xxx options judiciously.**

        Command Reference:
        Ubuntu_setup.sh [-h] [--force] [--viewer] [--rt] [--force-kern-from-deb] [--force-kern-apt-ver] [--force-linux-fw-apt-ver] [--debug]
        Create Ubuntu vm required image to dest /var/lib/libvirt/images/ubuntu.qcow2
        Or create Ubuntu RT vm required image to dest /var/lib/libvirt/images/ubuntu_rt.qcow2

        Place Intel bsp kernel debs (linux-headers.deb,linux-image.deb, linux-headers-rt.deb,linux-image-rt.deb) in guest_setup/<host_os>/unattend_ubuntu folder prior to running if platform BSP guide requires linux kernel installation from debian files.
        Install console log can be found at /var/log/libvirt/qemu/ubuntu_install.log
        Options:
            -h                          show this help message
            --force                     force clean if Ubuntu vm qcow file is already present
            --viewer                    show installation display
            --rt                        install Ubuntu RT
            --force-kern-from-deb       force Ubuntu vm to install kernel from local deb kernel files
            --force-kern-apt-ver        force Ubuntu vm to install kernel from PPA with given version
            --force-linux-fw-apt-ver    force Ubuntu vm to install linux-firmware from PPA with given version
            --debug                     Do not remove temporary files. For debugging only.

    Above command starts Ubuntu/Ubuntu RT guest VM install from installer. Installation progress can be tracked in the following ways:
    - "--viewer" option which display the progress using virt-viewer
    - via console from a terminal shell:
        sudo virsh console ubuntu
    - via remote VNC viewer of your choice by connect to <VM_IP>:5901. VM IP address can be found using the command:
        sudo virsh domifaddr ubuntu

6. Boot to newly installed Ubuntu VM as per [Launching Ubuntu/Ubuntu RT VM](#launching-ubuntuubuntu-rt-vm).

# Manual Ubuntu/Ubuntu RT VM guest configuration (only required if image not created using automated installation)
**Note: For reference . This section is not required when Ubuntu guest VM image was installed using KVM MultiOS Libvirt Portfolio release Ubuntu VM automated installation!"**

If and only if when reusing an existing VM image previously manually setup as per platform Intel Ubuntu BSP release, but still wish to configure such guest VM image for KVM MultiOS Portfolio release supported features.

Prerequisites:
- Guest VM image format should be in QCOW2
- Guest image file is named and located as per path set in <source file="..."> element of Ubuntu with VNC VM XML file.

Steps:
1. Boot guest VM

        ./platform/<plat>/launch_multios.sh -f -d ubuntu  
        Run in terminal on host platform:  

        virt-viewer -w --domain-name ubuntu

2. Copy the following files to guest VM via SSH:  

        ./guest_setup/ubuntu/unattend_ubuntu/setup_bsp.sh
        ./guest_setup/ubuntu/unattend_ubuntu/setup_pm_mgmt.sh
        ./host_setup/ubuntu/setup_swap.sh

3. Run in guest VM the following commands.  

        chmod +x setup_bsp.sh
        ./setup_bsp.sh --no-bsp-install
        sudo cp setup_swap.sh /usr/local/bin/setup_swap.sh
        sudo chmod +x /usr/local/bin/setup_swap.sh
        chmod +x ./setup_pm_mgmt.sh
        ./setup_pm_mgmt.sh
        sudo reboot now

# Launching Ubuntu/Ubuntu RT VM
Ubuntu/Ubuntu RT VM can be started with different display support as per below examples.
Refer to [here](README.md#vm-management) more details on VM managment.  

**Note:**  

    Ubuntu VM domain name: ubuntu
    Ubuntu RT VM domain name: ubuntu_rt

<table>
    <tr><th align="center">Example</th><th>Description</th></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -d &lt;domain&gt;</td><td>To launch ubuntu/ubuntu RT guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt;</td><td>To force launch ubuntu/ubuntu RT guest VM with VNC display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -g sriov &lt;domain&gt;</td><td>To force launch ubuntu/ubuntu RT guest VM configured with SR-IOV display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -g gvtd &lt;domain&gt;</td><td>To force launch ubuntu/ubuntu RT guest VM configured with GVT-d display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --usb keyboard</td><td>To launch ubuntu/ubuntu RT guest VM and passthrough USB Keyboard to it</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --pci wi-fi</td><td>To force launch ubuntu/ubuntu RT guest VM and passthrough PCI WiFi to it</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --pci network controller 2</td><td>To force launch ubuntu/ubuntu RT guest VM and passthrough the 2nd PCI Network Controller in lspci list to it</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --xml xxxx.xml</td><td>To force launch ubuntu/ubuntu RT guest VM and passthrough the device(s) in the XML file to it</td></tr>
</table>

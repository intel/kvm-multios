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
- Host platform is already setup for using KVM MultiOS Portfolio release as per instructions [here](README.md#host-setup).
- Host platform has network connection and Internet access and proxy variables (http_proxy, https_proxy, no_proxy) are set appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. "apt update" works.
- Host platform date/time is set up properly to current date/time.

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


For Intel kernel overlay installed from Intel PPA release, kernel name would be per "x.y.z-intel" format where x.y.z is the platform required kernel version. Also, "local" would not be found in "apt list --installed" output.

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

        vi ./guest_setup/<host_os>/unattend_ubuntu/setup_bsp.sh

        PPA_URLS=(
            "https://download.01.org/intel-linux-overlay/ubuntu jammy main non-free multimedia"
        )
        # corresponding GPG key for each PPA_URL entry
        # "auto" to auto get from ppa_url, "url of gpg key" or "force" to force trusted access without gpg key
        PPA_GPGS=(
            "auto"
        )
        # corresponding use proxy as set in host env variable or not for each PPA_URL entry
        # "" for use proxy or "--no-proxy"
        PPA_WGET_NO_PROXY=(
            ""
        )
        # additional apt proxy configuration required to access PPA urls. One line per entry.
        PPA_APT_CONF=(
            ""
        )
        PPA_PIN="release o=intel-iot-linux-overlay"
        PPA_PIN_PRIORITY=2000

4. If running behind proxy, ensure host platform machine running as VM host has proxy environment variables such as http_proxy/https_proxy/ftp_proxy/socks_server/no_proxy are set appropriately and reflected in bash environment before proceeding with next step.

5. Run below command to start Ubuntu/Ubuntu RT VM automated install from a terminal in host. Installed VM will be shutdown once installation is completed.

**Note: VM will restart multiple times and finally shutdown automatically after completion. Installation may take some time, please be patient.
DO NOT interfere or use VM before setup script exits successfully.**

        # To install Ubuntu VM
        ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer

        # To install Ubuntu RT VM
        ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --rt

        Command Reference:
        Ubuntu_setup.sh [-h] [--force] [--viewer] [--rt]
        Create Ubuntu vm required image to dest /var/lib/libvirt/images/ubuntu.qcow2
        Or create Ubuntu RT vm required image to dest /var/lib/libvirt/images/ubuntu_rt.qcow2

        Place Intel bsp kernel debs (linux-headers.deb,linux-image.deb, linux-headers-rt.deb,linux-image-rt.deb) in guest_setup/<host_os>/unattend_ubuntu folder prior to running if platform BSP guide requires linux kernel installation from debian files.
        Install console log can be found at /var/log/libvirt/qemu/ubuntu_install.log
        Options:
                -h        show this help message
                --force   force clean if Ubuntu vm qcow file is already present
                --viewer  show installation display
                --rt      install Ubuntu RT

    Above command starts Ubuntu/Ubuntu RT guest VM install from installer. Installation progress can be tracked in the following ways:
    - "--viewer" option which display the progress using virt-viewer
    - via console from a terminal shell:
        sudo virsh console ubuntu
    - via remote VNC viewer of your choice by connect to <VM_IP>:5901. VM IP address can be found using the command:
        sudo virsh domifaddr ubuntu

6. Boot to newly installed Ubuntu VM as per [Launching Ubuntu/Ubuntu RT VM](#launching-ubuntuubuntu-rt-vm).

# Manual Ubuntu/Ubuntu RT VM guest configuration (only required if image not created using automated installation)
This step is only required if reusing an existing VM image previously already manually setup as per platform Intel Ubuntu BSP release, and still wish to configure VM for KVM MultiOS Portfolio release supported features.

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

# Table of Contents
1. [Automated Ubuntu/Ubuntu RT VM Installation](#automated-ubuntuubuntu-rt-vm-installation)
    1. [Prerequisites](#prerequisites)
    1. [Running Ubuntu LTS Automated Install](#running-ubuntu-lts-automated-install)
1. [Manual Ubuntu/Ubuntu RT VM guest configuration (only required if image not created using automated installation)](#manual-ubuntuubuntu-rt-vm-guest-configuration-only-required-if-image-not-created-using-automated-installation)
1. [Launching Ubuntu/Ubuntu RT VM](#launching-ubuntuubuntu-rt-vm)

# Automated Ubuntu/Ubuntu RT VM Installation
The automated Ubuntu/Ubuntu RT VM installation will perform the following:
- install Ubuntu OS from release ISO installer
- install Intel BSP overlay release for hardware platform into VM
- configure VM for KVM MultiOS Portfolio release supported features.

Choose this option if you:
- want a fully unattended install of Ubuntu VM image from Ubuntu installer ISO with all dependencies installed with zero human intervention during installation.

***Notes***
- Automated install of Ubuntu desktop is done from Ubuntu live-server ISO.
- If desired user creation config is not added "user-data" config section of guest_setup/ubuntu/auto-install-ubuntu-desktop.yaml configuration file, guest VM will prompt for user creation upon bootup via Ubuntu welcome screen.
- For reference only: [Using Ubuntu Live-Server to automate Desktop installation](https://github.com/canonical/autoinstall-desktop/)

## Prerequisites
Obtain below required file and information to be ready and available prior to running automated install:
- Ubuntu linux-headers and linux-image debian files to be used for hardware platform as per platform Ubuntu BSP release (if guide indicates using .deb files for kernel overlay installation)
- Host platform BSP overlay release PPA download location, pgp keys, and PPA setup details as per host hardware platform Ubuntu BSP kernel overlay guide.

Host platform DUT setup:
- Host platform is setup as per platform release BSP guide and booted accordingly.
- Host platform has network connection and Internet access and proxy variables (http_proxy, https_proxy, no_proxy) are set appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. Running "sudo apt update" worked successfully.
- Host platform date/time is set up properly to current date/time.
- Host platform is already setup for using KVM MultiOS Portfolio release as per instructions [here](README.md#host-setup).
- User is already login to UI homescreen prior to any operations or user account has been to enable auto-login (required for VM support with Intel GPU SR-IOV).

## Running Ubuntu LTS Automated Install
1. Check platform BSP user guide if Intel kernel overlay is available via Intel PPA release. This information could be obtained from DUT platform BSP guide or inferred from a host platform which has been setup as per platform BSP user guide.

    If linux kernel overlay was installed locally, "local" would be shown in "apt list --installed" output.

    Example of host with kernel installed locally via .deb files as per BSP guide:
    ```
    $ uname -r
    x.y.z-aaaa-bbbbbb-cccccc

    $ apt list --installed | grep linux-headers-$(uname-a)
    linux-headers-x.y.z-aaaa-bbbbb-ccccc/now x.y-aaa-bbb amd64 [installed,local]

    $ apt list --installed | grep linux-image-$(uname-a)
    linux-image-x.y.z-aaaa-bbbbb-ccccc/now x.y-aaa-bbb amd64 [installed,local]
    ```

    For Intel kernel overlay installed from Intel PPA release, kernel package name and version could be as per example below
    where
    x.y.z is the platform required kernel package and
    aabbccdd is the exact kernel package version required. Also, "local" would not be found in "apt list --installed" output.

    Example of host with kernel installed from Intel PPA release as per BSP guide:
    ```
    $ uname -r
    x.y.z-intel

    $ apt list --installed | grep linux-headers-$(uname-a)
    linux-headers-x.y.z-intel/<ppa_source_name> aabbccdd amd64 [installed]

    $ apt list --installed | grep linux-image-$(uname-a)
    linux-image-x.y.z-intel/<ppa_source_name> aabbccdd amd64 [installed]
    ```

    For host DUT where platform BSP guide requires installation of Intel kernel overlay from .deb file, copy the same Ubuntu kernel headers and kernel image deb files to guest_setup/<host_os>/unattend_ubuntu folder prior to run Ubuntu guest VM auto installation.
    Refer to the Ubuntu BSP release guide for the host hardware platform for steps on obtaining required kernel debian files.

    Example of copy and rename required linux kernel .deb files for install Ubuntu VM:
    ```
    cp linux-headers-x.y.z-mainline-tracking-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-headers.deb
    cp linux-image-x.y.z-mainline-tracking-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-image.deb
    ```

    Example of copy and rename required linux kernel .deb files for install Ubuntu RT VM:
    ```
    cp linux-headers-x.y.z-mainline-tracking-rt-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-headers-rt.deb
    cp linux-image-x.y.z-mainline-tracking-rt-aaaaaaaaaaaaaa_b.c-ddd_amd64.deb guest_setup/<host_os>/unattend_ubuntu/linux-image-rt.deb
    ```

1. Ensure host DUT is set up for Internet access in your environment. Setup any proxy as necessary and ensure DUT time is setup properly for current date/time.

1. Ensure Ubuntu BSP installation PPA variables to be used in guest VM setup is set desired as per host platform Ubuntu BSP release guide.
   Edit the file ./guest_setup/<host_os>/unattend_ubuntu/setup_bsp.sh accordingly for the variables shown below according to platform hardware Ubuntu BSP release guide.

    ***Notes***
    - Replace /<ubuntu_version_codename/> in PPA_URLS definition below accordingly for guest VM version:
        - For Ubuntu 24.04: /<ubuntu_version_codename/> is "noble"

    Example of edit for Ubuntu VM PPA information:
    ```
    $ vi ./guest_setup/<host_os>/unattend_ubuntu/setup_bsp.sh

    # PPA url for Intel overlay installation
    # Add each required entry on new line
    PPA_URLS=(
        "https://download.01.org/intel-linux-overlay/ubuntu <ubuntu_version_codename> kernels main non-free multimedia"
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
    ```

1. If running behind proxy, ensure host platform machine running as VM host has proxy environment variables such as http_proxy/https_proxy/ftp_proxy/socks_server/no_proxy set appropriately in /etc/environment and reflected in bash shell before proceeding with next step.

1. There is no user creation specified by default for VM during automated installation. When VM boots after installation is completed, user will be prompted to create user account via Ubuntu welcome screen.

    If it is desired to create a default user duting automated installation, modify "user-data" section of <path to this repository source code directory on host machine>/guest_setup/ubuntu/auto-install-ubuntu-desktop.yaml configuration file like below:

    ***Notes***
    - \<path to respository source code directory on host machine\> refers to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
    - replace "\<user_name\>" in below example with desired user name
    - replace "\<user_password\"> in below example with desired user password
    - replace "\<description_of_user\>" in below example with description of desired user
    - For reference only: [Autoinstall configuration reference manual](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
    ```
      # Additional cloud-init configuration affecting the target
      # system can be supplied underneath a user-data section inside of
      # autoinstall.
      user-data:
        # This inhibits user creation, which for Desktop images means that
        # gnome-initial-setup will prompt for user creation on first boot.
        users:
          - name: '<user_name>'
            plain_text_passwd: '<user_password>'
            shell: /bin/bash
            lock_passwd: false
            gecos: '<description_of_user>'
            sudo: ALL=(ALL) NOPASSWD:ALL
            groups: [adm, cdrom, sudo, dip, plugdev, lpadmin, lxd, render]
        runcmd:
          - sed -i 's/#  AutomaticLoginEnable =/AutomaticLoginEnable =/g' /etc/gdm3/custom.conf
          - sed -i 's/#  AutomaticLogin = user1/AutomaticLogin = <user_name>/g' /etc/gdm3/custom.conf
          - cp /var/log/syslog /target/root/syslog_setup_cont
          # shutdown after install
          - shutdown
    ```

1. Run below command to start Ubuntu/Ubuntu RT VM automated install from a terminal in host. Installed VM will be shutdown once installation is completed.

    ***Notes***
    - \<path to respository source code directory on host machine\> refers to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
    - VM will restart multiple times and finally shutdown automatically after completion. Installation may take some time, please be patient.
    - ***DO NOT interfere or use VM before setup script exits successfully.***
    - Default storage size of the Ubuntu VM created is 60 GiB. Use option "--disk-size \<size in GiB\>" to customize VM disk size.
    - Use "--rt" option if desire to install Ubuntu RT VM with Intel BSP overlay RT version.
    - Depending on Intel BSP overlay release, Ubuntu VM kernel may need to be installed via PPA or from local build debian .deb files.
    - If wish to have automated install using linux kernel .deb files, kernel .deb files generated as per Intel BSP overlay release should be copied to \<path to respository source code directory on host machine\>guest_setup/<host_os>/unattend_ubuntu folder and renamed accordingly as:
        - Naming required for non-RT VM: linux-headers.deb and linux-image.deb
        - Naming required for RT VM: linux-headers-rt.deb and linux-image-rt.deb
    - Automated installation script would auto detect from host the following options to be used for guest by replicating host setup, unless "--force-xxx" options are being given as params. Detected setup options are:
        - Whether guest VM kernel to be installed from PPA or expected to be installed from linux kernel .deb files
        - If kernel is to be installed from PPA, the specific guest VM kernel version to be installed.
        - The specific guest VM Intel overlay linux-firmware package version to be installed from PPA (as this needs to match kernel for Intel GPU SR-IOV).
        - http_proxy, https_proxy, socks_server, ftp_proxy, no_proxy variables are set for VM as auto-detected from host environment.
    - **Only use --force-xxx options judiciously.**
    - The default Ubuntu guest VM libvirt domain name installed by default are fixed. If there is already similar named VM pre-defined in system, use "--force" option to force undefine and removal of existing VM domain and regenerate new image and domain definition.
    - Below command starts Ubuntu/Ubuntu RT guest VM install from installer ISO. Installation progress can be tracked in the following ways:
        - Replace \<ubuntu_domain_name\> in below commands accordingly:
            - For Ubuntu VM: \<ubuntu_domain_name\>  is "ubuntu"
            - For Ubuntu_RT VM: \<ubuntu_domain_name\> is "ubuntu_rt"
        - "--viewer" option which display the progress using virt-viewer
        - If "--viewer" option is not given initally, display still could be viewed via running below command in a graphical terminal in host:
            ```
            virt-viewer -w -r <ubuntu_domain_name>
            ```
        - to see serial console log from a terminal shell in host:
            ```
            virsh console <ubuntu_domain_name>
            ```
        - via VNC viewer of your choice by connecting to <VM_IP>:5901. VM IP address can be found using the command:
            ```
            virsh domifaddr <ubuntu_domain_name>
            ```

    Run one of below setup commands in a graphical terminal in host platform to install Ubuntu VM from \<path to respository source code directory on host machine\> directory:
    ```
    # First, change directory to <path to respository source code directory on host machine>
    cd <path to respository source code directory on host machine>

    # Run automated installation with pop up viewer for display using auto detection to replicate host setup for VM.
    ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer

    # The default storage size of the Ubuntu VM created is 60 GiB. To customize the size of the Ubuntu VM, add the option --disk-size <size in GiB>
    ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --disk-size <size in GiB>

    # To install Ubuntu RT VM (RT VM functionality is only applicable if running on RT host)
    ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --rt

    # To install Ubuntu VM kernel by local kernel .deb files instead of install kernel from Intel PPA (kernel image deb files need to be made already available at guest_setup/<host_os>/unattend_ubuntu folder prior to start of installation)
    # Required for non-RT VM: linux-headers.deb,linux-image.deb in guest_setup/<host_os>/unattend_ubuntu folder
    # Required for RT VM with (--rt option): linux-headers-rt.deb,linux-image-rt.deb in guest_setup/<host_os>/unattend_ubuntu folder
    ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --force-kern-from-deb

    # To install Ubuntu non-RT VM on Ubuntu RT host with specific kernel version installed from Intel PPA (assuming available in PPA)
    ./guest_setup/<host_os>/ubuntu_setup.sh --force --viewer --force-kern-apt-ver <non-rt kernel version>=<specific package version>

    # For exmaple, assumming RT host installed PPA kernel version 6.5rt-intel=231018t123235z-r1 with corresponding non-RT PPA kernel version 6.5-intel=231018t123235z-r1, then command to use would be:
    ./guest_setup/ubuntu/ubuntu_setup.sh --force --viewer --force-kern-apt-ver 6.5-intel=231018t123235z-r1
    ```

    Command Reference:
    ```
    Ubuntu_setup.sh [-h] [--force] [--viewer] [--disk-size] [--rt] [--force-kern-from-deb] [--force-kern-apt-ver] [--force-linux-fw-apt-ver] [--force-ubuntu-ver] [--debug]
    Create Ubuntu vm required image to dest /var/lib/libvirt/images/ubuntu.qcow2
    Or create Ubuntu RT vm required image to dest /var/lib/libvirt/images/ubuntu_rt.qcow2

    Place Intel bsp kernel debs (linux-headers.deb,linux-image.deb, linux-headers-rt.deb,linux-image-rt.deb) in guest_setup/<host_os>/unattend_ubuntu folder prior to running if platform BSP guide requires linux kernel installation from debian files.
    Install console log can be found at /var/log/libvirt/qemu/ubuntu_install.log
    Options:
        -h                          show this help message
        --force                     force clean if Ubuntu vm qcow file is already present
        --viewer                    show installation display
        --disk-size                 disk storage size of Ubuntu vm in GiB, default is 60 GiB
        --rt                        install Ubuntu RT
        --force-kern-from-deb       force Ubuntu vm to install kernel from local deb kernel files
        --force-kern-apt-ver        force Ubuntu vm to install kernel from PPA with given version
        --force-linux-fw-apt-ver    force Ubuntu vm to install linux-firmware from PPA with given version
        --force-ubuntu-ver          force Ubuntu vm version to install. E.g. "24.04" Default: same as host.
        --debug                     For debugging only. Does not remove temporary files.
    ```

1. Boot to newly installed Ubuntu VM as per [Launching Ubuntu/Ubuntu RT VM](#launching-ubuntuubuntu-rt-vm).

# Manual Ubuntu/Ubuntu RT VM guest configuration (only required if image not created using automated installation)
**Note: For reference . This section is not required when Ubuntu guest VM image was installed using KVM MultiOS Libvirt Portfolio release Ubuntu VM automated installation!"**

Choose this option if you are reusing an existing VM image previously manually setup with platform Intel Ubuntu BSP release, but wish to configure guest VM image for KVM MultiOS Portfolio release supported features.

Prerequisites:
- Guest VM image format should be in QCOW2. If required, use qemu-img to convert from raw .img VM image to qcow2 VM image.
    For example, to convert from raw image file to qcow2 format:
    ```
    qemu-img convert -f raw [path_to_raw_vm_image_to_be_converted] -O qcow2 [path_to_output_qcow2_vm_image_after_conversion]
    ```
- Guest VM has already been installed with Intel BSP overlay release for hardware platform.
- Guest VM has proxy variables (http_proxy, https_proxy, no_proxy) set appropriately in /etc/environment if required for network access.
- Guest VM has Internet apt access. ie. Running "sudo apt update" worked successfully.
- Guest VM date/time is set up properly to current date/time.
- Guest image file has been renamed and moved to \<DEFAULT_LIBVIRT_IMAGE_PATH\> path as set in file attribute of \<disk\>/\<source\> XML element of Ubuntu/Ubuntu-RT VM with VNC XML file. For Ubuntu host, \<DEFAULT_LIBVIRT_IMAGE_PATH\> is at "\var\lib\libvirt\images". Refer to [Guest OS libvirt Domain XML Naming Convention](README.md/#guest-os-libvirt-domain-xml-naming-convention) for exact XML file name.
- User is already login to UI homescreen prior to any operations or user account is set to enable auto-login (required for VM support with Intel GPU SR-IOV).
- The steps below use non-RT ubuntu guest VM for example, the commands could be applied to non-RT as desired

Steps:
1. Boot guest VM

    ***Notes***
    - Replace \<path to respository source code directory on host machine\> in below command to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
    - Replace \<ubuntu_domain_name\> in below commands accordingly:
        - For Ubuntu VM: \<ubuntu_domain_name\>  is "ubuntu"
        - For Ubuntu_RT VM: \<ubuntu_domain_name\> is "ubuntu_rt"

    Command to launch Ubuntu VM:
    ```
    <path to respository source code directory on host machine>/platform/client/launch_multios.sh -f -d <ubuntu_domain_name>
    ```

1.  Run below command in a graphical terminal after login to home screen on host platform to view VM display:

    ***Notes***
    - Replace \<ubuntu_domain_name\> in below commands accordingly:
        - For Ubuntu VM: \<ubuntu_domain_name\>  is "ubuntu"
        - For Ubuntu_RT VM: \<ubuntu_domain_name\> is "ubuntu_rt"

    Command to view Ubuntu VM display:

    ```
    virt-viewer -w -r --domain-name <ubuntu_domain_name>
    ```

1. Copy the following files from repository into the same folder location in guest VM:  

    ***Notes***
    - \<path to respository source code directory on host machine\> refers to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
    - File to be copied to same location in guest VM:
        - \<path to respository source code directory on host machine\>/guest_setup/ubuntu/unattend_ubuntu/setup_bsp.sh
        - \<path to respository source code directory on host machine\>/guest_setup/ubuntu/unattend_ubuntu/setup_pm_mgmt.sh
        - \<path to respository source code directory on host machine\>/host_setup/ubuntu/setup_swap.sh
        - \<path to respository source code directory on host machine\>/host_setup/ubuntu/setup_openvino.sh

1. Run the following commands in a bash terminal in guest VM.  

    ***Notes***
    - \<path_to_copied_scripts_in_guest_VM\> refers to folder in guest VM to which files copied in earlier step were placed.
    - Check host is using "i915" or "xe" kernel driver for Intel GPU in order to setup to use same driver in guest VM using command "lspci -D -k -s \<gpu_pci_address\>". Use this value to replace \<drm_driver_used_in_host\> for "-drm \<drm_driver_used_in_host\>" option in call to setup_bsp.sh script in commands below. 
        For example, the "kernel driver in use" field below shows "i915" driver is being used for Intel iGPU located at 0000:00:02.0
        ```
        user@localhost:~$ lspci -D -k -s 0000:00:02.0
        0000:00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)
                DeviceName: To Be Filled by O.E.M.
                Subsystem: Intel Corporation Raptor Lake-P [Iris Xe Graphics]
                Kernel driver in use: i915
                Kernel modules: i915
        ```
    - "--no-bsp-install" option is used with call to setup_bsp.sh script to skip setting up Intel BSP overlay for guest VM.
    - "--rt" option is used with call to setup_bsp.sh script for setting up Ubuntu RT guest VM.

    Command for setup Ubuntu VM with KVM MultiOS portfolio dependencies,
    ```
    cd <path_to_copied_scripts_in_guest_vm>
    chmod +x setup_bsp.sh
    ./setup_bsp.sh --no-bsp-install -drm <drm_driver_used_in_host>
    sudo cp setup_swap.sh /usr/local/bin/setup_swap.sh
    sudo chmod +x /usr/local/bin/setup_swap.sh
    chmod +x ./setup_pm_mgmt.sh
    ./setup_pm_mgmt.sh
    ```

    Command for setup Ubuntu RT VM with KVM MultiOS portfolio dependencies,
    ```
    cd <path_to_copied_scripts_in_guest_vm>
    chmod +x setup_bsp.sh
    ./setup_bsp.sh --no-bsp-install --rt -drm <drm_driver_used_in_host>
    sudo cp setup_swap.sh /usr/local/bin/setup_swap.sh
    sudo chmod +x /usr/local/bin/setup_swap.sh
    chmod +x ./setup_pm_mgmt.sh
    ./setup_pm_mgmt.sh
    ```

1. Run the following commands in a bash terminal in guest VM if desired to setup OpenVINO for use with Intel GPU and/or NPU in guest VM.

    ***Notes***
    - To use NPU in guest VM, VM must be (re)launched with Intel GPU SR-IOV and NPU passthrough options after all setup is completed.

    To setup OpenVINO with support for Intel GPU:
    ```
    cd <path_to_copied_scripts_in_guest_vm>
    chmod +x setup_openvino.sh
    ./setup_openvino.sh --neo
    ```

    To setup OpenVINO with support for Intel GPU ***and*** NPU:
    ```
    cd <path_to_copied_scripts_in_guest_vm>
    chmod +x setup_openvino.sh
    ./setup_openvino.sh --neo --npu
    ```

1. Reboot the VM finally from bash terminal in guest VM for changes to take effect.

    ```
    sudo reboot now
    ```

# Launching Ubuntu/Ubuntu RT VM
Ubuntu VM can be started with different display support as per below examples.  
Ubuntu RT VM can only be started without display support and access is via virsh console as mentioned in section [VM Misc Operations](README.md#vm-misc-operations)  
Refer to [here](README.md#vm-management) more details on VM managment.  

**Notes:**  
- Ubuntu VM domain name: ubuntu
- Ubuntu RT VM domain name: ubuntu_rt
- VM IP address can be found using the command:
    ```
    virsh domifaddr <domain_name>
    ```
- VM VNC port number can be found using the command:
    ```
    virsh domdisplay --type vnc <domain_name>
    ```
- VM SPICE port number can be found using the command:
    ```
    virsh domdisplay --type spice <domain_name>
    ```

<table>
    <tr><th align="center">Example</th><th>Description</th></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -d &lt;domain&gt;</td><td>To launch ubuntu with VNC and SPICE display or launch ubuntu_rt without display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt;</td><td>To force launch ubuntu/ubuntu RT guest</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -g sriov &lt;domain&gt;</td><td>To force launch ubuntu guest VM configured with SR-IOV display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -g gvtd &lt;domain&gt;</td><td>To force launch ubuntu guest VM configured with GVT-d display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --usb keyboard</td><td>To launch ubuntu/ubuntu RT guest VM and passthrough USB Keyboard to it</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --pci wi-fi</td><td>To force launch ubuntu/ubuntu RT guest VM and passthrough PCI WiFi to it</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --pci network controller 2</td><td>To force launch ubuntu/ubuntu RT guest VM and passthrough the 2nd PCI Network Controller in lspci list to it</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d &lt;domain&gt; -p &lt;domain&gt; --xml xxxx.xml</td><td>To force launch ubuntu/ubuntu RT guest VM and passthrough the device(s) in the XML file to it</td></tr>
</table>

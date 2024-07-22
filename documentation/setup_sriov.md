# Table of Contents
1. [Host Hardware and OS Setup](#host-hardware-and-os-setup)
  1. [BIOS Setup](#bios-setup)
  1. [Prerequisites](#prerequisites)
  1. [Running KVM MultiOS Host Setup](#running-kvm-multios-host-setup)

This setup guide provide the procedures to configure the host and VMs for using GPU SR-IOV with KVM MultiOS Portfolio release.

# Host Hardware and OS Setup
## BIOS Setup
Ensure the following options are enabled in the BIOS for Intel IoT host platform
- Intel Virtualization Technology (VMX)
- Intel VT for Directed I/O (VT-d)

## Prerequisites
Host platform DUT setup:
- Host platform have physical display monitor connection prior to installation run.
- Host platform is setup as per platform release BSP guide and booted accordingly.
- Host platform has network connection and Internet access and proxy variables (http_proxy, https_proxy, no_proxy) are set appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. Running "sudo apt update" worked successfully.
- Host platform date/time is set up properly to current date/time.

## Running KVM MultiOS Host Setup
1. Run KVM MultiOS Portfolio release host setup script to setup system for SR-IOV. System will rebooted at the end of script execution.

        ./host_setup/ubuntu/setup_host.sh -u GUI

        To view list of supported platforms:
        ./host_setup/ubuntu/setup_host.sh --help

2. After reboot, host system should be booted to GUI login.

3. Refer to [Virtual Machine Image Creation](README.md#virtual-machine-image-creation) for steps on creating desired VM images for running on host platform.
Refer to [platforms supported](platforms.md) for detailed information on what guest operating systems are supported on each platform. 

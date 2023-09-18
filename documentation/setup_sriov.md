# Table of Contents
1. [Host Hardware and OS Setup](#host-hardware-and-os-setup)
  1. [BIOS Setup](#bios-setup)
  2. [Operating System Setup](#operating-system-setup)

This setup guide provide the procedures to configure the host and VMs for using GPU SR-IOV with KVM MultiOS Portfolio release.

# Host Hardware and OS Setup
## BIOS Setup
Ensure the following options are enabled in the BIOS for Intel IOT host platform
- Intel Virtualization Technology (VMX)
- Intel VT for Directed I/O (VT-d)

## Operating System Setup
The guide assumes Intel IOT host platform used has first been setup for host operating system Intel BSP release. Refer to [platforms supported](platforms.md) for setup details) for respective platforms.

1. Run KVM MultiOS Portfolio release host setup script to setup system for SR-IOV. System will rebooted at the end of script execution.

        ./host_setup/ubuntu/setup_host.sh -u GUI

        To view list of supported platforms:
        ./host_setup/ubuntu/setup_host.sh --help

2. After reboot, host system should be booted to GUI login.

3. Refer to [Virtual Machine Image Creation](README.md#virtual-machine-image-creation) for steps on creating desired VM images for running on host platform.
Refer to [platforms supported](platforms.md) for detailed information on what guest operating systems are supported on each platform. 

# Table of Contents
1. [Host Hardware and OS Setup](#host-hardware-and-os-setup)
  1. [BIOS Setup](#bios-setup)
  1. [Prerequisites](#prerequisites)
  1. [Running KVM MultiOS Host Setup](#running-kvm-multios-host-setup)
  1. [Build OVMF binaries for Windows GVT-d](#build-ovmf-binaries-for-windows-gvt-d)
1. [Virtual Machine Additional Setup for GVT-d](#virtual-machine-additional-setup-for-gvt-d)

This setup guide provide the procedures to configure the host and VMs for using GVT-d with KVM MultiOS Portfolio release.

# Host Hardware and OS Setup
## BIOS Setup
Ensure the following options are enabled in the BIOS
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
1. Run host setup script to setup system for GVT-d. System will rebooted at the end of script execution.

        ./host_setup/ubuntu/setup_host.sh -u headless

        To view list of supported platforms:
        ./host_setup/ubuntu/setup_host.sh --help

2. After reboot, host system should now be booted to console login only.

3. Refer to [here](README.md#virtual-machine-image-creation) for steps on creating desired VM images for running on host platform.
Refer to platforms support documentation [here](platforms.md) for detailed information on what guest operating systems are supported on each platform. 

## Build OVMF Binaries for Windows GVT-d
OVMF binaries used for Windows with GVT-d need to be patched (0001-OvmfPkg-add-IgdAssignmentDxe.patch), else GPU driver would not load properly in windows VM.

To build the OVMF binaries, run

        ./host_setup/ubuntu/build_ovmf.sh

# Virtual Machine Additional Setup for GVT-d 
There are two different modes of operation for GVT-d, UPT and legacy, as discribed in
https://github.com/qemu/qemu/blob/master/docs/igd-assign.txt

In both modes, `x-igd-gms=2,x-igd-opregion=on` needs to be added to the iGPU passthrough command
Note: for each mode, the Intel GPU graphics driver must be installed at least once to work with GPU.

The libvirt xml should include
```
  ...

    <hostdev mode="subsystem" type="pci" managed="yes">
      <source>
        <address domain="0" bus="0" slot="2" function="0"/>
      </source>
      <alias name="ua-igpu"/>
    </hostdev>
  </devices>
  <qemu:commandline>
    <qemu:arg value="-set"/>
    <qemu:arg value="device.ua-igpu.x-igd-opregion=on"/>
    <qemu:arg value='-set'/>
    <qemu:arg value='device.ua-igpu.x-igd-gms=2'/>
  </qemu:commandline>
````
## Windows VM Additional Setup
### Windows GVT-d UPT mode
For first time setup of the Windows VM with GVT-d, it is easier to use UPT mode, where the main display is a VNC and the iGPU is the secondary<br>

Use VNC display to install GPU graphics driver and verify installed driver is initialized properly

1. Launch Windows VM in UPT mode

   for Windows 10

        sudo virsh define ./platform/client/libvirt_xml/windows_gvtd_upt_ovmf.xml
        sudo virsh start windows

   for Windows 11

        sudo virsh define ./platform/client/libvirt_xml/windows11_gvtd_upt_ovmf.xml
        sudo virsh start windows11

2. Install Intel Graphics GPU graphic driver.

### Windows GVT-d Legacy mode
Legacy mode is used when iGPU is configured as the main display.<br>
Before launching the windows in legacy GVT-d, ensure the VM can be connected via remote desktop for first time installation of the graphic driver

1. Refer to [VM Launch](README.md#vm-launch) to launch Windowd VM with GVT-d. 

2. Log in to Windows VM using remote desktop to install Intel Graphics GPU driver and reboot.

# Ubuntu VM Additional Setup

1. Refer to [VM Launch](README.md#vm-launch) to launch Ubuntu VM with GVT-d. 

2. Ensure kernel parameters `intel_iommu=on i915.enable_guc=3 i915.force_probe=*` are present in /etc/default/grub file for GRUB_CMDLINE_LINUX variable assignment.
Update GRUB commandline by `sudo update-grub`

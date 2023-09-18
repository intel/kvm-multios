# Table of Contents
1. [Automated Windows VM Installation](#automated-windows-vm-installation)
    1. [Prerequisites](#prerequisites)
    1. [Running Windows10 Automated Install](#running-windows10-automated-install)
1. [Launching Windows VM](#launching-windows-vm)

# Automated Windows VM Installation
The automated Windows guest VM automated installation will perform the following:
- install Windows from Windows installer iso.
- configure VM for KVM MultiOS Portfolio release supported features.
- install SR-IOV ZeroCopy drivers.

The created image is default able to work launching Windows VM with GPU SR-IOV virtualization.

Note: For using created image with GVT-d, user may need to re-run Intel graphics installer after launching Windows VM with GVT-d via Remote Desktop connection to the VM, then reboot VM to get physical display output with GVT-d.

## Prerequisites
Required:
- Windows noprompt installer iso file created in [NoPrompt Windows Installation ISO Creation](#noprompt-windows-installation-iso-creation)
- Windows update OS patch msu file
- Intel Graphics driver 64bit release zip archive for host platform
- Intel Graphics SR-IOV ZeroCopy driver zip archive for host platform

Host platform DUT setup:
- Host platform have physical display monitor connection prior to installation run.
- Host platform is setup as per platform release BSP guide and booted accordingly.
- Host platform is already setup for using KVM MultiOS Portfolio release as per instructions [here](README.md#host-setup).
- Host platform has network connection and Internet access and proxy variables (http_proxy, https_proxy, no_proxy) are set appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. "apt update" works.
- Host platform date/time is set up properly to current date/time.

### NoPrompt Windows10 Installation ISO Creation
Windows installation iso as downloaded from Windows direct is not suitable for unattended install as it requires human intervention to respond to a "Press Any Key To Boot From..." prompt from iso installation.
To get around this, an noprompt Windows installation iso needs to be generated once from the actual installation iso provided by Windows download for unattended Windows installation.

The generation of noprompt installation iso requires the use of a Windows machine with Windows ADK installed.
Reference: https://www.deploymentresearch.com/a-good-iso-file-is-a-quiet-iso-file

1. Install [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install#choose-the-right-adk-for-your-scenario) in Windows machine according to version of Windows installation iso to be used.
Take note of ADK installation destination path for later use.

| Windows Version | Window ADK Download |
| :-- | :-- |
| Windows 10 IOT Enterprise LTSC 21H2 | [Windows ADK for Windows 10, version 2004](https://go.microsoft.com/fwlink/?linkid=2120254)</br>[Windows PE add-on for the ADK, version 2004](https://go.microsoft.com/fwlink/?linkid=2120253)|

2. Download and save Create-NoPromptISO.ps1 script from [here](https://github.com/DeploymentResearch/DRFiles/raw/906151a1cdd55a14bc226196a3f597b0538273dd/Scripts/Create-NoPromptISO.ps1)

3. Edit WinPE_InputISOfile, WinPE_OutputISOfile and ADK_Path variables in CreateNoPromptISO.ps1 script with appropriate paths for input ISO file, output ISO file and ADK installation path on your Windows machine accordingly.

        notepad CreateNoPromptISO.ps1

        ...
        $WinPE_InputISOfile = "C:\ISO\Zero Touch WinPE 10 x64.iso"
        $WinPE_OutputISOfile = "C:\ISO\Zero Touch WinPE 10 x64 - NoPrompt.iso"
         
        $ADK_Path = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"

4. Open a PowerShell terminal in Windows machine and run CreateNoPromptISO.ps1 script

        cd <CreateNoPromptISO.ps1 location>
        .\CreateNoPromptISO.ps1

        Note: If you see "CreateNoPromptISO.ps1 cannot be loaded because running scripts is disabled on this system" error,
        run the following command in PowerShell prior to running CreateNoPromptISO.ps1.

        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted

The noprompt installation iso will be generated at path specified by WinPE_OutputISOfile variable in CreateNoPromptISO.ps1 script. This can be used for all subsequent Windows unattended installations.

## Running Windows10 Automated Install
1. Copy windows noprompt installer iso to the Intel host machine which is to run the guest VM.

        sudo cp <windowsNoPrompt.iso> guest_setup/ubuntu/unattend_win10/windowsNoPrompt.iso

2. Copy required installation files to guest_setup/ubuntu/unattend_win folder, renaming them as below.

        cp windows-kbxxxxxxx-x64_xxxxxxxxxxx.msu ./guest_setup/ubuntu/unattend_win10/windows-updates.msu
        cp <Driver-Release-64-bit.zip> ./guest_setup/ubuntu/unattend_win10/Driver-Release-64-bit.zip
        cp <ZCBuild_xxxx_MSFT_Signed.zip> ./guest_setup/ubuntu/unattend_win10/ZCBuild_MSFT_Signed.zip

3. Run below command to start Windows VM automated install from a terminal.

**Note: VM will restart multiple times and finally shutdown automatically after completion. Installation may take some time, please be patient. 
As part of windows installation process VM will be restarted in SR-IOV mode for installation of SR-IOV required drivers in the background. At this stage VM will no longer have display on virt-viewer UI nor on VNC. Instead VM display could be found on host platform physical monitor.
DO NOT interfere or use VM before setup script exits successfully.**

        ./guest_setup/ubuntu/win10_setup.sh -p client --force --viewer

        Command Reference:
        windows_setup.sh [-h] [-p] [--force] [--viewer]
        Create Windows vm required images and data to dest folder /var/lib/libvirt/images/windows.qcow2
        Place required Windows installation files as listed below in guest_setup/ubuntu/unattend_win folder prior to running.
        (windowNoPrompt.iso, windows-updates.msu, ZCBuild_MSFT_Signed.zip, Driver-Release-64-bit.zip)
        Options:
                -h        show this help message
                -p        specific platform to setup for, eg. "-p client"
                          Accepted values:
                            client
                            server
                --force   force clean if windows vm qcow is already present
                --viewer  show installation display

    This command will start Windows guest VM install from Windows installer. Installation progress can be tracked in the following ways:
    - "--viewer" option which display VM on virt-viewer
    - via remote VNC viewer of your choice by connect to <VM_IP>:5902. VM ip address can be found using the command:
        sudo virsh domifaddr windows

# Launching Windows VM
Windows VM can be run with different display support as per below examples.
Refer to [here](README.md#vm-management) more details on VM managment.

<table>
    <tr><th align="center">Example</th><th>Description</th></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -d windows</td><td>To launch Windows guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows</td><td>To force launch windows guest VM with VNC display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -g sriov windows</td><td>To force launch windows guest VM configured with SR-IOV display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -g gvtd windows</td><td>To force launch windows guest VM configured with GVT-d display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows --usb keyboard</td><td>To force launch windows and passthrough USB Keyboard to windows guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows --pci wi-fi</td><td>To force launch windows VM and passthrough PCI WiFi to windows guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows --pci network controller 2</td><td>To force launch windows VM and passthrough the 2nd PCI Network Controller in lspci list to windows guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows--xml xxxx.xml</td><td>To force launch windows VM and passthrough the device(s) in the XML file to windows guest VM</td></tr>
</table>

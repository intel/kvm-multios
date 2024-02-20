# Table of Contents
1. [Automated Windows VM Installation](#automated-windows-vm-installation)
    1. [Prerequisites](#prerequisites)
        1. [NoPrompt Windows10 Installation ISO Creation](#noprompt-windows10-installation-iso-creation)
        1. [Getting Ready for Automated Install](#getting-ready-for-automated-install)
    1. [Running Windows10 Automated Install](#running-windows10-automated-install)
        1. [Automated SRIOV Install with WHQL Certified Graphics Driver](#automated-sriov-install-with-whql-certified-graphics-driver)
        1. [Automated SRIOV Install with Intel Attest-signed Graphics Driver](#automated-sriov-install-with-intel-attest-signed-graphics-driver)
        1. [Windows10 Non-SR-IOV Automated Install](#windows10-non-sr-iov-automated-install) 
1. [Launching Windows VM](#launching-windows-vm)

# Automated Windows VM Installation
The automated Windows guest VM automated installation will perform the following:
- install Windows from Windows installer iso (modified for No Prompt installation).
- configure VM for KVM MultiOS Portfolio release supported features.
- install Windows GFX and SR-IOV ZeroCopy drivers for Intel GPU (if --no-sriov install option is not given).

The created image is default able to work launching Windows VM with GPU SR-IOV virtualization (if --no-sriov install option is not given).

**
Information:  
For using created image with GVT-d, user may need to re-run Intel graphics installer after launching Windows VM with GVT-d via Remote Desktop connection to the VM, then reboot VM to get physical display output with GVT-d. **

## Prerequisites
Required:
- Windows noprompt installer iso file created in [NoPrompt Windows Installation ISO Creation](#noprompt-windows-installation-iso-creation)
- Windows update OS patch msu file as per host platform BSP release guide
- Intel Graphics driver 64bit release 7z/zip archive for host platform
- Intel Graphics SR-IOV ZeroCopy driver zip archive for host platform

Host platform DUT setup:
- Host platform have physical display monitor connection with working display prior to installation run (unless VNC only install option is desired).
- Host platform is setup as per platform release BSP guide and booted accordingly to GUI desktop after login.
- Host platform has network connection and Internet access and proxy variables (http_proxy, https_proxy, no_proxy) are set appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. Running "sudo apt update" worked successfully.
- Host platform date/time is set up properly to current date/time.
- Host platform is already setup for using KVM MultiOS Portfolio release as per instructions [here](README.md#host-setup).

### NoPrompt Windows10 Installation ISO Creation
Windows installation iso as downloaded from Windows direct is not suitable for unattended install as it requires human intervention to respond to a "Press Any Key To Boot From..." prompt from iso installation.
To get around this, an NoPrompt Windows installation iso needs to be generated once from the actual installation iso provided by Windows download for unattended Windows installation. The created NoPrompt iso could be reused for all subsequent unattended Windows VM creation from same Windows ISO.

The generation of NoPrompt installation iso requires the use of a Windows machine with Windows ADK installed.
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

### Getting Ready for Automated Install
1. Copy windows noprompt installer iso to the Intel host machine which is to run the guest VM.

        cp <windowsNoPrompt.iso> guest_setup/ubuntu/unattend_win10/windowsNoPrompt.iso

2. Copy required Windows update OS patch msu file to guest_setup/ubuntu/unattend_win folder, renaming as below.

        cp windows-kbxxxxxxx-x64_xxxxxxxxxxx.msu ./guest_setup/ubuntu/unattend_win10/windows-updates.msu

3. Copy required Intel GPU GFX driver archive to guest_setup/ubuntu/unattend_win folder, ensure renaming as below.

        cp <Driver-Release-64-bit.zip> ./guest_setup/ubuntu/unattend_win10/Driver-Release-64-bit.zip
        OR
        cp <Driver-Release-64-bit.7z> ./guest_setup/ubuntu/unattend_win10/Driver-Release-64-bit.7z

4. Copy required Intel GPU SR-IOV Zero-copy driver build or installer archive to guest_setup/ubuntu/unattend_win folder, renaming as below.

        cp <ZCBuild_xxxx_MSFT_Signed.zip> ./guest_setup/ubuntu/unattend_win10/ZCBuild_MSFT_Signed.zip
        OR
        cp <ZC_Installer_xxxx.zip> ./guest_setup/ubuntu/unattend_win10/ZC_Installer.zip

5. Configure any additional driver/windows installations by modifying ./guest_setup/ubuntu/unattend_win10/additional_installs.yaml.
   Only installations which are capable of silent install without any user intervention required are supported for auto install.  
   Additional_install.yaml file has the format as below. 

        installations:
          - name: # unique name for this installation in yaml
            description: # description of installation
            filename: # filename of file in guest_setup/ubuntu/unattend_win10 folder containing install file.  
                      # If file is not present, attempt to download from download_url and rename as filename.
                      # If download fails, auto install will be aborted.
            download_url: # Empty string or download url to download installation file
            install_type: # msi | exe | cab | inf
            install_file: # path to installation msi/exe/cab/inf file(s) inside archive/folder to install with
                          # If "path_to\*.inf" is used as file, all inf inside install_file path + subdirs will be installed
            silent_install_option: # '' or options required to run silent installation as per installation guide
            enable_test_sign: # yes | no.

   Currently the default additional installations are provided for:
   - Intel® Wireless Bluetooth® for IT Administrators version
   - Intel® PROSet/Wireless Software and Drivers for IT Admins
   - Intel® Ethernet Adapter Complete Driver Pack
   If do not wish to have any of above additional installations, please remove accordingly in guest_setup/ubuntu/unattend_win10/additional_installs.yaml file prior to starting Windows Automated install.

Now system is ready to run Windows Automated install. Run Windows automated install as per following sections based on what type of VM support is desired and whether provided Intel GPU GFX driver used for installation is WHQL certifed or non-WHQL certified aka attest-signed.

Refer to here for information on WHQL certified vs Intel attest-signed graphics driver: [What Is the Difference between WHQL and Non-WHQL Certified Graphics Drivers?](https://www.intel.com/content/www/us/en/support/articles/000093158/graphics.html#summary)

## Running Windows10 Automated Install
**Note: VM will restart multiple times and finally shutdown automatically after completion. Installation may take some time, please be patient. 
As part of windows installation process VM may be restarted in SR-IOV mode for installation of SR-IOV required drivers in the background. At this stage VM will no longer have display on virt-viewer UI nor on VNC. Instead VM display could be found on host platform physical monitor.
DO NOT interfere or use VM before setup script exits successfully.**

        Command Reference:
        win10_setup.sh [-h] [-p] [--no-sriov] [--non-whql-gfx] [--force] [--viewer] [--debug]
        Create Windows vm required images and data to dest folder /var/lib/libvirt/images/windows.qcow2
        Place required Windows installation files as listed below in guest_setup/ubuntu/unattend_win10 folder prior to running.
        (windowsNoPrompt.iso4, windows-updates.msu4, ZCBuild_MSFT_Signed.zip4, Driver-Release-64-bit.[zip|7z])
        Options:
                -h                show this help message
                -p                specific platform to setup for, eg. "-p client "
                                  Accepted values:
                                    client
                                    server
                --no-sriov        Non-SR-IOV windows install. No GFX/SRIOV support to be installed
                --non-whql-gfx    GFX driver to be installed is non-WHQL signed but test signed
                --force           force clean if windows vm qcow is already present
                --viewer          show installation display
                --debug           Do not remove temporary files. For debugging only.


This command will start Windows guest VM install from Windows installer. Installation progress can be tracked in the following ways:
- "--viewer" option which display VM on virt-viewer
- via remote VNC viewer of your choice by connect to <VM_IP>:5902. VM ip address can be found using the command:
    virsh domifaddr windows

### Automated SRIOV Install with WHQL Certified Graphics Driver
If platform Intel GPU driver available for platform is WHQL certified, run below command to start Windows VM automated install from a GUI terminal on host platform.

        ./guest_setup/ubuntu/win10_setup.sh -p client --force --viewer


### Automated SRIOV Install with Intel Attest-signed Graphics Driver
If platform Intel GPU driver available for platform is non-WHQL certified (Intel attest-signed driver), run below command to start Windows VM automated install from a GUI terminal on host platform.

        ./guest_setup/ubuntu/win10_setup.sh -p client --non-whql-gfx --force --viewer


### Windows10 Non-SR-IOV Automated Install 
For Windows guest VM without Intel GPU SR-IOV drivers, run below command to start Windows VM automated install from a terminal.

        ./guest_setup/ubuntu/win10_setup.sh -p client --no-sriov --force --viewer


# Launching Windows VM
Windows VM can be run with different display support as per below examples.
Refer to [here](README.md#vm-management) for more details on VM managment.

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

# Table of Contents
1. [VM Installation](#vm-installation)
    1. [Manual Installation of Windows VM and Dependencies](#manual-installation-of-windows-vm-and-dependencies)
        1. [Prerequisites for Manual Install Steps](#prerequisites-for-manual-install)
        1. [Manual Install Steps](#manual-install-steps)
    1. [Automated Unattended Windows VM Installation](#automated-unattended-windows-vm-installation)
        1. [Prerequisites for Automated Unattended Installation](#prerequisites-for-automated-unattended-installation)
            1. [NoPrompt Windows Installation ISO Creation](#noprompt-windows-installation-iso-creation)
            1. [Getting Ready for Automated Unattended Install](#getting-ready-for-automated-unattended-install)
        1. [Running Windows Automated Unattended Install](#running-windows-automated-unattended-install)
            1. [SRIOV with WHQL Certified Graphics Driver Install](#sriov-with-whql-certified-graphics-driver-install)
            1. [SRIOV with Intel Attest-signed Graphics Driver Install](#sriov-with-intel-attest-signed-graphics-driver-install)
            1. [Non-SR-IOV Install](#non-sr-iov-install)
1. [Launching Windows VM](#launching-windows-vm)

# VM Installation

Windows guest VM installation can be either via:
  - Manual installation of guest VM with/or required dependencies.

      Choose this option if you:
      - already have ready a Windows VM image with required Windows version with KVM virtio paravirtualization drivers installed and only wish to install additional dependencies OR
      - wish to manually customise Windows guest installation options and all dependency installations.

***OR***

  - Automated unattended installation of Windows VM

      Choose this option if you:
      - want a fully unattended install of Windows VM image from Microsoft installer ISO with all dependencies installed with zero human intervention during installation.

      ***Notes***
      - Image has default autologon user with default password as set in guest_setup/ubuntu/unattend_winXX/autounattend.xml file \<AutoLogon\> entry. Can be modified in autounattend.xml file.
      - Image has OpenSSH enabled as set in guest_setup/ubuntu/unattend_winXX/autounattend.xml file. Can be removed by modifying autounattend.xml file.
      - Image has other Intel peripherals (Wi-Fi/Bluetooth/TSN Ethernet) drivers installed. Can be customised/removed by editing/removing guest_setup/ubuntu/unattend_winXX/additional_installs.yml file.
      - OS variant installed from ISO as specified by "\<InstallFrom\>" entry of guest_setup/ubuntu/unattend_winXX/autounattend.xml.

          ***Notes:***
          - If installation stops at OS selection screen, please ensure \<InstallFrom\> entry in autoattend.xml is set correctly to provided OS image name in installation ISO being used. "ImageX.exe /info" (available from Windows ADK) command could be used to check OS image name entry as encoded in install.wim file in ISO file being used for installation.
          - For \<InstallFrom\> entry reference: see [InstallFrom (microsoft-windows-setup-imageinstall-osimage-installfrom)](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-imageinstall-osimage-installfrom)
      - For Microsoft autounattend XML schema reference: refer to [Microsoft Unattended Windows Setup Reference](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/)

## Manual Installation of Windows VM and Dependencies
### Prerequisites for Manual Install
Required:
- Either Microsoft Windows IoT Enterprise installer ISO downloaded from Microsoft website OR preinstalled Windows guest VM qcow2 image file (of version as supported stated in host platform BSP release guide).
- Windows update OS patch msu file as per host platform release guide if not already installed in existing Windows guest VM qcow2 image file.
- Intel Graphics driver 64bit release 7z/zip archive for host platform as stated in host platform release guide.
- Intel Graphics SR-IOV ZeroCopy driver zip archive for host platform as stated in host platform release guide.

Host platform DUT setup:
- Host platform have physical display monitor connection with working display prior to installation run.
- Host platform is setup as per platform release BSP guide and booted accordingly to GUI desktop after login.
- Host platform has network connection and Internet access and proxy variables (http_proxy, https_proxy, no_proxy) are set appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. Running "sudo apt update" worked successfully.
- Host platform date/time is set up properly to current date/time.
- Host platform is already setup for using KVM MultiOS Portfolio release as per instructions [here](README.md#host-setup).
- User is already login to UI homescreen prior to any operations or user account is set to enable auto-login (required for VM support with Intel GPU SR-IOV).

### Manual Install Steps
1. Prepare and launch Windows VM guest image by following ***one of below two*** steps depending on whether: wish to reuse existing Windows VM qcow2 image file ***OR*** wish to manually install Windows VM image from Microsoft installer ISO:

    - ***Follow this step if and only if wish to reuse existing Windows VM qcow2 image file*** with host platform supported Windows OS version as per host platform release guide, proceed with sub-steps below. Otherwise, skip to next step for fresh manual installation.

        ***Notes***
        - \<path to respository source code directory on host machine\> in below command(s) refers to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
        - Default Windows VM configuration xml provided in this release uses Virtio disk interfaces for performance. As such, this requires any reused qcow2 image to be able to boot from Virtio disk for VM to be launched successfully.

            If reused qcow2 image is not installed to Virtio disk, additional steps given could be followed to modify disk emulation model in Window VM definition XML file to allow booting from existing qcow2 image's boot disk.
            Otherwise, modification to defaults in Windows VM definition XML file is required if do not wish to convert.

        - Default Windows VM configuration xml provided in this release uses Virtio NIC network interface emulation for performance. As such, this requires any reused qcow2 image to have KVM Virtio paravirtualization driver pre-installed for working network connection.

            If reused qcow2 image is not pre-installed with virtio network driver, please follow additional steps given to modify network nic emulation model in Window VM definition XML file to change network nic model to whatever is supported in reused qcow image, eg. Intel e1000e NIC emulation.
            Otherwise, modification to defaults in Windows VM definition XML file is required if do not wish to install required drivers.

        - Refer to [VM Misc Operations](README.md#vm-misc-operations) for virsh commands for misc VM operations.
        - Refer to [Guest OS Domain Naming Convention, MAC and IP Address](README.md#guest-os-domain-naming-convention-mac-and-ip-address) for VM defaults used in this release.

        ***Sub-steps to launch Windows VM with existing Windows VM qcow2 file:***

        1. ***Run this step if and only if existing qcow2 image is not installed to boot from Virtio disk***

            Edit \<target\> child element of \<disk\> XML element in Windows VM xml to correct bus disk interface emulation type during Windows installation of reused qcow2 image.

            ***Notes***
            - For Windows 10 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows_vnc_spice_ovmf.xml.
            - For Windows 11 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows11_vnc_spice_ovmf.xml.
            - Reference to libvirt XML schema: https://libvirt.org/formatdomain.html
            - the XML maybe edited back to use virtio disk after KVM Virtio paravirtualization drivers dependency installation if so desired.

            For example, if installed boot disk of existing qcow2 image is sata disk "sda" instead of virtio disk, change XML like below:

            Default \<target\> XML child element set to use virtio disk:
            ```
            <disk type="file" device="disk">
              ...
              <target dev="vda" bus="virtio"/>
            </disk>
            ```
            Update \<target\> XML child element set to use SATA disk "sda":
            ```
            <disk type="file" device="disk">
              ...
              <target dev="sda" bus="sata"/>
            </disk>
            ```

        1. ***Run this step if and only if existing qcow2 image does not have Virtio network driver installed***

            Edit \<model\> child element of \<interface\> XML element with child attribute "type=network" in Windows VM xml to change to supported NIC emulation model as supported in reused qcow2 image.

            ***Notes***
            - For Windows 10 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows_vnc_spice_ovmf.xml.
            - For Windows 11 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows11_vnc_spice_ovmf.xml.
            - Reference to libvirt XML schema: https://libvirt.org/formatdomain.html
            - the XML maybe edited back to use virtio network after KVM Virtio paravirtualization drivers dependency installation if so desired.

            For example, to change to Intel legacy e1000e PCIe NIC emulation, change XML like below:
            Default \<model\> XML child element set to use virtio network:
            ```
            <interface type="network">
              ...
              <model type="virtio"/>
            </interface>
            ```
            Update type attribute of \<model\> XML child element to use Intel e1000e NIC emulation or whichever is supported by reused qcow2 image:
            ```
            <interface type="network">
              ...
              <model type="e1000e"/>
            </interface>
            ```

        1. Copy Windows image qcow2 file to <LIBVIRT_DEFAULT_IMAGES_PATH>.

            Where for Ubuntu host:

                LIBVIRT_DEFAULT_IMAGES_PATH=/var/lib/libvirt/images/

        2. Rename copied Windows VM qcow2 image file in LIBVIRT_DEFAULT_IMAGES_PATH to:

            - If VM image OS version is Windows 10, rename to: "windows.qcow2"
            - If VM image OS version is Windows 11, rename to: "windows11.qcow2"

        3. Launch windows guest by running the below command for the corresponding Windows OS version in a bash shell in host machine:

            ***Notes:***
            - Replace \<path to respository source code directory on host machine\> in below command(s) to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.

            If VM is Windows 10:
            ````
            cd <path to this repository source code directory on host machine>
            ./platform/client/launch_multios.sh -f -d windows
            ````

            If VM is Windows 11:
            ````
            cd <path to this repository source code directory on host machine>
            ./platform/client/launch_multios.sh -f -d windows11
            ````

        4. Open a graphics terminal on host machine to run below virt-viewer command corresponding to Window VM OS version to view Windows VM display.

            ***Notes:***
            - Replace \<path to respository source code directory on host machine\> in below command(s) to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.

            If VM is Windows 10:
            ````
            cd <path to this repository source code directory on host machine>
            virt-viewer -w -r --domain-name windows
            ````

            If VM is Windows 11:
            ````
            cd <path to this repository source code directory on host machine>
            virt-viewer -w -r --domain-name windows11
            ````

        1. After reach Windows login screen, proceed with rest of dependencies setup below.

    - ***Follow this step if and only if wish to create fresh Windows VM image by manually run Windows installation from Microsoft installer ISO*** ONLY (aka. not reusing existing VM qcow2 image file), follow sub-steps below.

        ***Sub-steps to manually install fresh Windows VM image from boot ISO:***

        1. Download virtio-win.iso from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win.iso to temporary path in host machine.

        1. Run Windows guest installation with below virt-install command corresponding to desired Windows VM OS version in a graphical terminal window or bash shell in host machine (replace values accordingly).

            ***Notes:***
            - Replace <PATH_TO_WIN_INSTALLER_ISO> in command with path to Microsoft windows installer ISO file on host machine.
            - Replace <PATH_TO_VIRTIO_WIN_ISO> in command with path to virtio-win ISO file downloaded in earlier step on host machine.
            - Replace <SETUP_DISK_SIZE> in command with disk size in Gb for VM image. Eg. 60 for size of 60 Gb
            - For host is installed with Ubuntu OS:
                - Replace <LIBVIRT_DEFAULT_IMAGES_PATH> in command with "/var/lib/libvirt/images"
                - Replace <OVMF_DEFAULT_PATH> in command with"/usr/share/OVMF"
            - If command was run from a graphical terminal window in host machine, there will pop up a new window by default with VM display in host machine UI.
            - VM display during installation could also be viewed on at host machine IP address + port 5901 on any VNC viewer.

            Use below command if Windows VM OS version is Windows 10:
            ```
            virt-install \
            --name="windows" \
            --ram=4096 \
            --vcpus=4 \
            --cpu host \
            --machine q35 \
            --network network=default \
            --graphics vnc,listen=0.0.0.0,port=5901 \
            --cdrom "<PATH_TO_WIN_INSTALLER_ISO>" \
            --disk path="<LIBVIRT_DEFAULT_IMAGES_PATH>/windows.qcow2",format=qcow2,size=<SETUP_DISK_SIZE>,bus=virtio,cache=none \
            --disk path="<PATH_TO_VIRTIO_WIN_ISO>",device=cdrom \
            --os-variant win10 \
            --boot loader="<OVMF_DEFAULT_PATH>/OVMF_CODE_4M.ms.fd",loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template="<OVMF_DEFAULT_PATH>/OVMF_VARS_4M.fd" \
            --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
            --pm suspend_to_mem.enabled=off,suspend_to_disk.enabled=on \
            --features smm.state=on \
            --autoconsole graphical \
            --wait
            ```

            Use below command if Windows VM OS version is Windows 11:
            ```
            virt-install \
            --name="windows11" \
            --ram=4096 \
            --vcpus=4 \
            --cpu host \
            --machine q35 \
            --network network=default \
            --graphics vnc,listen=0.0.0.0,port=5901 \
            --cdrom "<PATH_TO_WIN_INSTALLER_ISO>" \
            --disk path="<LIBVIRT_DEFAULT_IMAGES_PATH>/windows11.qcow2",format=qcow2,size=<SETUP_DISK_SIZE>,bus=virtio,cache=none \
            --disk path="<PATH_TO_VIRTIO_WIN_ISO>",device=cdrom \
            --os-variant win11 \
            --boot loader="<OVMF_DEFAULT_PATH>/OVMF_CODE_4M.ms.fd",loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template="<OVMF_DEFAULT_PATH>/OVMF_VARS_4M.fd" \
            --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
            --pm suspend_to_mem.enabled=off,suspend_to_disk.enabled=on \
            --features smm.state=on \
            --autoconsole graphical \
            --wait
            ```

        1. Follow Microsoft on screen instructions to install Windows in the pop up window via "Custom: Install Windows only (advanced)" option.

            ***Notes***
            - There will not be any destination drive detected in "Where do you want to install Windows" installation dialog screen if Windows ISO used does not have Virtio disk driver viostor loaded by default.
            - Follow next step to load Virtio disk driver viostor before click "Next".

            1. In "Where do you want to install Windows" dialog screen, follow below sub-steps to load KVM virtio disk driver viostor for virtio disk to be used as installation destination.

                1. select "Load Driver" in dialog and click "Browse" to open "Browse to Folder" dialog.

                    ***Notes***
                    - "Red Hat VirtIO SCSI controller in virtio-win CD drive viostor folder should be shown as one of drivers to install after below step.

                1.  Browse to "virtio-win" CD drive, "viostor" folder and select the folder corresponding to Windows OS version.

                    ***Notes***
                    - For Windows 10, browse to "w10/amd64" and click "OK".
                    - For Windows 11, select "w11/amd64" and click "OK".

                1.  Click "Next" to start driver load in Windows installation.

                     ***Notes***
                     Windows installation should return to "Where do you want to install Windows" screen after driver is loaded.

        1. In "Where do you want to install Windows" installation dialog screen, select Drive0 drive which is present for install destination and click "Next".

        1. Proceed with rest of Windows installation as per Microsoft instructions.

        1. After booted into Windows login screen, proceed with rest of dependencies setup below.

1. In Windows VM, pause Windows auto-update via Settings -> Windows Update Settings -> Pause updates for 7 days. Close and reopen Windows Update Settings dialog to check updates is paused if not reflected.

1. In Windows VM, install Windows update OS patch msu downloaded as per host platform BSP release guide if not already installed. Reboot Windows guest VM as required per installation.

1. In Windows VM, install any other software or drivers wished to use with VM if not already installed. Reboot Windows guest VM as required after installation.

1. In Windows VM, follow below sub-steps to enable Windows hibernation mode if desired.

    1. In Windows VM, start a Windows Powershell with Administrative privileges (Run as administrator) via:

        Open the Start menu, type Windows PowerShell, select Windows PowerShell, and then select Run as administrator.

    1. Run below command in opened Powershell with Adminstrative privileges to disable Safe mode for next boot.

        ```
        powercfg.exe /HIBERNATE ON
        ```

1. Follow below sub-steps to install KVM Virtio paravirtualization drivers and other guest agents for Windows guest VM if not already installed. Refer to sub-steps below:

    ***Notes***
    - After installation completed, the guest agents and Virtio paravirtualization drivers pass usage information to KVM/QEMU and enable you to access USB devices and other functionality.
    - Provided Windows VM definition XML in this release default to using virtio disk for VM boot disk for performance. If reusing VM qcow2 image which was not installed from virtio boot disk and wish to convert to allow boot from virtio disk, additional steps for conversion are provided below to perform one-time conversion of image.

        If not wish to convert image, said additional steps could be skipped and user should modify \<disk\> element in provided Windows VM definition XMLs accordingly to switch to whatever boot disk bus interface (eg. ide/sata etc) emulation was used during installation of reused qcow2 image for further operations.
    - Reference to libvirt XML schema: https://libvirt.org/formatdomain.html

    1. ***Run this step if and only if was reusing VM qcow2 image which was installed on non-virtio emulation boot disk such as SATA/IDE disk*** (eg. VM was not installed from scratch as per manual install instructions above) ***and wish to convert reused VM image to be able to boot from virtio interface disk***.

        In host machine, run below commands to create a dummy disk image and attach as Virtio disk to running Windows VM. This is required so that Windows will load Virtio Disk driver during virtio driver installation.

        ***Notes***
        - Created dummy disk image in this step could be deleted after KVM virtio paravirtualization setup is all completed. In below example commands, it is created in /tmp in host machine as temporary file.
        - Replace <windows_vm_name> in below command with corresponding running Windows VM name as below as per Windows OS version:
            - For Windows 10 VM, <windows_vm_name> in command is "windows"
            - For Windows 11 VM, <windows_vm_name> in command is "windows11

        Command to create dummy disk image file:
        ```
        qemu-img create -f qcow2 /tmp/dummydisk.qcow2 100M
        ```
        Command to attach disk to VM with dummy disk image file:
        ```
        virsh attach-disk \
           --domain <windows_vm_name> \
           --source /tmp/dummydisk.qcow2 \
           --target vdb \
           --driver qemu \
           --subdriver raw \
           --cache none \
           --io native \
           --targetbus virtio \
           --config \
           --live
        ```

    1. If virtio-win ISO (from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win.iso) is not already present in Windows VM as CD drive, download and copy virtio-win.iso into VM.

    1. If virtio-win ISO is not already present in Windows VM as CD drive, double click virtio-win ISO iso file in Windows File Explorer to mount the iso file or extract ISO contents to a folder.

    1. In Windows VM, start a Windows Powershell with Administrative privileges (Run as administrator) via:

        Open the Start menu, type Windows PowerShell, select Windows PowerShell, and then select Run as administrator.

    1. In Windows VM, install KVM Virtio paravirtualization drivers for Windows VM via running the command below in earlier opened Powershell.

        ***Notes:***
        - Replace \<virtio-win-iso-extracted-path\> in below command with the path where virtio-win iso has been extracted or mounted to in Windows VM.
        - Installed application "Virtio-win-driver-installer" should be in Windows "Settings", "Apps & Features" list of installed apps after installation completed successfully.
        - After installation completes, the guest agents and drivers pass usage information to KVM/QEMU and enable you to access USB devices and other functionality.
        - If dummy disk image was earlier attached as virtio disk in earlier step, after installation was completed in Device Manager under Storage Controller that there will be at least 1 storage controller of type "Red Hat VirtIO SCSI Controller". This indicated the VirtIO driver is loaded. If it is not present or showing up as unknown device, please (re)install.
        - Optional: Add "/qn" option in below command -ArgumentList string if do not wish to manually interact with installer UI but only check after command completion that installation is in Windows installed apps list.
        - Warning: For Intel GPU SR-IOV with physical display for VM usage, do not use "ADDLOCAL=ALL" for virtio-win-gt-x64.msi installation as it will result in black screen on physical display for VM launched with Intel GPU SR-IOV.
        - For reference only: [Redhat virtio-win installer command ADDLOCAL reference](https://docs.redhat.com/en/documentation/red_hat_virtualization/4.4/html/virtual_machine_management_guide/installing_guest_agents_and_drivers_windows#values_for_addlocal_to_customize_virtio_win_command_line_installation)

        Powershell Command to install only Virtio drivers:
        ```
        Start-Process msiexec.exe -Wait -ArgumentList '/i "<virtio-win-iso-extracted-path>\virtio-win-gt-x64.msi" ADDLOCAL="FE_network_driver,FE_balloon_driver,FE_pvpanic_driver,FE_qemupciserial_driver,FE_vioinput_driver,FE_viorng_driver,FE_vioscsi_driver,FE_vioserial_driver,FE_viostor_driver"'
        ```

    1. In Windows VM, install QEMU Guest agent service for Windows VM via running below command in earlier opened Windows Powershell.

        ***Notes:***
        - Replace \<virtio-win-iso-extracted-path\> in below command with the path where virtio-win iso has been extracted or mounted to in Windows VM.
        - Installed application "QEMU guest agent" should be seen in Windows "Settings", "Apps & Features" in list of installed apps after installation completed.
        - Optional: Add "/qn" option in below command -ArgumentList string if do not wish to manually interact with installer UI but only check after command completion that installation is in Windows installed apps list.

        Command:
        ```
        Start-Process msiexec.exe -ArgumentList '/i "<virtio-win-iso-extracted-path>\guest-agent\qemu-ga-x86_64.msi"'
        ```

    1. ***Run this step if and only if reusing existing qcow2 image which did not have Virtio network driver installed and had modified Windows VM definition XML file earlier, and now wish to restore to using virtio network connection for performance***.

       Edit \<model\> child element of \<interface\> XML element with child attribute "type=network" in Windows VM xml file to modify to NIC emulation as virtio network.

        ***Notes***
        - For Windows 10 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows_vnc_spice_ovmf.xml.
        - For Windows 11 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows11_vnc_spice_ovmf.xml.
        - Reference to libvirt XML schema: https://libvirt.org/formatdomain.html
        - the XML maybe edited back to use virtio network after KVM Virtio paravirtualization drivers dependency installation if so desired.

        Default \<model\> XML child element set to use virtio network:
        ```
        <interface type="network">
          ...
          <model type="virtio"/>
        </interface>
        ```

    1. ***Run below sub-steps if and only if was reusing VM qcow2 image which was installed on non-virtio boot disk*** such as SATA/IDE disk (aka. VM was not installed from scratch as per manual install instructions above) ***and wishes to convert reused VM image to be able to boot from virtio disk***.

        ***Sub-steps to convert image to boot from virtio boot disk***

        1. In Windows VM, run below command in earlier Powershell opened with Adminstrative rights to set Windows VM next boot to safeboot mode so that virtio drivers will be loaded in VM image on next bootup.

            ```
            bcdedit /set "{current}" safeboot minimal
            ```

        1. In Windows VM, shutdown Windows VM via:

            Open the Start Menu, select Power icon, select "Shut down".

        1. Edit \<target\> child element of \<disk\> XML element in Windows VM XML file corresponding to Windows OS version back so that boot disk is set as VirtIO disk if was modified earlier to non-virtio disk.

            ***Notes***
            - For Windows 10 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows_vnc_spice_ovmf.xml.
            - For Windows 11 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows11_vnc_spice_ovmf.xml.
            - For reference only: libvirt XML schema: https://libvirt.org/formatdomain.html

            Update \<target\> XML child element to use virtio disk:
            ```
            <disk type="file" device="disk">
              ...
              <target dev="vda" bus="virtio"/>
            </disk>
            ```

        1. Launch windows guest as defined by above modified XML file by running the below command for the corresponding Windows OS version in a bash shell in host machine:

            ***Notes:***
            - Replace \<path to respository source code directory on host machine\> in below command(s) to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
            - launch_multios.sh helper script will always undefine VM and redefine and launch VM as defined per XML file.
            - dummydisk.qcow2 created in earlier step is now redundant and can be removed after VM launch.

            Commands to run if VM OS version is Windows 10:
            ````
            cd <path to this repository source code directory on host machine>
            ./platform/client/launch_multios.sh -f -d windows
            ````

            Commands to run if VM OS version is Windows 11:
            ````
            cd <path to this repository source code directory on host machine>
            ./platform/client/launch_multios.sh -f -d windows11
            ````

        1. Open a graphics terminal on host machine to run below virt-viewer command corresponding to Window VM OS version to view Windows VM display.

            ***Notes:***
            - Replace \<path to respository source code directory on host machine\> in below command(s) to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
            - Windows will boot in Safe mode, scan and correct C: drive and devices, before finally reboot into safe mode UI login screen after successful completion.

            Commands to run if VM OS version is Windows 10:
            ````
            cd <path to this repository source code directory on host machine>
            virt-viewer -w -r --domain-name windows
            ````

            Commands to run if VM OS version is Windows 11:
            ````
            cd <path to this repository source code directory on host machine>
            virt-viewer -w -r --domain-name windows11
            ````

        1. In Windows VM, right click on Start Menu -> Run -> Enter "powershell" to start a Windows Powershell with Administrative privileges (Run as administrator) via:

            Open the Start menu, type Windows PowerShell, select Windows PowerShell, and then select Run as administrator.

        1. Run below command in opened Powershell with Adminstrative privileges to disable Safe mode for next boot.

            ```
            bcdedit /set "{current}" safeboot minimal
            ```

        1. In Windows VM, right click on Start Menu -> Shutdown or restart -> Restart to restart VM.

            VM should boot into normal boot UI after restart.

    1. In Windows VM, shutdown Windows VM via:

        Open the Start Menu, select Power icon, select "Shut down".

1. If wish to use VM with Intel GPU SR-IOV, manually install all Intel GPU SR-IOV dependencies and setup if not already installed with by following sub-steps below:

    1. Generate Intel GPU SR-IOV dependencies installation helper script via a bash shell on host machine. This will be used later in subsequent steps.

        ***Notes***
        - Check host platform release guide to see if Intel GPU driver is a WHQL-certified driver or Intel Attest-signed Graphics Driver and select corresponding command below as required setup is different for these two types of driver.
        - Replace \<path to respository source code directory on host machine\> in below command(s) to path in host machine where KVM MultiOS libvirt portfolio release source code directory as downloaded from github.
        - Replace \<winxx_setup_script\> in below command(s) depending on Window 10 or Windows 11 VM:
            - If Windows 10 VM: replace with "win10_setup.sh"
            - If Windows 11 VM: replace with "win11_setup.sh"
        - Following helper script will be generated in below folder in host machine after command is run:
            - For Windows 10 command: \<path to respository source code directory on host machine\>\guest_setup\ubuntu\unattend_win10\gfx_zc_install.ps1
            - For Windows 11 command: \<path to respository source code directory on host machine\>\guest_setup\ubuntu\unattend_win11\gfx_zc_install.ps1
        - Warning: Non-WHQL certified or Intel Attest-signed driver package will require Windows test-signing mode enabled to work and will be enabled by generated helper script accordingly.

        ***Command to use when Intel GPU driver package is installer with WHQL-certified drivers:***
        ```
        cd <path to this repository source code directory on host machine>
        .\guest_setup\ubuntu\<winxx_setup_script> --gen-gfx-zc-script
        ```

        ***Commands to use depending on Intel GPU driver package is installer or non-installer package with Intel Attest-signed drivers:***
        - For package without installer, use
            ```
            cd <path to this repository source code directory on host machine>
            .\guest_setup\ubuntu\<winxx_setup_script> --non-whql-gfx --gen-gfx-zc-script
            ```

        - For package with installer provided, use
            ```
            cd <path to this repository source code directory on host machine>
            .\guest_setup\ubuntu\<winxx_setup_script> --non-whql-gfx-installer --gen-gfx-zc-script
            ```

    1. ***Run this step if and only if reusing existing qcow2 image which was not installed to boot from Virtio disk and did not convert to Virtio boot disk*** in earlier "KVM virtio paravirtualization drivers and dependencies" installation step.

        Edit \<target\> child element of \<disk\> XML element in Windows VM xml to correct bus disk interface emulation type during Windows installation of reused qcow2 image.

        ***Notes***
        - For Windows 10 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows_sriov_ovmf.xml.
        - For Windows 11 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows11_sriov_ovmf.xml.
        - Reference to libvirt XML schema: https://libvirt.org/formatdomain.html

        For example, if installed boot disk of existing qcow2 image is sata disk "sda" instead of virtio "vda" disk, change XML like below:

        Default \<target\> XML child element set to use virtio disk:
        ```
        <disk type="file" device="disk">
          ...
          <target dev="vda" bus="virtio"/>
        </disk>
        ```
        Updated \<target\> XML child element set to use SATA disk "sda":
        ```
        <disk type="file" device="disk">
          ...
          <target dev="sda" bus="sata"/>
        </disk>
        ```

    1. ***Run this step if and only if reused qcow2 image does not have Virtio network driver installed, and did not install virtio network driver*** in above "KVM virtio paravirtualization drivers" dependency installation step.

        Edit \<model\> child element of \<interface\> XML element with child attribute "type=network" in Windows VM xml to change to supported NIC emulation model as supported in reused qcow2 image.

        ***Notes***
        - For Windows 10 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows_vnc_spice_ovmf.xml.
        - For Windows 11 VM, file to modify is \<path to respository source code directory on host machine\>\platform\client\libvirt_xml\windows11_vnc_spice_ovmf.xml.
        - Reference to libvirt XML schema: https://libvirt.org/formatdomain.html
        - the XML maybe edited back to use virtio network after KVM Virtio paravirtualization drivers dependency installation if so desired.

        For example, to change to Intel legacy e1000 NIC emulation, change XML like below:
        Default \<model\> XML child element set to use virtio network:
        ```
        <interface type="network">
          ...
          <model type="virtio"/>
        </interface>
        ```
        Update type attribute of \<model\> XML child element to use Intel e1000 emulation:
        ```
        <interface type="network">
          ...
          <model type="e1000e"/>
        </interface>
        ```

    1. Start Windows guest with Intel GPU SR-IOV enabled by running below command corresponding to Windows VM OS version in a bash shell on host machine.

        ***Notes***
        - Replace \<path to respository source code directory on host machine\> to the path of where KVM MultiOS libvirt portfolio release source code directory as downloaded from github in below commands.
        - Windows VM display will come up on a new QEMU Window in physical monitor display on host machine graphical UI.
        - Wait for VM display to become active and boot to Windows UI login screen.
        - Enabling Windows Remote Connection via "Remote Desktop Settings" could help with debugging if VM with Intel GPU SR-IOV on physical display is not working after installation.
        - For reference only: refer to [VM Misc Operations](README.md#vm-misc-operations) for virsh commands for other misc VM operations if desired.
        - For reference only: refer to [Guest OS Domain Naming Convention, MAC and IP Address](README.md#guest-os-domain-naming-convention-mac-and-ip-address) for VM defaults used in this release.

        To start Windows 10 VM with Intel GPU SR-IOV:
        ```
        cd <path to repository source code directory on host machine>
        ./platform/client/launch_multios.sh -f -d windows -g sriov windows
        ```

        To start Windows 11 VM with Intel GPU SR-IOV:
        ```
        cd <path to repository source code directory on host machine>
        ./platform/client/launch_multios.sh -f -d windows11 -g sriov windows11
        ```

    1. In Windows VM, create a temporary directory to store all installation files and scripts, such as  "C:\Temp".

        ***Notes***
        - All subsequent steps refer to this created temporary directory as "\<path_to_temp_dir_in_win_vm\>".

    1. In Windows VM. download Intel GPU SR-IOV Zero-copy driver archive as per host platform release specified download link into earlier created \<path_to_temp_dir_in_win_vm\> directory. Extract all contents to path ***"\<path_to_temp_dir_in_win_vm\>" without any additional folder name***.

        ***Notes***
        - ***"\<path_to_temp_dir_in_win_vm\>*** is folder path where generated gfx_zc_install.ps1 helper script will look for Zero-Copy driver installation in.
        - Zero-Copy driver installation contents already is in folder by default after extraction.

    1. If required Intel GPU driver is not yet installed in Windows VM, download Intel GPU driver package as per host platform release specified download link into earlier created \<path_to_temp_dir_in_win_vm\> directory and extract all contents to path ***"\<path_to_temp_dir_in_win_vm\>\GraphicsDriver"***.

        ***Notes***
        - ***"\<path_to_temp_dir_in_win_vm\>\GraphicsDriver"*** is folder path where generated gfx_zc_install.ps1 helper script will look for graphics driver installer in.

    1. In Windows VM, copy gfx_zc_install.ps1 helper script generated in earlier step corresponding to Windows VM OS version into ***same \<path_to_temp_dir_in_win_vm\> directory*** in VM.

        ***Notes***
        - Earlier step should have generated helper script in below folder in host machine:
            - For Windows 10 command: \<path to respository source code directory on host machine\>\guest_setup\ubuntu\unattend_win10\gfx_zc_install.ps1
            - For Windows 11 command: \<path to respository source code directory on host machine\>\guest_setup\ubuntu\unattend_win11\gfx_zc_install.ps1
            - If Windows VM already has required GPU driver package installed and thus wish to skip install by helper gfx_zc_install.ps1 script, modify script in VM to set $SkipGFXInstall variable like below to skip GFX driver installation:
                ```
                # Skip GFX driver package install
                $SkipGFXInstall=$True
                ```

    1. In Windows VM, start a Windows Powershell with Administrative privileges (Run as administrator) via:

        Open the Start menu, type Windows PowerShell, select Windows PowerShell, and then select Run as administrator.

    1. In Windows VM opened Windows Powershell with Administrative privileges, change directory to \<path_to_temp_directory_in_win_vm\> and enable powershell script execution. Answer (Y)es to resulting user prompt before proceeding with next step in this opened Powershell window.

        Powershell Commands:
        ```
        cd <path_to_temp_directory_in_win_vm>
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted
        ```

        Powershell Output Example:
        ```
        Execution Policy Change
        The execution policy helps protect you from scripts that you do not trust. Changing the execution policy might expose
        you to the security risks described in the about_Execution_Policies help topic at
        https:/go.microsoft.com/fwlink/?LinkID=135170. Do you want to change the execution policy?
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"): Y
        ```

    1. In opened Windows Powershell from above step, run Intel GPU Intel SR-IOV depdencies setup helper script.

        ***Notes***
        - Windows VM will reboot after installation.

        Command to run helper installation script:
        ```
        cd <path_to_temp_directory_in_win_vm>
        .\gfx_zc_install.ps1
        ```

    1. In Windows VM after successful installation, check that

        - In Windows Device Manager, below devices should be loaded properly and has no errors:
            - "Display Adapter -> Intel xxx Graphics"
            - "Display Adapter -> DVServerUMD Device"
            - "System -> DVServerKMD driver"
        - In Windows Task Manager, GPU tab is showing correct information.

    1. In Windows VM after successfull installation, resume the Windows updates via "Update & Security" > "Windows Update" > “Resume updates”.

## Automated Unattended Windows VM Installation
The automated unattended Windows guest VM installation will perform the following:
- install Windows from Windows installer iso (modified for No Prompt installation).
- configure VM for KVM MultiOS Portfolio release supported features.
- install Windows GFX and SR-IOV ZeroCopy drivers for Intel GPU (unless --no-sriov option is given).

The created image is default able to work launching Windows VM with GPU SR-IOV virtualization (unless --no-sriov option is given).

**
Information:  
- For using created image with GVT-d, user may need to re-run Intel graphics installer after launching Windows VM with GVT-d via Remote Desktop connection to the VM, then reboot VM to get physical display output with GVT-d. **

### Prerequisites for Automated Unattended Installation
Required:
- Windows noprompt installer iso file created in [NoPrompt Windows Installation ISO Creation](#noprompt-windows-installation-iso-creation).
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
- User is already login to UI homescreen prior to any operations or user account is set to enable auto-login (required for VM support with Intel GPU SR-IOV).

#### NoPrompt Windows Installation ISO Creation
Windows installation iso as downloaded from Windows direct is not suitable for unattended install as it requires human intervention to respond to a "Press Any Key To Boot From..." prompt from iso installation.
To get around this, an NoPrompt Windows installation iso needs to be generated once from the actual installation iso provided by Windows download for unattended Windows installation. This generated ISO could be used for multiple installations across releases for same Windows VM OS version.

The generation of NoPrompt installation iso requires use of a Windows machine with Windows ADK toolkit correspoding to the Windows VM OS version installed.
Reference: https://www.deploymentresearch.com/a-good-iso-file-is-a-quiet-iso-file

1. On any windows machine, install [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install#choose-the-right-adk-for-your-scenario) in Windows machine corresponding to OS version of WindowsInstaller.iso used for generation of WindowsInstallerNoPrompt.iso.

    ***Notes***
    - During ADK installation, take note of ADK installation destination path for use in later step.

    | Windows Version | Window ADK Download |
    | :-- | :-- |
    | Windows 10 IoT Enterprise LTSC 21H2 | [Windows ADK for Windows 10, version 2004](https://go.microsoft.com/fwlink/?linkid=2120254)</br>[Windows PE add-on for the ADK, version 2004](https://go.microsoft.com/fwlink/?linkid=2120253)|
    | Windows 11 IoT Enterprise 22H2 | [Windows ADK for Windows 11, version 22H2](https://go.microsoft.com/fwlink/?linkid=2196127)</br>[Windows PE add-on for the ADK, version 22H2](https://go.microsoft.com/fwlink/?linkid=2196224)|

1. Download and save Create-NoPromptISO.ps1 helper script from [here](https://github.com/DeploymentResearch/DRFiles/raw/906151a1cdd55a14bc226196a3f597b0538273dd/Scripts/Create-NoPromptISO.ps1) onto windows machine.

1. Edit $WinPE_InputISOfile, $WinPE_OutputISOfile and $ADK_Path of CreateNoPromptISO.ps1 script as per notes below.

    ***Notes***
    - $WinPE_InputISOfile set to path to input WindowsInstaller.iso file to generate from.
    - $WinPE_OutputISOfile set to output filename of output WindowsInstallerNoPrompt.iso file to generate to.
    - $ADK_PATH set to ADK installation destination path from earlier step. Eg. "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit" for windows 10.

    Contents of CreateNoPromptISO.ps1 to be modified:
    ```
    ...
    $WinPE_InputISOfile = "<Path_to_input_WindowsInstaller.iso>"
    $WinPE_OutputISOfile = "<Path_to_output_WindowsInstallerNoPrompt.iso>"

    $ADK_Path = "<Path_to_ADK_installation_destination_folder_in_windows_machine>"
    ...
    ```

1. In Windows VM, start a Windows Powershell with Administrative privileges (Run as administrator) via:

    Open the Start menu, type Windows PowerShell, select Windows PowerShell, and then select Run as administrator.

1. In Windows VM opened Windows Powershell with Administrative privileges, change directory to \<path_to_temp_directory_in_win_vm\> and enable powershell script execution. Answer (Y)es to resulting user prompt before proceeding with next step in this opened Powershell window.

    Powershell Commands:
    ```
    cd <path_to_temp_directory_in_win_vm>
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted
    ```

    Powershell Output Example:
    ```
    Execution Policy Change
    The execution policy helps protect you from scripts that you do not trust. Changing the execution policy might expose
    you to the security risks described in the about_Execution_Policies help topic at
    https:/go.microsoft.com/fwlink/?LinkID=135170. Do you want to change the execution policy?
    [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"): Y
    ```

1. Run earlier modified CreateNoPromptISO.ps1 script in opened Powershell in windows machine:

    ```
    cd <Path_to_modified_CreateNoPromptISO.ps1>
    .\CreateNoPromptISO.ps1
    ```

The noprompt installation iso will be generated at path as set to $WinPE_OutputISOfile variable in CreateNoPromptISO.ps1 script. This iso can be used for all Windows unattended installations of the same version between releases.

#### Getting Ready for Automated Unattended Install

All required files needed for unattended install needs to be present in \<unattend_winXX\> folder on the Intel host machine which is to run the guest VM.

***Notes***
- All the folders mentioned below are relative to the git repository
    - For Windows 10 VM, \<path_to_unattend_winXX_folder\> is "./guest_setup/ubuntu/unattend_win10"
    - For Windows 11 VM, \<path_to_unattend_winXX_folder\> is "./guest_setup/ubuntu/unattend_win11"


1. Go to the git repository folder.

    ```
    cd <git repository>
    ```

1. Copy windows noprompt installer iso to \<path_to_unattend_winXX_folder\> and name iso file as "windowsNoPrompt.iso".

    ```
    cp <windowsNoPrompt.iso> <path_to_unattend_winXX_folder>/windowsNoPrompt.iso
    ```

1. Copy required Windows update OS patch msu file to \<path_to_unattend_winXX_folder\> folder and name file as "windows-updates.msu"

    ```
    cp <windows-kbxxxxxxx-x64_xxxxxxxxxxx.msu> <path_to_unattend_winXX_folder>/windows-updates.msu
    ```

1. Copy required Intel GPU GFX driver archive to \<path_to_unattend_winXX_folder\> folder, and rename to "Driver-Release-64-bit.zip" or "Driver-Release-64-bit.7z" accordingly to original file is zip or 7z archive.

    ```
    cp <Driver-Release-64-bit.zip> /Driver-Release-64-bit.zip
    OR
    cp <Driver-Release-64-bit.7z> /Driver-Release-64-bit.7z
    ```

1. Copy required Intel GPU SR-IOV Zero-copy driver build or installer archive to \<path_to_unattend_winXX_folder\> folder and name file as "ZCBuild_MSFT_Signed.zip" or "ZCBuild_MSFT_Signed_Installer.zip" depending on original file is with or without Installer"
    ```
    cp <ZCBuild_xxxx_MSFT_Signed.zip> ./guest_setup/ubuntu/<unattend_winxx>/ZCBuild_MSFT_Signed.zip
    OR
    cp <ZCBuild_xxxx_MSFT_Signed_Installer.zip> ./guest_setup/ubuntu/<unattend_winxx>/ZCBuild_MSFT_Signed_Installer.zip
    ```

1. Configure any additional driver/windows installations by removing or modifying \<path_to_unattend_winXX_folder\>/additional_installs.yaml.

    Only installations which are capable of silent install without any user intervention required are supported for auto install.

    ***Notes***
    - If do not wish to have any additional installations at all, remove additional_installs.yaml file in \<path_to_unattend_winXX_folder\> folder prior to starting Windows Automated install where:
        - XX=10 for Windows 10 OS VM
        - XX=11 for Windows 11 OS VM
    - Currently the default additional installations are provided for:
        - Intel® Wireless Bluetooth® for IT Administrators version
        - Intel® PROSet/Wireless Software and Drivers for IT Admins
        - Intel® Ethernet Adapter Complete Driver Pack
    - If "filename" as configured in additional_installs.yaml is provided in \<path_to_unattend_winXX_folder\> folder, automated installation when run will not attempt to download it, otherwise installation process will attempt download as per configured "download_url" in additional_installs.yaml file.
    - Additional_install.yaml file has the format as below.
        ```
        installations:
          - name: # unique name (in single word) for this installation in yaml
            description: # description of installation
            filename: # filename of file in ./guest_setup/ubuntu/<unattend_winxx> folder containing install file.
                      # If file is not present, attempt to download from download_url and rename as filename.
                      # If download fails, auto install will be aborted.
            download_url: # Empty string or download url to download installation file
            install_type: # msi | exe | cab | inf
            install_file: # path to installation msi/exe/cab/inf file(s) inside archive/folder to install with
                          # If "path_to\*.inf" is used as file, all inf inside install_file path + subdirs will be installed
            silent_install_option: # '' or options required to run silent installation as per installation guide
            enable_test_sign: # yes | no.
        ````
1. Download virtio-win.iso from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win.iso into \<path_to_unattend_winXX_folder\>.

    ***Notes***
    - if virtio-win.iso is not found in \<path_to_unattend_winXX_folder\>, it will be downloaded during automatic automated install.

Now system is ready to run Windows Automated Unattended install. Proceed to run Windows automated install command as per next section.

### Running Windows Automated Unattended Install
***Notes:***
- "\<path_to_git_repository_on_host\>" in this section refers to the folder path of where this git repository source codes are found in host machine.
- "\<path_to_winXX_setup.sh\>" in this section refers to the helper scipt used to run automated unattended installation:
    - for installing Windows 10 VM, the script is: \<path_to_git_repository_on_host\>/guest/ubuntu/win10_setup.sh
    - for installing Windows 11 VM, the script is: \<path_to_git_repository_on_host\>/guest/ubuntu/win11_setup.sh
- Different command parameters of helper script is used to run Window automated unattended install depending on:
    - what type of VM support is desired
    - provided Intel GPU GFX driver package for platform is WHQL certifed or Intel attest-signed package.
    - For Intel attest-signed package, does it come with installer in package or not.
    - For reference only: information on WHQL certified vs Intel attest-signed graphics driver: [What Is the Difference between WHQL and Non-WHQL Certified Graphics Drivers?](https://www.intel.com/content/www/us/en/support/articles/000093158/graphics.html#summary)
- Following sub-sections give example of command to used to start VM automated unattended installation of VM depending on the various conditions listed above.
- Installation progress once started can be tracked in the following ways:
    - "--viewer" option which display VM on virt-viewer
    - via remote VNC viewer of your choice by connect to <Host_IP>:<VNC_PORT>, eg.
        - for Windows10, <Host_IP>:5902
        - for Windows11, <Host_IP>:5905
- VM will restart multiple times and finally shutdown automatically after installation completion. Installation may take some time, please be patient.
- As part of windows installation process VM may be restarted in SR-IOV mode for installation of SR-IOV required drivers in the background. At this stage VM will no longer have display on virt-viewer UI nor on VNC. Instead VM display could be found on host platform physical monitor.
DO NOT interfere or use VM before setup script exits successfully.

Command Reference for Windows Automated Unattended installation helper script:
```
<path_to_winXX_setup.sh> [-h] [-p] [--disk-size] [--no-sriov] [--non-whql-gfx] [--non-whql-gfx-installer] [--force] [--viewer] [--debug] [--dl-fail-exit] [--gen-gfx-zc-script]
Create Windows vm required images and data to dest folder /var/lib/libvirt/images/windows.qcow2
Place required Windows installation files as listed below in ./guest_setup/ubuntu/<unattend_winxx> folder prior to running.
(windowsNoPrompt.iso, windows-updates.msu, ZCBuild_MSFT_Signed.zip|ZCBuild_MSFT_Signed_Installer.zip, Driver-Release-64-bit.[zip|7z])
Options:
        -h                        show this help message
        -p                        specific platform to setup for, eg. "-p client "
                                  Accepted values:
                                    client
                                    server
        --disk-size               disk storage size of windows vm in GiB, default is 60 GiB
        --no-sriov                Non-SR-IOV windows install. No GFX/SRIOV support to be installed
        --non-whql-gfx            GFX driver to be installed is non-WHQL signed but test signed without installer
        --non-whql-gfx-installer  GFX driver to be installed is non-WHQL signed but test signed with installer
        --force                   force clean if windows vm qcow is already present
        --viewer                  show installation display
        --debug                   Do not remove temporary files. For debugging only.
        --dl-fail-exit            Do not continue on any additional installation file download failure.
        --gen-gfx-zc-script       Generate SRIOV setup Powershell helper script only, do not run installation.
```


### SRIOV with WHQL Certified Graphics Driver Install
If platform Intel GPU driver available for platform is WHQL certified (default always comes with installer), run below command to start Windows VM automated install from a GUI terminal on host platform.

```
<path_to_winXX_setup.sh> -p client --force --viewer
```
The default storage size of the Windows VM created is 60 GiB. To customize the size of the Windows VM, add the option --disk-size <size in GiB>
```
<path_to_winXX_setup.sh> -p client --force --viewer --disk-size <size in GiB>
```

#### SRIOV with Intel Attest-signed Graphics Driver Install
If platform Intel GPU driver available for platform is non-WHQL certified (Intel attest-signed driver), it can either come with installer provided in package or no installer provided in package.

Choose corresponding command from below to start Windows VM automated install from a GUI terminal on host platform depending if the package comes with installer or not.

***Notes***
- for non-WHQL signed driver, Windows testsigning mode will always be enabled.


Below command to be used for Intel Attest-signed Graphics Driver without installer in package:
```
<path_to_winXX_setup>.sh -p client --non-whql-gfx --force --viewer
```

Below command to be used for Intel Attest-signed Graphics Driver with installer in package:
```
<path_to_winXX_setup>.sh -p client --non-whql-gfx-installer --force --viewer
```
#### Non-SR-IOV Install
For Windows guest VM without Intel GPU SR-IOV drivers, run below command to start Windows VM automated install from a terminal.

```
<path_to_winXX_setup.sh> -p client --no-sriov --force --viewer
```

# Launching Windows VM
Windows VM can be run with different display support as per below examples.
Refer to [here](README.md#vm-management) for more details on VM managment.

**Notes:**
- Windows 10 VM domain name: windows
- Windows 11 VM domain name: windows11
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

<table>
    <tr><th align="center">Example</th><th>Description</th></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -d windows</td><td>To launch Windows10 guest VM with VNC and SPICE display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows</td><td>To force launch windows10 guest VM with VNC and SPICE display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -g sriov windows</td><td>To force launch windows10 guest VM configured with SR-IOV display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -g gvtd windows</td><td>To force launch windows10 guest VM configured with GVT-d display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows --usb keyboard</td><td>To force launch windows10 guest VM and passthrough USB Keyboard to windows10 guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows --pci wi-fi</td><td>To force launch windows10 guest VM and passthrough PCI WiFi to windows10 guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows --pci network controller 2</td><td>To force launch windows10 guest VM and passthrough the 2nd PCI Network Controller in lspci list to windows10 guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows -p windows--xml xxxx.xml</td><td>To force launch windows10 guest VM and passthrough the device(s) in the XML file to windows10 guest VM</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -d windows11</td><td>To launch Windows11 guest VM with VNC and SPICE display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows11</td><td>To force launch windows11 guest VM with VNC and SPICE display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows11 -g sriov windows11</td><td>To force launch windows11 guest VM configured with SR-IOV display</td></tr>
    <tr><td rowspan="1">./platform/xxxx/launch_multios.sh -f -d windows11 -g gvtd windows11</td><td>To force launch windows11 guest VM configured with GVT-d display</td></tr>
</table>

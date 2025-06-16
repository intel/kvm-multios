# Table of Contents
1. [Overview](#overview)
1. [Automated Android VM Installation](#automated-android-vm-installation)
    1. [Host Setup](#host-setup)
    1. [Running Automated Install](#running-automated-install)
1. [Launching Android VM](#launching-android-vm)
1. [Basic Android VM Operations](#basic-android-vm-operations)

# Overview
This page describes the steps to create and install the Android VM, along with examples of typical launch commands and basic commands to operate it.

Note:
* The KVM MultiOS Portfolio release provides only limited support for Android CiV guests.
  It is intended solely for demonstration purposes and is not validated.
  Users are encouraged to collaborate with ISV/OSV partners to evaluate and develop the solution using a reference Base Release from the Celadon Project.
  For more information, please visit:
  * [Celadon Ecosystem](https://www.intel.com/content/www/us/en/developer/topic-technology/open/celadon/ecosystem.html)
  * [Celadon Base Releases](https://projectceladon.github.io/celadon-documentation/release-notes/base-releases.html)

# Automated Android VM Installation
The automated Android VM installation will perform the following:
- Configure the host and setup all dependent services required by Android VM
- Install Android VM from the release file

## Host setup
Please ensure that the host has been setup according to the following:
- Host platform is setup as per the release BSP guide and booted accordingly.
- Host platform has network connection and Internet access. Set the proxy variables (http_proxy, https_proxy, no_proxy) appropriately in /etc/environment if required for network access.
- Host platform has Internet apt access. ie. Running "sudo apt update" works correctly.
- Host platform date/time is set up properly to the current date/time.
- Host platform is already setup for using KVM MultiOS Portfolio release as per instructions [here](README.md#host-setup).
- User is already login to UI homescreen prior to any operations, or user account is set to enable auto-login (required for VM support with Intel GPU SR-IOV).

## Running Automated Install
1. Run the following command for installing using default settings

        ./guest_setup/ubuntu/android_setup.sh -p client --forceclean -r <path to caas-releasefiles-userdebug.tar.gz>

   This script will decompress caas-releasefiles-userdebug.tar.gz and create the necessary supporting files in /var/lib/libvirt/images/android folder.

   Next, the script will create a temporary VM under the android_install domain, and use it to flash CiV from the intermediate files into the android.qcow2 image file. Note that there is no VM display during this time.

   To view the Android flashing progress in console, run:

        sudo virsh console android_install

   The Android flashing console log can be found at /var/log/libvirt/qemu/android-install-serial0.log

   **The android_install VM will automatically exit once installation has completed. The Android VM is ready to use, and the default domain is named as "android".**

   Note: To use another VM domain name, use the "--dupxml" option to duplicate xml files with a different domain name. See the example below.


2. The default storage size of the Android VM created is 40 GiB. To customize the size of the Android VM, add the option --disk-size <size in GiB>

        ./guest_setup/ubuntu/android_setup.sh -p client --forceclean -r <path to caas-releasefiles-userdebug.tar.gz> --disk-size <size in GiB>

3. To duplicate and create a second or subsequent VM with a custom domain name.

        ./guest_setup/ubuntu/android_setup.sh -p client --noinstall --dupxml -n custom_domain_name

   Note: This will skip all setup, reuse the intiial setup files and proceed directly to duplicate a VM with a custom domain name.

Command reference:

        android_setup.sh [-h] [-f] [-n] [-p] [-r] [-t] [--disk-size] [--noinstall] [--forceclean] [--dupxml] [--qemufromsrc]
        Installs Celadon system dependencies and create android vm images from CIV releasefiles archive to dest folder /var/lib/libvirt/images/<vm_domain_name>
        Options:
                -h            Show this help message
                -r            Celadon releasefiles archive file. "-r caas-releasefiles-userdebug.tar.gz". If option is present, any existing dest folder will be deleted.
                -t            Dest folder to decompress releasefiles archive into. Default: "-t ./caas-releasefiles"
                -f            Celadon flashfiles zip archive file. "Default is auto set to caas-flashfiles-xxxx.zip as found in dest folder specified by -t option"
                -n            Android vm libvirt domain name. Default: "-n android"
                -p            specific platform to setup for, eg. "-p client "
                              Accepted values:
                                client
                                server
                --disk-size   Disk storage size of Android vm in GiB, default is 40 GiB
                --noinstall   Only rebuild Android per vm required images and data output. Needs folder specified by -t option to be present and with valid contents.
                --forceclean  Delete android VM dest folder if exists. Default not enabled
                --dupxml      Duplicate Android guest XM xmls for this VM (when not using "-n android")
                --qemufromsrc Rebuild qemu from source and install (overwrites existing platform BSP installation. Do not use if unsure.)
                --suspend     Enable Android autosuspend


# Launching Android VM
Android VM can be started with different types of display support as per the examples below. Refer to [VM Management](README.md#vm-management) for more details on VM management.

<table>
    <tr><th align="center">Example</th><th>Description</th></tr>
    <tr><td rowspan="1">./platform/client/launch_multios.sh -f -d android -g sriov android</td><td>To force launch android guest VM configured with SR-IOV display</td></tr>
    <tr><td rowspan="1">./platform/client/launch_multios.sh -f -d android -g gvtd android</td><td>To force launch android guest VM configured with GVT-d display</td></tr>
    <tr><td rowspan="1">./platform/client/launch_multios.sh -f -d android -p android --usb keyboard</td><td>To android and passthrough USB Keyboard to android guest VM</td></tr>
    <tr><td rowspan="1">./platform/client/launch_multios.sh -f -d android -p android --pci wi-fi</td><td>To force launch android VM and passthrough PCI WiFi to android guest VM</td></tr>
    <tr><td rowspan="1">./platform/client/launch_multios.sh -f -d android -p android --pci network controller 2</td><td>To force launch android VM and passthrough the 2nd PCI Network Controller in lspci list to android guest VM</td></tr>
    <tr><td rowspan="1">./platform/client/launch_multios.sh -f -d android -p android --xml xxxx.xml</td><td>To force launch android VM and passthrough the device(s) in the XML file to android guest VM</td></tr>
</table>

**Note: Due Android OS design, not all typical VM management methods applicable for Android VM. See [Basic Android VM operations](#basic-android-vm-operations)**

# Basic Android VM Operations
Connect to Android VM via ADB.


        sudo virsh domifaddr android
         Name       MAC address          Protocol     Address
        -------------------------------------------------------------------------------
        vnet26     52:54:00:ab:cd:33    ipv4         192.168.122.33/24

        adb connect 192.168.122.33:5555
        connected to 192.168.122.33:5555

        adb devices
        List of devices attached
        192.168.122.33:5555     device

Note: The default for <vm_name> is "android". Replace it if using a different VM domain name.

Setup proxy for Android

        adb shell
        caas:/ # su
        caas:/ # settings put global http_proxy <proxy_url>:<proxy_port>

Clear proxy for Android

        adb shell
        caas:/ # su
        caas:/ # settings put global http_proxy null

Shutdown Android via ADB

        adb reboot -p

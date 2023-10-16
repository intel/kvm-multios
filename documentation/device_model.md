# Virtual Machine Device Model Supported

<table>
    <tr><th rowspan="2">Component</th><th colspan="4">Guest VMs</th></tr>
    <tr><td align="center">Ubuntu 22.04 VM</td><td align="center">Windows IOT Enterprise LTSC 21H1</td><td align="center">Android 13 VM</td></tr>
    <tr><td rowspan="4"> Host </td><td colspan="3" align="center">Libvirt 8.0.0</td></tr>
    <tr><td class="centre" colspan="3" align="center">KVM/QEMU 8.0.0</td></tr>
    <tr><td colspan="3" align="center">Ubuntu 22.04</td></tr>
    <tr><td colspan="3" align="center">Intel IOT kernel (exact version may differ for each platform)</td></tr>
    <tr><td>Storage</td><td>Sharing</td><td>Sharing</td><td>Sharing</td></tr>
    <tr><td>iGPU *</td><td>SR-IOV or GVT-d*</td><td>SR-IOV or GVT-d*</td><td>virtio-gpu, SR-IOV, GVT-d*</td></tr>
    <tr><td>Display*</td><td>SR-IOV or GVT-d* or VNC:1</td><td>SR-IOV or GVT-d* or VNC:2</td><td>SR-IOV or GVT-d* or VNC:3</td></tr>
    <tr><td>USB inputs (mouse/keyboard)</td><td colspan="3" align="center">Passthrough or emulation</td></td></tr>
    <tr><td>LAN</td><td colspan="3" align="center">Virtual NAT</td></tr>
    <tr><td>External PCI Ethernet Adapter</td><td colspan="3" align="center">Passthrough**</td></tr>
    <tr><td>External USB Ethernet Adapter</td><td colspan="3" align="center">Passthrough</td></tr>
    <tr><td>TSN i225 Ethernet Adapter</td><td colspan="3" align="center">Passthrough</td></tr>
    <tr><td>Wi-fi</td><td colspan="3" align="center">Passthrough</td></tr>
    <tr><td>Bluetooth</td><td colspan="3" align="center">Passthrough</td></tr>
    <tr><td>SATA controller</td><td colspan="3" align="center">Passthrough**</td></tr>
    <tr><td>USB Controller</td><td colspan="3" align="center">Passthrough</td></tr>
    <tr><td>Serial Controller</td><td colspan="3" align="center">Passthrough**</td></tr>
    <tr><td>VPU</td><td colspan="3" align="center">Passthrough</td></tr>
    <tr><td>IPU</td><td colspan="3" align="center">Passthrough**</td></tr>
</table>

**Notes**
For all devices, a device which is passthrough to a VM can only be used by that guest VM only and is not available to any other VM or to host.
</br>\* GVT-d can only be applied for one running VM while other runnings VMs will be using VNC or no display.
</br>\*\* Not validated in this release

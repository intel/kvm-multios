# Virtual Machine Device Model Supported

<table>
    <tr><th rowspan="2">Component</th><th colspan="5">Guest VMs</th></tr>
    <tr><td align="center">Ubuntu 24.04</td><td align="center">Windows 10 IoT Enterprise</td><td align="center">Android CIV</td><td align="center">Windows 11 IoT Enterprise</td></tr>
    <tr><td rowspan="4"> Host </td><td colspan="4" align="center">Libvirt 10.0.0 (Ubuntu 24.04)</td></tr>
    <tr><td class="centre" colspan="4" align="center">KVM/QEMU 9.1.0</td></tr>
    <tr><td colspan="4" align="center">Ubuntu 24.04</td></tr>
    <tr><td colspan="4" align="center">Intel IoT kernel (exact version may differ for each platform)</td></tr>
    <tr><td>Storage</td><td>Sharing</td><td>Sharing</td><td>Sharing</td><td>Sharing</td></tr>
    <tr><td>iGPU *</td><td>SR-IOV or GVT-d*</td><td>SR-IOV or GVT-d*</td><td>virtio-gpu, SR-IOV, GVT-d*</td><td>SR-IOV or GVT-d*</td></tr>
    <tr><td>Display*</td><td>SR-IOV or GVT-d* or VNC,SPICE</td><td>SR-IOV or GVT-d* or VNC,SPICE</td><td>SR-IOV or GVT-d*</td><td>SR-IOV or GVT-d* or VNC,SPICE</td></tr>
    <tr><td>Audio</td><td colspan="4" align="center">emulation</td></tr>
    <tr><td>USB inputs (mouse/keyboard)</td><td colspan="4" align="center">Passthrough or emulation</td></td></tr>
    <tr><td>LAN</td><td colspan="4" align="center">Virtual NAT</td></tr>
    <tr><td>External PCI Ethernet Adapter</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>External USB Ethernet Adapter</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>TSN i225/i226 Ethernet Adapter</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>Wi-fi</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>Bluetooth</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>SATA controller</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>USB Controller</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>Serial Controller</td><td colspan="4" align="center">Passthrough**</td></tr>
    <tr><td>NPU</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>IPU</td><td colspan="4" align="center">Passthrough</td></tr>
    <tr><td>TPM</td><td>Passthrough</td><td colspan="3" align="center">SW emulation</td></tr>
</table>

**Notes**
For all devices, a device which is passthrough to a VM can only be used by that guest VM only and is not available to any other VM or to host.
</br>\* GVT-d can only be applied for one running VM while other runnings VMs will be using VNC/SPICE or no display.
</br>\*\* Not validated in this release

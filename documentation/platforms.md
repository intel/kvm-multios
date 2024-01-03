# Table of Contents
1. [Intel IOT Platforms Supported](#intel-iot-platforms-supported)
    1. [Amston Lake](#amston-lake)
    1. [Meteor Lake](#meteor-lake)
    1. [Raptor Lake PS](#raptor-lake-ps)
    1. [Alder Lake (For Development only)](#alder-lake-for-development-only)

# Intel IOT Platforms Supported
| Supported Intel IOT platform | Supported Host and Guest OS Details
| :-- | :--
| Amston Lake | [refer here](platforms.md#amston-lake)
| Meteor Lake | [refer here](platforms.md#meteor-lake)
| Raptor Lake PS | [refer here](platforms.md#raptor-lake-ps)
| Alder Lake | [refer here](platforms.md#alder-lake)

## Amston Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF | BIOS/IFWI (min ver required) |
|:---|:---|:---|:---|
| Alder Lake – N SODIMM DDR5 CRB | Amston Lake | NA | Please refer to platform BSP release notes |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 22.04 Intel IOT release</br>See <a href="">Ubuntu with Kernel Overlay on Amston Lake – for Edge Platforms -- Get Started Guide (Document ID: xxxxxx)</a> for details</td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IOT release</br>See <a href="">Ubuntu with Kernel Overlay on Amston Lake – for Edge Platforms -- Get Started Guide (Document ID: xxxxxx)</a> for details</td><td>Yes</td><td>Yes</td>
    </tr>
    <tr><td align="left"><a href="">Celadon IOT Android12 release 2023 ww42</a></td><td>No</td><td>Yes</td></tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IOT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us">(Windows ISO – LTSC Enterprise download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: <a href="">31.0.101.4824</a></br>
Windows Zero-copy driver release: <a href="">ZCBuild_1384_MSFT_Signed.zip(4.0.0.1384)</a>
      </td><td>Yes</td><td>Yes</td>
    </tr>
</table>

# Meteor Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF | BIOS/IFWI (min ver required) |
|:---|:---|:---|:---|
| Meteor Lake – H SODIMM DDR5 RVP | Meteor Lake – H (H68) Silicon C1 and beyond | NA | Please refer to  <a href="https://cdrdv2.intel.com/v1/dl/getContent/779460?explicitVersion=true">Ubuntu with Kernel Overlay on Meteor Lake – U/H for Edge Platforms -- Get Started Guide (Document ID: 779460)</a> for details |
| Meteor Lake – U SODIMM DDR5 RVP | Meteor Lake – U (U28) Silicon C1 and beyond | NA | Please refer to  <a href="https://cdrdv2.intel.com/v1/dl/getContent/779460?explicitVersion=true">Ubuntu with Kernel Overlay on Meteor Lake – U/H for Edge Platforms -- Get Started Guide (Document ID: 779460)</a> for details |
| Meteor Lake - PS SODIMM DDR5 CRB | Meteor Lake - PS (682 & 281) Silicon B0 and beyond | NA | Please refer to <a href="https://cdrdv2.intel.com/v1/dl/getContent/788267?explicitVersion=true">Meteor Lake - PS Ubuntu with Kernel Overlay - Get Started Guide (Document ID: 788267)</a> for details |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 22.04 Intel IOT release</br>Meteor Lake - U/H, see <a href="https://cdrdv2.intel.com/v1/dl/getContent/779460?explicitVersion=true">Ubuntu with Kernel Overlay on Meteor Lake – U/H for Edge Platforms -- Get Started Guide (Document ID: 779460)</a> for details</br>Meteor Lake - PS, see <a href="https://cdrdv2.intel.com/v1/dl/getContent/788267?explicitVersion=true">Meteor Lake - PS Ubuntu with Kernel Overlay - Get Started Guide (Document ID: 788267)</a> for details</td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IOT release</br>Meteor Lake - U/H, see <a href="https://cdrdv2.intel.com/v1/dl/getContent/779460?explicitVersion=true">Ubuntu with Kernel Overlay on Meteor Lake – U/H for Edge Platforms -- Get Started Guide (Document ID: 779460)</a> for details</br>Meteor Lake - PS, see <a href="https://cdrdv2.intel.com/v1/dl/getContent/788267?explicitVersion=true">Meteor Lake - PS Ubuntu with Kernel Overlay - Get Started Guide (Document ID: 788267)</a> for details</td><td>Yes</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IOT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us">(Windows ISO – LTSC Enterprise download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: <a href="">31.0.101.4928</a></br>
Windows Zero-copy driver release: <a href="">ZCBuild_1314_MSFT_Signed.zip (4.0.0.1314)</a>
      </td><td>Yes</td><td>Yes</td>
    </tr>
</table>

## Raptor Lake PS
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF | BIOS/IFWI (min ver required) |
|:---|:---|:---|:---|
| Raptor Lake - PS SODIMM DDR5 RVP | Raptor Lake (682/282) - PS Silicon J2 and beyond | NA | Please refer to <a href="https://cdrdv2.intel.com/v1/dl/getContent/787965?explicitVersion=true">Ubuntu with Kernel Overlay on Raptor Lake PS – for Edge Platforms -- Get Started Guide (Document ID: 787965)</a> for details |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 22.04 Intel IOT release</br>See <a href="https://cdrdv2.intel.com/v1/dl/getContent/787965?explicitVersion=true">Ubuntu with Kernel Overlay on Raptor Lake PS – for Edge Platforms -- Get Started Guide (Document ID: 787965)</a> for details</td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IOT release</br>See <a href="https://cdrdv2.intel.com/v1/dl/getContent/787965?explicitVersion=true">Ubuntu with Kernel Overlay on Raptor Lake PS – for Edge Platforms -- Get Started Guide (Document ID: 787965)</a> for details</td><td>Yes</td><td>Yes</td>
    </tr>
    <tr><td align="left"><a href="">Celadon IOT Android12 release 2023 ww42</a></td><td>No</td><td>Yes</td></tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IOT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us">(Windows ISO – LTSC Enterprise download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: <a href="">31.0.101.4824</a></br>
Windows Zero-copy driver release: <a href="">ZCBuild_1384_MSFT_Signed.zip(4.0.0.1384)</a>
      </td><td>Yes</td><td>Yes</td>
    </tr>
</table>

# Alder Lake (For Development only)
**Note**: KVM MultiOS Portfolio release does not officially support Alder Lake. This is being used as a N-1 development platform only.

| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF | BIOS/IFWI (min ver required) |
|:---|:---|:---|:---|
| Alder Lake – S SODIMM DDR5 RVP | Alder Lake S QYMF/C1 Silicon | QYFK/B1 | Please refer to platform BSP release notes |
| Alder Lake – P SODIMM DDR5 RVP | Alder Lake P QYZW/J0 Silicon | NA | Please refer to platform BSP release notes |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 22.04 Intel IOT release</br>See <a href="https://cdrdv2.intel.com/v1/dl/getContent/779460?explicitVersion=true">Ubuntu with Kernel Overlay on Meteor Lake – U/H for Edge Platforms -- Get Started Guide (Document ID: 779460)</a> for details</td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IOT release</br>See <a href="https://cdrdv2.intel.com/v1/dl/getContent/779460?explicitVersion=true">Ubuntu with Kernel Overlay on Meteor Lake – U/H for Edge Platforms -- Get Started Guide (Document ID: 779460)</a> for details</td><td>Yes</td><td>Yes</td>
    </tr>
    <tr><td align="left"><a href="">Celadon IOT Android13 release 2023 ww23</a></td><td>Yes</td><td>Yes</td></tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IOT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us">(Windows ISO – LTSC Enterprise download)</a></br>
Window 10 OS patch required: <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: <a href="">31.0.101.4928</a></br>
Windows Zero-copy driver release: <a href="">ZCBuild_1314_MSFT_Signed.zip(4.0.0.1314)</a>
      </td><td>Yes</td><td>Yes</td>
    </tr>
</table>

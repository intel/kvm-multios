# Table of Contents
1. [Intel IoT Platforms Supported](#intel-iot-platforms-supported)
    1. [Bartlett Lake](#bartlett-lake)
    1. [Twin Lake](#twin-lake)
    1. [Arrow Lake](#arrow-lake)
    1. [Amston Lake and Alder Lake N](#amston-lake-and-alder-lake-n)
    1. [Meteor Lake](#meteor-lake)
    1. [Raptor Lake P and PS](#raptor-lake-p-and-ps)

# Intel IoT Platforms Supported
| Supported Intel IoT platform | Supported Host and Guest OS Details
| :-- | :--
| Bartlett Lake | [refer here](platforms.md#bartlett-lake)
| Twin Lake | [refer here](platforms.md#twin-lake)
| Arrow Lake | [refer here](platforms.md#arrow-lake)
| Amston Lake | [refer here](platforms.md#amston-lake-and-alder-lake-n)
| Meteor Lake | [refer here](platforms.md#meteor-lake)
| Raptor Lake PS | [refer here](platforms.md#raptor-lake-p-and-ps)
| Raptor Lake P | [refer here](platforms.md#raptor-lake-p-and-ps)
| Alder Lake N | [refer here](platforms.md#amston-lake-and-alder-lake-n)

## Bartlett Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Bartlett Lake – S SODIMM DDR5 RVP</br>Bartlett Lake – S UDIMM DDR5 RVP | Bartlett Lake – S Hybrid (8161/881/601) Silicon QS and beyond | Bartlett Lake - S PCH QS and beyond |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037768-x64_a627ecbec3d8dad1754d541b7f89d534a6bdec69.msu">Windows10.0 19044.4412 (kb5037768)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6556</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.2033 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/72f34af9-6ab3-4bb0-9dfe-103e56a305fb/public/windows11.0-kb5044284-x64_d7eb7ceaa4798b92b988fd7dcc7c6bb39476ccf3.msu">Windows11.0 26100.2033 (kb5044284)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6556</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
</table>

## Twin Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Alder Lake - N  SODIMM DDR5 CRB | Twin Lake Silicon QS and beyond | NA |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.2033 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/72f34af9-6ab3-4bb0-9dfe-103e56a305fb/public/windows11.0-kb5044284-x64_d7eb7ceaa4798b92b988fd7dcc7c6bb39476ccf3.msu">Windows11.0 26100.2033 (kb5044284)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6556</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

## Arrow Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Arrow Lake – S UDIMM DDR5 RVP | Arrow Lake – S Silicon QS and beyond | Arrow Lake -S PCH QS and beyond |
| Arrow Lake – H SODIMM DDR5 CRB | Arrow Lake – H Silicon QS and beyond | NA |
| Arrow Lake – U SODIMM DDR5 CRB | Arrow Lake – U Silicon QS and beyond | NA |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037768-x64_a627ecbec3d8dad1754d541b7f89d534a6bdec69.msu">Windows10.0 19044.4412 (kb5037768)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6314</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/1a28d3c1-84ce-4108-ba95-3e918453a297/public/windows11.0-kb5040529-x64_fb312553946fb0b8a29324ba9f58c25ff6590979.msu">Windows11.0 26100.1301 (kb5040529)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6314</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

## Amston Lake and Alder Lake N
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Alder Lake - N SODIMM DDR5 CRB | Amston Lake Silicon J0 and beyond | NA |
| Alder Lake - N SODIMM DDR5 CRB | Alder Lake-N Silicon N0 and beyond | NA |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2024/10/windows10.0-kb5044273-x64_71347fa01079c2b6278a0f48282b8ff3ded2f1e0.msu">Windows10.0 19044.5011 (kb5044273)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6556</br>
Windows Zero-copy driver release: 4.0.0.1797</a>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.2033 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/72f34af9-6ab3-4bb0-9dfe-103e56a305fb/public/windows11.0-kb5044284-x64_d7eb7ceaa4798b92b988fd7dcc7c6bb39476ccf3.msu">Windows11.0 26100.2033 (kb5044284)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6556</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

## Meteor Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Meteor Lake – H SODIMM DDR5 RVP | Meteor Lake – H (H68) Silicon C1 and beyond | NA |
| Meteor Lake – U SODIMM DDR5 RVP | Meteor Lake – U (U28) Silicon C1 and beyond | NA |
| Meteor Lake - PS SODIMM DDR5 CRB | Meteor Lake - PS (682 & 281) Silicon B0 and beyond | NA |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2024/05/windows10.0-kb5037768-x64_a627ecbec3d8dad1754d541b7f89d534a6bdec69.msu">Windows10.0 19044.4412 (kb5037768)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6134</br>
Windows Zero-copy driver release: 4.0.0.1742</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/1a28d3c1-84ce-4108-ba95-3e918453a297/public/windows11.0-kb5040529-x64_fb312553946fb0b8a29324ba9f58c25ff6590979.msu">Windows11.0 26100.1301 (kb5040529)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6134</br>
Windows Zero-copy driver release: 4.0.0.1742</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

## Raptor Lake P and PS
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Raptor Lake - PS SODIMM DDR5 RVP | Raptor Lake (682/282) - PS Silicon QS and beyond | NA |
| Raptor Lake - P SODIMM DDR5 CRB | Raptor Lake (682/282) - P Silicon QS and beyond | NA |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required: Windows10.0 19044.5371 <a href="https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2025/01/windows10.0-kb5049981-x64_bda073f7d8e14e65c2632b47278924b8a0f6b374.msu">(kb5049981)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6556</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required: Windows11.0 26100.3037 <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">(kb5043080)</a> and <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/2d3f9ba9-5096-4b23-9709-3af7d7a2103f/public/windows11.0-kb5050094-x64_3d5a5f9ef20fc35cc1bd2ccb08921ee8713ce622.msu">(kb5050094)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6556</br>
Windows Zero-copy driver release: 4.0.0.1797</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

Notes:
* GVT-d can only be applied for one running VM while other runnings VMs will be using VNC/SPICE or no display.
  GVT-d is not fully validated in this release.
* The KVM MultiOS Portfolio release provides only limited support for Android CiV guests.
  It is intended solely for demonstration purposes and is not validated.
  Users are encouraged to collaborate with ISV/OSV partners to evaluate and develop the solution using a reference Base Release from the Celadon Project.
  For more information, please visit:
  * [Celadon Ecosystem](https://www.intel.com/content/www/us/en/developer/topic-technology/open/celadon/ecosystem.html)
  * [Celadon Base Releases](https://projectceladon.github.io/celadon-documentation/release-notes/base-releases.html)

# Table of Contents
1. [Intel IoT Platforms Supported](#intel-iot-platforms-supported)
    1. [Arrow Lake](#arrow-lake)
    1. [Amston Lake](#amston-lake-and-alder-lake-n)
    1. [Meteor Lake](#meteor-lake)
    1. [Raptor Lake PS](#raptor-lake-ps)
    1. [Alder Lake N](#amston-lake-and-alder-lake-n)

# Intel IoT Platforms Supported
| Supported Intel IoT platform | Supported Host and Guest OS Details
| :-- | :--
| Arrow Lake | [refer here](platforms.md#arrow-lake)
| Amston Lake | [refer here](platforms.md#amston-lake-and-alder-lake-n)
| Meteor Lake | [refer here](platforms.md#meteor-lake)
| Raptor Lake PS | [refer here](platforms.md#raptor-lake-ps)
| Alder Lake N | [refer here](platforms.md#amston-lake-and-alder-lake-n)

## Arrow Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Arrow Lake – S UDIMM DDR5 RVP | Arrow Lake – S Silicon B0 and beyond | Arrow Lake -S PCH B0 and beyond |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="4" align="left">Ubuntu 22.04 Intel IoT release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IoT release</br></td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5424</br>
Windows Zero-copy driver release: 4.0.0.1574</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 22H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/396ddabf-b27a-451e-a898-31d0427a36f7/public/windows11.0-kb5035942-x64_3f37174fadabd9d29ffe92a92b3422557586f645.msu">Windows11.0 kb5035942</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5424</br>
Windows Zero-copy driver release: 4.0.0.1574</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
</table>

## Amston Lake and Alder Lake N
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Amston Lake SODIMM DDR5 RVP | Amston Lake Silicon J0 and beyond | NA |
| Alder Lake – N SODIMM DDR5 CRB | Alder Lake-N Silicon N0 and beyond | NA |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="5" align="left">Ubuntu 22.04 Intel IoT release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IoT release</br></td><td>Yes</td><td>Yes</td>
    </tr>
    <tr><td align="left">Celadon IoT Android12 release 2024</td><td>No</td><td>Yes</td></tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5382</br>
Windows Zero-copy driver release: 4.0.0.1574</a>
      </td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 22H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/396ddabf-b27a-451e-a898-31d0427a36f7/public/windows11.0-kb5035942-x64_3f37174fadabd9d29ffe92a92b3422557586f645.msu">Windows11.0 kb5035942</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5382</br>
Windows Zero-copy driver release: 4.0.0.1574</br>
      </td><td>NA</td><td>Yes</td>
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
      <td rowspan="4" align="left">Ubuntu 22.04 Intel IoT release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IoT release</br></td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5445</br>
Windows Zero-copy driver release: 4.0.0.1574</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 22H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/396ddabf-b27a-451e-a898-31d0427a36f7/public/windows11.0-kb5035942-x64_3f37174fadabd9d29ffe92a92b3422557586f645.msu">Windows11.0 kb5035942</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5445</br>
Windows Zero-copy driver release: 4.0.0.1574</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
</table>

## Raptor Lake PS
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Raptor Lake - PS SODIMM DDR5 RVP | Raptor Lake (682/282) - PS Silicon J2 and beyond | NA |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="5" align="left">Ubuntu 22.04 Intel IoT release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 22.04 Intel IoT release</br></td><td>NA</td><td>Yes</td>
    </tr>
    <tr><td align="left">Celadon IoT Android12 release 2024</td><td>No</td><td>Yes</td></tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/05/windows10.0-kb5026361-x64_961f439d6b20735f067af766e1813936bf76cb94.msu">Windows10.0 kb5026361</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5382</br>
Windows Zero-copy driver release: 4.0.0.1574</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 22H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/396ddabf-b27a-451e-a898-31d0427a36f7/public/windows11.0-kb5035942-x64_3f37174fadabd9d29ffe92a92b3422557586f645.msu">Windows11.0 kb5035942</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.5382</br>
Windows Zero-copy driver release: 4.0.0.1574</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
</table>

# Table of Contents
1. [Intel IoT Platforms Supported](#intel-iot-platforms-supported)
    1. [Nova Lake S](#nova-lake-S)
    1. [Wildcat Lake](#wildcat-lake)
    1. [Panther Lake H](#panther-lake-h)
    1. [Bartlett Lake S 12P](#bartlett-lake-s-12p)
    1. [Bartlett Lake S](#bartlett-lake-s)
    1. [Twin Lake](#twin-lake)
    1. [Arrow Lake](#arrow-lake)
    1. [Amston Lake and Alder Lake N](#amston-lake-and-alder-lake-n)
    1. [Meteor Lake](#meteor-lake)
    1. [Raptor Lake P and PS](#raptor-lake-p-and-ps)

# Intel IoT Platforms Supported
| Supported Intel IoT platform | Supported Host and Guest OS Details
| :-- | :--
| Nova Lake S | [refer here](platforms.md#nova-lake-S)
| Wildcat Lake | [refer here](platforms.md#wildcat-lake)
| Panther Lake H | [refer here](platforms.md#panther-lake-h)
| Bartlett Lake S 12P | [refer here](platforms.md#bartlett-lake-s-12p)
| Bartlett Lake S | [refer here](platforms.md#bartlett-lake-s)
| Twin Lake | [refer here](platforms.md#twin-lake)
| Arrow Lake | [refer here](platforms.md#arrow-lake)
| Amston Lake | [refer here](platforms.md#amston-lake-and-alder-lake-n)
| Meteor Lake | [refer here](platforms.md#meteor-lake)
| Raptor Lake PS | [refer here](platforms.md#raptor-lake-p-and-ps)
| Raptor Lake P | [refer here](platforms.md#raptor-lake-p-and-ps)
| Alder Lake N | [refer here](platforms.md#amston-lake-and-alder-lake-n)

## Nova Lake S
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Nova Lake - S SODIMM DDR5 RVP | Nova Lake S A0 Silicon and beyond | PCH/A0 and beyond |

<table>
    <tr><th align="center">Host Operating System</th><th>Guest VM Operating Systems</th><th>GVT-d Supported</th><th>GPU SR-IOV Supported</th></tr>
    <!-- Host Operating System -->
    <tr>
      <td rowspan="3" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>Yes</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 22H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required: <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 kb5043080</a> and <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/66b28d24-251c-4c0a-8a19-82bc599deac3/public/windows11.0-kb5077241-x64_739bca934f7f45038f9752637f632afa52c35f75.msu">windows11.0-kb5077241</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8672</br>
Windows Zero-copy driver release: 5.0.0.2319</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
</table>

## Wildcat Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Wildcat Lake SODIMM DDR5 | Wildcat Lake Silicon A1 and beyond | NA |

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
   <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required: Windows11.0 26100.8737 <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">(kb5043080)</a> and <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/0c7a093a-ecf2-4386-afa5-75bcd763ae00/public/windows11.0-kb5095093-x64_871fd990cedd9d3da6c90ca8b1dd0cc62b42c330.msu">(kb5095093)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8860</br>
Windows Zero-copy driver release: 5.0.0.2537</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

## Panther Lake H
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Panther Lake H SODIMM DDR5 CRB | Panther Lake H Silicon B0 and beyond (12Xe/4Xe) | NA |

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
   <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required: Windows11.0 26100.8737 <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">(kb5043080)</a> and <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/0c7a093a-ecf2-4386-afa5-75bcd763ae00/public/windows11.0-kb5095093-x64_871fd990cedd9d3da6c90ca8b1dd0cc62b42c330.msu">(kb5095093)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8860</br>
Windows Zero-copy driver release: 5.0.0.2516</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

## Bartlett Lake S 12P
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Bartlett Lake S UDIMM DDR5 RVP | Bartlett Lake S12P ES, QS and beyond |Bartlett Lake S12P ES, QS and beyond |

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
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.8117 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b1318d9f-d80a-4556-ab47-792cf5303d43/public/windows11.0-kb5086672-x64_97df4ed279e18da5b02308a5a3361313520fd346.msu">Windows11.0 26100.8117 (kb5086672)</a></br>
BTL-S 12P Integrated GPU Intel(R) Graphics driver version:101.7085</br>
Windows Zero-copy driver release: 5.0.0.2400</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
</table>

## Bartlett Lake S
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Bartlett Lake  S SODIMM DDR5 RVP | Bartlett Lake S Hybrid (8161/881/601) Silicon QS and beyond | Bartlett Lake  S PCH QS and beyond |

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
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.8117 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b1318d9f-d80a-4556-ab47-792cf5303d43/public/windows11.0-kb5086672-x64_97df4ed279e18da5b02308a5a3361313520fd346.msu">Windows11.0 26100.8117 (kb5086672)</a></br>
BTL-S Integrated GPU Intel(R) Graphics driver version: 101.7085</br>
Windows Zero-copy driver release: 5.0.0.2400</br>
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
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.8117 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b1318d9f-d80a-4556-ab47-792cf5303d43/public/windows11.0-kb5086672-x64_97df4ed279e18da5b02308a5a3361313520fd346.msu">Windows11.0 26100.8117 (kb5086672)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.7085</br>
Windows Zero-copy driver release: 5.0.0.2400</br>
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
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.8117 (kb5043080)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b1318d9f-d80a-4556-ab47-792cf5303d43/public/windows11.0-kb5086672-x64_97df4ed279e18da5b02308a5a3361313520fd346.msu">Windows11.0 26100.8117 (kb5086672)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8724</br>
Windows Zero-copy driver release: 5.0.0.2400</br>
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
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.8117 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b1318d9f-d80a-4556-ab47-792cf5303d43/public/windows11.0-kb5086672-x64_97df4ed279e18da5b02308a5a3361313520fd346.msu">Windows11.0 26100.8117 (kb5086672)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.7085</br>
Windows Zero-copy driver release: 5.0.0.2400</br>
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
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.8584 (kb5043080)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7342fa97-e584-4465-9b3d-71e771c9db5b/public/windows11.0-kb5065426-x64_32b5f85e0f4f08e5d6eabec6586014a02d3b6224.msu">Windows11.0 26100.6584 (kb5065426)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8132</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
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
      <td rowspan="3" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required: Windows11.0 26100.3037 <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">(kb5043080)</a> and <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/2d3f9ba9-5096-4b23-9709-3af7d7a2103f/public/windows11.0-kb5050094-x64_3d5a5f9ef20fc35cc1bd2ccb08921ee8713ce622.msu">(kb5050094)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6733</br>
Windows Zero-copy driver release: 4.0.0.1918</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

Notes:
* GVT-d can only be applied for one running VM while other runnings VMs will be using VNC/SPICE or no display.
  GVT-d is not fully validated in this release.

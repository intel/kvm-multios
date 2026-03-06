# Table of Contents
1. [Intel IoT Platforms Supported](#intel-iot-platforms-supported)
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

## Wildcat Lake
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Wildcat Lake SODIMM DDR5 | Wildcat Lake Silicon A0 (ES1) and beyond | NA |

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
Window 11 OS patch required: Windows11.0 26100.6584 <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">(kb5043080)</a> and <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7342fa97-e584-4465-9b3d-71e771c9db5b/public/windows11.0-kb5065426-x64_32b5f85e0f4f08e5d6eabec6586014a02d3b6224.msu">(kb5065426)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8344</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
</table>

## Panther Lake H
| Hardware Board Type | Silicon/Stepping/QDF | PCH Stepping/QDF |
|:---|:---|:---|
| Panther Lake H SODIMM DDR5 CRB | Panther Lake H Silicon B0 and beyond | NA |

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
Window 11 OS patch required: Windows11.0 26100.7462 <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">(kb5043080)</a> and <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/9d6e2b81-b755-4e68-af73-9f4ee41cd758/public/windows11.0-kb5072033-x64_a62291f0bad9123842bf15dcdd75d807d2a2c76a.msu">(kb5072033)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8361</br>
Windows Zero-copy driver release: 5.0.0.2223</br>
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
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/10/windows10.0-kb5066791-x64_3210d264091be5effb3253d05397c4daefba44c8.msu">Windows10.0 19044.6456 (kb5066791)</a></br>
BTL-S 12P Integrated GPU Intel(R) Graphics driver version:101.7082</br>
Windows Zero-copy driver release: 4.0.0.2223</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.7171 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/5315757b-0dc6-4282-a148-c7bf0b6b0e90/public/windows11.0-kb5068861-x64_acc4fe9c928835c0d44cdc0419d1867dbd2b62b2.msu">Windows11.0 26100.7171 (kb5068861)</a></br>
BTL-S 12P Integrated GPU Intel(R) Graphics driver version:101.7082</br>
Windows Zero-copy driver release: 4.0.0.2223</br>
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
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/09/windows10.0-kb5065429-x64_83acdf09e991adf6d9b1fa9c69f1f58c84e86c28.msu">Windows10.0 19044.6332 (kb5065429)</a></br>
BTL-S Integrated GPU Intel(R) Graphics driver version: 101.7077</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
      </td><td>NA</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.6584 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7342fa97-e584-4465-9b3d-71e771c9db5b/public/windows11.0-kb5065426-x64_32b5f85e0f4f08e5d6eabec6586014a02d3b6224.msu">Windows11.0 26100.6584 (kb5065426)</a></br>
BTL-S Integrated GPU Intel(R) Graphics driver version: 101.7077</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
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
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=21955    87&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required: <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/09/windows10.0-kb5065429-x64_83acdf09e991adf6d9b1fa9c69f1f58c84e86c28.msu">Windows10.0 19044.6332 kb5065429</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.7077</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
      </td><td>Yes</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.6584 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7342fa97-e584-4465-9b3d-71e771c9db5b/public/windows11.0-kb5065426-x64_32b5f85e0f4f08e5d6eabec6586014a02d3b6224.msu">Windows11.0 26100.6584 (kb5065426)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.7077</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
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
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/09/windows10.0-kb5065429-x64_83acdf09e991adf6d9b1fa9c69f1f58c84e86c28.msu">Windows10.0 19044.6332 (kb5065429)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8132</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.6584 (kb5043080)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7342fa97-e584-4465-9b3d-71e771c9db5b/public/windows11.0-kb5065426-x64_32b5f85e0f4f08e5d6eabec6586014a02d3b6224.msu">Windows11.0 26100.6584 (kb5065426)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8132</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
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
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/09/windows10.0-kb5065429-x64_83acdf09e991adf6d9b1fa9c69f1f58c84e86c28.msu">Windows10.0 19044.6332 (kb5065429)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.7077</br>
Windows Zero-copy driver release: 4.0.0.2164</a>
      </td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise">Windows 11 IoT Enterprise 24H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195682&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 11 OS patch required <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu">Windows11.0 26100.6584 (kb5043080)</a> <a href="https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7342fa97-e584-4465-9b3d-71e771c9db5b/public/windows11.0-kb5065426-x64_32b5f85e0f4f08e5d6eabec6586014a02d3b6224.msu">Windows11.0 26100.6584 (kb5065426)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.7077</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
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
Window 10 OS patch required <a href="https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2025/09/windows10.0-kb5065429-x64_83acdf09e991adf6d9b1fa9c69f1f58c84e86c28.msu">Windows10.0 19044.6332 (kb5065429)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.8132</br>
Windows Zero-copy driver release: 4.0.0.2164</br>
      </td><td>Yes*</td><td>Yes</td>
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
      <td rowspan="4" align="left">Ubuntu 24.04 release</br></td>
    </tr>
    <!-- Guest Operating Systems -->
    <tr>
      <td align="left">Ubuntu 24.04 release</br></td><td>Yes*</td><td>Yes</td>
    </tr>
    <tr>
      <td align="left"><a href="https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise">Windows 10 IoT Enterprise LTSC 21H2</a><a href="https://go.microsoft.com/fwlink/p/?linkid=2195587&clcid=0x409&culture=en-us&country=us"> (ISO download)</a></br>
Window 10 OS patch required: Windows10.0 19044.5371 <a href="https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2025/01/windows10.0-kb5049981-x64_bda073f7d8e14e65c2632b47278924b8a0f6b374.msu">(kb5049981)</a></br>
Integrated GPU Intel(R) Graphics driver version: 101.6733</br>
Windows Zero-copy driver release: 4.0.0.1918</br>
      </td><td>Yes*</td><td>Yes</td>
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
* The KVM MultiOS Portfolio release provides only limited support for Android CiV guests.
  It is intended solely for demonstration purposes and is not validated.
  Users are encouraged to collaborate with ISV/OSV partners to evaluate and develop the solution using a reference Base Release from the Celadon Project.
  For more information, please visit:
  * [Celadon Ecosystem](https://www.intel.com/content/www/us/en/developer/topic-technology/open/celadon/ecosystem.html)
  * [Celadon Base Releases](https://projectceladon.github.io/celadon-documentation/release-notes/base-releases.html)
